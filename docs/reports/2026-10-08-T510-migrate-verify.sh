#!/usr/bin/env bash
# =============================================================================
# T510 迁移收尾断言（#21 · F3 / F4 / F7 + B2）—— 独立验收脚本（双模式）
#
# 用法：
#   bash docs/reports/2026-10-08-T510-migrate-verify.sh --baseline
#       → 现状 0.12.1「体检」：断言缺陷仍可复现（PASS = 缺陷在场，供修复前后对照）
#   bash docs/reports/2026-10-08-T510-migrate-verify.sh
#       → 修复后验收：按 PRD §7 AC 逐条断言（AC-F3-x / AC-F4-x / AC-F7-x + AC-DOC/REL）
#
# 纪律：
#   - 只读本仓（bin/nao-skill.js、package.json、.agents/**、docs/**），不修改任何仓库文件
#   - 所有夹具建在 mktemp 临时目录（--target 显式传入 / cwd 在夹具内），不碰本仓与下游三仓
#   - 退出码：0 = 全部断言 PASS；1 = 有断言 FAIL
#
# 判据来源：docs/prds/2026-10-08-migrate-cleanup-0.13.0.md §7（AC）
#           docs/reports/2026-10-08-T510-arch-review.md（判定式 / 实测 E1–E5 / B2）
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$REPO/bin/nao-skill.js"
PKG_VERSION="$(node -p "try{require('$REPO/package.json').version}catch(e){'?'}")"

MODE="ac"
case "${1:-}" in
  --baseline) MODE="baseline" ;;
  "" ) ;;
  * ) printf '未知参数: %s（可用: --baseline）\n' "$1" >&2; exit 2 ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nao-t510-verify.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------- 计数 / 断言
PASS=0; FAIL=0
declare -A AC_PASS=() AC_FAIL=()
AC="PRE"
_ok()  { PASS=$((PASS+1)); AC_PASS[$AC]=$(( ${AC_PASS[$AC]:-0} + 1 )); printf '  [PASS] %s\n' "$*"; }
_bad() { FAIL=$((FAIL+1)); AC_FAIL[$AC]=$(( ${AC_FAIL[$AC]:-0} + 1 )); printf '  [FAIL] %s\n' "$*"; }
_sec() { AC="$1"; printf '\n--- %s · %s\n' "$1" "$2"; }
_note(){ printf '  [NOTE] %s\n' "$*"; }

eq()      { [ "$1" = "$2" ] && _ok "$3" || _bad "$3（期望=$1 实际=$2）"; }
neq()     { [ "$1" != "$2" ] && _ok "$3" || _bad "$3（不应等于 $1）"; }
truthy()  { [ "$1" = "1" ] && _ok "$2" || _bad "$2"; }
file()    { [ -f "$1" ] && _ok "$2" || _bad "$2（文件不存在: $1）"; }
absent()  { [ ! -e "$1" ] && _ok "$2" || _bad "$2（不应存在: $1）"; }
contains(){ printf '%s' "$1" | grep -qF -- "$2" && _ok "$3" || _bad "$3（未包含: $2）"; }
not_cont(){ printf '%s' "$1" | grep -qF -- "$2" && _bad "$3（不应包含: $2）" || _ok "$3"; }
matches() { printf '%s' "$1" | grep -qE -- "$2" && _ok "$3" || _bad "$3（不匹配: $2）"; }
sfile()   { grep -qF -- "$2" "$1" 2>/dev/null && _ok "$3" || _bad "$3（$1 未包含: $2）"; }

RC=0; OUT=""; ERR=""
run() { # run <fixture-dir> <子命令...>
  local d="$1"; shift
  ( cd "$d" && node "$CLI" "$@" ) >"$WORK/out" 2>"$WORK/err"
  RC=$?
  OUT="$(cat "$WORK/out")"; ERR="$(cat "$WORK/err")"
}
both() { printf '%s\n%s' "$OUT" "$ERR"; }

# ---------------------------------------------------------------- 夹具
new_fx() { mktemp -d "$WORK/fx.XXXXXX"; }
git_fx() { ( cd "$1" && git init -q && git config user.email qa@local && git config user.name qa \
             && git add -A && git commit -qm fixture ) >/dev/null 2>&1; }
