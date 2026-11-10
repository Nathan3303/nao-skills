#!/usr/bin/env node
// herdr 测试替身（test double）—— #96 二期 B4：D 类用例 herdr 侧的**确定性**后端。
//
// 为什么需要替身（而不是真 herdr + 真 pi）：
//   真 herdr 的「就绪/在线」判据要 pi 生命周期钩子权威（`agent_session` + `screen_detection_skipped`），
//   而 pi 的 herdr 集成装在**用户 HOME 的 pi 配置**里 ⇒ 测试要么污染用户 ~/.pi/agent/sessions，
//   要么换 HOME（换 HOME 后集成不加载 ⇒ 就绪门永不通过）。本替身把 herdr 的结构化事实
//   （pane.label / pane.cwd / process-info.argv / agent_status / state_change_seq）做成**可编排的夹具**，
//   于是 shared 用例的断言面仍只落在「我们自己的输出 / argv / 文件内容」上（PRD AC2.7 的 shared 定义），
//   与 B1/B2/B3 用 PATH 桩测 herdr 分支的口径一致。
//
// 状态：`$XDG_CONFIG_HOME/herdr/sessions/<session>/double-state.json`
//   `herdr --session S server` 建状态（幂等）；`session delete` 删目录 ⇒ `session list` 变空。
// 可编排旋钮（写进 state.knobs，测试用）：
//   pi_seq      pi 会话的 state_change_seq（默认 1；=0 ⇒ 就绪门的「必须观测到迁移」不满足）
//   pi_skip     screen_detection_skipped（默认 true；false ⇒ 集成缺失档）
//   pi_session  agent_session 是否存在（默认 true；false ⇒ 集成缺失档）
//   pi_status   agent_status（默认 idle）
// 台账：所有调用以一行 `<argv>` 追加到 `$T4_HERDR_CALL_LOG`（若设置）——用例据它断言「交给后端的原始命令」。
'use strict';
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const callLog = process.env.T4_HERDR_CALL_LOG || '';
if (callLog) {
  try { fs.appendFileSync(callLog, argv.join(' ') + '\n'); } catch (e) { /* 忽略：日志非判据 */ }
}

const die = (obj, code) => { process.stderr.write(JSON.stringify(obj) + '\n'); process.exit(code === undefined ? 1 : code); };
const out = (obj) => { process.stdout.write(JSON.stringify(obj) + '\n'); process.exit(0); };

// ---- 解析 `--session <s>`（唯一入口恒注入；缺 ⇒ 与真 CLI 一样拒绝）----
let session = '';
const rest = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--session') { session = argv[i + 1] || ''; i++; continue; }
  if (argv[i] === '--setsid') { continue; }
  rest.push(argv[i]);
}
if (!session) die({ error: { code: 'missing_session', message: 'need --session <name>' } });

const cfg = process.env.XDG_CONFIG_HOME || path.join(process.env.HOME || '/tmp', '.config');
const sdir = path.join(cfg, 'herdr', 'sessions', session);
const sfile = path.join(sdir, 'double-state.json');

const DEFAULT_KNOBS = { pi_seq: 1, pi_skip: true, pi_session: true, pi_status: 'idle' };
const emptyState = () => ({
  panes: {},          // pane_id -> {pane_id, terminal_id, workspace_id, tab_id, label, cwd, fg, argv, cmd, shell_pid}
  workspaces: {},     // ws_id  -> {workspace_id, label, order}
  seq: { ws: 0, pane: {} },
  knobs: Object.assign({}, DEFAULT_KNOBS),
});

function readState() {
  try { return JSON.parse(fs.readFileSync(sfile, 'utf8')); } catch (e) { return null; }
}
function writeState(st) {
  fs.mkdirSync(sdir, { recursive: true });
  const tmp = sfile + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(st));
  fs.renameSync(tmp, sfile);
}
function needState() {
  const st = readState();
  if (!st) die({ error: { code: 'server_not_running', message: `no herdr server at ${sdir}` } });
  return st;
}

