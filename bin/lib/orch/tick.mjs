// bin/lib/orch/tick.mjs —— 一次性 tick（T567-B · ADR D4 · AC5–AC8）
//
// 形态（ADR D4）：**一次性 tick + systemd timer**，无常驻循环 ⇒ 没有内存态，「daemon 半死」整类消失。
// 三段式（D4）：写 intent（fsync）→ 副作用（ensure + 通知）→ 提交 row；崩在任一段由下一 tick 用 WAL 恢复。
// 铁律（PRD §六 / D4）：
//   · 目标角色 working / unknown（含 absent）⇒ **零 ensure**、只记等待（AC6）
//   · 有 intent 而 row 仍 queued ⇒ 先探（session_id + cwd）再判：命中 ⇒ 补提交；未命中 ⇒ blocked(dispatch_unknown)，**绝不自动重派**（AC8）
//   · 派单 15m 无回执 ⇒ blocked(no_ack) + 追问一次，attempt 不递增（AC7）
//   · 写盘 CAS：落盘前重读 queue.jsonl 比对 sha，变了 ⇒ rc=1 零写入（不覆盖人的编辑）
// 时钟注入：`--now <ISO>` 或 `NAO_ORCH_NOW`（AC7 的 15m 判据一律走注入时钟，**禁 sleep 等真实时间**）。
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { parseQueue, parseQueueText, validateQueue, renderRegion, spliceRegion, STATES } from '../queue.mjs';
import { fleetExec, notifyPm, gitExec, runTool } from './fleet.mjs';
import {
  walPath, lockPath, ensureOrchDir, appendWal, readWal, indexWal, intentKey, sha256,
} from './wal.mjs';

export const ACK_TIMEOUT_MS = 15 * 60 * 1000;
export const STALL_TIMEOUT_MS = 90 * 60 * 1000;
export const TICK_BUDGET_MS = 120 * 1000;
const DONE_STATES = new Set(['qa_pass', 'merging', 'merged', 'released']);

export class OrchError extends Error {}

export function resolveNow(opts = {}) {
  const raw = opts.now || process.env.NAO_ORCH_NOW || '';
  if (raw) {
    const ms = Date.parse(raw);
    if (!Number.isFinite(ms)) throw new OrchError(`时钟注入非法（--now / NAO_ORCH_NOW）：${raw}`);
    return ms;
  }
  return Date.now();
}

export function isoSeconds(ms) {
  return new Date(Math.floor(ms / 1000) * 1000).toISOString().replace('.000Z', 'Z');
}

export function resolveRoot(explicit) {
  if (explicit) return path.resolve(explicit);
  const r = gitExec(['rev-parse', '--show-toplevel']);
  if (r.rc === 0 && r.out.trim()) return r.out.trim();
  return process.cwd();
}

export function resolveCtx(opts = {}) {
  const root = resolveRoot(opts.root);
  return {
    root,
    queuePath: opts.queue ? path.resolve(opts.queue) : path.join(root, 'docs', 'queue.jsonl'),
    receiptsDir: path.join(root, 'docs', 'queue'),
    targetPath: path.join(root, 'docs', 'tasks-state.md'),
    wal: walPath(root),
    lock: lockPath(root),
  };
}

function readQueueFile(queuePath) {
  if (!existsSync(queuePath)) throw new OrchError(`队列文件不存在：${queuePath}`);
  const text = readFileSync(queuePath, 'utf8');
  const { rows, errors: parseErrors } = parseQueue(queuePath);
  const { errors, byId } = validateQueue(queuePath, rows, parseErrors);
  return { text, sha: sha256(text), rows, errors, byId };
}

// 行替换只改目标行（其余行**逐字保留**），避免整表重排把人的排版/键序冲掉。
function rewriteRow(text, id, patch) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i].trim();
    if (raw === '') continue;
    let row;
    try {
      row = JSON.parse(raw);
    } catch {
      continue;
    }
    if (!row || row.id !== id) continue;
    lines[i] = JSON.stringify({ ...row, ...patch });
    return lines.join('\n');
  }
  throw new OrchError(`队列里找不到行 ${id}（CAS 拒绝整表重写）`);
}

