#!/usr/bin/env bash
# 用例 17 —— 角色→子代理 agent 的单一事实（运行时注册扩展 · E-lite）（T527）
#
# PRD：docs/prds/2026-10-14-role-agents-runtime-registration.md（§三 范围 1–5 · §五 BR1–BR9 · §七 AC2–AC7）
# 被测对象：.agents/extensions/nao-role-agents.mjs + package.json pi 段 + .agents/scripts/nao-fleet.sh check
#
# 断言分组：
#   A 纯装配：6 条定义 · 名称集 ↔ roles.yaml 双向一一对应 · 无 subagent- 前缀 · 定义形状（无 tools/model/advertise）
#   B 装配字节比对（AC2）：6 条 systemPrompt 的卡正文段 == 卡文件去 frontmatter 正文（探针独立实现去 frontmatter）
#   C 锚点 cross-assert（AC3）：锚点行 == nao-fleet.sh build_system_prompt 的 printf 段逐字（独立抽取 %s 格式串）
#   D description（AC2）：== 卡 frontmatter description（探针独立解析）
#   E schema 探针（AC5）：假 pi.events + pi-subagents 真 owner ⇒ 注册 ×6 + listRuntimeAgentConfigs == 6 + 字段口径
#   F 幂等与韧性（AC5/AC7）：session_start 连发 2 次净 6 · dispose 幂等 · NAO_ROLE_AGENTS=off · 无 owner 仅 warn 不 throw
#   G 三态负控（AC6）：改卡 1 行 ⇒ 漂移被探针检出 · 删 manifest 声明 ⇒ check FAIL · 加 advertise ⇒ 注册被拒
#
# 能力门（BR7）：node 或 pi-subagents 缺失 ⇒ t4_skip（不 FAIL、不计 DEGRADE）。
# 零成本（BR7）：只读 Node 探针 + 夹具副本；不真跑子代理（无 LLM/网络/pi-intercom/tmux）。
# 边界（BR7）：不断言 pi-subagents 自身文案；只断言经它注册后**我方**定义的产物与 schema 判定。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
SUBAGENT_PKG="$REAL_AGENT_DIR/npm/node_modules/pi-subagents"
EVENTS_JS="$SUBAGENT_PKG/src/agents/runtime-agent-events.js"
REGISTRY_JS="$SUBAGENT_PKG/src/agents/runtime-agent-registry.js"
EXT_FILE="$T4_ROOT/.agents/extensions/nao-role-agents.mjs"
FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"

# ---- 能力门：node + pi-subagents（缺则整例 SKIP，不 FAIL/不计 DEGRADE）----
command -v node >/dev/null 2>&1 \
  || t4_skip "环境缺少 node ⇒ 用例 17（只读 Node 探针）SKIP（不 FAIL、不计 DEGRADE）"
[ -f "$EVENTS_JS" ] && [ -f "$REGISTRY_JS" ] \
  || t4_skip "环境缺少 pi-subagents（$SUBAGENT_PKG）⇒ 用例 17 SKIP（不 FAIL、不计 DEGRADE）"

t4_assert_file "$EXT_FILE" "扩展文件存在（.agents/extensions/nao-role-agents.mjs）"

# ============================================================ 共用的只读探针
PROBE="$T4_CACHE_DIR/probe17.mjs"
cat > "$PROBE" <<'PROBE_JS'
import { pathToFileURL } from "node:url";
import { readFileSync } from "node:fs";

const [root, refRoot, eventsJs, registryJs, fleetScript, mode] = process.argv.slice(2);
const emit = (name, ok, detail = "") => process.stdout.write(`R\t${ok ? "ok" : "bad"}\t${name}\t${detail}\n`);
const ANCHOR_SEP = "\n## 环境锚点\n";

const { registerRuntimeAgentEventListener } = await import(pathToFileURL(eventsJs).href);
const { listRuntimeAgentConfigs } = await import(pathToFileURL(registryJs).href);
const ext = await import(pathToFileURL(`${root}/.agents/extensions/nao-role-agents.mjs`).href);

