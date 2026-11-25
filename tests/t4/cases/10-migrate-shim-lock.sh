#!/usr/bin/env bash
# 用例 10 —— T510 migrate 收尾：shim 判定式 / 开关 / 单行 lock 去重 / B2 / 失败告警（Issue #21）
#
# AC 覆盖（PRD docs/prds/2026-10-08-migrate-cleanup-0.13.0.md §7）：
#   AC-F3-1/3  .nao-migrated 不再写入 + 存量标记不读写
#   AC-F4-1/2/3/4  minimal 判定 + 开关覆盖 + init 边界
#   AC-F7-1/2/3    单行去重逐字节不变 / 多行 / 失败恰一行 warn
#   AC-F7-4 (=B2)  无 legacy 资产时去重照常
#   AC-F8 (B1)     --dry-run 预演：清单逐条 + 盘面零写入 + 无 legacy 边界 + 与 --force 互斥 + 清单==真跑
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd git

CLI="$T4_ROOT/bin/nao-skill.js"
[ -f "$CLI" ] || t4_blocked "bin/nao-skill.js 缺失"

# --- 本地执行封装（直接跑仓库 CLI，不依赖 tarball 物化）------------------------
T510_OUT=""; T510_ERR=""; T510_RC=0
t510_run() { # t510_run <dir> <args...>
  local d="$1"; shift
  local of ef
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$d" && node "$CLI" "$@" ) >"$of" 2>"$ef"
  T510_RC=$?
  T510_OUT="$(cat "$of")"; T510_ERR="$(cat "$ef")"
  rm -f "$of" "$ef"
}
both()    { printf '%s\n%s' "$T510_OUT" "$T510_ERR"; }
porcelain(){ ( cd "$1" && git status --porcelain 2>/dev/null ); }
md5f()    { md5sum "$1" 2>/dev/null | awk '{print $1}'; }
mtimef()  { stat -c %Y "$1" 2>/dev/null; }
hits()    { grep -oF -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' '; }
git_commit_all() { ( cd "$1" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1; }

# --- 夹具 --------------------------------------------------------------------
make_minimal() { # .agents/prompts 存在 · 无 scripts · 全仓 nao 引用 0
  local d="$1" r
  mkdir -p "$d/.agents/prompts" "$d/docs"
  for r in product-manager frontend-developer test-engineer; do
    printf -- '---\nname: %s\ndescription: synthetic minimal role card\n---\n' "$r" > "$d/.agents/prompts/$r.md"
  done
  printf '# Synthetic minimal project\n\n纯描述性 demo，无舰队引用。\n' > "$d/README.md"
  printf '# Plan\n\n- 记录需求\n' > "$d/docs/plan.md"
}
make_clean() { local d="$1"; mkdir -p "$d/docs"; printf '# clean project\n' > "$d/README.md"; }
make_legacy() { # 旧版全套 .agents/（含真 nao-fleet.sh）+ 共享 skill
  local d="$1"
  mkdir -p "$d/.agents"
  cp -a "$T4_ROOT/.agents/." "$d/.agents/"
  printf '0.0.1-legacy\n' > "$d/.agents/.nao-version"
  mkdir -p "$d/.agents/skills/nue-ui-dev"
  printf -- '---\nname: nue-ui-dev\ndescription: downstream shared skill (must survive)\n---\n' \
    > "$d/.agents/skills/nue-ui-dev/SKILL.md"
  printf '# 夹具 AGENTS.md\n' > "$d/AGENTS.md"
}
make_migrated() { # shim 就位 + 版本一致 + docs 有 nao-fleet 引用
  local d="$1"
  mkdir -p "$d/.agents/scripts" "$d/docs"
  cp "$T4_ROOT/bin/shim/nao-fleet.sh" "$d/.agents/scripts/nao-fleet.sh"
  chmod +x "$d/.agents/scripts/nao-fleet.sh"
  printf '%s' "$PKG_VERSION" > "$d/.agents/.nao-version"
  printf '# 夹具 AGENTS.md\n' > "$d/AGENTS.md"
  printf '舰队体检：bash .agents/scripts/nao-fleet.sh check\n' > "$d/docs/README.md"
}
lock_single() { printf '%s' '{"skills":{"frontend-design":{"source":"anthropics/skills","ref":"main"},"keep-me":{"source":"example/keep","ref":"v1"}},"version":1}'; }
LOCK_SINGLE_EXPECTED='{"skills":{"keep-me":{"source":"example/keep","ref":"v1"}},"version":1}'
lock_fail_dup() { printf '%s' '{"skills":{"frontend-design":{"source":"a/b","ref":"main"},"keep-me":{"source":"c/d","ref":"v1"},"frontend-design":{"source":"a/b","ref":"main"}},"version":1}'; }
# 形态①：唯一 key 但末位属性无可安全删除的分隔逗号（合法 JSON，文本级裁剪拒绝）
lock_trim_unsafe() { printf '%s' '{"skills":{"frontend-design":{"source":"a/b","ref":"main"}},"version":1}'; }
lock_multi2() { # 2 空格缩进多行
  cat <<'EOF'
{
  "version": 1,
  "skills": {
    "frontend-design": {
      "source": "anthropics/skills",
      "ref": "main"
    },
    "keep-me": {
      "source": "example/keep",
      "ref": "v1"
    }
  }
}
EOF
}
expected_multiline() {
  awk '/"frontend-design"/{skip=1} skip{if(/^[[:space:]]+},?$/){skip=0} next} {print}' "$1"
}

# ============================================================== F3
fx="$(t4_fixture)"; make_legacy "$fx"
t510_run "$fx" migrate
t4_assert_eq "0" "$T510_RC" "F3: legacy migrate exit=0"
t4_assert_absent "$fx/.agents/.nao-migrated" "F3: 迁移后不写 .agents/.nao-migrated"
t4_assert_eq "0" "$(grep -c 'MIGRATED_FILE' "$CLI" 2>/dev/null || true)" "F3: 代码无 MIGRATED_FILE 写入点"

fxmk="$(t4_fixture)"; make_legacy "$fxmk"
printf '0.0.0-old\n' > "$fxmk/.agents/.nao-migrated"
t510_run "$fxmk" migrate
t4_assert_eq "0" "$T510_RC" "F3-3: 带存量 .nao-migrated migrate exit=0"
t4_assert_eq "0.0.0-old" "$(cat "$fxmk/.agents/.nao-migrated" 2>/dev/null)" "F3-3: 存量 .nao-migrated 未被读写"

# ============================================================== F4-1 minimal
fxm="$(t4_fixture)"; make_minimal "$fxm"
nref="$(grep -rlE 'nao-fleet|nao-skill|NAO_SKILLS' "$fxm" 2>/dev/null | wc -l | tr -d ' ')"
t4_assert_eq "0" "$nref" "F4-1 前置: minimal 夹具全仓引用命中 0"
t510_run "$fxm" migrate
t4_assert_eq "0" "$T510_RC" "F4-1: minimal migrate exit=0"
t4_assert_absent "$fxm/.agents/scripts/nao-fleet.sh" "F4-1: 未创建 shim"
t4_assert_contains "$(both)" "纯文档迁移" "F4-1: 输出含「纯文档迁移」告知"
t4_assert_contains "$(both)" "--shim" "F4-1: 输出含逃生口 --shim"

# ============================================================== F4-3 开关
fxa="$(t4_fixture)"; make_legacy "$fxa"
t510_run "$fxa" migrate --no-shim
t4_assert_eq "0" "$T510_RC" "F4-3: legacy migrate --no-shim exit=0"
t4_assert_absent "$fxa/.agents/scripts/nao-fleet.sh" "F4-3: --no-shim 不写 shim"

fxb="$(t4_fixture)"; make_minimal "$fxb"
t510_run "$fxb" migrate --shim
t4_assert_eq "0" "$T510_RC" "F4-3: minimal migrate --shim exit=0"
t4_assert_file "$fxb/.agents/scripts/nao-fleet.sh" "F4-3: --shim 强制写入 shim"

fxc="$(t4_fixture)"; make_legacy "$fxc"
t510_run "$fxc" migrate --shim --no-shim
t4_assert_eq "2" "$T510_RC" "F4-3: --shim --no-shim 互斥 ⇒ exit 2"
t4_assert_not_contains "$T510_ERR" "未知参数" "F4-3: 冲突报错非「未知参数」"
t4_assert_match "$T510_ERR" '互斥|不能同时|冲突' "F4-3: 冲突错误含互斥语义"

# ============================================================== F4-2 已迁移仓零回归
fxr="$(t4_fixture)"; make_migrated "$fxr"; git_commit_all "$fxr" fixture
shim="$fxr/.agents/scripts/nao-fleet.sh"
m0="$(md5f "$shim")"; t0="$(mtimef "$shim")"
sleep 1
t510_run "$fxr" migrate
t4_assert_eq "0" "$T510_RC" "F4-2: migrated migrate exit=0"
t4_assert_eq "$m0" "$(md5f "$shim")" "F4-2: shim 内容不变"
t4_assert_eq "$t0" "$(mtimef "$shim")" "F4-2: shim mtime 不变"
t4_assert_eq "" "$(porcelain "$fxr")" "F4-2: git status --porcelain 为空"

# ============================================================== F4-4 init 边界
fxd="$(t4_fixture)"; make_clean "$fxd"
t510_run "$fxd" init
t4_assert_eq "0" "$T510_RC" "F4-4: init exit=0"
t4_assert_file "$fxd/.agents/scripts/nao-fleet.sh" "F4-4: init 默认写 shim"

fxe="$(t4_fixture)"; make_clean "$fxe"
t510_run "$fxe" init --no-shim
t4_assert_eq "0" "$T510_RC" "F4-4: init --no-shim exit=0"
t4_assert_absent "$fxe/.agents/scripts/nao-fleet.sh" "F4-4: init --no-shim 不写 shim"
t4_assert_ne "" "$(both)" "F4-4: init --no-shim 打印 warn"

fxf="$(t4_fixture)"; make_legacy "$fxf"
t510_run "$fxf" init --force
t4_assert_eq "0" "$T510_RC" "F4-4: init --force 走 migrate exit=0"
t4_assert_file "$fxf/.agents/scripts/nao-fleet.sh" "F4-4: init --force 转 migrate 仍装 shim"

# ============================================================== F7-1 单行去重
fx1="$(t4_fixture)"; make_legacy "$fx1"; lock_single > "$fx1/skills-lock.json"
t510_run "$fx1" migrate
t4_assert_eq "0" "$T510_RC" "F7-1: 单行 lock migrate exit=0"
t4_assert_eq "0" "$(hits "$fx1/skills-lock.json" 'frontend-design')" "F7-1: frontend-design 命中 0"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$fx1/skills-lock.json" >/dev/null 2>&1 \
  && t4_ok "F7-1: 结果仍是合法 JSON" || t4_bad "F7-1: 结果 JSON 非法"
if cmp -s <(printf '%s' "$LOCK_SINGLE_EXPECTED") "$fx1/skills-lock.json"; then
  t4_ok "F7-1: 除被删条目外逐字节不变（无整文件重排）"
else
  t4_bad "F7-1: 与「仅删该条目」不一致"
  diff <(printf '%s\n' "$LOCK_SINGLE_EXPECTED") "$fx1/skills-lock.json" 2>/dev/null | head -5
fi

# ============================================================== F7-2 多行保缩进
fx2="$(t4_fixture)"; make_legacy "$fx2"; lock_multi2 > "$fx2/skills-lock.json"
expected_multiline "$fx2/skills-lock.json" > "$T4_CACHE_DIR/t510-lock-expected.json"
t510_run "$fx2" migrate
t4_assert_eq "0" "$T510_RC" "F7-2: 2 空格多行 lock migrate exit=0"
t4_assert_eq "0" "$(hits "$fx2/skills-lock.json" 'frontend-design')" "F7-2: frontend-design 命中 0"
if cmp -s "$T4_CACHE_DIR/t510-lock-expected.json" "$fx2/skills-lock.json"; then
  t4_ok "F7-2: 与「逐行去条」期望逐字节一致"
else
  t4_bad "F7-2: 与期望不一致"
  diff "$T4_CACHE_DIR/t510-lock-expected.json" "$fx2/skills-lock.json" 2>/dev/null | head -5
fi

# ============================================================== F7-3a 失败不静默 · 形态②真重复（D6）
fx3="$(t4_fixture)"; make_legacy "$fx3"; lock_fail_dup > "$fx3/skills-lock.json"
m3="$(md5f "$fx3/skills-lock.json")"
t510_run "$fx3" migrate
t4_assert_eq "0" "$T510_RC" "F7-3a: 真重复时 migrate exit=0（其余步骤完成）"
t4_assert_eq "$m3" "$(md5f "$fx3/skills-lock.json")" "F7-3a: lock 文件字节不变"
t4_assert_eq "1" "$(printf '%s' "$T510_ERR" | grep -c '手工移除' || true)" "F7-3a: 恰一行「手工移除」warn"
t4_assert_contains "$T510_ERR" "存在重复 frontend-design" "F7-3a/D6: 形态② 文案点名「存在重复」"
t4_assert_not_contains "$T510_ERR" "未能安全去重" "F7-3a/D6: 形态② 不得混用形态① 文案"
t4_assert_not_contains "$T510_ERR" "文本形态不支持自动裁剪" "F7-3a/D6: 形态② 不带裁剪理由"

# ============================================================== F7-3b 失败不静默 · 形态①唯一 key 未能安全裁剪（D6）
fx3b="$(t4_fixture)"; make_legacy "$fx3b"; lock_trim_unsafe > "$fx3b/skills-lock.json"
m3b="$(md5f "$fx3b/skills-lock.json")"
t510_run "$fx3b" migrate
t4_assert_eq "0" "$T510_RC" "F7-3b: 未能安全裁剪时 migrate exit=0（其余步骤完成）"
t4_assert_eq "$m3b" "$(md5f "$fx3b/skills-lock.json")" "F7-3b: lock 文件字节不变"
t4_assert_eq "1" "$(printf '%s' "$T510_ERR" | grep -c '手工移除' || true)" "F7-3b: 恰一行「手工移除」warn"
t4_assert_contains "$T510_ERR" "未能安全去重 frontend-design（文本形态不支持自动裁剪）" "F7-3b/D6: 形态① 文案点名真实原因（非「重复」）"
t4_assert_not_contains "$T510_ERR" "存在重复" "F7-3b/D6: 形态① 不得误报「重复」（唯一 key 不是重复）"
t4_assert_eq "1" "$(printf '%s' "$T510_ERR" | grep -c '未能安全去重' || true)" "F7-3b/D6: 形态① 恰一行专用 warn（不静默/不重复）"

# ============================================================== F7-4 (=B2) 无 legacy 去重
fxb2="$(t4_fixture)"; make_clean "$fxb2"; lock_single > "$fxb2/skills-lock.json"
t510_run "$fxb2" migrate
t4_assert_eq "0" "$T510_RC" "B2: 无 legacy 资产 migrate exit=0"
t4_assert_eq "0" "$(hits "$fxb2/skills-lock.json" 'frontend-design')" "B2: 去重照常生效（命中 0）"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$fxb2/skills-lock.json" >/dev/null 2>&1 \
  && t4_ok "B2: 结果仍是合法 JSON" || t4_bad "B2: 结果 JSON 非法"
t4_assert_match "$(both)" 'init|去重|skills-lock' "B2: 输出说明走的是 init/去重路径"

fxb2b="$(t4_fixture)"; make_clean "$fxb2b"; lock_multi2 > "$fxb2b/skills-lock.json"
t510_run "$fxb2b" migrate
t4_assert_eq "0" "$(hits "$fxb2b/skills-lock.json" 'frontend-design')" "B2: 多行形态亦去重（命中 0）"

# ============================================================== F8 B1 dry-run 预演阀门
tree_sig() { ( cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}' ); }

# F8-1 主路径：清单逐条 + 盘面零写入（树 sha 含 .agents/.pi/.nao-obsolete）
fx8="$(t4_fixture)"; make_legacy "$fx8"; lock_single > "$fx8/skills-lock.json"
sig8="$(tree_sig "$fx8")"
t510_run "$fx8" migrate --dry-run
t4_assert_eq "0" "$T510_RC" "F8-1/AC1: migrate --dry-run exit=0"
t4_assert_contains "$T510_OUT" "预演（--dry-run，不写盘）" "F8-1/AC1: 输出明示预演"
t4_assert_contains "$T510_OUT" "remove .agents/prompts（备份 .agents/.nao-obsolete/" "F8-1/AC1: 逐条列出目录类资产 + 备份目标"
t4_assert_contains "$T510_OUT" "remove .agents/roles.yaml" "F8-1/AC1: 逐条列出文件类资产"
t4_assert_contains "$T510_OUT" "将移除 skills-lock.json" "F8-1/AC1: 锁定去重动作也进清单"
t4_assert_contains "$T510_OUT" "预演完成：将移除" "F8-1/AC1: 结尾给出总数"
t4_assert_eq "$sig8" "$(tree_sig "$fx8")" "F8-1/AC1: 预演前后树 sha 一致（零写入）"
t4_assert_absent "$fx8/.agents/.nao-obsolete" "F8-1/AC1: 预演不建 .nao-obsolete"

# F8-2 边界：无 legacy ⇒ 「无可移除项」+ rc=0 + 盘面不变
fx8b="$(t4_fixture)"; make_clean "$fx8b"
sig8b="$(tree_sig "$fx8b")"
t510_run "$fx8b" migrate --dry-run
t4_assert_eq "0" "$T510_RC" "F8-2/AC2: 无 legacy 时 dry-run exit=0"
t4_assert_contains "$T510_OUT" "无可移除项" "F8-2/AC2: 输出「无可移除项」"
t4_assert_eq "$sig8b" "$(tree_sig "$fx8b")" "F8-2/AC2: 无 legacy 预演盘面不变"

# F8-3 负向闭环：不带 --dry-run 真跑仍照旧（备份目录内容 + 汇总行 + rc）
fx8c="$(t4_fixture)"; make_legacy "$fx8c"; lock_single > "$fx8c/skills-lock.json"
t510_run "$fx8c" migrate
t4_assert_eq "0" "$T510_RC" "F8-3/AC3: 真跑 exit=0（回归）"
t4_assert_contains "$T510_OUT" "迁移完成：移除" "F8-3/AC3: 汇总行照旧"
t4_assert_contains "$T510_OUT" "备份在 .agents/.nao-obsolete/" "F8-3/AC3: 备份位置照旧"
t4_assert_dir "$(ls -d "$fx8c/.agents/.nao-obsolete/"*/prompts 2>/dev/null | head -1)" "F8-3/AC3: 真跑仍备份 prompts 目录"
t4_assert_file "$(ls -d "$fx8c/.agents/.nao-obsolete/"*/roles.yaml 2>/dev/null | head -1)" "F8-3/AC3: 真跑仍备份 roles.yaml"
t4_assert_eq "0" "$(hits "$fx8c/skills-lock.json" 'frontend-design')" "F8-3/AC3: 真跑去重照旧生效"
t4_assert_absent "$fx8c/.agents/prompts" "F8-3/AC3: 真跑仍移除旧资产"

# F8-4 异常：--dry-run 与 --force 互斥 ⇒ exit 2；未知组合 ⇒ exit 2
sig8d="$(tree_sig "$fx8")"
t510_run "$fx8" migrate --dry-run --force
t4_assert_eq "2" "$T510_RC" "F8-4/AC4: --dry-run --force ⇒ exit 2"
t4_assert_contains "$T510_ERR" "互斥" "F8-4/AC4: 点名互斥（不是静默取舍）"
t4_assert_eq "$sig8d" "$(tree_sig "$fx8")" "F8-4/AC4: 拒绝后盘面不变"
t510_run "$fx8" migrate --dry-run --plugins
t4_assert_eq "2" "$T510_RC" "F8-4/AC4: 未知组合 ⇒ exit 2"

# F8-5 设计一致性：预演清单 == 真跑实际动作清单（同夹具两跑逐项相等）
fx8e="$(t4_fixture)"; make_legacy "$fx8e"; lock_single > "$fx8e/skills-lock.json"
t510_run "$fx8e" migrate --dry-run
dry_items="$(printf '%s\n' "$T510_OUT" | sed -n 's/.*  remove \(\.agents\/[^（]*\)（.*/\1/p' | sort)"
fx8f="$(t4_fixture)"; make_legacy "$fx8f"; lock_single > "$fx8f/skills-lock.json"
t510_run "$fx8f" migrate -v
real_items="$(printf '%s\n' "$T510_OUT" | sed -n 's/.*backup+remove \(\.agents\/[^ ]*\) → .*/\1/p' | sort)"
t4_assert_ne "" "$dry_items" "F8-5/AC5: 预演清单非空（判据不空转）"
t4_assert_eq "$dry_items" "$real_items" "F8-5/AC5: 预演清单与真跑动作清单逐项相等"
t4_assert_ge 10 "$(printf '%s\n' "$dry_items" | grep -c . || true)" "F8-5/AC5: 覆盖目录/文件/脚本/skill 多类（≥10 项）"

t4_exit