function casWrite(queuePath, expectedSha, nextText) {
  const current = readFileSync(queuePath, 'utf8');
  if (sha256(current) !== expectedSha) return { ok: false, why: 'queue.jsonl 在本次 tick 内被外部修改（sha 不符）⇒ 零写入' };
  writeFileSync(queuePath, nextText);
  return { ok: true, sha: sha256(nextText) };
}

function loadStatus(ctx) {
  const r = fleetExec('status', ['--json'], { repoRoot: ctx.root });
  if (r.rc === 127) return { ok: false, rc: 1, why: `nao-fleet.sh 不可达：${r.err.trim()}` };
  if (r.rc === 3) return { ok: false, rc: 3, why: 'fleet 前提不满足（rc=3：pane/socket/protocol）⇒ 环境级失败，本 tick 不写 blocked' };
  if (r.rc !== 0) return { ok: false, rc: 1, why: `nao-fleet.sh status --json 失败（rc=${r.rc}）：${r.err.trim().split('\n')[0]}` };
  let st;
  try {
    st = JSON.parse(r.out);
  } catch (e) {
    return { ok: false, rc: 1, why: `status --json 不是合法 JSON：${e.message}` };
  }
  if (!st || st.schema !== 1 || !Array.isArray(st.sessions)) {
    return { ok: false, rc: 1, why: `status --json 契约不符（schema=${st && st.schema}）` };
  }
  return { ok: true, status: st };
}

function sessionsFor(status, role) {
  return status.sessions.filter((s) => s && s.role === role);
}

function samePath(a, b) {
  if (!a || !b) return false;
  try {
    return path.resolve(a) === path.resolve(b);
  } catch {
    return false;
  }
}

// AC10（多仓不串仓）：只有「role(+task) 命中」且「repo == 本仓」的会话才是目标。
//   同名 / repo 不可判定 ⇒ **不猜**（fail-closed）：ok:false + `news` 供 journal 点名，调用方 skip + 零投递。
//   `why`：exact 命中以外 = absent（无会话）/ busy（本仓 working）/ unknown（本仓不可判）/
//          foreign（只有他仓会话）/ ambiguous（本仓多条或 repo 不可判定）。
export function selectTarget(status, role, task, repoRoot) {
  const roleHits = sessionsFor(status, role).filter((s) => s.online);
  const owned = (s) => samePath(s.repo, repoRoot);
  const exact = task ? roleHits.filter((s) => s.task === task) : [];
  const exactLocal = exact.filter(owned);
  if (exactLocal.length > 1) {
    return {
      ok: false, why: 'ambiguous', names: exactLocal.map((s) => s.name),
      news: `同名跨仓歧义：${exactLocal.map((s) => s.name).join('/')} 均在本仓且 task=${task} ⇒ 不猜、不投递`,
    };
  }
  if (exactLocal.length === 1) {
    const s = exactLocal[0];
    if (s.agent === 'working') return { ok: false, why: 'busy' };
    if (s.agent !== 'idle' || s.deliverable === false) return { ok: false, why: 'unknown' };
    return { ok: true, session: s, exact: true };
  }
  if (exact.length > 0) {
    const undecidable = exact.filter((s) => !s.repo);
    if (undecidable.length > 0) {
      return {
        ok: false, why: 'ambiguous', names: undecidable.map((s) => s.name),
        news: `同名跨仓歧义：role+task 命中但 repo 不可判定（${undecidable.map((s) => s.name).join('/')}）⇒ 不猜、不投递`,
      };
    }
    return {
      ok: false, why: 'foreign',
      news: `role+task 命中仅在他仓（${exact.map((s) => s.repo || '?').join('/')}）⇒ 不投递`,
    };
  }
  const local = roleHits.filter(owned);
  if (local.length === 0) {
    if (roleHits.length === 0) return { ok: false, why: 'absent' };
    const undecidable = roleHits.filter((s) => !s.repo);
    if (undecidable.length > 0) {
      return {
        ok: false, why: 'ambiguous', names: undecidable.map((s) => s.name),
        news: `同名跨仓歧义：role=${role} 的会话 repo 不可判定（${undecidable.map((s) => s.name).join('/')}）⇒ 不猜、不投递`,
      };
    }
    return {
      ok: false, why: 'foreign',
      news: `role=${role} 仅在他仓在线（${roleHits.map((s) => s.repo || '?').join('/')}）⇒ 不投递`,
    };
  }
  if (local.some((s) => s.agent === 'working')) return { ok: false, why: 'busy' };
  const idle = local.find((s) => s.agent === 'idle' && s.deliverable !== false);
  if (idle) return { ok: true, session: idle, exact: false };
  return { ok: false, why: 'unknown' };
}