git_commit_all() { ( cd "$1" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1; }
porcelain() { ( cd "$1" && git status --porcelain 2>/dev/null ); }

# 旧版全套 .agents/（含真实旧脚本 + prompts/common/checklists/templates + 共享 skill）
make_legacy() {
  local d="$1"
  mkdir -p "$d/.agents"
  cp -a "$REPO/.agents/." "$d/.agents/"
  printf '0.0.1-legacy\n' > "$d/.agents/.nao-version"
  mkdir -p "$d/.agents/skills/nue-ui-dev"
  printf -- '---\nname: nue-ui-dev\ndescription: downstream shared skill (must survive)\n---\n' \
    > "$d/.agents/skills/nue-ui-dev/SKILL.md"
  printf '# 夹具 AGENTS.md\n' > "$d/AGENTS.md"
}

# minimal 型：.agents/prompts/** 存在 · 无 .agents/scripts/ · 全仓 nao 引用 0
make_minimal() {
  local d="$1"
  mkdir -p "$d/.agents/prompts" "$d/docs"
  local r
  for r in product-manager frontend-developer test-engineer; do
    printf -- '---\nname: %s\ndescription: synthetic minimal role card\n---\n' "$r" \
      > "$d/.agents/prompts/$r.md"
  done
  printf '# Synthetic minimal project\n\n纯描述性 demo，无舰队引用。\n' > "$d/README.md"
  printf '# Plan\n\n- 记录需求\n' > "$d/docs/plan.md"
}

# 已迁移仓型：shim 就位 + .nao-version=当前版本 + docs 含 nao-fleet 引用
make_migrated() {
  local d="$1"
  mkdir -p "$d/.agents/scripts" "$d/docs"
  cp "$REPO/bin/shim/nao-fleet.sh" "$d/.agents/scripts/nao-fleet.sh"
  chmod +x "$d/.agents/scripts/nao-fleet.sh"
  printf '%s' "$PKG_VERSION" > "$d/.agents/.nao-version"   # writeVersion() 不写尾随换行
  printf '# 夹具 AGENTS.md\n' > "$d/AGENTS.md"
  printf '舰队体检：bash .agents/scripts/nao-fleet.sh check\n' > "$d/docs/README.md"
}

# 干净项目型（无 legacy 资产）
make_clean() { local d="$1"; mkdir -p "$d/docs"; printf '# clean\n' > "$d/README.md"; }

lock_single() {
  printf '%s' '{"skills":{"frontend-design":{"source":"anthropics/skills","ref":"main"},"keep-me":{"source":"example/keep","ref":"v1"}},"version":1}'
}
LOCK_SINGLE_EXPECTED='{"skills":{"keep-me":{"source":"example/keep","ref":"v1"}},"version":1}'

lock_fail_dup() { # 单行 + 同名 key 重复 ⇒ 删除后 key 仍在（校验失败）
  printf '%s' '{"skills":{"frontend-design":{"source":"a/b","ref":"main"},"keep-me":{"source":"c/d","ref":"v1"},"frontend-design":{"source":"a/b","ref":"main"}},"version":1}'
}
lock_fail_last() { # 单行 + 目标为末位属性且无前置分隔逗号 ⇒ 无法安全裁剪（返回 null）
  printf '%s' '{"version":1,"skills":{"frontend-design":{"source":"a/b"}}}'
}

lock_multi() { # $1 = 缩进空格数
  local ind="$1" pad
  pad="$(printf '%*s' "$ind" '')"
  cat <<EOF
{
${pad}"version": 1,
${pad}"skills": {
${pad}${pad}"frontend-design": {
${pad}${pad}${pad}"source": "anthropics/skills",
${pad}${pad}${pad}"ref": "main"
${pad}${pad}},
${pad}${pad}"keep-me": {
${pad}${pad}${pad}"source": "example/keep",
${pad}${pad}${pad}"ref": "v1"
${pad}${pad}}
${pad}}
}
EOF
}

# 与「逐行去掉该条目块」的期望结果一致（沿用并扩展 tests/t4/cases/08）
expected_multiline() {
  awk '/"frontend-design"/{skip=1} skip{if(/^[[:space:]]+},?$/){skip=0} next} {print}' "$1"
}

md5f() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }
mtimef() { stat -c %Y "$1" 2>/dev/null; }
hits() { grep -oF -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' '; }

