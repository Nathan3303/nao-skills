#!/usr/bin/env bash
# 用例 18 —— codegraph 四态检测 / 默认零 fork / 遥测注入 / 契约文案（T532 · #53）
#
# 判据来源：docs/prds/2026-10-28-codegraph-plugin.md v5
#   §三-1（四态 + 单实现 + 删 rc=1）· §三-9（回归护栏）· §五 BR1/BR2/BR5/BR7/BR10/BR11
#   §七 AC1（四态前缀 + rc 恒 0）· AC2（--strict 不升级）· AC3（技能口径）· AC4（卡/清单口径）
#   AC7（两条变异负控 + md5 还原）· AC8（副产物静态面）· AC11（默认 check 零外部进程）
#
# 断言分组：
#   A 四态前缀（默认 `check`，full=0）：未声明 / 已声明但无 CLI / 无索引 / 齐备（含 -v 提示）
#   B AC11 零 fork：默认 `check` 的 codegraph 调用 = 0；`check -v` = 1；`ensure` 调用点静态 = full=1
#   C full=1 文本契约：pending / up to date / 不可解析（三态各命中一次）+ `--strict` 不升级
#   D 变异负控（AC7）：① 摘插件条目 ② 摘 `.codegraph` ⇒ 各命中新前缀且 `check` rc 不变；还原后 md5 一致
#   E 单源与遥测（BR5/BR10）：包名等值断言（fleet 常量 ↔ `bin/nao-skill.js`）+ spawn_one 字面量
#   F 副产物纪律（BR11/AC8）：`.gitignore` 单文件、入库零命中、机制侧不写不删不杀
#   G 文档口径（AC3/AC4 可测面）：技能必备句 + 唯一硬编码工具名 + 卡内禁用工具名零命中
#
# 能力门（不整例 SKIP，避免静态断言被吞）：
#   真装类（G 组之外的 `codegraph status` 真实原文）只在 CLI + 本仓 `.codegraph/` 齐备时跑；
#   缺失 ⇒ `[NOTE] static-contract`（白名单 tag，`T4_REQUIRE_FULL=1` 亦通过）。
# 零成本：只读 grep + 夹具副本；不 spawn `codegraph serve`（不产生 daemon，BR11）。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
SKILL="$T4_ROOT/.agents/skills/codegraph.md"
BINJS="$T4_ROOT/bin/nao-skill.js"
PKG='@sean_pedersen/pi-codegraph'

t4_assert_file "$FLEET" "被测脚本存在（nao-fleet.sh）"
t4_assert_file "$SKILL" "技能文件存在（codegraph.md）"

# ---------------------------------------------------------------- 夹具
FX="$T4_CACHE_DIR/c18/repo"
AG="$T4_CACHE_DIR/c18/home/.pi/agent"
STUB="$T4_CACHE_DIR/c18/bin"
LOG="$T4_CACHE_DIR/c18/calls.log"
mkdir -p "$FX" "$AG" "$STUB"
cp -r "$T4_ROOT/.agents" "$FX/.agents" || t4_blocked "夹具复制 .agents 失败"
printf '{"packages":["npm:pi-web-access"]}\n' > "$AG/settings.json"

# 记录型 stub：每次调用追加一行；输出由 CG_STUB_MODE 决定（契约原文取自 codegraph 1.6.2 实测）
cat > "$STUB/codegraph" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CG_STUB_LOG:-/dev/null}"
case "${CG_STUB_MODE:-up}" in
  up)         printf '✓ Index is up to date\n' ;;
  pending)    printf 'Pending Changes:\n  Modified:  1 files\n\u2139 Run "codegraph sync" to update the index\n' ;;
  uninit)     printf '\u26a0 Not initialized\n' ;;
  unparsable) printf 'garbage output\n' ;;
esac
exit 0
STUB
chmod +x "$STUB/codegraph"

# 去掉所有含 codegraph 可执行的 PATH 目录（保留 pi 等其它命令）
NO_CG_PATH=""
IFS=':' read -ra _parts <<< "$PATH"
for _d in "${_parts[@]}"; do
  [ -n "$_d" ] || continue
  [ -x "$_d/codegraph" ] && continue
  NO_CG_PATH="${NO_CG_PATH:+$NO_CG_PATH:}$_d"
