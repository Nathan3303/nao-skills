#!/usr/bin/env bash
# 用例 16 —— nao 版子代理桥指令模板 + 协议条款 + 配置 schema（T526）
#
# PRD：docs/prds/2026-10-14-intercom-bridge-instructions.md（§三 范围 1–6 · §五 BR1–BR8 · §七 AC2–AC7）
# 被测对象（nao 自身契约，非 pi-subagents 文案）：
#   · .agents/templates/pi-subagents/intercom-bridge.md（G1 回执归属 / G2 身份禁令 / G3 证据格式 · 无 {orchestratorTarget}）
#   · .agents/templates/pi-subagents/README.md（安装说明 · 相对 instructionFile · 无绝对家目录路径）
#   · .agents/common/intercom-protocol.md 新小节「会话内子代理（授权与回执归属）」四条齐备
#   · pi-subagents 的 validateIntercomBridgeConfig / resolveIntercomBridge（动态 import，桩配置）
#
# 断言分组：
#   A 模板文件存在/可读
#   B G1/G2/G3 关键条款（逐字 · 可被「删 G1 / 删证据格式段」负控击穿）
#   C 模板不含 {orchestratorTarget}（BR4 · 可被「加回占位符」负控击穿）
#   D README 安装说明（相对路径 · 排障入口 · 无绝对家目录路径）
#   E 协议小节四条齐备（且只指针、不复刻 T525 行）
#   F pi-subagents 桥解析 + 配置 schema（合法接受 / 非法拒绝 / 我方模板非插值）
#
# 能力门（AC5/BR6/BR7）：node 或 pi-subagents 缺失 ⇒ t4_skip（不 FAIL、不计 DEGRADE）。
# 零成本（BR7）：只读 Node 探针 + 桩配置；不真跑子代理（无 LLM/网络/pi-intercom/tmux）。
# 边界（BR6）：不断言 pi-subagents 自身默认文案；只断言经它解析后**我方**模板的产物。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
SUBAGENT_PKG="$REAL_AGENT_DIR/npm/node_modules/pi-subagents"
BRIDGE_JS="$SUBAGENT_PKG/src/intercom/intercom-bridge.js"

TPL_DIR="$T4_ROOT/.agents/templates/pi-subagents"
TEMPLATE="$TPL_DIR/intercom-bridge.md"
README="$TPL_DIR/README.md"
PROTOCOL="$T4_ROOT/.agents/common/intercom-protocol.md"

# ---- 能力门：node + pi-subagents（缺则整例 SKIP，不 FAIL/不 DEGRADE）----
command -v node >/dev/null 2>&1 \
  || t4_skip "环境缺少 node ⇒ 用例 16（只读 Node 探针）SKIP（不 FAIL、不计 DEGRADE）"
[ -f "$BRIDGE_JS" ] \
  || t4_skip "环境缺少 pi-subagents（$BRIDGE_JS）⇒ 用例 16 SKIP（不 FAIL、不计 DEGRADE）"

# ============================================================ A 模板文件
t4_assert_file "$TEMPLATE" "A 模板文件存在（.agents/templates/pi-subagents/intercom-bridge.md）"
[ -r "$TEMPLATE" ] && t4_ok "A 模板文件可读" || t4_bad "A 模板文件不可读: $TEMPLATE"
TPL="$(cat "$TEMPLATE" 2>/dev/null || true)"

# ============================================================ B G1/G2/G3 关键条款
# G1 回执归属（BR1/BR3 · AC2）
t4_assert_contains "$TPL" "不等于回执" "B G1：子代理结果「不等于回执」"
t4_assert_contains "$TPL" "只能由父角色" "B G1：终态 done「只能由父角色」发出"
t4_assert_contains "$TPL" "PM 只认父角色" "B G1：PM 只认父角色 done"
# G2 身份禁令（BR2 · AC2）
t4_assert_contains "$TPL" "不得以舰队角色名义" "B G2：不得以舰队角色名义回执"
t4_assert_contains "$TPL" "不得发送 \`done\` 形态的消息" "B G2：不得发送 done 形态消息"
t4_assert_contains "$TPL" "不得直接向 PM 发送" "B G2：不得直发 PM"
t4_assert_contains "$TPL" "contact_supervisor" "B G2：需决策走 contact_supervisor"
# G3 证据契约（BR3 · AC2）
t4_assert_contains "$TPL" "命令 + exit code + 例数/文件数（或断言数）+ 路径" "B G3：证据格式逐字（命令+exit+例数/文件数+路径）"

# ============================================================ C 无占位符（BR4）
t4_assert_not_contains "$TPL" '{orchestratorTarget}' "C 模板不含 {orchestratorTarget} 占位符"

# ============================================================ D README 安装说明（BR5）
t4_assert_file "$README" "D 安装说明存在（同目录 README.md）"
RD="$(cat "$README" 2>/dev/null || true)"
t4_assert_contains "$RD" 'nao-intercom-bridge.md' "D 说明给出目标文件名"
t4_assert_contains "$RD" '"instructionFile": "nao-intercom-bridge.md"' "D 说明给出相对 instructionFile 配置样例"
t4_assert_contains "$RD" '"resultDelivery": false' "D 说明保持 resultDelivery=false"
t4_assert_contains "$RD" '/subagents-doctor' "D 说明含排障入口 /subagents-doctor"
t4_assert_contains "$RD" '本批不写任何用户配置文件' "D 说明声明本批不写用户配置"
if grep -qE '/home/[A-Za-z0-9_.-]+' "$README" "$TEMPLATE" 2>/dev/null; then
  t4_bad "D 模板/说明含绝对家目录路径（/home/…）—— 仓库红线"
