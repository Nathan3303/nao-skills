// bin/lib/queue.mjs —— 队列/回执契约的纯函数单一事实源（T567-B · ADR D1）
//
// 引入方：`bin/nao-queue`（CLI，阶段 1）与 `bin/nao-orch`（tick，阶段 2）**同引本模块**。
// 硬判据（ADR D1）：状态表 / 字段表 / 校验 / 渲染只在这里定义一次 —— 复制到任一 CLI = 状态机双源 = 违规。
// 零依赖 / 零网络（唯一外部副作用 = `verifyPushed` 的 `git ls-remote`，由 CLI 用 --no-push-check 显式跳过）。
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

// 状态机（PRD §四 逐字）：queued → dispatched → working → qa → (qa_fail → working) → qa_pass → merging → merged → released
//   `blocked` 入口 = no_ack(15m，派单后) / stalled(90m，working 中) / attempt>2（qa 侧）
//                   / dispatch_unknown（T567-B：WAL 有派单意图但探不到目标会话 ⇒ 冻结 + 交人，禁自动重派）。
//   `blocked → queued` = 人工看原因后重新排队（PRD 未逐字定义出口；取最小可恢复出口，单点在本表）。
//   **唯一事实源**：`bin/nao-queue` 与 `bin/nao-orch` 都从这里取（复制本表 = 双源 = 违规，ADR D1）。
const STATES = ['queued', 'dispatched', 'working', 'qa', 'qa_fail', 'qa_pass', 'merging', 'merged', 'released', 'blocked'];
const TRANSITIONS = {
  // T567-B 契约补记（ADR D4）：`queued → blocked` = 派单意图已落盘、但恢复期探不到目标会话
  //   （dispatch_unknown）⇒ 冻结交人。没有这条边，恢复只能「重派」或「留一个无人知道的 queued」。
  queued: ['dispatched', 'blocked'],
  dispatched: ['working', 'blocked'],
  working: ['qa', 'blocked'],
  qa: ['qa_pass', 'qa_fail', 'blocked'],
  qa_fail: ['working', 'blocked'],
  qa_pass: ['merging', 'blocked'],
  merging: ['merged', 'blocked'],
  merged: ['released'],
  released: [],
  blocked: ['queued'],
};
// 渲染分区：待派发 = 还没派出去；进行中 = 在飞或等人处理；merged/released 归人写归档墙（不渲染）。
const REGION_STATES = {
  dispatch: ['queued'],
  active: ['dispatched', 'working', 'qa', 'qa_fail', 'qa_pass', 'merging', 'blocked'],
};
const MARKER_BEGIN = (r) => `<!-- nao-queue:begin ${r} -->`;
const MARKER_END = (r) => `<!-- nao-queue:end ${r} -->`;
const GENERATED_HEAD = '<!-- generated: 由 `bin/nao-queue render` 生成 · 唯一事实源 `docs/queue.jsonl` · 禁手改（下次渲染会覆盖） -->';

const QUEUE_FIELDS = [
  'id', 'kind', 'title', 'state', 'prio', 'deps', 'repo', 'branch',
  'owner', 'qa', 'acs', 'attempt', 'created', 'updated', 'blocked_reason',
];
const RECEIPT_FIELDS = ['id', 'author', 'at', 'head', 'pushed', 'gates', 'acs', 'blocked', 'artifacts', 'deviation'];
const DATE_RE = /^\d{4}-\d{2}-\d{2}(?:[T ][0-9:.]+(?:Z|[+-][0-9:]{2,5})?)?$/;
const SHA_RE = /^[0-9a-f]{7,40}$/;