// 角色忙闲（单仓口径，导出供诊断）：只看本仓会话，他仓 working 不阻塞本仓派单。
export function roleState(status, role, repoRoot) {
  const t = selectTarget(status, role, '', repoRoot);
  if (t.ok) return { online: true, agent: 'idle', deliverable: true, session: t.session };
  if (t.why === 'busy') return { online: true, agent: 'working', deliverable: false };
  if (t.why === 'unknown') return { online: true, agent: 'unknown', deliverable: false };
  return { online: false, agent: 'unknown', deliverable: false };
}

function findSession(status, name, cwd) {
  if (!name) return null;
  return status.sessions.find((s) => {
    if (!s || s.name !== name) return false;
    if (!s.online) return false;
    if (!cwd) return true;
    return path.resolve(s.cwd || '') === path.resolve(cwd);
  }) || null;
}

// ensure 后的真实身份：同样要求 repo == 本仓（AC10）；多条 = 歧义（调用方 fail-closed）。
function findLocalRoleTask(status, role, id, repoRoot) {
  return status.sessions.filter((s) => s && s.online && s.role === role && s.task === id && samePath(s.repo, repoRoot));
}

// 通知目标也只用本仓 pm（AC10）：0 条 ⇒ 不通知（不猜他仓）；>1 条 ⇒ 同名歧义，不通知。
function pmTarget(status, repoRoot) {
  if (!repoRoot) return null;
  const pms = status.sessions.filter((s) => s && s.online && s.role === 'pm' && samePath(s.repo, repoRoot));
  if (pms.length !== 1) return null;
  return { name: pms[0].name, cwd: pms[0].cwd || repoRoot };
}

function notify(ctx, status, text) {
  const t = pmTarget(status, ctx.root);
  if (!t) return { skipped: 'pm-offline-or-ambiguous' };
  // 消息带会话名 + cwd（PRD §十.3：禁裸名；本仓 pm 的名字可能是 pm(T900) 这类派生名）
  return notifyPm(`${text}（pm=${t.name} cwd=${t.cwd || '?'}）`, t.name);
}

// 测试注入点（**只在显式 env 下运行**）：`NAO_ORCH_HOOK` = 可执行文件，参数 = 相位名。
//   用于 AC8「intent 后、提交前被 kill -9」与 CAS「提交前队列被外部改」两类崩溃/竞态的机械复现。
function runHook(phase) {
  const hook = process.env.NAO_ORCH_HOOK;
  if (!hook) return;
  process.env.NAO_ORCH_TICK_PID = String(process.pid);
  runTool(hook, [phase], { timeout: 20_000 });
}

function receiptExists(ctx, id) {
  return existsSync(path.join(ctx.receiptsDir, `${id}.receipt.json`));
}

function depsSatisfied(row, byId) {
  const deps = Array.isArray(row.deps) ? row.deps : [];
  return deps.every((d) => {
    const dep = byId.get(d);
    return dep && DONE_STATES.has(dep.state);
  });
}

function sortRows(rows) {
  return [...rows].sort((a, b) => {
    const pa = String(a.prio);
    const pb = String(b.prio);
    if (pa !== pb) return pa < pb ? -1 : 1;
    return String(a.id) < String(b.id) ? -1 : 1;
  });
}