done
t4_info "夹具：repo=$FX · agent_dir=$AG · stub=$STUB"

# 运行夹具内的 check：$1=stub|nostub  $2=mode  $3...=check 参数
C18_RC=0; C18_OUT=""
run_cg_check() {
  local kind="$1" mode="$2"; shift 2
  : > "$LOG"
  local path="$NO_CG_PATH"
  [ "$kind" = "stub" ] && path="$STUB:$NO_CG_PATH"
  local of ef; of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$FX" && env PI_CODING_AGENT_DIR="$AG" PATH="$path" \
      CG_STUB_MODE="$mode" CG_STUB_LOG="$LOG" \
      bash .agents/scripts/nao-fleet.sh check "$@" ) >"$of" 2>"$ef"
  C18_RC=$?
  C18_OUT="$(cat "$of"; cat "$ef")"
  rm -f "$of" "$ef"
}
cg_calls() { [ -f "$LOG" ] && awk 'END { print NR + 0 }' "$LOG" || printf '0'; }

# ============================================================ A 四态（默认 check，full=0）
# A1 未声明插件（settings 无包名）
run_cg_check nostub up
t4_assert_eq "0" "$C18_RC" "A1 未声明：check rc=0（codegraph 永不进 rc）"
t4_assert_contains "$C18_OUT" "· codegraph 插件未声明" "A1 未声明：命中契约前缀 · （含装法）"
t4_assert_contains "$C18_OUT" "npm:@sean_pedersen/pi-codegraph" "A1 未声明：提示含可复制装法命令"

# A2 已声明但 CLI 不在 PATH
printf '{"packages":["npm:pi-web-access","npm:%s"]}\n' "$PKG" > "$AG/settings.json"
run_cg_check nostub up
t4_assert_eq "0" "$C18_RC" "A2 已声明无 CLI：check rc=0"
t4_assert_contains "$C18_OUT" "! codegraph 插件已声明但 CLI 不在 PATH" "A2 已声明无 CLI：命中契约前缀 !"

# A3 已声明 + CLI stub + 无 .codegraph
run_cg_check stub up
t4_assert_eq "0" "$C18_RC" "A3 无索引：check rc=0"
t4_assert_contains "$C18_OUT" "! codegraph 已就绪但当前仓无索引" "A3 无索引：命中契约前缀 !（含 init 命令）"
t4_assert_contains "$C18_OUT" "codegraph init" "A3 无索引：提示含真实命令 codegraph init"

# A4 齐备（默认 full=0 ⇒ 不 fork，但仍要明说新鲜度看 -v，BR9 不静默）
mkdir -p "$FX/.codegraph"
run_cg_check stub up
t4_assert_eq "0" "$C18_RC" "A4 齐备（默认）：check rc=0"
t4_assert_contains "$C18_OUT" "✓ codegraph 齐备（索引新鲜度用 -v 查）" "A4 齐备：默认文案含「新鲜度用 -v 查」"

# ============================================================ B AC11 默认零 fork
t4_assert_eq "0" "$(cg_calls)" "B1 默认 check：codegraph 调用 0 次（零外部进程）"
run_cg_check stub up -v
t4_assert_eq "1" "$(cg_calls)" "B2 check -v：codegraph 调用 1 次（每仓一次 status）"
# B3 ensure 调用点静态：必须是 full=1（否则 ensure 看不到 pending）
t4_assert_match "$(grep -n 'codegraph_state "\$repo"' "$FLEET" | head -1)" 'codegraph_state "\$repo" 1' \
  "B3 ensure 调用点用 full=1（静态）"

# ============================================================ C full=1 文本契约三态
run_cg_check stub pending -v
t4_assert_eq "0" "$C18_RC" "C1 pending：check -v rc=0（BR1 放松，不再 rc=1）"
t4_assert_contains "$C18_OUT" "! codegraph 索引 pending" "C1 pending：命中契约前缀 !（第五组）"
t4_assert_contains "$C18_OUT" "codegraph sync" "C1 pending：提示含真实命令 codegraph sync"