class UsageError extends Error {}
function readText(p, what) {
  if (!existsSync(p)) throw new UsageError(`${what} 不存在：${p}`);
  return readFileSync(p, 'utf8');
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function typeOf(v) {
  if (v === null) return 'null';
  return Array.isArray(v) ? 'array' : typeof v;
}

function short(v) {
  const s = JSON.stringify(v);
  return s === undefined ? String(v) : s.length > 60 ? `${s.slice(0, 57)}...` : s;
}

// ---------------------------------------------------------------- 队列解析 / 校验

function parseQueue(file) {
  const text = readText(file, '队列文件');
  const rows = [];
  const errors = [];
  text.split('\n').forEach((line, i) => {
    const raw = line.trim();
    if (raw === '') return;
    let row;
    try {
      row = JSON.parse(raw);
    } catch (e) {
      errors.push(`${file}:${i + 1}: 不是合法 JSON（${e.message}）`);
      return;
    }
    if (!isPlainObject(row)) {
      errors.push(`${file}:${i + 1}: 一行必须是 JSON 对象（实际 ${typeOf(row)}）`);
      return;
    }
    row.__loc = `${file}:${i + 1}`;
    rows.push(row);
  });
  return { rows, errors };
}

const nonEmptyString = (v) => typeof v === 'string' && v.trim() !== '';

function validateQueue(file, rows, parseErrors) {
  const errors = [...parseErrors];
  const byId = new Map();
  for (const r of rows) {
    const where = r.__loc;
    for (const f of QUEUE_FIELDS) {
      if (!(f in r)) errors.push(`${where}: 缺少必需字段 \`${f}\``);
    }
    if (!nonEmptyString(r.id)) {
      errors.push(`${where}: id 必须是非空字符串`);
      continue;
    }
    if (!/^[A-Za-z0-9._-]+$/.test(r.id)) errors.push(`${where}: id 只允许 [A-Za-z0-9._-]（实际 ${short(r.id)}）`);
    if (byId.has(r.id)) errors.push(`${where}: id 重复（${r.id}，先见 ${byId.get(r.id).__loc}）`);
    else byId.set(r.id, r);

    for (const f of ['kind', 'title', 'prio', 'repo', 'branch']) {
      if (f in r && !nonEmptyString(r[f])) errors.push(`${where}: \`${f}\` 必须是非空字符串（实际 ${short(r[f])}）`);
    }
    for (const f of ['owner', 'qa', 'blocked_reason']) {
      if (f in r && typeof r[f] !== 'string') errors.push(`${where}: \`${f}\` 必须是字符串（实际 ${typeOf(r[f])}）`);
    }
    if (typeof r.state !== 'string' || !STATES.includes(r.state)) {
      errors.push(`${where}: state 取值非法（${short(r.state)}；合法值 ${STATES.join('/')}）`);
    }
    if (!Number.isInteger(r.attempt) || r.attempt < 0) errors.push(`${where}: attempt 必须是 >=0 的整数（实际 ${short(r.attempt)}）`);
    if ('attempt' in r && Number.isInteger(r.attempt) && r.attempt > 2 && r.state !== 'blocked') {
      errors.push(`${where}: attempt=${r.attempt} > 2 ⇒ state 必须是 blocked（PRD §四：attempt>2 进入 blocked）`);
    }
    if (r.state === 'blocked' && !nonEmptyString(r.blocked_reason)) {
      errors.push(`${where}: state=blocked 时必须写 blocked_reason（PRD：blocked 保留原因）`);
    }
    if (r.state !== 'blocked' && nonEmptyString(r.blocked_reason)) {
      errors.push(`${where}: state=${r.state} 却写了 blocked_reason（只有 blocked 才带原因）`);
    }
    for (const f of ['deps', 'acs']) {
      if (!Array.isArray(r[f])) {
        if (f in r) errors.push(`${where}: \`${f}\` 必须是数组（实际 ${typeOf(r[f])}）`);
        continue;
      }
      for (const item of r[f]) {
        if (!nonEmptyString(item)) errors.push(`${where}: \`${f}\` 的条目必须是非空字符串（实际 ${short(item)}）`);
      }
      if (new Set(r[f]).size !== r[f].length) errors.push(`${where}: \`${f}\` 内有重复条目`);
    }
    if (Array.isArray(r.deps) && r.deps.includes(r.id)) errors.push(`${where}: deps 不得依赖自身（${r.id}）`);
    for (const f of ['created', 'updated']) {
      if (f in r && !DATE_RE.test(String(r[f]))) errors.push(`${where}: \`${f}\` 必须是 YYYY-MM-DD 或 ISO 时间（实际 ${short(r[f])}）`);
    }
    if (typeof r.owner === 'string' && r.state && REGION_STATES.active.includes(r.state) && r.owner.trim() === '') {
      errors.push(`${where}: state=${r.state}（在飞）时 owner 必须非空`);
    }
  }
  // deps 必须指向本队列里的任务（单一事实源 ⇒ 依赖不能悬空）
  for (const r of rows) {
    if (!Array.isArray(r.deps)) continue;
    for (const d of r.deps) {
      if (nonEmptyString(d) && !byId.has(d)) errors.push(`${r.__loc}: deps 指向不存在的任务 ${d}`);
    }
  }
  return { errors, byId };
}

// ---------------------------------------------------------------- 渲染

function cmpRow(a, b) {
  const pa = String(a.prio), pb = String(b.prio);
  if (pa !== pb) return pa < pb ? -1 : 1;
  return String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0;
}

function formatRow(r) {
  const deps = Array.isArray(r.deps) && r.deps.length ? r.deps.join(',') : '-';
  const acs = Array.isArray(r.acs) && r.acs.length ? r.acs.join(',') : '-';
  const parts = [
    `- **${r.id}**`,
    `${r.state}`,
    String(r.title),
    `prio=${r.prio}`,
    `owner=${nonEmptyString(r.owner) ? r.owner : '-'}`,
    `qa=${nonEmptyString(r.qa) ? r.qa : '-'}`,
    `deps=${deps}`,
    `acs=${acs}`,
    `attempt=${r.attempt}`,
    `branch=${r.branch}`,
    `updated=${r.updated}`,
  ];
  if (nonEmptyString(r.blocked_reason)) parts.push(`blocked_reason=${r.blocked_reason}`);
  return parts.join(' · ');
}

function renderRegion(region, rows) {
  const lines = [GENERATED_HEAD];
  const picked = rows.filter((r) => REGION_STATES[region].includes(r.state)).sort(cmpRow);
  if (picked.length === 0) lines.push('- （空）');
  for (const r of picked) lines.push(formatRow(r));
  return lines.join('\n');
}

function spliceRegion(text, region, body, file) {
  const begin = MARKER_BEGIN(region);
  const end = MARKER_END(region);
  const i = text.indexOf(begin);
  const j = text.indexOf(end);
  if (i < 0 || j < 0) throw new UsageError(`目标文件 ${file} 缺少标记 ${begin} / ${end}（标记缺失不静默追加）`);
  if (text.indexOf(begin, i + 1) >= 0 || text.indexOf(end, j + 1) >= 0) throw new UsageError(`目标文件 ${file} 的标记 ${begin} / ${end} 重复`);
  if (j < i) throw new UsageError(`目标文件 ${file} 的标记顺序错（end 在 begin 之前）`);
  return `${text.slice(0, i + begin.length)}\n${body}\n${text.slice(j)}`;
}

function firstDiffLines(a, b, limit = 12) {
  const la = a.split('\n');
  const lb = b.split('\n');
  const out = [];
  const max = Math.max(la.length, lb.length);
  let shown = 0;
  for (let i = 0; i < max && shown < limit; i += 1) {
    if (la[i] !== lb[i]) {
      out.push(`  行 ${i + 1}: 当前=${la[i] === undefined ? '<缺行>' : JSON.stringify(la[i])}`);
      out.push(`  行 ${i + 1}: 期望=${lb[i] === undefined ? '<缺行>' : JSON.stringify(lb[i])}`);
      shown += 1;
    }
  }
  if (shown === 0 && la.length !== lb.length) out.push('  行数不同（内容逐行相同，疑为行尾差异）');
  return out;
}

// ---------------------------------------------------------------- 回执校验

// gates.check.log 的路径锚点（PRD §六）：绝对路径原样；相对路径按**仓库根**解析
// （`git rev-parse --show-toplevel`，以调用 cwd 为起点）；仓库根不可判定 ⇒ 判红（fail closed，不静默跳过）。
let repoRootCache;
function repoRootOrNull() {
  if (repoRootCache !== undefined) return repoRootCache;
  try {
    repoRootCache = git(['rev-parse', '--show-toplevel'], { stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch {
    repoRootCache = null;
  }
  return repoRootCache;
}

function checkLogError(where, logPath) {
  let file;
  if (path.isAbsolute(logPath)) {
    file = logPath;
  } else {
    const root = repoRootOrNull();
    if (!root) {
      return `${where}: gates.check.log 是相对路径（${logPath}）但调用 cwd 不在 git 仓内 ⇒ 无法按仓库根锚定（PRD §六 锚点）`;
    }
    file = path.join(root, logPath);
  }
  let isFile = false;
  try {
    isFile = statSync(file).isFile();
  } catch {
    isFile = false;
  }
  if (!isFile) {
    return `${where}: gates.check.log 指向不存在的文件：${logPath}（按仓库根解析为 ${file}）—— 自述 pass 无日志 ⇒ 判红（PRD §六）`;
  }
  return null;
}

function checkReceipt(obj, file, queueById, opts) {
  const errors = [];
  const base = path.basename(file);
  const where = file;
  const wantId = base.replace(/\.receipt\.json$/, '');
  if (!isPlainObject(obj)) return [`${where}: 回执必须是 JSON 对象（实际 ${typeOf(obj)}）`];
  for (const f of RECEIPT_FIELDS) {
    if (!(f in obj)) errors.push(`${where}: 缺少必需字段 \`${f}\``);
  }
  if ('schema' in obj && !Number.isInteger(obj.schema)) errors.push(`${where}: \`schema\` 若存在必须是整数（PRD §八：建议 schema:1）`);
  if (typeof obj.id !== 'string' || obj.id.trim() === '') errors.push(`${where}: id 必须是非空字符串`);
  else if (obj.id !== wantId) errors.push(`${where}: id=${short(obj.id)} 与文件名 ${base} 不一致（应为 ${wantId}）`);
  if (typeof obj.author !== 'string' || obj.author.trim() === '') errors.push(`${where}: author 必须是非空字符串`);
  if (typeof obj.at !== 'string' || !DATE_RE.test(obj.at)) errors.push(`${where}: at 必须是 YYYY-MM-DD 或 ISO 时间（实际 ${short(obj.at)}）`);
  if (typeof obj.head !== 'string' || !SHA_RE.test(obj.head)) errors.push(`${where}: head 必须是 7–40 位小写十六进制 sha（实际 ${short(obj.head)}）`);
  if (typeof obj.pushed !== 'boolean') errors.push(`${where}: pushed 必须是布尔（实际 ${typeOf(obj.pushed)}）`);
  if (typeof obj.blocked !== 'boolean') errors.push(`${where}: blocked 必须是布尔（实际 ${typeOf(obj.blocked)}）`);
  if (typeof obj.deviation !== 'string') errors.push(`${where}: deviation 必须是字符串（无偏离写空串；实际 ${typeOf(obj.deviation)}）`);
  if (!Array.isArray(obj.artifacts)) errors.push(`${where}: artifacts 必须是数组（实际 ${typeOf(obj.artifacts)}）`);
  else for (const a of obj.artifacts) if (!nonEmptyString(a)) errors.push(`${where}: artifacts 条目必须是非空字符串`);

  // gates{check{rc,log},full{rc,cases,pass,fail,note}}
  if (!isPlainObject(obj.gates)) {
    errors.push(`${where}: gates 必须是对象（实际 ${typeOf(obj.gates)}）`);
  } else {
    for (const g of ['check', 'full']) {
      const gate = obj.gates[g];
      if (!isPlainObject(gate)) {
        errors.push(`${where}: gates.${g} 必须是对象（实际 ${typeOf(gate)}）`);
        continue;
      }
      if (!Number.isInteger(gate.rc)) errors.push(`${where}: gates.${g}.rc 必须是整数（实际 ${short(gate.rc)}）`);
      const expect = g === 'check' ? ['log'] : ['cases', 'pass', 'fail', 'note'];
      for (const f of expect) {
        if (!(f in gate)) errors.push(`${where}: gates.${g} 缺少字段 \`${f}\``);
      }
      if (g === 'check' && 'log' in gate && !nonEmptyString(gate.log)) errors.push(`${where}: gates.check.log 必须指向日志（非空字符串）`);
      // 非空还不够：必须指向真实文件（PRD §六「回执伪造」条 · 锚点见 PRD 六後注）。
      if (g === 'check' && nonEmptyString(gate.log)) {
        const logErr = checkLogError(where, gate.log);
        if (logErr) errors.push(logErr);
      }
      if (g === 'full') {
        for (const f of ['cases', 'pass', 'fail']) {
          if (f in gate && (!Number.isInteger(gate[f]) || gate[f] < 0)) errors.push(`${where}: gates.full.${f} 必须是 >=0 的整数（实际 ${short(gate[f])}）`);
        }
        if ('note' in gate && typeof gate.note !== 'string') errors.push(`${where}: gates.full.note 必须是字符串（实际 ${typeOf(gate.note)}）`);
        if (Number.isInteger(gate.pass) && Number.isInteger(gate.fail) && gate.rc === 0 && gate.fail > 0) {
          errors.push(`${where}: gates.full.rc=0 但 fail=${gate.fail}（自述与计数矛盾）`);
        }
      }
    }
  }

  // acs[{id,how,evidence}] —— 且必须是队列行 acs 的子集
  if (!Array.isArray(obj.acs)) {
    errors.push(`${where}: acs 必须是数组（实际 ${typeOf(obj.acs)}）`);
  } else {
    const row = queueById.get(obj.id);
    const seen = new Set();
    obj.acs.forEach((a, idx) => {
      const at = `${where}: acs[${idx}]`;
      if (!isPlainObject(a)) {
        errors.push(`${at} 必须是对象（实际 ${typeOf(a)}）`);
        return;
      }
      for (const f of ['id', 'how', 'evidence']) {
        if (!(f in a)) errors.push(`${at} 缺少字段 \`${f}\``);
        else if (!nonEmptyString(a[f])) errors.push(`${at}.${f} 必须是非空字符串（空证据 = 未验证；实际 ${short(a[f])}）`);
      }
      if (nonEmptyString(a.id)) {
        if (seen.has(a.id)) errors.push(`${at}: AC 重复（${a.id}）`);
        seen.add(a.id);
        if (row && Array.isArray(row.acs) && !row.acs.includes(a.id)) errors.push(`${at}: ${a.id} 不在队列行 ${row.id} 的 acs 里（${row.acs.join(',')}）`);
      }
    });
  }

  if (!queueById.has(obj.id)) errors.push(`${where}: 队列里没有 ${short(obj.id)}（回执不得脱离队列）`);

  // pushed:true ⇒ 远端复核（AC2）。默认开；--no-push-check 是显式逃生阀（跳过必打 NOTICE）。
  if (obj.pushed === true && !opts.noPushCheck && SHA_RE.test(String(obj.head))) {
    const row = queueById.get(obj.id);
    const branch = row && typeof row.branch === 'string' ? row.branch : '';
    const verr = verifyPushed(obj.head, branch, opts.remote);
    if (verr) errors.push(`${where}: pushed:true 与 git ls-remote 不一致 —— ${verr}`);
  }
  return errors;
}

function git(args, opts = {}) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts });
}

// pushed:true 的判据 =「该 head 已在远端任一 head 上（或为其祖先）」。
//   为什么不是「等于某分支 tip」：回执文件本身要进下一次提交 ⇒ head 恒落后 tip；分支合并后被删也不该翻红。
//   squash 合并例外：祖先链被丢弃 ⇒ 原分支提交不再可达，head 须取**squash 交付提交**（回执 head 语义 = 已合并的交付提交）。
function verifyPushed(head, branch, remote) {
  let out;
  try {
    out = git(['ls-remote', '--heads', remote]);
  } catch (e) {
    const msg = (e.stderr || e.message || '').toString().trim().split('\n')[0];
    return `git ls-remote --heads ${remote} 失败（${msg || '未知错误'}）`;
  }
  const tips = out.split('\n').map((l) => l.split(/\s+/)[0]).filter(Boolean);
  if (tips.length === 0) return `远端 ${remote} 没有任何 head（分支都没推送）`;
  if (tips.includes(head)) return null;
  for (const tip of tips) {
    try {
      git(['merge-base', '--is-ancestor', head, tip]);
      return null;
    } catch {
      /* 继续试下一个 tip */
    }
  }
  return `head=${head} 不在 ${remote} 的任何 head 里${branch ? `（队列行分支 ${branch}）` : ''} —— 未推送或已被裁掉`;
}


export {
  STATES, TRANSITIONS, REGION_STATES, MARKER_BEGIN, MARKER_END, GENERATED_HEAD,
  QUEUE_FIELDS, RECEIPT_FIELDS, DATE_RE, SHA_RE, UsageError,
  readText, isPlainObject, typeOf, short, nonEmptyString,
  parseQueue, validateQueue, cmpRow, formatRow, renderRegion, spliceRegion, firstDiffLines,
  repoRootOrNull, checkLogError, checkReceipt, git, verifyPushed,
};
