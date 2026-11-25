// bin/lib/orch/wal.mjs —— 派单账（WAL）+ 整 tick 独占锁 + CAS（T567-B · ADR D1/D4）
//
// 硬判据（ADR D1「防双源」）：WAL **只回答「这次派单的意图 / 时刻 / 目标」**，
//   从它**不得推断任何 row 的 `state`** —— 状态事实只在 `docs/queue.jsonl`。
//   记录类型：intent（写副作用前）· ensured（ensure 成功后拿到的真实会话身份）
//            · committed（row 已落盘为 dispatched）· aborted（环境级失败，允许下 tick 重试）
//            · nudge（追问过一次）· dispatch_unknown / recovered（恢复期结论）
// 落盘：append-only + 每条 `fsync`（崩在任一点至多丢最后一条不完整行，读取端跳过坏行并点名）。
import { openSync, writeSync, fsyncSync, closeSync, readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

export const ORCH_DIR = path.join('docs', 'queue', '.orch');

export function orchDir(root) {
  return path.join(root, ORCH_DIR);
}

export function walPath(root) {
  return path.join(orchDir(root), 'wal.jsonl');
}

export function lockPath(root) {
  return path.join(orchDir(root), 'lock');
}

export function ensureOrchDir(root) {
  mkdirSync(orchDir(root), { recursive: true });
}

export function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

// append-only + fsync：调用方必须**在写副作用之前**调用（ADR D4 三段式第一段）。
export function appendWal(file, record) {
  const line = `${JSON.stringify({ ...record, wal_at: new Date().toISOString() })}\n`;
  const fd = openSync(file, 'a');
  try {
    writeSync(fd, line);
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  return line.length;
}

export function readWal(file) {
  if (!existsSync(file)) return { records: [], bad: [] };
  const text = readFileSync(file, 'utf8');
  const records = [];
  const bad = [];
  text.split('\n').forEach((line, i) => {
    const raw = line.trim();
    if (raw === '') return;
    try {
      const obj = JSON.parse(raw);
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) records.push(obj);
      else bad.push({ line: i + 1, why: 'not-object' });
    } catch {
      bad.push({ line: i + 1, why: 'bad-json' });
    }
  });
  return { records, bad };
}

// 幂等键（ADR D4）：不含 attempt ⇒ AC7 追问后的重派必撞；不含 at ⇒ 同 attempt 的两次尝试不可分。
export function intentKey(id, attempt, atIso) {
  return `${id}#attempt=${attempt}#at=${atIso}`;
}

// 按任务号聚合 WAL：取「最近一条 intent」+ 其后最近的 ensured/aborted/committed 记录。
export function indexWal(records) {
  const byId = new Map();
  for (const r of records) {
    if (!r || typeof r.id !== 'string') continue;
    let e = byId.get(r.id);
    if (!e) {
      e = { id: r.id, intent: null, ensured: null, committed: null, aborted: null, nudges: 0, unknown: 0 };
      byId.set(r.id, e);
    }
    switch (r.type) {
      case 'intent': e.intent = r; e.ensured = null; e.aborted = null; break;
      case 'ensured': e.ensured = r; break;
      case 'committed': e.committed = r; break;
      // aborted = 环境级失败（rc=3）/ ensure 失败 ⇒ 本次意图作废，下 tick 允许重试（不是任务级 blocked）
      case 'aborted': e.aborted = r; e.intent = null; e.ensured = null; break;
      case 'nudge': e.nudges += 1; break;
      case 'dispatch_unknown': e.unknown += 1; break;
      default: break;
    }
  }
  return byId;
}

// 锁元信息（**不参与锁判定** —— 锁由内核对 fd 持有；此处只为人读「谁持锁」）。
export function writeLockInfo(file, pid, startedIso) {
  try {
    writeFileSync(file, `${pid} ${startedIso}\n`);
  } catch {
    /* 只读文件系统/竞态：持锁人信息缺失不影响锁语义 */
  }
}

export function readLockInfo(file) {
  if (!existsSync(file)) return null;
  const raw = readFileSync(file, 'utf8').trim();
  if (!raw) return null;
  const [pid, started] = raw.split(/\s+/);
  return { pid: pid || '?', started: started || '?' };
}
