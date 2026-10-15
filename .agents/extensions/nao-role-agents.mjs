// .agents/extensions/nao-role-agents.mjs
// T527 —— 角色→pi-subagents agent 的单一事实（运行时注册扩展 · E-lite）
//
// 契约点（外部公开面，升版漂移由 tests/t4/cases/17 探针 fail-loud）：
//   事件名 pi-subagents:runtime-agent-register:v1（docs/extension-api.md §Runtime agent registration）
//
// BR1 零副本    ：运行时读 .agents/prompts/*.md + .agents/roles.yaml；无生成物、无静态副本。
// BR2 同卡同锚  ：systemPrompt = 卡正文（去 frontmatter）逐字节 + 环境锚点行（与
//                 `.agents/scripts/nao-fleet.sh` build_system_prompt 的 printf 段逐字一致；
//                 唯一双写点，由 cases/17 cross-assert 兜住）。
// BR3 命名纪律  ：nao-<role-id>（6 个）· 不设 alias · 不占 subagent- 前缀。
// BR4 上下文口径：systemPromptMode=replace + inheritProjectContext=true（否则卡内 AGENTS.md 契约静默丢失）。
// BR5 韧性      ：注册/装配失败仅 warn、绝不 throw；session_start 先 dispose 再注册（幂等）。
// BR6 逃生阀    ：NAO_ROLE_AGENTS=off ⇒ 不注册。
// BR9 分发面    ：扩展在**每个 trusted 会话**加载（非仅舰队会话），前提同 pi.skills。

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const RUNTIME_AGENT_REGISTER_EVENT = "pi-subagents:runtime-agent-register:v1";
export const RUNTIME_AGENT_REGISTER_VERSION = 1;
export const ENV_ANCHOR_HEADING = "## 环境锚点";
export const ROLE_AGENT_PREFIX = "nao-";

// 包根 = <pkg>/.agents/extensions/<this> 向上两级
const EXT_DIR = dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = resolve(EXT_DIR, "..", "..");

function warn(msg) {
  try {
    console.warn(`[nao-role-agents] ${msg}`);
  } catch {
    /* 日志失败不得影响会话 */
  }
}

/** root 是否是 nao 机制包根（有 .agents/roles.yaml 才算，防把 shim-only 项目当包根） */
export function hasRoleMechanism(root) {
  try {
    return readFileSync(join(root, ".agents", "roles.yaml"), "utf8").length > 0;
  } catch {
    return false;
  }
}

/** 锚点用的 NAO_SKILLS：优先 env；env 指向的不是机制包根则回退扩展自身包根（下游 shim-only 场景） */
export function resolveSkillsRoot(env = process.env) {
  const fromEnv = env && env.NAO_SKILLS;
  if (fromEnv && hasRoleMechanism(fromEnv)) return resolve(fromEnv);
  return PKG_ROOT;
}

/** 环境锚点行 —— 与 nao-fleet.sh:1068 的 printf 段逐字一致（cases/17 AC3 cross-assert） */
export function buildAnchorLine(skillsRoot) {
  return `- NAO_SKILLS=${skillsRoot}（nao 机制**包根**；@.agents/... 引用一律以 \`$NAO_SKILLS/.agents/\` 为根解析。注意：项目内 \`.agents/\` 只有 shim，不存机制副本）`;
}

/** 拆分卡片：frontmatter 文本 + 正文（正文 = 首块 frontmatter 之后，逐字节保留原样） */
export function splitCard(raw) {
  if (!raw.startsWith("---\n")) return { frontmatter: "", body: raw };
  const end = raw.indexOf("\n---\n", 3);
  if (end < 0) return { frontmatter: "", body: raw };
  return { frontmatter: raw.slice(4, end + 1), body: raw.slice(end + 5) };
}

/**
 * 卡正文（去 frontmatter + 首尾空白）—— pi-subagents registry 要求
 * `systemPrompt.trim() === systemPrompt`（禁首尾空白，实测 error: "must be a non-empty string
 * without leading or trailing whitespace"），故只归一化首尾空白，内部逐字节保留。
 */
export function cardBody(raw) {
  const { body } = splitCard(raw);
  return body.replace(/^\n+/, "").replace(/\s+$/, "");
}

