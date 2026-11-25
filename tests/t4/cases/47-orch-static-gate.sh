#!/usr/bin/env bash
# 用例 47 —— AC9 静态闸：orch 绝不自带合并/发版/推主干能力（T567-B · ADR D5②）
#
# 断言组：
#   ① 闸体存在且**正控为真**：本仓真件（`bin/nao-orch` + `bin/lib/orch/**`）0 命中
#   ② 扫面完整：被扫文件集 == nao-orch + 全部 orch 模块（少扫一个文件 = 假绿）
#   ③ 闸体自证（承重性）：8 条判据逐条注入 ⇒ 每条都必须命中；删掉判据 ⇒ 同一条注入不再命中
#   ④ 注释行豁免：`// gh pr merge` 不红（不是「全文 grep」的空转闸）
#   ⑤ 三条注入必红（ADR 原文）：`gh pr merge 1 --squash` / `npm publish` / `cp.execSync('git push origin main')`
#   ⑥ 结构层单点（AC9①）：`child_process` 只出现在 `bin/lib/orch/fleet.mjs`；fleet 子命令白名单外一律拒绝
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd grep

ORCH="$T4_ROOT/bin/nao-orch"
ORCH_LIB="$T4_ROOT/bin/lib/orch"
LAB="$T4_CACHE_DIR/c47-$$"
rm -rf "$LAB"; mkdir -p "$LAB"

# ---------------------------------------------------------------- ① 正控：真件 0 命中
t4_assert_file "$ORCH" "① 被测件存在：bin/nao-orch"
t4_assert_eq "" "$(t4_scan_orch_forbidden "$T4_ROOT")" "① 正控：本仓真件 0 命中（含 nao-orch 与全部 orch 模块）"