function renderTarget(ctx, rows) {
  if (!existsSync(ctx.targetPath)) return { rendered: false, why: 'tasks-state 不存在' };
  try {
    let text = readFileSync(ctx.targetPath, 'utf8');
    if (!text.endsWith('\n')) text += '\n';
    let next = spliceRegion(text, 'active', renderRegion('active', rows), ctx.targetPath);
    next = spliceRegion(next, 'dispatch', renderRegion('dispatch', rows), ctx.targetPath);
    if (next !== text) writeFileSync(ctx.targetPath, next);
    return { rendered: true, changed: next !== text };
  } catch (e) {
    return { rendered: false, why: e.message };
  }
}

// 恢复相位（AC8）：WAL 有 intent 而 row 仍 queued ⇒ 先探再判，**绝不自动重派**。
function recoverPhase(ctx, st, queue, wal, opts, counters) {
  const { rows, byId } = queue;
  let text = queue.text;
  let sha = queue.sha;
  for (const row of sortRows(rows)) {
    if (opts.only && row.id !== opts.only) continue;
    const rowNow = byId.get(row.id);
    if (!rowNow || rowNow.state !== 'queued') continue;
    const e = wal.get(row.id);
    if (!e || !e.intent) continue;
    const target = e.ensured
      ? { name: e.ensured.session_id, cwd: e.ensured.cwd }
      : { name: e.intent.session_id, cwd: e.intent.cwd };
    const hit = findSession(st, target.name, target.cwd);
    if (hit) {
      const next = rewriteRow(text, row.id, { state: 'dispatched', updated: opts.nowIso });
      const w = casWrite(ctx.queuePath, sha, next);
      if (!w.ok) return { rc: 1, why: w.why, text, sha };
      text = next;
      sha = w.sha;
      appendWal(ctx.wal, { type: 'recovered', id: row.id, key: e.intent.key, session_id: hit.name, cwd: hit.cwd || target.cwd });
      counters.recovered += 1;
      counters.dispatched += 1;
      continue;
    }
    const next = rewriteRow(text, row.id, { state: 'blocked', blocked_reason: 'dispatch_unknown', updated: opts.nowIso });
    const w = casWrite(ctx.queuePath, sha, next);
    if (!w.ok) return { rc: 1, why: w.why, text, sha };
    text = next;
    sha = w.sha;
    appendWal(ctx.wal, { type: 'dispatch_unknown', id: row.id, key: e.intent.key, session_id: target.name, cwd: target.cwd });
    notify(ctx, st, `orch: ${row.id} 派单未知（WAL 有 intent 但找不到会话 ${target.name} @ ${target.cwd}）⇒ blocked(dispatch_unknown)，不自动重派，请人工核对`);
    counters.blocked += 1;
  }
  return { rc: 0, text, sha };
}

// 追问相位（AC7）：派单 15m 无回执 ⇒ blocked(no_ack) + 追问一次，attempt 不变。
function ackPhase(ctx, st, queue, wal, opts, counters) {
  const { rows, byId } = queue;
  let text = queue.text;
  let sha = queue.sha;
  for (const row of sortRows(rows)) {
    if (opts.only && row.id !== opts.only) continue;
    const rowNow = byId.get(row.id);
    if (!rowNow || rowNow.state !== 'dispatched') continue;
    const at = Date.parse(rowNow.updated);
    if (!Number.isFinite(at)) continue;
    if (opts.nowMs - at < ACK_TIMEOUT_MS) continue;
    if (receiptExists(ctx, row.id)) continue;
    const e = wal.get(row.id);
    if (e && e.nudges > 0) continue;
    const next = rewriteRow(text, row.id, { state: 'blocked', blocked_reason: 'no_ack', updated: opts.nowIso });
    const w = casWrite(ctx.queuePath, sha, next);
    if (!w.ok) return { rc: 1, why: w.why, text, sha };
    text = next;
    sha = w.sha;
    appendWal(ctx.wal, { type: 'nudge', id: row.id, key: `${row.id}#no_ack`, attempt: rowNow.attempt });
    notify(ctx, st, `orch: ${row.id} 派单 15m 无回执 ⇒ blocked(no_ack)（追问一次，attempt 不递增），请核对 ${rowNow.owner} 会话`);
    counters.blocked += 1;
    counters.nudged += 1;
  }
  return { rc: 0, text, sha };
}