// —— 独立实现（不复用扩展内部函数，保证字节比对非自证）——
function independentBody(raw) {
  const lines = raw.split("\n");
  let start = 0;
  if (lines[0] === "---") {
    const end = lines.indexOf("---", 1);
    start = end >= 0 ? end + 1 : 0;
  }
  return lines.slice(start).join("\n").replace(/^\n+/, "").replace(/\s+$/, "");
}
function independentDescription(raw) {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(raw);
  if (!m) return "";
  for (const line of m[1].split("\n")) {
    if (line.startsWith("description:")) return line.replace(/^description:[ \t]*/, "");
  }
  return "";
}
function parseRoleIds(yaml) {
  return [...yaml.matchAll(/^  ([a-z0-9][a-z0-9-]*):[ \t]*$/gm)].map((m) => m[1]);
}
function parseCards(yaml) {
  const map = {};
  let cur = null;
  for (const line of yaml.split("\n")) {
    let m = /^  ([a-z0-9][a-z0-9-]*):[ \t]*$/.exec(line);
    if (m) { cur = m[1]; continue; }
    m = /^    card:[ \t]*(\S+)[ \t]*$/.exec(line);
    if (m && cur) map[cur] = m[1];
  }
  return map;
}
function expectedAnchor(refRoot) {
  const src = readFileSync(fleetScript, "utf8");
  const line = src.split("\n").find((l) => l.includes("## 环境锚点") && l.includes("NAO_SKILLS=%s"));
  const q1 = line.indexOf("'");
  const q2 = line.indexOf("'", q1 + 1);
  const fmt = line.slice(q1 + 1, q2); // 文件内为字面 \n（反斜杠 n）
  const body = fmt.slice("\\n## 环境锚点\\n".length, -"\\n".length);
  return body.replace("%s", refRoot);
}
function fakePi() {
  const handlers = new Map();
  const record = (ev, h) => { if (!handlers.has(ev)) handlers.set(ev, []); handlers.get(ev).push(h); return () => {}; };
  return {
    on: record,
    registerTool: () => () => {},
    events: { on: record, emit: (ev, p) => { for (const h of handlers.get(ev) || []) h(p); } },
    fire: (ev) => { for (const h of handlers.get(ev) || []) h({}); },
  };
}