# ---------------------------------------------------------------- ② 扫面完整
_scanned="$(t4_scan_orch_forbidden "$T4_ROOT" >/dev/null 2>&1; true)"
# 用注入法确认每个文件都被扫到：逐个副本注入一条，必须红
n_mod=0
for f in "$ORCH" "$ORCH_LIB"/*.mjs; do
  [ -f "$f" ] || continue
  n_mod=$((n_mod + 1))
done
t4_assert_ge 4 "$n_mod" "② 扫面文件数 = $n_mod（nao-orch + orch 模块 ≥4）"
_missing=""
for f in "$ORCH" "$ORCH_LIB"/*.mjs; do
  [ -f "$f" ] || continue
  cp="$LAB/$(basename "$f")"
  { cat "$f"; printf '\nnpm publish\n'; } > "$cp"
  out="$(t4_scan_orch_forbidden "$cp")"
  [ -n "$out" ] || _missing="$_missing $(basename "$f")"
done
t4_assert_eq "" "$_missing" "② 每个被扫文件都承重（逐个注入 npm publish 都必须红）"

# ---------------------------------------------------------------- ③ 闸体自证：8 条判据逐条承重
_inj="$LAB/all-patterns.txt"
cat > "$_inj" <<'INJ'
gh pr merge 1 --squash
gh release create v1
git push origin main
git tag v1
git merge feat/x
npm publish
cp.execSync('ls')
spawn('x', { shell: true })
INJ
_out="$(t4_scan_orch_forbidden "$_inj")"
for pat in 'gh pr merge' 'gh release create' 'git push origin main' 'git tag' 'git merge' 'npm publish' 'execSync' 'shell: true'; do
  t4_assert_contains "$_out" "$pat" "③ 判据承重：注入 \`$pat\` 必命中"
done
t4_assert_ge 8 "$(printf '%s\n' "$_out" | grep -c . || true)" "③ 8 条注入 = 8 行命中（无重复计数/无吞行）"

# 删掉判据 ⇒ 同一条注入不再命中（防「判据被删 = 空转绿」）
_scanfun="$LAB/scanner.sh"
awk '/^t4_scan_orch_forbidden\(\) \{/,/^}$/' "$T4_ROOT/tests/t4/lib.sh" > "$_scanfun"
t4_assert_ge 20 "$(grep -c . "$_scanfun" || true)" "③ 闸体已取出（行数自证，防空函数）"
grep -vF "'npm[[:space:]]+publish'" "$_scanfun" > "$_scanfun.mut"
out="$(T4_ROOT="$T4_ROOT" bash -c "source '$T4_ROOT/tests/t4/lib.sh' >/dev/null 2>&1; source '$_scanfun.mut'; t4_scan_orch_forbidden '$_inj'")"
t4_assert_not_contains "$out" "npm publish" "③ 负控：删掉 npm 判据 ⇒ 该条注入不再命中（判据承重，不是文档）"
t4_assert_contains "$out" "gh pr merge" "③ 负控对照：同一次变异里其它判据仍命中（不是整闸失效）"

# ---------------------------------------------------------------- ④ 注释行豁免
_comment="$LAB/comment.txt"
printf '// gh pr merge 1 --squash\n# npm publish\n * git push origin main\n' > "$_comment"
t4_assert_eq "" "$(t4_scan_orch_forbidden "$_comment")" "④ 注释行（// · # · *）全部豁免（不是全文 grep 的空转闸）"
printf 'const x = 1; // gh pr merge\n' > "$_comment"
t4_assert_ne "" "$(t4_scan_orch_forbidden "$_comment")" "④ 反向：行内注释之前的真代码仍受管（豁免只按行首）"

# ---------------------------------------------------------------- ⑤ 三条注入必红（ADR 原文）
_inj3="$LAB/nao-orch.copy"
{ cat "$ORCH"; printf '\n# 注入\ngh pr merge 1 --squash\n'; } > "$_inj3"
t4_assert_contains "$(t4_scan_orch_forbidden "$_inj3")" "gh pr merge" "⑤ 注入①：nao-orch 里 \`gh pr merge 1 --squash\` ⇒ 必红"
{ cat "$ORCH_LIB/fleet.mjs"; printf '\nnpm publish\n'; } > "$_inj3"
t4_assert_contains "$(t4_scan_orch_forbidden "$_inj3")" "npm publish" "⑤ 注入②：fleet.mjs 里 \`npm publish\` ⇒ 必红"
{ cat "$ORCH_LIB/tick.mjs"; printf "\ncp.execSync('git push origin main');\n"; } > "$_inj3"
out="$(t4_scan_orch_forbidden "$_inj3")"
t4_assert_contains "$out" "execSync" "⑤ 注入③a：\`cp.execSync(...)\` ⇒ 必红（execSync）"
t4_assert_contains "$out" "git push origin main" "⑤ 注入③b：同一条里 \`git push origin main\` ⇒ 必红"

# ---------------------------------------------------------------- ⑥ 结构层：唯一外部执行面
_cp_files="$(grep -rl 'child_process' "$ORCH" "$ORCH_LIB" 2>/dev/null | sed "s#^$T4_ROOT/##" | sort || true)"
t4_assert_eq "bin/lib/orch/fleet.mjs" "$_cp_files" "⑥ 结构层：child_process 只出现在 bin/lib/orch/fleet.mjs（唯一外部出口）"
t4_assert_eq "0" "$(grep -c 'shell:' "$ORCH_LIB/fleet.mjs" 2>/dev/null || true)" "⑥ fleet.mjs 内零 shell 选项"
t4_assert_contains "$(grep -E '^const FLEET_SUBS' -A6 "$ORCH_LIB/fleet.mjs")" "'status'" "⑥ 子命令白名单含 status"
for forbidden_sub in merge publish release push tag; do
  t4_assert_not_contains "$(grep -E '^const FLEET_SUBS' -A6 "$ORCH_LIB/fleet.mjs")" "'$forbidden_sub'" "⑥ 白名单不含 $forbidden_sub"
done
# 白名单外的子命令真的被拒（运行时负控，不只是文本）
out="$(node -e '
import("'"$ORCH_LIB"'/fleet.mjs").then((m) => {
  try { m.fleetExec("merge", []); console.log("NO-THROW"); }
  catch (e) { console.log("THROW " + e.message.split("（")[0]); }
});' 2>&1)"
t4_assert_contains "$out" "THROW 子命令不在白名单" "⑥ 运行时：fleetExec(\"merge\") 抛错（白名单承重）"
out="$(node -e '
import("'"$ORCH_LIB"'/fleet.mjs").then((m) => {
  try { m.fleetExec("status", ["--nope"]); console.log("NO-THROW"); }
  catch (e) { console.log("THROW " + e.message); }
});' 2>&1)"
t4_assert_contains "$out" "不接受旗标" "⑥ 运行时：未声明旗标被拒（禁旗标吃位置参数）"

t4_exit