# =============================================================================
printf '======================================================================\n'
printf 'T510 migrate 验收断言 · mode=%s\n' "$MODE"
printf '  repo      : %s\n' "$REPO"
printf '  CLI       : %s (v%s)\n' "$CLI" "$PKG_VERSION"
printf '  夹具根    : %s（退出时清理）\n' "$WORK"
if [ "$MODE" = "baseline" ]; then
  printf '  语义      : 断言「缺陷仍可复现」；PASS=缺陷在场（修复后应整体转 FAIL，再切默认模式）\n'
else
  printf '  语义      : 断言「AC 达成」；PASS=符合 PRD §7\n'
fi
printf '  门禁基线  : npm test rc=0 · tests/t4/run.sh 10 用例/179 断言/0 FAIL · check rc=0\n'
printf '======================================================================\n'

# -------------------------------------------------------------------- F3
_sec AC-F3-1 "迁移后 .nao-migrated 不存在 + 代码无写入点"
fx="$(new_fx)"; make_legacy "$fx"; git_fx "$fx"
run "$fx" migrate
if [ "$MODE" = "baseline" ]; then
  truthy "$([ -e "$fx/.agents/.nao-migrated" ] && echo 1 || echo 0)" "BASELINE: 旧版迁移后 .agents/.nao-migrated 被写入（死标记在场）"
  n="$(grep -c 'MIGRATED_FILE' "$CLI" 2>/dev/null || true)"
  truthy "$([ "${n:-0}" -ge 1 ] && echo 1 || echo 0)" "BASELINE: bin/nao-skill.js 仍含 MIGRATED_FILE 写入点（出现 ${n:-0} 处）"
else
  eq 0 "$RC" "AC-F3-1: migrate exit=0"
  absent "$fx/.agents/.nao-migrated" "AC-F3-1: 迁移后 .agents/.nao-migrated 不存在"
  eq 0 "$(grep -c 'MIGRATED_FILE' "$CLI" 2>/dev/null || true)" "AC-F3-1: bin/nao-skill.js 无 MIGRATED_FILE 写入点"
fi

_sec AC-F3-2 "幂等：二次 migrate 无提示 + git 干净"
run "$fx" migrate
run2="$(both)"
if [ "$MODE" = "baseline" ]; then
  _note "基线：二次 migrate rc=$RC（此断言与标记无关，理应已绿）"
fi
eq 0 "$(printf '%s' "$run2" | grep -cE '(迁移|migrat|nao-obsolete)' || true)" "AC-F3-2: 二次 migrate 输出不含迁移提示（BR4）"
git_commit_all "$fx" "after-migrate"
run "$fx" migrate
eq "" "$(porcelain "$fx")" "AC-F3-2: CLI 版本一致时 git status --porcelain 为空"

_sec AC-F3-3 "存量 .nao-migrated 只读不写 / init 不阻塞"
fx3="$(new_fx)"; make_legacy "$fx3"
printf '0.0.0-old\n' > "$fx3/.agents/.nao-migrated"
git_fx "$fx3"
run "$fx3" migrate
eq 0 "$RC" "AC-F3-3: migrate exit=0（不阻塞）"
got="$(cat "$fx3/.agents/.nao-migrated" 2>/dev/null)"
if [ "$MODE" = "baseline" ]; then
  eq "$PKG_VERSION" "$got" "BASELINE: migrate 覆写存量 .nao-migrated（0.0.0-old → v$PKG_VERSION）"
else
  eq "0.0.0-old" "$got" "AC-F3-3: 存量 .nao-migrated 未被读写（保持 0.0.0-old）"