// ---- 由 pane.run 的命令串推导「前台进程」（名字 / argv / 是否 pi）----
function unquote(s) {
  if (s === undefined) return '';
  if (/^'.*'$/.test(s)) return s.slice(1, -1).replace(/'\\''/g, "'");
  if (/^".*"$/.test(s)) return s.slice(1, -1).replace(/\\"/g, '"');
  return s;
}
function tokenize(cmd) {
  const toks = [];
  let cur = ''; let q = null; let i = 0;
  while (i < cmd.length) {
    const c = cmd[i];
    if (q) {
      if (c === q) { q = null; i++; continue; }
      if (c === '\\' && q === '"') { cur += cmd[i + 1] || ''; i += 2; continue; }
      cur += c; i++; continue;
    }
    // `$'...'`（bash printf %q 的 ANSI-C 引用形态）：解析转义后再入 token
    //   （pm 注入消息是多行文本，%q 会产出 `$'line1\nline2'`；不解析则 argv 与真实字节不符）
    if (c === '$' && cmd[i + 1] === "'") {
      i += 2;
      let piece = '';
      while (i < cmd.length) {
        const ch = cmd[i];
        if (ch === "'") { i++; break; }
        if (ch === '\\') {
          const nx = cmd[i + 1];
          const map = { n: '\n', t: '\t', r: '\r', '\\': '\\', "'": "'", '"': '"' };
          piece += (map[nx] !== undefined ? map[nx] : nx);
          i += 2; continue;
        }
        piece += ch; i++;
      }
      cur += piece; continue;
    }
    if (c === "'" || c === '"') { q = c; i++; continue; }
    if (/\s/.test(c)) { if (cur) { toks.push(cur); cur = ''; } i++; continue; }
    cur += c; i++;
  }
  if (cur) toks.push(cur);
  return toks;
}
function flagValue(cmd, flag) {
  const t = tokenize(cmd);
  const i = t.indexOf(flag);
  return i >= 0 ? (t[i + 1] || '') : '';
}
function deriveProcess(cmd) {
  const isPi = /(^|&&\s*|\s)pi\s+--name\s/.test(cmd) || /(^|&&\s*)exec\s+pi\s+/.test(cmd);
  const argvName = flagValue(cmd, '--name');
  const prompt = flagValue(cmd, '--append-system-prompt');
  if (isPi) {
    const av = ['pi', '--name', argvName];
    if (prompt) av.push('--append-system-prompt', prompt);
    const t = tokenize(cmd);
    const dash = t.indexOf('--');
    if (dash >= 0) { av.push('--'); if (t[dash + 1] !== undefined) av.push(t.slice(dash + 1).join(' ')); }
    return { fg: 'pi', argv: av, cmdline: 'pi ' + av.slice(1).join(' ') };
  }
  const first = (cmd.trim().split(/\s+/)[0] || 'bash').replace(/^.*\//, '');
  return { fg: first, argv: [first], cmdline: cmd };
}

function paneObj(p, st) {
  const ag = st.panes[p] && st.panes[p].fg === 'pi' ? (readKnobs(st).pi_status || 'idle') : 'unknown';
  return {
    agent_status: ag,
    cwd: st.panes[p].cwd,
    focused: true,
    foreground_cwd: st.panes[p].cwd,
    pane_id: p,
    revision: 1,
    tab_id: st.panes[p].tab_id,
    terminal_id: st.panes[p].terminal_id,
    workspace_id: st.panes[p].workspace_id,
    label: st.panes[p].label,
  };
}
function readKnobs(st) { return Object.assign({}, DEFAULT_KNOBS, st.knobs || {}); }

function agentObj(p, st) {
  const k = readKnobs(st);
  const pane = st.panes[p];
  if (!pane || pane.fg !== 'pi') return null;
  const o = {
    agent: 'pi',
    agent_status: k.pi_status,
    cwd: pane.cwd,
    foreground_cwd: pane.cwd,
    pane_id: p,
    revision: 1,
    state_change_seq: Number(k.pi_seq) || 0,
    tab_id: pane.tab_id,
    terminal_id: pane.terminal_id,
    workspace_id: pane.workspace_id,
  };
  if (k.pi_session) o.agent_session = { agent: 'pi', kind: 'path', source: 'herdr:pi', value: 'double://' + p };
  if (k.pi_skip) o.screen_detection_skipped = true;
  return o;
}

const sub = rest[0] || '';
const a1 = rest[1] || '';

if (sub === '--version') { process.stdout.write('herdr 0.9.1\n'); process.exit(0); }

if (sub === 'api' && a1 === 'schema') {
  process.stdout.write('Herdr API schema (test double)\nprotocol: 22\nversion: 0.9.1\n');
  process.exit(0);
}

if (sub === 'api' && a1 === 'snapshot') {
  const st = readState();
  if (!st) die({ error: { code: 'server_not_running', message: `no herdr server at ${sdir}` } });
  out({
    id: 'cli:api:snapshot',
    result: {
      snapshot: { agents: [], layouts: [], panes: [], protocol: 22, tabs: [], version: '0.9.1', workspaces: [] },
      type: 'session_snapshot',
    },
  });
}

if (sub === 'server') { if (!readState()) writeState(emptyState()); process.exit(0); }

if (sub === 'session' && a1 === 'list') {
  const st = readState();
  out({ sessions: st ? [{ name: session }] : [] });
}

if (sub === 'session' && a1 === 'stop') { process.exit(0); }

if (sub === 'session' && a1 === 'delete') {
  try { fs.rmSync(sdir, { recursive: true, force: true }); } catch (e) { /* 幂等 */ }
  process.exit(0);
}

if (sub === 'workspace' && a1 === 'list') {
  const st = needState();
  const ws = Object.keys(st.workspaces)
    .sort((x, y) => st.workspaces[x].order - st.workspaces[y].order)
    .map((w) => ({
      active_tab_id: st.workspaces[w].tab_id,
      agent_status: 'unknown',
      label: st.workspaces[w].label,
      number: st.workspaces[w].order,
      pane_count: Object.keys(st.panes).filter((p) => st.panes[p].workspace_id === w).length,
      tab_count: 1,
      workspace_id: w,
    }));
  out({ result: { workspaces: ws, type: 'workspace_list' } });
}

if (sub === 'workspace' && a1 === 'create') {
  const st = needState();
  const cwd = flagValue(rest.join(' '), '--cwd') || process.cwd();
  const label = flagValue(rest.join(' '), '--label');
  st.seq.ws += 1;
  const wid = 'w' + st.seq.ws;
  const tid = wid + ':t1';
  const pid = wid + ':p1';
  st.workspaces[wid] = { workspace_id: wid, label: label, order: st.seq.ws, tab_id: tid };
  st.panes[pid] = { pane_id: pid, terminal_id: 'term_' + wid + '_p1', workspace_id: wid, tab_id: tid, label: '', cwd: cwd, fg: 'bash', argv: ['bash'], cmd: '', shell_pid: 900000 + st.seq.ws * 10 };
  writeState(st);
  out({
    id: 'cli:workspace:create',
    result: {
      pane: paneObj(pid, st),
      root_pane: {
        agent_status: 'unknown', cwd: cwd, focused: true, foreground_cwd: cwd, pane_id: pid,
        revision: 0, tab_id: tid, terminal_id: 'term_' + wid + '_p1', workspace_id: wid,
      },
      tab: { agent_status: 'unknown', focused: true, label: '1', number: 1, pane_count: 1, tab_id: tid, workspace_id: wid },
      type: 'workspace_created',
      workspace: { active_tab_id: tid, agent_status: 'unknown', focused: true, label: label, number: st.seq.ws, pane_count: 1, tab_count: 1, workspace_id: wid },
    },
  });
}

if (sub === 'workspace' && a1 === 'close') {
  const st = needState();
  const wid = rest[2] || '';
  delete st.workspaces[wid];
  for (const p of Object.keys(st.panes)) if (st.panes[p].workspace_id === wid) delete st.panes[p];
  writeState(st);
  out({ result: { type: 'workspace_closed', workspace_id: wid } });
}

if (sub === 'pane' && a1 === 'list') {
  const st = needState();
  const wflag = rest.indexOf('--workspace');
  const only = wflag >= 0 ? rest[wflag + 1] : '';
  const panes = Object.keys(st.panes)
    .filter((p) => !only || st.panes[p].workspace_id === only)
    .sort()
    .map((p) => paneObj(p, st));
  out({ result: { panes: panes, type: 'pane_list' } });
}

if (sub === 'pane' && a1 === 'split') {
  const st = needState();
  const base = rest[2] || '';
  if (!st.panes[base]) die({ error: { code: 'pane_not_found', message: 'no pane ' + base } });
  const cwd = flagValue(rest.join(' '), '--cwd') || st.panes[base].cwd;
  const wid = st.panes[base].workspace_id;
  st.seq.pane[wid] = (st.seq.pane[wid] || 1) + 1;
  const pid = wid + ':p' + st.seq.pane[wid];
  st.panes[pid] = { pane_id: pid, terminal_id: 'term_' + wid + '_p' + st.seq.pane[wid], workspace_id: wid, tab_id: st.panes[base].tab_id, label: '', cwd: cwd, fg: 'bash', argv: ['bash'], cmd: '', shell_pid: 900000 + st.seq.pane[wid] * 10 };
  writeState(st);
  out({ id: 'cli:pane:split', result: { pane: paneObj(pid, st), type: 'pane_split' } });
}

if (sub === 'pane' && a1 === 'rename') {
  const st = needState();
  const pid = rest[2] || '';
  const label = rest[3] || '';
  if (!st.panes[pid]) die({ error: { code: 'pane_not_found', message: 'no pane ' + pid } });
  st.panes[pid].label = label;
  writeState(st);
  out({ id: 'cli:pane:rename', result: { pane: paneObj(pid, st), type: 'pane_info' } });
}

if (sub === 'pane' && a1 === 'run') {
  const st = needState();
  const pid = rest[2] || '';
  const cmd = rest.slice(3).join(' ');
  // 用例侧「交给后端的原始命令」取证口（与 tmux 侧桩 split-window 落盘同口径）：
  //   每行一条 **raw 命令串**（不重排、不去引号）⇒ 用例可做字节级期望对照。
  // 失败注入（与 tmux 侧桩 split-window 的 NAO_T539_FAIL_SPLIT 同口径）：
  //   命中的 `--name` ⇒ pane run 返回错误（模拟「该目标 pane 起不来」），用于 ensure 三态/摘要夹具。
  const failNames = (process.env.T4_HERDR_FAIL_NAME || '').split(/\s+/).filter(Boolean);
  const runName = flagValue(cmd, '--name');
  if (failNames.indexOf(runName) >= 0) {
    die({ error: { code: 'pane_run_failed', message: 'injected failure for ' + runName } });
  }
  const spawnLog = process.env.T4_HERDR_SPAWN_LOG || '';
  if (spawnLog) { try { fs.appendFileSync(spawnLog, cmd + '\n'); } catch (e) { /* 非判据 */ } }
  if (!st.panes[pid]) die({ error: { code: 'pane_not_found', message: 'no pane ' + pid } });
  const d = deriveProcess(cmd);
  st.panes[pid].cmd = cmd;
  st.panes[pid].fg = d.fg;
  st.panes[pid].argv = d.argv;
  writeState(st);
  out({ id: 'cli:pane:run', result: { pane_id: pid, type: 'pane_run' } });
}

if (sub === 'pane' && a1 === 'close') {
  const st = needState();
  const pid = rest[2] || '';
  const wid = st.panes[pid] ? st.panes[pid].workspace_id : '';
  delete st.panes[pid];
  // 真 herdr：关掉 workspace 的最后一个 pane ⇒ 该 workspace 随之消失（空 workspace 不复存在）
  if (wid && !Object.keys(st.panes).some((p) => st.panes[p].workspace_id === wid)) delete st.workspaces[wid];
  writeState(st);
  out({ id: 'cli:pane:close', result: { pane_id: pid, type: 'pane_closed' } });
}

if (sub === 'pane' && a1 === 'process-info') {
  const st = needState();
  const pf = rest.indexOf('--pane');
  const pid = pf >= 0 ? rest[pf + 1] : '';
  const pane = st.panes[pid];
  if (!pane) die({ error: { code: 'pane_not_found', message: 'no pane ' + (pid || '<empty>'), detail: 'pane_not_found' } });
  out({
    id: 'cli:pane:process_info',
    result: {
      process_info: {
        foreground_process_group_id: pane.shell_pid,
        foreground_processes: [{ argv: pane.argv, cmdline: pane.cmdline || pane.argv.join(' '), cwd: pane.cwd, name: pane.fg, pid: pane.shell_pid }],
        pane_id: pid,
        shell_pid: pane.shell_pid,
      },
      type: 'pane_process_info',
    },
  });
}

if (sub === 'agent' && a1 === 'list') {
  const st = needState();
  const agents = Object.keys(st.panes).sort().map((p) => agentObj(p, st)).filter(Boolean);
  out({ result: { agents: agents, type: 'agent_list' } });
}

if (sub === 'agent' && a1 === 'explain') {
  process.stdout.write('test double: agent explain\n');
  process.exit(0);
}

if (sub === 'pane' && a1 === 'report-agent') {
  // 桩 pane 的合成入口：已接钩子权威的 pane 上真实 herdr 是静默 no-op；替身按旋钮写状态即可
  const st = needState();
  const pf = rest.indexOf('--pane');
  const pid = pf >= 0 ? rest[pf + 1] : '';
  const sf = rest.indexOf('--status');
  const stt = sf >= 0 ? rest[sf + 1] : '';
  if (pid && st.panes[pid] && stt) {
    st.knobs.pi_status = stt;
    st.knobs.pi_seq = (Number(st.knobs.pi_seq) || 0) + 1;
    writeState(st);
  }
  out({ result: { pane_id: pid, type: 'pane_agent_report' } });
}

die({ error: { code: 'unknown_command', message: 'test double 未实现：' + rest.join(' ') } });
