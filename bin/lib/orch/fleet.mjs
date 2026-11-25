// bin/lib/orch/fleet.mjs —— orch 的**唯一外部执行面**（T567-B · ADR D5 · AC9）
//
// 结构层闸（AC9①）：`child_process` 只出现在本文件（tests/t4/cases/47 静态断言）；
//   全部调用走 `execFile` + argv 数组 + 固定命令名，**零 shell**、零字符串拼命令 ⇒
//   队列里的任何字符串都不可能变成命令（最多成为一个 argv 元素，且先过 token 白名单）。
//
// 四个入口（都只接受 argv 数组）：
//   fleetExec(sub, argv)      nao-fleet.sh 子命令白名单：status / ensure / close / session-start
//   notifyPm(msg, to)         intercom 通知（文本作为**单个 argv** 传递；无 to ⇒ 跳过，返回 skipped）
//   flockExec(argv)           固定命令 = flock（tick 独占锁；内核对 fd 释锁 ⇒ 无 stale 锁）
//   gitExec(argv) / runTool() 固定命令 = git / systemctl 等只读工具（子命令白名单在调用点收窄）
import { execFileSync } from 'node:child_process';
import { accessSync, constants } from 'node:fs';
import path from 'node:path';

// 旗标声明 = 白名单本身：`value` 需一个已校验参数，`bool` 不接受参数（禁「旗标吃位置参数」这类歧义）。
const FLEET_SUBS = new Map([
  ['status', { flags: new Map([['--json', 'bool']]), max: 2 }],
  ['ensure', { flags: new Map([['--task', 'value'], ['--force', 'bool']]), max: 4 }],
  ['close', { flags: new Map([['--task', 'value'], ['--force', 'bool']]), max: 4 }],
  ['session-start', { flags: new Map([['--session', 'value']]), max: 2 }],
]);

// argv 元素白名单：会话名/角色/任务号/时间戳/路径都落在这里；控制字符/换行/引号一律拒（无 shell，但仍收窄）。
const SAFE_TOKEN = /^[A-Za-z0-9._:@()/+-]+$/;

export class FleetError extends Error {}

function assertToken(value, what) {
  if (typeof value !== 'string' || value === '' || !SAFE_TOKEN.test(value)) {
    throw new FleetError(`${what} 非法（只允许 [A-Za-z0-9._:@()/+-]+）：${JSON.stringify(value)}`);
  }
  return value;
}

function checkFleetArgv(sub, argv) {
  const spec = FLEET_SUBS.get(sub);
  if (!spec) throw new FleetError(`子命令不在白名单：${JSON.stringify(sub)}（允许：${[...FLEET_SUBS.keys()].join('/')}）`);
  if (!Array.isArray(argv)) throw new FleetError('argv 必须是数组（禁字符串拼命令）');
  if (argv.length > spec.max) throw new FleetError(`${sub} 的参数过多（${argv.length} > ${spec.max}）`);
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (typeof a !== 'string') throw new FleetError(`${sub} argv[${i}] 必须是字符串`);
    if (a.startsWith('-')) {
      const kind = spec.flags.get(a);
      if (!kind) throw new FleetError(`${sub} 不接受旗标 ${a}（允许：${[...spec.flags.keys()].join('/')}）`);
      if (kind !== 'value') continue;
      if (i + 1 >= argv.length) throw new FleetError(`${sub} 的 ${a} 缺少参数值`);
      assertToken(argv[i + 1], `${sub} ${a} 的值`);
      i += 1;
      continue;
    }
    assertToken(a, `${sub} 的位置参数`);
  }
  return true;
}

// fleet 可执行文件解析：显式 env（测试/下游覆盖）> PATH > 机制包内路径。都不在 ⇒ 返回 null（调用方 rc=1，零写入）。
export function resolveFleet(repoRoot) {
  const explicit = process.env.NAO_ORCH_FLEET;
  if (explicit) {
    try {
      accessSync(explicit, constants.X_OK);
      return explicit;
    } catch {
      return null;
    }
  }
  for (const dir of (process.env.PATH || '').split(':')) {
    if (!dir) continue;
    const cand = path.join(dir, 'nao-fleet.sh');
    try {
      accessSync(cand, constants.X_OK);
      return cand;
    } catch {
      /* 继续找 */
    }
  }
  if (repoRoot) {
    const cand = path.join(repoRoot, '.agents', 'scripts', 'nao-fleet.sh');
    try {
      accessSync(cand, constants.X_OK);
      return cand;
    } catch {
      /* 继续找 */
    }
  }
  return null;
}

function runArgv(cmd, argv, opts = {}) {
  const timeout = opts.timeout || 30_000;
  try {
    const out = execFileSync(cmd, argv, {
      encoding: 'utf8',
      timeout,
      maxBuffer: 8 * 1024 * 1024,
      stdio: opts.stdio || ['ignore', 'pipe', 'pipe'],
      env: opts.env || process.env,
      // cwd 显式透传（AC10：orch 绑一仓 ⇒ 子进程的仓归属锚点 = 本仓根，不依赖调用方 cwd）
      ...(opts.cwd ? { cwd: opts.cwd } : {}),
    });
    return { rc: 0, out: out || '', err: '' };
  } catch (e) {
    const rc = typeof e.status === 'number' ? e.status : 1;
    const out = typeof e.stdout === 'string' ? e.stdout : '';
    const err = typeof e.stderr === 'string' ? e.stderr : String(e.message || '');
    return { rc, out, err: e.code === 'ENOENT' ? `命令不可达：${cmd}` : err };
  }
}

// 唯一 fleet 出口（AC9①）：白名单 + argv-only + 单次硬超时 30s。
export function fleetExec(sub, argv = [], opts = {}) {
  checkFleetArgv(sub, argv);
  const cmd = opts.command || resolveFleet(opts.repoRoot);
  if (!cmd) return { rc: 127, out: '', err: 'nao-fleet.sh 不可达（PATH 与机制包内路径都没有）' };
  return runArgv(cmd, [sub, ...argv], { timeout: opts.timeout ?? 30_000, cwd: opts.cwd });
}

// intercom 通知（PRD §十.3）：命令 = `pi-intercom`（PATH）或 env 显式指定；消息整体作为一个 argv。
//   失败不影响 tick 结论（ADR D7：journald + queue.jsonl 留证即可），只回报状态供日志。
export function notifyPm(text, to, opts = {}) {
  if (!to) return { rc: 0, out: '', err: '', skipped: 'no-target' };
  const cmd = opts.command || process.env.NAO_ORCH_NOTIFY || null;
  if (!cmd) return { rc: 0, out: '', err: '', skipped: 'no-notifier' };
  const argv = ['send', '--to', assertToken(to, 'notify --to'), '--text', String(text)];
  return runArgv(cmd, argv, { timeout: opts.timeout ?? 10_000 });
}

export function flockExec(argv, opts = {}) {
  if (!Array.isArray(argv)) throw new FleetError('flock argv 必须是数组');
  return runArgv('flock', argv, { timeout: opts.timeout || 0, stdio: opts.stdio, env: opts.env });
}

export function gitExec(argv, opts = {}) {
  if (!Array.isArray(argv)) throw new FleetError('git argv 必须是数组');
  return runArgv('git', argv, { timeout: opts.timeout ?? 10_000 });
}

export function runTool(cmd, argv, opts = {}) {
  if (!Array.isArray(argv)) throw new FleetError('argv 必须是数组');
  return runArgv(cmd, argv, { timeout: opts.timeout ?? 15_000 });
}
