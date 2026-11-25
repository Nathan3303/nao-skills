// bin/lib/orch/systemd.mjs —— doctor + systemd 单元安装/卸载（T567-B · ADR D6）
//
// 形态：`Type=oneshot` service（ExecStart = <node> <bin/nao-orch> tick，TimeoutStartSec=120）
//   + timer（`OnCalendar=*:0/<interval>` · `Persistent=true` · `RandomizedDelaySec=15s`）。
//   为什么是日历式 + Persistent：`Persistent=` 只对 `OnCalendar=` 生效 —— 关机/休眠错过的 tick 要补跑。
// 三条硬约束：
//   ① 安装前先跑 doctor（node/herdr/pi/git/flock 可达 · fleet status --json rc=0（内含 protocol=22 闸门）·
//      队列可校验 · 非 git 仓直接拒）；任一失败 ⇒ **不 enable** 且 exit 3。
//   ② 幂等：内容 sha 相同 ⇒ 不写盘、不 daemon-reload；连装两次 `diff -r` 为空。
//   ③ 默认**不 enable / 不启用**（阶段 2 默认关闭，ADR D6 / PRD §九）；显式 `--enable` 才 enable。
// 自定义 journal 字段需原生协议 ⇒ 零依赖下不做：程序读面 = `nao-orch board --json`。
import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { parseQueue, validateQueue } from '../queue.mjs';
import { resolveFleet, fleetExec, runTool, flockExec, gitExec } from './fleet.mjs';
import { resolveCtx } from './tick.mjs';

function which(cmd) {
  for (const d of (process.env.PATH || '').split(':')) {
    if (!d) continue;
    const c = path.join(d, cmd);
    try {
      if (existsSync(c)) return c;
    } catch {
      /* 继续 */
    }
  }
  return null;
}

function xdgConfigHome() {
  return process.env.XDG_CONFIG_HOME || path.join(process.env.HOME || '', '.config');
}

export function validateQueueOnly(ctx) {
  if (!existsSync(ctx.queuePath)) return { ok: false, why: `队列文件不存在：${ctx.queuePath}` };
  const { rows, errors: parseErrors } = parseQueue(ctx.queuePath);
  const { errors } = validateQueue(ctx.queuePath, rows, parseErrors);
  if (errors.length) return { ok: false, why: `队列不可校验（${errors.length} 项）：${errors[0]}` };
  return { ok: true, rows: rows.length };
}