if (mode === "drift") {
  // 改卡 1 行（夹具副本）⇒ 与 refRoot 卡正文比对必须出现漂移
  const defs = ext.buildRoleAgentDefinitions({ root, skillsRoot: root });
  let mismatches = 0;
  for (const d of defs) {
    const refBody = independentBody(readFileSync(`${refRoot}/.agents/prompts/${d.card}`, "utf8"));
    const idx = d.definition.systemPrompt.indexOf(ANCHOR_SEP);
    const seg = idx >= 0 ? d.definition.systemPrompt.slice(0, idx) : "";
    if (seg !== refBody) mismatches++;
  }
  emit("drift-detected", mismatches > 0, `mismatches=${mismatches}`);
} else if (mode === "advertise") {
  // 给定义加 advertise（上游显式拒）⇒ schema 探针必须报错（探针非空转）
  const defs = ext.buildRoleAgentDefinitions({ root, skillsRoot: root });
  const pi = fakePi();
  registerRuntimeAgentEventListener(pi);
  const injected = [{ ...defs[0], definition: { ...defs[0].definition, advertise: true } }];
  const outcome = ext.registerRoleAgents(pi, injected);
  const detail = outcome.errors[0] || "no error";
  emit("advertise-rejected", outcome.registrations.length === 0 && /advertise/.test(detail), detail);
} else {
  // —— 主路径 ——
  const refYaml = readFileSync(`${refRoot}/.agents/roles.yaml`, "utf8");
  const ids = parseRoleIds(refYaml);
  const cards = parseCards(refYaml);
  const defs = ext.buildRoleAgentDefinitions({ root, skillsRoot: refRoot });
  const names = defs.map((d) => d.name);
  const expectedNames = ids.map((id) => `nao-${id}`);

  emit("defs-count-6", defs.length === 6, `n=${defs.length}`);
  emit("names-bidirectional", JSON.stringify([...names].sort()) === JSON.stringify([...expectedNames].sort()),
    `names=${names.join(",")} · roles=${ids.join(",")}`);
  emit("no-subagent-prefix", !names.some((n) => n.startsWith("subagent-")), "");
  emit("names-unique", names.length === new Set(names).size, "");

  const anchorExpected = expectedAnchor(refRoot);
  for (const d of defs) {
    const raw = readFileSync(`${refRoot}/.agents/prompts/${d.card}`, "utf8");
    const idx = d.definition.systemPrompt.indexOf(ANCHOR_SEP);
    const seg = idx >= 0 ? d.definition.systemPrompt.slice(0, idx) : "";
    emit(`body-bytes-${d.role}`, seg === independentBody(raw), `card=${d.card}`);
    emit(`description-${d.role}`, d.description === independentDescription(raw), `desc=${d.description}`);
    const anchor = idx >= 0 ? d.definition.systemPrompt.slice(idx + ANCHOR_SEP.length) : "";
    emit(`anchor-${d.role}`, anchor === anchorExpected, `card=${d.card}`);
  }

  emit("shape-no-tools-model-advertise",
    defs.every((d) => d.definition.tools === undefined && d.definition.model === undefined && d.definition.advertise === undefined), "");
  emit("shape-mode-replace", defs.every((d) => d.definition.systemPromptMode === "replace"), "");
  emit("shape-inherit-project", defs.every((d) => d.definition.inheritProjectContext === true), "");
  emit("card-in-role-map", defs.every((d) => cards[d.role] === d.card), "");

  // —— 假总线 + pi-subagents 真 owner：注册 ×6 ——
  const pi = fakePi();
  registerRuntimeAgentEventListener(pi);
  const teardown = ext.default(pi);
  pi.fire("session_start");
  const regs = listRuntimeAgentConfigs(pi);
  emit("registry-count-6", regs.length === 6, `n=${regs.length}`);
  emit("registry-fields", regs.every((a) => a.systemPromptMode === "replace" && a.inheritProjectContext === true
    && a.aliases === undefined && a.tools === undefined && a.model === undefined), "");
  // 幂等：session_start 连发 2 次 ⇒ 净 6
  pi.fire("session_start");
  emit("idempotent-start-6", listRuntimeAgentConfigs(pi).length === 6, `n=${listRuntimeAgentConfigs(pi).length}`);
  // dispose 幂等
  teardown();
  teardown();
  emit("dispose-idempotent-0", listRuntimeAgentConfigs(pi).length === 0, `n=${listRuntimeAgentConfigs(pi).length}`);

  // —— 逃生阀 NAO_ROLE_AGENTS=off ——
  const pi2 = fakePi();
  registerRuntimeAgentEventListener(pi2);
  const t2 = ext.default(pi2);
  process.env.NAO_ROLE_AGENTS = "off";
  pi2.fire("session_start");
  const offCount = listRuntimeAgentConfigs(pi2).length;
  delete process.env.NAO_ROLE_AGENTS;
  pi2.fire("session_start");
  emit("escape-valve-off-0", offCount === 0, `off=${offCount}`);
  emit("escape-valve-reenable-6", listRuntimeAgentConfigs(pi2).length === 6, "");
  t2();

  // —— 韧性：无 owner ⇒ 仅 warn、不 throw ——
  const pi3 = fakePi();
  const t3 = ext.default(pi3);
  let threw = false;
  try { pi3.fire("session_start"); } catch { threw = true; }
  emit("no-owner-no-throw", !threw, "");
  emit("no-owner-zero", listRuntimeAgentConfigs(pi3).length === 0, "");
  t3();
}
PROBE_JS

# run_probe <root> <refRoot> <mode> —— 输出 R 行到 $PROBE_OUT
run_probe() {
  local root="$1" ref="$2" mode="$3"
  PROBE_OUT="$T4_CACHE_DIR/probe17-$mode.out"
  PROBE_ERR="$T4_CACHE_DIR/probe17-$mode.err"
  env -u NAO_ROLE_AGENTS NAO_SKILLS="$T4_ROOT" \
    node "$PROBE" "$root" "$ref" "$EVENTS_JS" "$REGISTRY_JS" "$FLEET" "$mode" >"$PROBE_OUT" 2>"$PROBE_ERR"
  return $?
}
assert_probe_runs() {
  local mode="$1" rc="$2" n out err
  out="$T4_CACHE_DIR/probe17-$mode.out"; err="$T4_CACHE_DIR/probe17-$mode.err"
  n="$(grep -c $'^R\t' "$out" 2>/dev/null || true)"; n="${n:-0}"
  if [ "$rc" != "0" ] || [ "$n" -lt 1 ]; then
    t4_bad "node 探针[$mode] 执行失败（rc=$rc · 产出 $n 行 · stderr: $(head -c 300 "$err" 2>/dev/null | tr '\n' ' '))"
    return 1
  fi
  t4_ok "node 探针[$mode] 执行成功（rc=0 · 产出 $n 条）"
  return 0
}