// 停滞相位（PRD §六 已实现口径 · 90m stalled）：working 行 + 派单 intent 距今 ≥90m + 当前 HEAD == 派单时 HEAD
//   ⇒ blocked(stalled) + 通知（与 no_ack 同口径，attempt 不递增）。
//   判据材料 = WAL intent 的 `at` + `head`（PRD §四 不新增 dispatch_at 字段）；缺 head（阶段 2 旧 WAL）⇒ 不动作。
export function gitHead(root) {
  const r = gitExec(['rev-parse', 'HEAD'], { cwd: root });
  const head = r.rc === 0 ? r.out.trim() : '';
  return /^[0-9a-f]{7,40}$/.test(head) ? head : '';
}

function stalledPhase(ctx, st, queue, wal, opts, counters) {
  const { rows, byId } = queue;
  let text = queue.text;
  let sha = queue.sha;
  const headNow = opts.head || '';
  if (!headNow) return { rc: 0, text, sha };
  for (const row of sortRows(rows)) {
    if (opts.only && row.id !== opts.only) continue;
    const rowNow = byId.get(row.id);
    if (!rowNow || rowNow.state !== 'working') continue;
    const e = wal.get(row.id);
    const intent = e && e.intent;
    if (!intent || !intent.at) continue;
    const at = Date.parse(intent.at);
    if (!Number.isFinite(at)) continue;
    if (opts.nowMs - at < STALL_TIMEOUT_MS) continue;
    if (!intent.head) continue;
    if (intent.head === headNow) {
      if (receiptExists(ctx, row.id)) continue;
      const next = rewriteRow(text, row.id, { state: 'blocked', blocked_reason: 'stalled', updated: opts.nowIso });
      const w = casWrite(ctx.queuePath, sha, next);
      if (!w.ok) return { rc: 1, why: w.why, text, sha };
      text = next;
      sha = w.sha;
      appendWal(ctx.wal, { type: 'stalled', id: row.id, key: intent.key, attempt: rowNow.attempt, head: headNow });
      notify(ctx, st, `orch: ${row.id} working 90m 且 HEAD 未变（${headNow.slice(0, 7)}）⇒ blocked(stalled)，请核对 ${rowNow.owner} 会话`);
      counters.blocked += 1;
      counters.stalled += 1;
    } else {
      // HEAD 变了 = 仓有进展（提交/合并）⇒ 不判停滞（可能正在推进），只记观测
      process.stderr.write(`orch: ${row.id} working 已超 90m 但 HEAD 已变（${String(intent.head).slice(0, 7)} → ${headNow.slice(0, 7)}）⇒ 不判 stalled\n`);
    }
  }
  return { rc: 0, text, sha };
}