// doctor：返回 {ok, lines[], fleet} —— 逐项点名，任一项 fail ⇒ ok=false（安装侧据此 exit 3 且不 enable）
export function doctor(opts = {}) {
  const ctx = resolveCtx(opts);
  const lines = [];
  let ok = true;
  const add = (good, key, detail) => {
    lines.push(`doctor: ${good ? 'ok' : 'fail'} ${key}=${detail}`);
    if (!good) ok = false;
  };

  const major = Number(process.versions.node.split('.')[0]);
  add(major >= 18, 'node', `${process.execPath} v${process.versions.node}`);

  for (const k of ['git', 'flock']) {
    const p = which(k);
    add(Boolean(p), k, p || '不可达（PATH 内没有）');
  }
  // herdr / pi：缺失只影响 tick 能否真的派单 ⇒ 同样判 fail（doctor 是安装闸门）
  for (const k of ['herdr', 'pi']) {
    const p = which(k);
    add(Boolean(p), k, p || '不可达（PATH 内没有）');
  }

  const toplevel = gitExec(['rev-parse', '--show-toplevel']);
  const isRepo = toplevel.rc === 0 && toplevel.out.trim() !== '';
  add(isRepo, 'repo', isRepo ? toplevel.out.trim() : '不在 git 仓内（拒绝安装：WorkingDirectory 无法锚定）');

  const q = validateQueueOnly(ctx);
  add(q.ok, 'queue', q.ok ? `${ctx.queuePath}（${q.rows} 行）` : q.why);

  const fleetPath = resolveFleet(ctx.root);
  add(Boolean(fleetPath), 'fleet', fleetPath || 'nao-fleet.sh 不可达（PATH 与机制包内路径都没有）');

  // protocol=22 / pane / socket 三件套的判据 = fleet status 的 rc 语义（term_require 内含），此处不重复实现。
  let statusOk = false;
  let statusDetail = 'fleet 不可达，未探测';
  if (fleetPath) {
    const r = fleetExec('status', ['--json'], { repoRoot: ctx.root });
    if (r.rc === 0) {
      try {
        const j = JSON.parse(r.out);
        statusOk = j && j.schema === 1 && Array.isArray(j.sessions);
        statusDetail = statusOk ? `schema=1 sessions=${j.sessions.length}` : `契约不符（schema=${j && j.schema}）`;
      } catch (e) {
        statusDetail = `不是合法 JSON：${e.message}`;
      }
    } else if (r.rc === 3) {
      statusDetail = 'rc=3 前提不满足（pane/socket/protocol 任一不达）';
    } else {
      statusDetail = `rc=${r.rc} ${r.err.trim().split('\n')[0]}`;
    }
  }
  add(statusOk, 'status-json', statusDetail);

  // 通知器（不阻断安装，但必须可见）：未设 ⇒ orch 只写 journald + queue.jsonl，不调 intercom
  const notifier = process.env.NAO_ORCH_NOTIFY || '';
  if (notifier) add(true, 'notify', notifier);
  else lines.push('doctor: warn notify=未设（blocked/追问通知只落 journald + queue.jsonl；要唤醒 PM 请设 NAO_ORCH_NOTIFY 后重装）');

  // lock 可用性（flock 二进制存在时才算；不能仅凭 binary 存在就假定内核允许）
  const lk = flockExec(['--version']);
  add(lk.rc === 0, 'flock-runtime', lk.rc === 0 ? lk.out.trim().split('\n')[0] : `rc=${lk.rc}`);

  return { ok, lines, ctx, fleetPath };
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function renderUnit(template, vars) {
  let out = template;
  for (const [k, v] of Object.entries(vars)) out = out.split(`@${k}@`).join(v);
  return out;
}

function environmentLines(session) {
  const dirs = [];
  for (const d of [path.dirname(process.execPath), ...(process.env.PATH || '').split(':')]) {
    if (d && !dirs.includes(d)) dirs.push(d);
  }
  const lines = [`Environment=PATH=${dirs.join(':')}`, `Environment=NAO_ORCH_NODE=${process.execPath}`];
  // 通知器：安装时若已设 NAO_ORCH_NOTIFY（绝对路径、无空白字符）就写进 unit ——
  //   否则 timer 环境里没有它，blocked/追问通知就只剩 journald + queue.jsonl 留证。
  const notifier = process.env.NAO_ORCH_NOTIFY || '';
  if (/^\/[^\s]*$/.test(notifier)) lines.push(`Environment=NAO_ORCH_NOTIFY=${notifier}`);
  if (session) {
    lines.push('Environment=HERDR_ENV=1', `Environment=HERDR_SESSION=${session}`);
    // socket 由 herdr 私有根发现（不猜会话名；找不到就不写，doctor/日志会点名）
    const sockDir = path.join(xdgConfigHome(), 'herdr', 'sessions', session);
    let sock = null;
    try {
      const cand = readdirSync(sockDir).filter((f) => f.endsWith('.sock')).map((f) => path.join(sockDir, f));
      if (cand.length === 1) sock = cand[0];
    } catch {
      sock = null;
    }
    if (sock) lines.push(`Environment=HERDR_SOCKET_PATH=${sock}`);
  }
  return lines.join('\n');
}

function systemctl(args) {
  return runTool('systemctl', ['--user', ...args], { timeout: 20_000 });
}

export function installSystemd(opts = {}) {
  const dr = doctor(opts);
  if (!dr.ok) return { rc: 3, doctor: dr, why: 'doctor 未过 ⇒ 不写单元、不 enable（exit 3）' };
  const interval = String(opts.interval || '2');
  if (!/^[1-9][0-9]?$/.test(interval) || Number(interval) > 60) {
    return { rc: 2, why: `--interval 非法：${interval}（1..60 分钟）` };
  }
  const srcDir = path.join(dr.ctx.root, '.agents', 'systemd');
  const svcTpl = readFileSync(path.join(srcDir, 'nao-orch.service.in'), 'utf8');
  const tmrTpl = readFileSync(path.join(srcDir, 'nao-orch.timer.in'), 'utf8');
  const vars = {
    NODE: process.execPath,
    ORCH: path.join(dr.ctx.root, 'bin', 'nao-orch'),
    WORKDIR: dr.ctx.root,
    INTERVAL: interval,
    ENVIRONMENT: environmentLines(opts.session || ''),
  };
  const units = [
    ['nao-orch.service', renderUnit(svcTpl, vars)],
    ['nao-orch.timer', renderUnit(tmrTpl, vars)],
  ];
  const dir = path.join(xdgConfigHome(), 'systemd', 'user');
  mkdirSync(dir, { recursive: true });
  let changed = 0;
  for (const [name, body] of units) {
    const file = path.join(dir, name);
    const prev = existsSync(file) ? readFileSync(file, 'utf8') : null;
    if (prev !== null && sha256(prev) === sha256(body)) continue; // 幂等：内容相同 ⇒ 不写盘
    writeFileSync(file, body);
    changed += 1;
  }
  let reloaded = false;
  let enabled = false;
  if (changed > 0) {
    const r = systemctl(['daemon-reload']);
    reloaded = r.rc === 0;
  }
  if (opts.enable) {
    const r = systemctl(['enable', '--now', 'nao-orch.timer']);
    enabled = r.rc === 0;
    if (!enabled) return { rc: 3, doctor: dr, units: dir, changed, why: `systemctl enable 失败：${r.err.trim() || `rc=${r.rc}`}` };
    if (opts.linger) runTool('loginctl', ['enable-linger'], { timeout: 20_000 });
  }
  return { rc: 0, doctor: dr, units: dir, changed, reloaded, enabled };
}

export function uninstallSystemd(opts = {}) {
  const dir = path.join(xdgConfigHome(), 'systemd', 'user');
  const files = ['nao-orch.timer', 'nao-orch.service'].map((n) => path.join(dir, n));
  const present = files.filter((f) => existsSync(f));
  if (present.length === 0) return { rc: 0, units: dir, removed: 0, note: '未安装（幂等：无作用）' };
  systemctl(['disable', '--now', 'nao-orch.timer']); // 先停/禁用；未 enable 时 rc≠0 不算失败（幂等）
  for (const f of present) {
    try {
      unlinkSync(f);
    } catch {
      /* 已消失 */
    }
  }
  systemctl(['daemon-reload']);
  return { rc: 0, units: dir, removed: present.length };
}