else
  t4_ok "D 模板/说明无绝对家目录路径（只用 ~/ 或 \$HOME/）"
fi

# ============================================================ E 协议小节（BR8 · AC3）
t4_assert_contains "$(cat "$PROTOCOL")" "## 会话内子代理（授权与回执归属）" "E 协议新增小节标题存在"
SECTION="$(awk '/^## 会话内子代理（授权与回执归属）/{f=1;next} f&&/^## /{exit} f' "$PROTOCOL")"
[ -n "$SECTION" ] && t4_ok "E 协议小节可提取（非空）" || t4_bad "E 协议小节为空"
t4_assert_contains "$SECTION" "授权" "E 协议① 授权"
t4_assert_contains "$SECTION" "回执归属（硬性）" "E 协议② 回执归属（硬性）"
t4_assert_contains "$SECTION" "子代理禁令" "E 协议③ 子代理禁令"
t4_assert_contains "$SECTION" "证据格式" "E 协议④ 证据格式"
t4_assert_contains "$SECTION" "见上文「子代理会话不属舰队会话身份模型」" "E 协议只指针引用 T525 边界行"
t4_assert_contains "$SECTION" "此处不重复" "E 协议显式声明不重复 T525 内容"
t4_assert_not_contains "$SECTION" "只对其汇总计数" "E 协议不复刻 T525 行内容（无「只对其汇总计数」）"
t4_assert_not_contains "$SECTION" "显式拒绝" "E 协议不复刻 T525 行内容（无「显式拒绝」）"

# ============================================================ F pi-subagents 桥解析 + 配置 schema（AC2/AC4）
PROBE="$T4_CACHE_DIR/probe16.mjs"
cat > "$PROBE" <<'PROBE_JS'
import { pathToFileURL } from "node:url";

const [bridgeJs, templateDir, templateName] = process.argv.slice(2);
const mod = await import(pathToFileURL(bridgeJs).href);
const out = (name, ok, detail = "") => process.stdout.write(`R\t${ok ? "ok" : "bad"}\t${name}\t${detail}\n`);

// 配置 schema：合法样例必须被接受
const legal = [
  ["full-always", { mode: "always", instructionFile: "nao-intercom-bridge.md", resultDelivery: false }],
  ["mode-off", { mode: "off" }],
  ["mode-fork-only", { mode: "fork-only" }],
  ["empty-object", {}],
];
for (const [name, value] of legal) {
  const r = mod.validateIntercomBridgeConfig({ value, label: "intercomBridge" });
  out(`schema-legal-${name}`, r.ok === true, r.ok ? "" : `error=${r.error}`);
}

// 配置 schema：非法样例必须被拒绝
const illegal = [
  ["mode-invalid", { mode: "sometimes" }],
  ["instructionFile-number", { instructionFile: 123 }],
  ["resultDelivery-string", { resultDelivery: "yes" }],
  ["unknown-key", { notify: true }],
  ["not-object", "always"],
];
for (const [name, value] of illegal) {
  const r = mod.validateIntercomBridgeConfig({ value, label: "intercomBridge" });
  out(`schema-illegal-${name}`, r.ok === false, r.ok ? "accepted illegal" : "");
}

// 经真实桥解析：我方模板作为 instructionFile（桩 orchestratorTarget，非真跑子代理）
const bridge = mod.resolveIntercomBridge({
  config: { mode: "always", instructionFile: templateName, resultDelivery: false },
  orchestratorTarget: "pm",
  agentDir: templateDir,
  settingsDir: templateDir,
  context: "run",
});
out("resolve-active", bridge.active === true, `active=${bridge.active}`);
out("resolve-no-interpolation", bridge.interpolatesOrchestratorTarget === false,
  `interpolatesOrchestratorTarget=${bridge.interpolatesOrchestratorTarget}`);
const instr = bridge.instruction || "";
out("resolve-carries-g1", instr.includes("不等于回执"), "");
out("resolve-carries-g2", instr.includes("contact_supervisor") && instr.includes("不得直接向 PM 发送"), "");
out("resolve-carries-g3", instr.includes("命令 + exit code + 例数/文件数（或断言数）+ 路径"), "");
out("resolve-no-placeholder", !instr.includes("{orchestratorTarget}"), "");
PROBE_JS

PROBE_OUT="$T4_CACHE_DIR/probe16.out"
PROBE_ERR="$T4_CACHE_DIR/probe16.err"
node "$PROBE" "$BRIDGE_JS" "$TPL_DIR" "intercom-bridge.md" >"$PROBE_OUT" 2>"$PROBE_ERR"
PROBE_RC=$?
N_LINES="$(grep -c $'^R\t' "$PROBE_OUT" 2>/dev/null || true)"
N_LINES="${N_LINES:-0}"
if [ "$PROBE_RC" != "0" ] || [ "$N_LINES" -lt 1 ]; then
  t4_bad "F node 探针执行失败（rc=$PROBE_RC · 产出 $N_LINES 行 · stderr: $(head -c 300 "$PROBE_ERR" 2>/dev/null | tr '\n' ' '))"
else
  t4_ok "F node 探针执行成功（rc=0 · 产出 $N_LINES 条）"
fi
while IFS=$'\t' read -r tag status name detail; do
  [ "$tag" = "R" ] || continue
  case "$status" in
    ok)  t4_ok  "F $name${detail:+（$detail）}" ;;
    bad) t4_bad "F $name${detail:+（$detail）}" ;;
    *)   t4_bad "F 未识别探针状态: $status" ;;
  esac
done < "$PROBE_OUT"

t4_exit