// 派单相位：AC6 闸门（本仓 working/unknown ⇒ 零 ensure）+ AC10 归属闸（他仓/歧义 ⇒ 零 ensure）→ WAL intent → ensure → ensured → 提交。
function dispatchPhase(ctx, st, queue, opts, counters) {
  const { rows, byId } = queue;
  let text = queue.text;
  let sha = queue.sha;
  for (const row of sortRows(rows)) {
    if (opts.only && row.id !== opts.only) continue;
    const rowNow = byId.get(row.id);
    if (!rowNow || rowNow.state !== 'queued') continue;
    if (!depsSatisfied(rowNow, byId)) { counters.waiting += 1; continue; }
    const role = typeof rowNow.owner === 'string' ? rowNow.owner.trim() : '';
    if (!role) { counters.skipped += 1; continue; }
    // AC6 + AC10：目标必须同时满足「role(+task) 命中」与「repo == 本仓」；他仓/同名歧义 ⇒ 零 ensure、不猜。
    const sel = selectTarget(st, role, rowNow.id, ctx.root);
    if (!sel.ok) {
      if (sel.news) process.stderr.write(`orch: ${rowNow.id} 跳过（${sel.news}）\n`);
      if (sel.why === 'foreign' || sel.why === 'ambiguous') counters.skipped += 1;
      else counters.waiting += 1;
      continue;
    }
    const at = opts.nowIso;
    const key = intentKey(rowNow.id, rowNow.attempt, at);
    const predicted = `${role}(${rowNow.id})`;
    appendWal(ctx.wal, {
      type: 'intent', id: rowNow.id, key, attempt: rowNow.attempt, at, role,
      // AC11 · 90m stalled 判据材料：派单时的 HEAD（只读；内容变了说明仓有进展）
      head: opts.head || '',
      session_id: predicted, cwd: ctx.root, row_sha: sha,
      // AC10：目标 = 本仓这个会话的 name + cwd（禁裸名跨仓；WAL 留证供恢复期探测）
      target: { name: sel.session.name, cwd: sel.session.cwd || ctx.root },
      target_repo: sel.session.repo || ctx.root,
    });
    let ens;
    try {
      // `${role}@${root}` 把「哪一个仓」写进 argv（fleet 的 @<仓路径> 通道），cwd 同时锚到本仓根（双保险）
      ens = fleetExec('ensure', ['--task', rowNow.id, `${role}@${ctx.root}`], { repoRoot: ctx.root, cwd: ctx.root });
    } catch (e) {
      appendWal(ctx.wal, { type: 'aborted', id: rowNow.id, key, reason: 'ensure_argv', detail: String(e.message || e) });
      process.stderr.write(`orch: ${rowNow.id} 跳过（ensure argv 无法安全表达本仓：${e.message}）\n`);
      counters.failed += 1;
      continue;
    }
    if (ens.rc === 3) {
      appendWal(ctx.wal, { type: 'aborted', id: rowNow.id, key, reason: 'fleet_premise', rc: ens.rc });
      counters.envFail += 1;
      continue;
    }
    if (ens.rc !== 0) {
      appendWal(ctx.wal, { type: 'aborted', id: rowNow.id, key, reason: 'ensure_failed', rc: ens.rc });
      counters.failed += 1;
      continue;
    }
    // ensure 可能落槽位（`rd-infra2(T567)`）⇒ 重新取一次 status 拿真实身份（探针与 WAL 都对得上）
    const st2 = loadStatus(ctx);
    const hits = st2.ok ? findLocalRoleTask(st2.status, role, rowNow.id, ctx.root) : [];
    if (hits.length > 1) {
      appendWal(ctx.wal, {
        type: 'aborted', id: rowNow.id, key, reason: 'ambiguous_target', names: hits.map((s) => s.name),
      });
      process.stderr.write(`orch: ${rowNow.id} 跳过（同名跨仓歧义：ensure 后本仓出现 ${hits.map((s) => s.name).join('/')}）\n`);
      counters.skipped += 1;
      continue;
    }
    const real = hits[0] || null;
    const ident = real ? { name: real.name, cwd: real.cwd || ctx.root } : { name: predicted, cwd: ctx.root };
    appendWal(ctx.wal, { type: 'ensured', id: rowNow.id, key, session_id: ident.name, cwd: ident.cwd });
    runHook('before-commit');
    const next = rewriteRow(text, rowNow.id, { state: 'dispatched', updated: at });
    const w = casWrite(ctx.queuePath, sha, next);
    if (!w.ok) return { rc: 1, why: w.why, text, sha };
    text = next;
    sha = w.sha;
    appendWal(ctx.wal, { type: 'committed', id: rowNow.id, key, session_id: ident.name, cwd: ident.cwd });
    notify(ctx, st, `orch: 已派单 ${rowNow.id} → ${role}（会话 ${ident.name} cwd=${ident.cwd}）`);
    counters.dispatched += 1;
  }
  return { rc: 0, text, sha };
}