/** 取 frontmatter 单行字段（首个命中） */
export function frontmatterField(frontmatter, key) {
  for (const line of frontmatter.split("\n")) {
    const m = /^([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*)$/.exec(line);
    if (m && m[1] === key) return m[2];
  }
  return "";
}

/** 严格子集解析 roles.yaml（角色 id 2 空格 / card 4 空格），保持声明顺序 */
export function parseRolesYaml(text) {
  const roles = [];
  let cur = null;
  for (const line of text.split("\n")) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    let m = /^  ([a-z0-9][a-z0-9-]*):[ \t]*$/.exec(line);
    if (m) {
      cur = { role: m[1], card: "" };
      roles.push(cur);
      continue;
    }
    m = /^    card:[ \t]*(\S+)[ \t]*$/.exec(line);
    if (m && cur) cur.card = m[1];
  }
  return roles.filter((r) => r.role && r.card);
}

/**
 * 纯装配：读机制文件 → 6 条 agent 定义（不触碰 pi / 事件总线，便于探针逐字节比对）。
 * @returns {{name:string,role:string,card:string,description:string,definition:object}[]}
 */
export function buildRoleAgentDefinitions({ root, skillsRoot } = {}) {
  const base = root || PKG_ROOT;
  const anchorRoot = skillsRoot || base;
  const roles = parseRolesYaml(readFileSync(join(base, ".agents", "roles.yaml"), "utf8"));
  const anchorLine = buildAnchorLine(anchorRoot);
  return roles.map(({ role, card }) => {
    const raw = readFileSync(join(base, ".agents", "prompts", card), "utf8");
    const { frontmatter } = splitCard(raw);
    const description = frontmatterField(frontmatter, "description");
    return {
      name: `${ROLE_AGENT_PREFIX}${role}`,
      role,
      card,
      description,
      definition: {
        description,
        // BR2 同卡同锚：cardBody 逐字节 + 与 nao-fleet.sh 逐字一致的锚点段（`\n## 环境锚点\n<行>`）
        systemPrompt: `${cardBody(raw)}\n${ENV_ANCHOR_HEADING}\n${anchorLine}`,
        systemPromptMode: "replace",
        inheritProjectContext: true,
      },
    };
  });
}

/** 经事件总线注册（逐条 try/catch；无 owner 即停）。返回 {registrations, errors}，绝不 throw。 */
export function registerRoleAgents(pi, definitions) {
  const registrations = [];
  const errors = [];
  for (const def of definitions) {
    const request = {
      version: RUNTIME_AGENT_REGISTER_VERSION,
      name: def.name,
      definition: def.definition,
    };
    try {
      pi.events.emit(RUNTIME_AGENT_REGISTER_EVENT, request);
      const result = request.result;
      if (result === undefined) {
        errors.push(`${def.name}: pi-subagents 未安装/未就绪（事件无 owner 响应）`);
        break; // 后续同名合同样无人接管，不刷屏
      }
      if (result.ok === false) throw result.error;
      if (!result.ok || !result.registration || typeof result.registration.dispose !== "function") {
        throw new Error("注册结果格式非法（缺 registration.dispose）");
      }
      registrations.push(result.registration);
    } catch (error) {
      errors.push(`${def.name}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return { registrations, errors };
}

/** 释放注册（幂等：其 dispose 自身幂等；异常吞掉不 throw） */
export function disposeRoleAgents(registrations) {
  for (const reg of registrations || []) {
    try {
      reg.dispose();
    } catch {
      /* 清理失败不得影响会话 */
    }
  }
}

/**
 * pi 扩展工厂（薄 glue）：
 *   session_start    → 先 dispose 再注册（幂等；NAO_ROLE_AGENTS=off 跳过）
 *   session_shutdown → dispose
 * 任何失败仅 warn，绝不 throw（最坏 = 无 agent，不伤会话）。
 */
export default function naoRoleAgents(pi) {
  let registrations = [];
  const teardown = () => {
    disposeRoleAgents(registrations);
    registrations = [];
  };

  const onSessionStart = () => {
    teardown(); // BR5 幂等：重复 session_start 净 6 条
    if (String(process.env.NAO_ROLE_AGENTS || "").toLowerCase() === "off") return; // BR6
    try {
      const root = resolveSkillsRoot();
      const definitions = buildRoleAgentDefinitions({ root, skillsRoot: root });
      const outcome = registerRoleAgents(pi, definitions);
      registrations = outcome.registrations;
      for (const err of outcome.errors) warn(`注册失败（仅 warn）: ${err}`);
    } catch (error) {
      warn(`装配失败（仅 warn）: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  try {
    pi.on("session_start", onSessionStart);
    pi.on("session_shutdown", teardown);
  } catch (error) {
    warn(`生命周期挂载失败（仅 warn）: ${error instanceof Error ? error.message : String(error)}`);
  }
  return teardown;
}