fi
fx3b="$(new_fx)"; make_clean "$fx3b"
printf '0.0.0-old\n' > "$fx3b/.agents-seed-marker"    # 占位，避免误判路径
mkdir -p "$fx3b/.agents"; printf '0.0.0-old\n' > "$fx3b/.agents/.nao-migrated"
rm -f "$fx3b/.agents-seed-marker"
git_fx "$fx3b"
run "$fx3b" init
eq 0 "$RC" "AC-F3-3: init 在带旧标记的干净项目 exit=0"
eq "0.0.0-old" "$(cat "$fx3b/.agents/.nao-migrated" 2>/dev/null)" "AC-F3-3: init 不读写存量 .nao-migrated"
d3="$(grep -lF '已废弃' "$REPO/README.md" "$REPO/docs/adr/2026-10-08-migrate-shim-and-marker.md" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MODE" = "baseline" ]; then
  _note "基线：README/ADR「已废弃」说明为文档项（ADR 已含），不计入缺陷复现"
else
  truthy "$([ "${d3:-0}" -ge 1 ] && echo 1 || echo 0)" "AC-F3-3: README 或 ADR 有 .nao-migrated「已废弃」说明"
fi

# -------------------------------------------------------------------- F4
_sec AC-F4-1 "minimal 型：不写 shim + 显式告知"
fxm="$(new_fx)"; make_minimal "$fxm"; git_fx "$fxm"
nref="$(grep -rlE 'nao-fleet|nao-skill|NAO_SKILLS' "$fxm" 2>/dev/null | wc -l | tr -d ' ')"
eq 0 "$nref" "前置: minimal 夹具全仓 nao-fleet|nao-skill|NAO_SKILLS 命中 0"
run "$fxm" migrate
if [ "$MODE" = "baseline" ]; then
  truthy "$([ -f "$fxm/.agents/scripts/nao-fleet.sh" ] && echo 1 || echo 0)" "BASELINE: minimal 迁移后凭空出现 .agents/scripts/nao-fleet.sh（F4 缺陷）"
else
  eq 0 "$RC" "AC-F4-1: migrate exit=0"
  absent "$fxm/.agents/scripts/nao-fleet.sh" "AC-F4-1: 未创建 .agents/scripts/nao-fleet.sh"
  contains "$(both)" "纯文档迁移" "AC-F4-1: 输出含「纯文档迁移」告知"
  contains "$(both)" "--shim" "AC-F4-1: 输出含逃生口 --shim 提示"
fi
# F4 判定式（NFR2）：.pi/** 硬排除 —— 夹具仅 .pi/ 内含 nao-fleet/nao-skill 字样，判定不得因此为 true
fxpi="$(new_fx)"; make_minimal "$fxpi"
mkdir -p "$fxpi/.pi/npm/node_modules/@nathan33/nao-skill/.agents/scripts"
printf 'bash .agents/scripts/nao-fleet.sh check\n' \
  > "$fxpi/.pi/npm/node_modules/@nathan33/nao-skill/.agents/scripts/nao-fleet.sh"
printf '{"packages":["npm:@nathan33/nao-skill@%s"]}\n' "$PKG_VERSION" > "$fxpi/.pi/settings.json"
git_fx "$fxpi"
run "$fxpi" migrate
if [ "$MODE" = "baseline" ]; then
  truthy "$([ -f "$fxpi/.agents/scripts/nao-fleet.sh" ] && echo 1 || echo 0)" "BASELINE: 仅 .pi/ 引用的夹具仍被无条件装 shim（F4 缺陷）"
else
  absent "$fxpi/.agents/scripts/nao-fleet.sh" "AC-F4-1/判定式: .pi/** 硬排除 —— 仅 .pi/ 含引用不得判为需装 shim"
fi

_sec AC-F4-2 "已迁移仓：shim 内容与 mtime 不变 + git 干净"
fxr="$(new_fx)"; make_migrated "$fxr"; git_fx "$fxr"
shim="$fxr/.agents/scripts/nao-fleet.sh"
m0="$(md5f "$shim")"; t0="$(mtimef "$shim")"
sleep 1
run "$fxr" migrate
eq 0 "$RC" "AC-F4-2: migrate exit=0"
eq "$m0" "$(md5f "$shim")" "AC-F4-2: shim 内容不变"
eq "$t0" "$(mtimef "$shim")" "AC-F4-2: shim mtime 不变"
eq "" "$(porcelain "$fxr")" "AC-F4-2: git status --porcelain 为空（零回归）"