export function tick(opts = {}) {
  const ctx = resolveCtx(opts);
  ensureOrchDir(ctx.root);
  const nowMs = opts.nowMs ?? resolveNow(opts);
  const nowIso = isoSeconds(nowMs);
  const counters = {
    scanned: 0, dispatched: 0, blocked: 0, skipped: 0, waiting: 0,
    recovered: 0, nudged: 0, stalled: 0, failed: 0, envFail: 0,
  };
  const head = gitHead(ctx.root);
  let queue;
  try {
    queue = readQueueFile(ctx.queuePath);
  } catch (e) {
    return { rc: 1, counters, journal: { why: e.message } };
  }
  const { errors, byId } = queue;
  counters.scanned = byId.size;
  if (errors.length) {
    // D7：队列被手改或非法 ⇒ rc=1 零写入（不尽力而为、不渲染）
    return { rc: 1, counters, queuePath: ctx.queuePath, errors };
  }
  const st = loadStatus(ctx);
  if (!st.ok) return { rc: st.rc, counters, why: st.why };
  const wal = indexWal(readWal(ctx.wal).records);
  const opts2 = { ...opts, nowMs, nowIso, head, only: opts.only || '' };

  const r1 = recoverPhase(ctx, st.status, queue, wal, opts2, counters);
  if (r1.rc !== 0) return { rc: r1.rc, counters, why: r1.why };
  const q1 = { ...queue, text: r1.text, sha: r1.sha };
  // 提交后行状态已变：重读表格视图（只用于判定，不再落盘）
  const q1View = { ...readRowsFromText(q1.text), sha: q1.sha };
  const r2 = ackPhase(ctx, st.status, q1View, wal, opts2, counters);
  if (r2.rc !== 0) return { rc: r2.rc, counters, why: r2.why };
  const q2 = { ...q1, text: r2.text, sha: r2.sha };
  const q2View = { ...readRowsFromText(q2.text), sha: q2.sha };
  const r3 = stalledPhase(ctx, st.status, q2View, wal, opts2, counters);
  if (r3.rc !== 0) return { rc: r3.rc, counters, why: r3.why };
  const q3 = { ...q2, text: r3.text, sha: r3.sha };
  const q3View = { ...readRowsFromText(q3.text), sha: q3.sha };
  const r4 = dispatchPhase(ctx, st.status, q3View, opts2, counters);
  if (r4.rc !== 0) return { rc: r4.rc, counters, why: r4.why };
  const render = renderTarget(ctx, readRowsFromText(r4.text).rows);
  return { rc: 0, counters, render, queuePath: ctx.queuePath, walPath: ctx.wal };
}

// 内存视图：文本 → 行（不落盘）
function readRowsFromText(text) {
  const rows = [];
  const byId = new Map();
  for (const line of text.split('\n')) {
    const raw = line.trim();
    if (!raw) continue;
    let row;
    try {
      row = JSON.parse(raw);
    } catch {
      continue;
    }
    if (!row || typeof row.id !== 'string') continue;
    rows.push(row);
    byId.set(row.id, row);
  }
  return { rows, byId, text };
}

export function journalLine(ctx, nowIso, counters, rc) {
  const repo = path.basename(ctx.root);
  return `orch tick=${nowIso} repo=${repo} scanned=${counters.scanned} dispatched=${counters.dispatched} blocked=${counters.blocked} stalled=${counters.stalled} skipped=${counters.skipped} waiting=${counters.waiting} recovered=${counters.recovered} nudged=${counters.nudged} rc=${rc}`;
}

// ---------------------------------------------------------------- board / reap