# ============================================================ A–F 主路径
run_probe "$T4_ROOT" "$T4_ROOT" main
MAIN_RC=$?
if assert_probe_runs main "$MAIN_RC"; then
  while IFS=$'\t' read -r tag status name detail; do
    [ "$tag" = "R" ] || continue
    case "$status" in
      ok)  t4_ok  "主路径 $name${detail:+（$detail）}" ;;
      bad) t4_bad "主路径 $name${detail:+（$detail）}" ;;
      *)   t4_bad "主路径 未识别探针状态: $status" ;;
    esac
  done < "$T4_CACHE_DIR/probe17-main.out"
fi

# ============================================================ G 三态负控（AC6）
# M-A 改卡 1 行（夹具副本）⇒ 漂移被探针检出（不触碰仓库工作区）
FXA="$T4_CACHE_DIR/neg-card"
rm -rf "$FXA"; mkdir -p "$FXA"
cp -r "$T4_ROOT/.agents" "$FXA/.agents"
cp "$T4_ROOT/package.json" "$FXA/package.json"
t4_assert_file "$FXA/.agents/prompts/test-engineer.md" "M-A 夹具：卡副本存在"
sed -i 's/^# 测试工程师（QA）$/# 测试工程师（QA）· MUTATED-ONE-LINE/' "$FXA/.agents/prompts/test-engineer.md"
t4_assert_contains "$(cat "$FXA/.agents/prompts/test-engineer.md")" "MUTATED-ONE-LINE" "M-A 夹具：卡正文已改 1 行"
run_probe "$FXA" "$T4_ROOT" drift
DRIFT_RC=$?
if assert_probe_runs drift "$DRIFT_RC"; then
  DRIFT_LINE="$(grep 'drift-detected' "$T4_CACHE_DIR/probe17-drift.out" || true)"
  t4_assert_match "$DRIFT_LINE" $'^R\tok\tdrift-detected' "M-A 改卡 1 行 ⇒ 探针检出漂移（FAIL 语义）"
fi

# M-B 删 manifest 声明（夹具副本）⇒ 真 check FAIL
FXB="$T4_CACHE_DIR/neg-manifest"
rm -rf "$FXB"; mkdir -p "$FXB"
cp -r "$T4_ROOT/.agents" "$FXB/.agents"
node -e '
const fs=require("fs");
const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
delete (p.pi||{}).extensions;
fs.writeFileSync(process.argv[2], JSON.stringify(p,null,2)+"\n");
' "$T4_ROOT/package.json" "$FXB/package.json"
if command -v node >/dev/null 2>&1 && grep -q '"extensions"' "$FXB/package.json"; then
  t4_bad "M-B 夹具：pi.extensions 未被删除"
else
  t4_ok "M-B 夹具：pi.extensions 已从副本删除"
fi
of="$T4_CACHE_DIR/neg-manifest-check.out"
( cd "$FXB" && env -u NAO_ROLE_AGENTS NAO_SKILLS="$FXB" timeout 120 bash "$FLEET" check ) >"$of" 2>&1
NEG_RC=$?
t4_assert_ne "0" "$NEG_RC" "M-B 删 pi.extensions 声明 ⇒ check rc≠0"
t4_assert_contains "$(cat "$of")" "pi.extensions 未声明或非法" "M-B check 报错点名 pi.extensions 缺项"

# M-C 给定义加 advertise ⇒ pi-subagents 注册被拒（探针非空转）
run_probe "$T4_ROOT" "$T4_ROOT" advertise
ADV_RC=$?
if assert_probe_runs advertise "$ADV_RC"; then
  ADV_LINE="$(grep $'^R\t' "$T4_CACHE_DIR/probe17-advertise.out" || true)"
  t4_assert_match "$ADV_LINE" $'^R\tok\tadvertise-rejected' "M-C 加 advertise ⇒ 注册被拒（探针检出）"
fi

t4_exit