run_cg_check stub pending -v --strict
t4_assert_eq "0" "$C18_RC" "C2 pending + --strict：rc=0（--strict 不升级）"

run_cg_check stub up -v
t4_assert_contains "$C18_OUT" "✓ codegraph 齐备" "C3 up to date：-v 命中 ✓ 齐备（无 -v 尾巴）"
t4_assert_not_contains "$C18_OUT" "索引新鲜度用 -v 查" "C3 up to date：-v 下不再出现默认尾巴"

run_cg_check stub unparsable -v
t4_assert_eq "0" "$C18_RC" "C4 不可解析：rc=0"
t4_assert_contains "$C18_OUT" "! codegraph status 输出不可解析" "C4 不可解析：命中兜底前缀 !"

# ============================================================ D 变异负控（AC7）
# D1 摘插件条目 ⇒ 「齐备」不再命中、改命中「未声明」；check rc 不变；还原后 md5 一致
md5_before="$(md5sum "$AG/settings.json" | awk '{print $1}')"
cp "$AG/settings.json" "$T4_CACHE_DIR/c18/settings.bak"
printf '{"packages":["npm:pi-web-access"]}\n' > "$AG/settings.json"
run_cg_check stub up -v
t4_assert_not_contains "$C18_OUT" "✓ codegraph 齐备" "D1 摘插件条目：「齐备」断言不再命中（变异可检出）"
t4_assert_contains "$C18_OUT" "· codegraph 插件未声明" "D1 摘插件条目：改命中「未声明」"
t4_assert_eq "0" "$C18_RC" "D1 摘插件条目：check rc 仍 0（不是 check 失败）"
cp "$T4_CACHE_DIR/c18/settings.bak" "$AG/settings.json"
t4_assert_eq "$md5_before" "$(md5sum "$AG/settings.json" | awk '{print $1}')" "D1 还原后 settings.json md5 一致"

# D2 摘 .codegraph ⇒ 「齐备」不再命中、改命中「无索引」；还原（重建目录）后一致性恢复
rmdir_or_rm() { rm -rf "$1"; }
rmdir_or_rm "$FX/.codegraph"
run_cg_check stub up -v
t4_assert_not_contains "$C18_OUT" "✓ codegraph 齐备" "D2 摘 .codegraph：「齐备」断言不再命中"
t4_assert_contains "$C18_OUT" "! codegraph 已就绪但当前仓无索引" "D2 摘 .codegraph：改命中「无索引」"
t4_assert_eq "0" "$C18_RC" "D2 摘 .codegraph：check rc 仍 0"
mkdir -p "$FX/.codegraph"
run_cg_check stub up -v
t4_assert_contains "$C18_OUT" "✓ codegraph 齐备" "D2 还原 .codegraph：恢复「齐备」"

# ============================================================ E 单源（BR5）+ 遥测（BR10）
T4_PKG_FLEET="$(grep -m1 -oE '^CODEGRAPH_PKG="[^"]+"' "$FLEET" | sed -e 's/^CODEGRAPH_PKG="//' -e 's/"$//')"
T4_PKG_BIN="$(node -e '
  const fs = require("fs");
  const s = fs.readFileSync(process.argv[1], "utf8");
  const m = s.match(/codegraph:\s*\{\s*pkg:\s*'"'"'([^'"'"']+)'"'"'/);
  process.stdout.write(m ? m[1] : "<missing>");
' "$BINJS" 2>/dev/null || echo '<node-error>')"
t4_assert_eq "$T4_PKG_BIN" "$T4_PKG_FLEET" "E1 包名单源等值（fleet CODEGRAPH_PKG ↔ bin/nao-skill.js PI_PLUGINS.codegraph）"

SPAWN_BODY="$(awk '/^spawn_one\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$FLEET")"
t4_assert_contains "$SPAWN_BODY" 'export CODEGRAPH_TELEMETRY=0' "E2 spawn_one 注入 CODEGRAPH_TELEMETRY=0（字面量）"
t4_assert_not_contains "$SPAWN_BODY" 'DO_NOT_TRACK' "E2 不注入 DO_NOT_TRACK（过宽，BR10）"