// 回执摘要（只读 `docs/queue/*.receipt.json`）：坏 JSON 只计数（board 不是 validator，判红归 nao-queue）。
export function readReceipts(ctx) {
  const out = { total: 0, ids: [], latest: [], unreadable: 0 };
  if (!existsSync(ctx.receiptsDir)) return out;
  let names = [];
  try {
    names = readdirSync(ctx.receiptsDir).filter((f) => f.endsWith('.receipt.json')).sort();
  } catch {
    return out;
  }
  for (const f of names) {
    const file = path.join(ctx.receiptsDir, f);
    let obj;
    try {
      obj = JSON.parse(readFileSync(file, 'utf8'));
    } catch {
      out.unreadable += 1;
      continue;
    }
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
      out.unreadable += 1;
      continue;
    }
    out.total += 1;
    const id = typeof obj.id === 'string' && obj.id ? obj.id : f.slice(0, -'.receipt.json'.length);
    out.ids.push(id);
    const gates = obj.gates && typeof obj.gates === 'object' ? obj.gates : {};
    const rcOf = (g) => (g && Number.isFinite(g.rc) ? g.rc : null);
    const acs = Array.isArray(obj.acs) ? obj.acs : [];
    out.latest.push({
      id,
      author: typeof obj.author === 'string' ? obj.author : '',
      at: typeof obj.at === 'string' ? obj.at : '',
      head: typeof obj.head === 'string' ? obj.head : '',
      pushed: obj.pushed === true,
      gates: { check: rcOf(gates.check), full: rcOf(gates.full) },
      acs: acs.length,
    });
  }
  out.latest.sort((a, b) => {
    if (String(a.at) !== String(b.at)) return String(a.at) < String(b.at) ? 1 : -1;
    return String(a.id) < String(b.id) ? -1 : 1;
  });
  return out;
}

// AC11：board 的数值与 queue.jsonl **同 tick 快照**。硬实现 = 队列文本只读一次（下面的 readFileSync），
//   之后的行/计数/任务全从这份 text 派生；测试在 `board-after-queue` 钩子里改队列文件 ⇒ 输出必须不变。
//   禁落盘、禁缓存：不 mkdir `.orch`、不写任何文件（第二事实源 = 违规）。
export function board(opts = {}) {
  const ctx = resolveCtx(opts);
  const nowMs = opts.nowMs ?? resolveNow(opts);
  if (!existsSync(ctx.queuePath)) return { rc: 1, errors: [`队列文件不存在：${ctx.queuePath}`] };
  const text = readFileSync(ctx.queuePath, 'utf8');
  runHook('board-after-queue');
  const parsed = parseQueueText(ctx.queuePath, text);
  const { errors } = validateQueue(ctx.queuePath, parsed.rows, parsed.errors);
  if (errors.length) return { rc: 1, errors };
  const walRead = readWal(ctx.wal);
  const wal = indexWal(walRead.records);
  const tasks = sortRows(parsed.rows).map((r) => {
    const at = Date.parse(r.updated);
    const ageMin = Number.isFinite(at) ? Math.max(0, Math.round((nowMs - at) / 60000)) : null;
    const e = wal.get(r.id);
    return {
      id: r.id, title: r.title, state: r.state, owner: r.owner, qa: r.qa, prio: r.prio,
      deps: Array.isArray(r.deps) ? r.deps : [], attempt: r.attempt, updated: r.updated, age_min: ageMin,
      blocked_reason: r.blocked_reason || '',
      wal: e && e.intent ? 'intent' : e && e.committed ? 'committed' : '',
      repo: r.repo, branch: r.branch,
    };
  });
  // digits = 状态表全集（缺项补 0）：形状稳定，调用方不必判「键在不在」
  const digits = {};
  for (const s of STATES) digits[s] = 0;
  for (const r of tasks) if (Object.prototype.hasOwnProperty.call(digits, r.state)) digits[r.state] += 1;
  return {
    rc: 0, ctx, tickAt: isoSeconds(nowMs), tasks, digits,
    receipts: readReceipts(ctx), walBad: walRead.bad,
  };
}

export function reap(opts = {}) {
  const ctx = resolveCtx(opts);
  const queue = readQueueFile(ctx.queuePath);
  if (queue.errors.length) return { rc: 1, errors: queue.errors };
  const { records, bad } = readWal(ctx.wal);
  const wal = indexWal(records);
  const terminal = new Set(['merged', 'released']);
  const out = [];
  for (const [id, e] of wal) {
    const row = queue.byId.get(id);
    if (!row) out.push({ id, why: '队列已无此行（WAL 孤儿意图，人工核对后可忽略）', key: e.intent && e.intent.key });
    else if (terminal.has(row.state)) out.push({ id, why: `状态 ${row.state}（终态）仍留 WAL 记录`, key: (e.intent && e.intent.key) || '' });
  }
  return { rc: 0, ctx, reapable: out, walBad: bad, records: records.length };
}