_sec AC-F4-3 "开关覆盖：--no-shim / --shim / 互斥 exit 2"
fxa="$(new_fx)"; make_legacy "$fxa"; git_fx "$fxa"
run "$fxa" migrate --no-shim
if [ "$MODE" = "baseline" ]; then
  eq 2 "$RC" "BASELINE: --no-shim 未被识别（未知参数 exit 2）"
else
  eq 0 "$RC" "AC-F4-3: migrate --no-shim exit=0"
  absent "$fxa/.agents/scripts/nao-fleet.sh" "AC-F4-3: --no-shim 不写 shim"
fi
fxb="$(new_fx)"; make_minimal "$fxb"; git_fx "$fxb"
run "$fxb" migrate --shim
if [ "$MODE" = "baseline" ]; then
  eq 2 "$RC" "BASELINE: --shim 未被识别（未知参数 exit 2）"
else
  eq 0 "$RC" "AC-F4-3: minimal migrate --shim exit=0"
  file "$fxb/.agents/scripts/nao-fleet.sh" "AC-F4-3: --shim 强制写入 shim"
fi
fxc="$(new_fx)"; make_legacy "$fxc"; git_fx "$fxc"
run "$fxc" migrate --shim --no-shim
eq 2 "$RC" "AC-F4-3: --shim --no-shim 互斥 ⇒ exit 2"
if [ "$MODE" = "ac" ]; then
  not_cont "$ERR" "未知参数" "AC-F4-3: 冲突报错为可读互斥信息（非『未知参数』）"
  matches "$ERR" '互斥|不能同时|冲突' "AC-F4-3: 冲突错误含互斥语义"
fi

_sec AC-F4-4 "init 边界：默认装 / --no-shim 不装并 warn / --force 转 migrate 仍装"
fxd="$(new_fx)"; make_clean "$fxd"; git_fx "$fxd"
run "$fxd" init
eq 0 "$RC" "AC-F4-4: init exit=0"
file "$fxd/.agents/scripts/nao-fleet.sh" "AC-F4-4: init 默认写 shim"
fxe="$(new_fx)"; make_clean "$fxe"; git_fx "$fxe"
run "$fxe" init --no-shim
if [ "$MODE" = "baseline" ]; then
  eq 2 "$RC" "BASELINE: init --no-shim 未被识别（未知参数 exit 2）"
else
  eq 0 "$RC" "AC-F4-4: init --no-shim exit=0"
  if [ "$RC" = 0 ]; then
    absent "$fxe/.agents/scripts/nao-fleet.sh" "AC-F4-4: init --no-shim 不写 shim"
    truthy "$([ -n "$(both)" ] && echo 1 || echo 0)" "AC-F4-4: init --no-shim 打印 warn"
  else
    _bad "AC-F4-4: init --no-shim 未生效（rc=$RC）⇒ 跳过子断言"
  fi
fi
fxf="$(new_fx)"; make_legacy "$fxf"; git_fx "$fxf"
run "$fxf" init --force
eq 0 "$RC" "AC-F4-4: init --force 走 migrate exit=0"
file "$fxf/.agents/scripts/nao-fleet.sh" "AC-F4-4: init --force 转 migrate 仍装 shim"

# -------------------------------------------------------------------- F7
_sec AC-F7-1 "单行压缩 lock：去重 + 除被删 token 外其余字节不变"
fx1="$(new_fx)"; make_legacy "$fx1"; lock_single > "$fx1/skills-lock.json"; git_fx "$fx1"
run "$fx1" migrate
if [ "$MODE" = "baseline" ]; then
  eq 1 "$(hits "$fx1/skills-lock.json" 'frontend-design')" "BASELINE: 单行 lock 静默跳过（frontend-design 仍在，1 命中）"
  eq 0 "$(printf '%s' "$ERR" | grep -cE 'skills-lock|手工移除|去重' || true)" "BASELINE: 无任何 lock 告警（静默失败）"