# ============================================================ F 副产物纪律（BR11/AC8）
t4_assert_contains "$(cat "$T4_ROOT/.gitignore")" ".pi/APPEND_SYSTEM.md" "F1 .gitignore 覆盖单文件 .pi/APPEND_SYSTEM.md"
t4_assert_eq "" "$(grep -nE '^\.pi/?$' "$T4_ROOT/.gitignore" || true)" "F1 未 ignore 整个 .pi/（只单文件）"
if git -C "$T4_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  t4_assert_eq "" "$(git -C "$T4_ROOT" ls-files -- .pi/APPEND_SYSTEM.md)" "F2 入库零命中（git ls-files 为空）"
else
  t4_note static-contract "F2 非 git 工作区：入库零命中改由 F1 的 .gitignore 断言替代"
fi
t4_assert_eq "" "$(grep -nE 'APPEND_SYSTEM|pkill .*codegraph|kill .*codegraph' "$FLEET" || true)" \
  "F3 机制侧不写/不删副产物、不杀 daemon（脚本零命中）"

# ============================================================ G 文档口径（AC3/AC4 可测面）
SKILL_TXT="$(cat "$SKILL")"
t4_assert_contains "$SKILL_TXT" "codegraph_explore" "G1 技能含唯一硬编码原生入口 codegraph_explore"
t4_assert_contains "$SKILL_TXT" "有插件无索引 / 无 CLI ⇒ 不生效" "G1 技能含「有插件无索引/无 CLI ⇒ 不生效」"
t4_assert_contains "$SKILL_TXT" "插件不供 system prompt 指引（截至 pi 1.4.0 / pi-codegraph 0.1.0）" \
  "G1 技能含注入不生效的版本戳说明"
t4_assert_not_contains "$SKILL_TXT" "codegraph init -i" "G2 技能用 codegraph init（不带已废弃的 -i）"
t4_assert_contains "$SKILL_TXT" "禁 cat 全文" "G2 技能保留「禁 cat 全文」"
t4_assert_contains "$SKILL_TXT" '( cd /tmp && pi' "G3 技能含非会话 pi 的 cwd 规避法（BR11）"
t4_assert_contains "$SKILL_TXT" "codegraph daemons" "G3 技能含 daemon 手工停法（机制不代杀）"
t4_assert_eq "" "$(grep -rnE 'codegraph_(search|callers|callees|impact|node|context|files|status)' \
  "$T4_ROOT/.agents/prompts" "$T4_ROOT/.agents/checklists" "$SKILL" 2>/dev/null || true)" \
  "G4 禁用工具名零命中（只允许 codegraph_explore，BR7）"
CARDS_WITH_CG="$(grep -rl "codegraph" "$T4_ROOT/.agents/prompts" | wc -l | tr -d ' ')"
t4_assert_eq "6" "$CARDS_WITH_CG" "G5 六张角色卡均含 codegraph 口径"
BAD_CARDS="$(grep -rL "codegraph_explore" $(grep -rl "codegraph" "$T4_ROOT/.agents/prompts") 2>/dev/null || true)"
t4_assert_eq "" "$BAD_CARDS" "G5 每张提及 codegraph 的卡都给出原生入口（codegraph_explore）"

# ============================================================ H 真装类（能力门 → NOTE static-contract）
if command -v codegraph >/dev/null 2>&1 && [ -d "$T4_ROOT/.codegraph" ]; then
  REAL_ST="$(cd "$T4_ROOT" && codegraph status 2>&1 || true)"
  case "$REAL_ST" in
    *"Index is up to date"*|*"Pending Changes"*|*"Not initialized"*)
      t4_ok "H1 真实 CLI 原文仍命中冻结契约串（codegraph 1.6.2 实测基线）" ;;
    *) t4_bad "H1 真实 CLI 原文未命中任何冻结契约串（上游文案漂移？）：$(printf '%s' "$REAL_ST" | head -3 | tr '\n' ' ')" ;;
  esac
else
  t4_note static-contract "H1 缺 codegraph CLI 或本仓 .codegraph/ ⇒ 真装类原文断言跳过（契约串已由 C 组 stub 断言覆盖）"
fi

t4_exit
