#!/usr/bin/env bash
# 用例 08 —— 评审修复回归（F1 lock 文本级删条保缩进 · F2 init --force 走 migrate 防混装）
#
# F1: 4 空格缩进 skills-lock.json + 旧版全套 .agents/ → migrate 后
#     `git diff --numstat -- skills-lock.json` 变更只限该条目（不得整文件重排/缩进变化）
# F2: 旧版全套 + init（无 --force）→ 拒绝且 rc≠0；init --force → 走 migrate，
#     无 .agents/prompts / .agents/skills/frontend-design 残留，shim 就位（无混装/双注册）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
t4_require_cmd git
if ! t4_cli_supports migrate && ! t4_cli_supports init; then
  t4_blocked "CLI 既无 migrate 也无 init（T2/T3 bin/）"
fi

legacy_fixture() { # 旧版全套 .agents/ + 一个共享 skill 目录
  local fx="$1"
  mkdir -p "$fx/.agents"
  cp -a "$T4_ROOT/.agents/." "$fx/.agents/"
  printf '0.0.1-legacy\n' > "$fx/.agents/.nao-version"
  mkdir -p "$fx/.agents/skills/nue-ui-dev"
  printf -- '---\nname: nue-ui-dev\ndescription: downstream shared skill (must survive)\n---\n' \
    > "$fx/.agents/skills/nue-ui-dev/SKILL.md"
}

# ============================================================== F1
fx="$(t4_fixture)"
legacy_fixture "$fx"
cat > "$fx/skills-lock.json" <<'JSON'
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
JSON
before_lines="$(wc -l < "$fx/skills-lock.json")"
entry_lines="$(awk '/"frontend-design"/{f=1} f{print; if(/^[[:space:]]+},?$/) exit}' "$fx/skills-lock.json" | wc -l)"
cp "$fx/skills-lock.json" "$T4_CACHE_DIR/lock-before.json"
# 期望结果 = 原文件逐行去掉 frontend-design 条目块（保留其余字节/缩进不变）
awk '/"frontend-design"/{skip=1} skip{if(/^[[:space:]]+},?$/){skip=0} next} {print}' \
  "$T4_CACHE_DIR/lock-before.json" > "$T4_CACHE_DIR/lock-expected.json"
( cd "$fx" && git add -A && git commit -q -m fixture ) >/dev/null 2>&1

t4_materialize "$fx"
t4_run_migrate "$fx"
t4_info "F1 migrate rc=$T4_RC · frontend-design 条目行数≈$entry_lines / 原文件 $before_lines 行"

numstat="$(cd "$fx" && git diff --numstat -- skills-lock.json 2>/dev/null)"
added="${numstat%%[[:space:]]*}"; deleted="$(printf '%s' "$numstat" | awk '{print $2}')"
t4_info "F1 git diff --numstat: ${numstat:-<空>}"
t4_assert_eq "0" "${added:-x}" "F1: 纯删除（added=0，无整文件重排/缩进新增）"
[ -n "${deleted:-}" ] && [ "${deleted:-0}" -ge 3 ] && [ "${deleted:-99}" -le $((entry_lines + 1)) ] \
  && t4_ok "F1: 删除行数 $deleted 限定该条目（≤ $((entry_lines + 1))）" \
  || t4_bad "F1: 删除行数异常（deleted=${deleted:-空}，期望 3..$((entry_lines + 1))）"

# 强判据：迁移结果与「原文件仅删该条目」逐字节一致（其余行/缩进零变化）
if diff -q "$T4_CACHE_DIR/lock-expected.json" "$fx/skills-lock.json" >/dev/null 2>&1; then
  t4_ok "F1: 结果 == 原文件逐行仅删该条目（其余字节/缩进零变化）"
else
  t4_bad "F1: 结果与「仅删该条目」不一致（存在整文件重排/缩进变化）"
  diff -u "$T4_CACHE_DIR/lock-expected.json" "$fx/skills-lock.json" 2>/dev/null | head -20
fi
t4_assert_eq "0" "$(grep -c 'frontend-design' "$fx/skills-lock.json" || true)" "F1: frontend-design 已移除"
t4_assert_eq "$(grep '"keep-me"' "$T4_CACHE_DIR/lock-before.json")" "$(grep '"keep-me"' "$fx/skills-lock.json")" "F1: keep-me 行逐字节不变（未被重排）"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$fx/skills-lock.json" >/dev/null 2>&1 \
  && t4_ok "F1: 结果仍是合法 JSON" || t4_bad "F1: 结果 JSON 非法"

# ============================================================== F2
fx2="$(t4_fixture)"
legacy_fixture "$fx2"
t4_materialize "$fx2"

t4_run_init "$fx2"            # init 无 --force → 必须拒绝
t4_info "F2 init(no-force) rc=$T4_RC"
[ "$T4_RC" -ne 0 ] && t4_ok "F2: init 无 --force 拒绝旧版安装（rc=$T4_RC≠0）" || t4_bad "F2: init 未拒绝（rc=0）"
t4_assert_dir "$fx2/.agents/prompts" "F2: 拒绝后未做部分迁移（.agents/prompts 仍在）"
t4_assert_dir "$fx2/.agents/skills/frontend-design" "F2: 拒绝后 nao 资产仍在（无部分动作）"

t4_run_init "$fx2" --force    # init --force → 走 migrate
t4_info "F2 init --force rc=$T4_RC"
t4_assert_eq "0" "$T4_RC" "F2: init --force exit=0（走 migrate）"
t4_assert_absent "$fx2/.agents/prompts" "F2: 无 .agents/prompts 残留（不混装）"
t4_assert_absent "$fx2/.agents/skills/frontend-design" "F2: 无 .agents/skills/frontend-design 残留（无双注册风险）"
t4_assert_dir "$fx2/.agents/skills/nue-ui-dev" "F2: 共享 skill 目录保留"
t4_assert_dir "$fx2/.agents/.nao-obsolete" "F2: 旧资产已备份 .nao-obsolete"
t4_require_shim "$fx2"
t4_run_shim "$fx2" -u NAO_SKILLS -u NAO_SHIM_ENTERED
t4_assert_eq "0" "$T4_RC" "F2: 迁移后 shim check exit=0（无混装）"

t4_exit