else
  eq 0 "$RC" "AC-F7-1: migrate exit=0"
  eq 0 "$(hits "$fx1/skills-lock.json" 'frontend-design')" "AC-F7-1: frontend-design 命中 0"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$fx1/skills-lock.json" >/dev/null 2>&1 \
    && _ok "AC-F7-1: 结果仍是合法 JSON" || _bad "AC-F7-1: 结果 JSON 非法"
  if cmp -s <(printf '%s' "$LOCK_SINGLE_EXPECTED") "$fx1/skills-lock.json"; then
    _ok "AC-F7-1: 结果 == 仅删该条目（其余字节逐字节不变）"
  else
    _bad "AC-F7-1: 结果与「仅删该条目」不一致（存在整文件重排）"
    diff <(printf '%s\n' "$LOCK_SINGLE_EXPECTED") "$fx1/skills-lock.json" | head -5
  fi
fi

_sec AC-F7-2 "4 空格 / 2 空格多行 lock：与「逐行去条」期望逐字节一致"
for ind in 4 2; do
  fx2="$(new_fx)"; make_legacy "$fx2"
  lock_multi "$ind" > "$fx2/skills-lock.json"
  expected_multiline "$fx2/skills-lock.json" > "$WORK/lock-expected.json"
  git_fx "$fx2"
  run "$fx2" migrate
  eq 0 "$(hits "$fx2/skills-lock.json" 'frontend-design')" "AC-F7-2(${ind}空格): frontend-design 命中 0"
  if cmp -s "$WORK/lock-expected.json" "$fx2/skills-lock.json"; then
    _ok "AC-F7-2(${ind}空格): 与「逐行去条」期望逐字节一致"
  else
    _bad "AC-F7-2(${ind}空格): 与期望不一致"
    diff "$WORK/lock-expected.json" "$fx2/skills-lock.json" | head -5
  fi
done

_sec AC-F7-3 "无法安全去重：文件不变 + 恰一行 warn（不静默）"
# 形态①：末位属性且无前置分隔逗号 ⇒ 无法安全裁剪（removeJsonProperty 返回 null）
fx3c="$(new_fx)"; make_legacy "$fx3c"; lock_fail_last > "$fx3c/skills-lock.json"; git_fx "$fx3c"
m3="$(md5f "$fx3c/skills-lock.json")"
run "$fx3c" migrate
eq 0 "$RC" "AC-F7-3: migrate exit=0（其余步骤完成）"
eq "$m3" "$(md5f "$fx3c/skills-lock.json")" "AC-F7-3: lock 文件字节不变"
nwarn="$(printf '%s' "$ERR" | grep -c '手工移除' || true)"
if [ "$MODE" = "baseline" ]; then
  eq 0 "$nwarn" "BASELINE: 静默失败（无「手工移除」告警）"
else
  eq 1 "$nwarn" "AC-F7-3: 恰一行「手工移除」warn"
fi
# 形态②：单行 + 同名 key 重复 ⇒ 删除后 key 仍在（强制校验失败）
fx3d="$(new_fx)"; make_legacy "$fx3d"; lock_fail_dup > "$fx3d/skills-lock.json"; git_fx "$fx3d"
m4="$(md5f "$fx3d/skills-lock.json")"
run "$fx3d" migrate
eq 0 "$RC" "AC-F7-3(重复key): migrate exit=0"
eq "$m4" "$(md5f "$fx3d/skills-lock.json")" "AC-F7-3(重复key): lock 文件字节不变"
nwarn2="$(printf '%s' "$ERR" | grep -c '手工移除' || true)"
if [ "$MODE" = "baseline" ]; then
  eq 0 "$nwarn2" "BASELINE(重复key): 静默失败"
else
  eq 1 "$nwarn2" "AC-F7-3(重复key): 恰一行「手工移除」warn"
fi

_sec AC-F7-4 "B2：无 legacy 资产 + lock 含 frontend-design ⇒ 去重照常"
fxb2="$(new_fx)"; make_clean "$fxb2"; lock_single > "$fxb2/skills-lock.json"; git_fx "$fxb2"
run "$fxb2" migrate
if [ "$MODE" = "baseline" ]; then
  eq 1 "$(hits "$fxb2/skills-lock.json" 'frontend-design')" "BASELINE: B2 静默跳过（无 legacy ⇒ 早退 init，去重不执行）"
  eq 0 "$(printf '%s' "$ERR" | grep -c '手工移除' || true)" "BASELINE: 无 lock 告警"
else
  eq 0 "$RC" "AC-F7-4: migrate exit=0"
  eq 0 "$(hits "$fxb2/skills-lock.json" 'frontend-design')" "AC-F7-4: 去重照常生效（命中 0）"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$fxb2/skills-lock.json" >/dev/null 2>&1 \
    && _ok "AC-F7-4: 结果仍是合法 JSON" || _bad "AC-F7-4: 结果 JSON 非法"
  matches "$(both)" 'init|去重|skills-lock' "AC-F7-4: 输出说明走的是 init/去重路径"
fi
fxb2b="$(new_fx)"; make_clean "$fxb2b"
lock_multi 4 > "$fxb2b/skills-lock.json"; git_fx "$fxb2b"
run "$fxb2b" migrate
if [ "$MODE" = "baseline" ]; then
  eq 1 "$(hits "$fxb2b/skills-lock.json" 'frontend-design')" "BASELINE: B2 多行无 legacy 亦静默跳过"
else
  eq 0 "$(hits "$fxb2b/skills-lock.json" 'frontend-design')" "AC-F7-4: B2 多行形态亦去重（命中 0）"
fi

# -------------------------------------------------------------------- DOC / REL（仅验收模式计入）
_sec AC-DOC/REL "文档与发布件一致性（静态）"
if [ "$MODE" = "baseline" ]; then
  _note "文档/发布件为交付项，基线模式仅记录：README --shim 未写、SKILL.md/--help 未同步、package.json=$PKG_VERSION"
else
  sfile "$REPO/README.md" "--no-shim" "AC-DOC: README 记录 --shim/--no-shim 开关"
  sfile "$REPO/README.md" "纯文档" "AC-DOC: README 记录 minimal/纯文档例外"
  h="$(node "$CLI" --help 2>&1)"
  contains "$h" "--shim" "AC-DOC: --help 含 --shim"
  contains "$h" "--no-shim" "AC-DOC: --help 含 --no-shim"
  matches "$h" '判定|引用|nao-fleet' "AC-DOC: --help 说明判定式"
  tpl="$(cat "$REPO/.agents/templates/AGENTS.md.example" 2>/dev/null)"
  matches "$tpl" '纯文档|无引用' "AC-DOC: 模板指针段补「纯文档仓除外」"
  sk="$(cat "$REPO/.agents/skills/nao-fleet/SKILL.md" 2>/dev/null)"
  matches "$sk" '--no-shim|判定式|纯文档' "AC-DOC: SKILL.md §3 同步判定/开关"
  sfile "$REPO/docs/adr/2026-10-08-migrate-shim-and-marker.md" "已废弃" "AC-DOC: ADR 说明 .nao-migrated 已废弃"
  eq "0.13.0" "$PKG_VERSION" "AC-REL: package.json = 0.13.0"
  file "$REPO/docs/releases/v0.13.0.md" "AC-REL: docs/releases/v0.13.0.md 存在"
  rel="$(cat "$REPO/docs/releases/v0.13.0.md" 2>/dev/null)"
  matches "$rel" '升级|回滚' "AC-REL: release notes 含升级/回滚说明"
fi
_note "AC-GOV（PR 评论 / 恰好 1 commit / arch 终签）与 AC-SCOPE（diff 面审查）属流程判据，由 PM/RD 在 PR 侧核对，不在本脚本自动断言"

# ---------------------------------------------------------------- 汇总
printf '\n======================================================================\n'
printf 'T510 汇总（mode=%s）\n' "$MODE"
printf '  %-12s %4s %4s\n' "AC" "PASS" "FAIL"
all_ac="$(printf '%s\n' "${!AC_PASS[@]}" "${!AC_FAIL[@]}" | sort -u)"
for a in $all_ac; do
  printf '  %-12s %4s %4s\n' "$a" "${AC_PASS[$a]:-0}" "${AC_FAIL[$a]:-0}"
done
printf '  %-12s %4s %4s\n' "TOTAL" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAIL (%d 项断言未过)\n' "$FAIL"
  printf '======================================================================\n'
  exit 1
fi
printf 'RESULT: PASS\n'
printf '======================================================================\n'
exit 0
