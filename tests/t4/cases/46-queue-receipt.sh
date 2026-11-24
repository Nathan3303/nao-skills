#!/usr/bin/env bash
# 用例 46 —— 编排器阶段 1：队列与回执契约（T566 · PRD `docs/prds/2026-11-24-orchestrator.md` §四 / §五 AC1–AC4）
#
# 被测对象 = `bin/nao-queue`（零依赖 Node CLI；单源 `docs/queue.jsonl`）。
# 断言组（编号 ↔ AC）：
#   ① AC1 回执 schema：完整回执通过；缺字段 / 空证据 / 自述与计数矛盾 / id 与文件名不一致 / 回执脱离队列 ⇒ 逐条点名必红
#   ② AC2 pushed:true 与 `git ls-remote` 一致（正控：head 在远端；负控：未推送的提交 ⇒ 红；空远端 ⇒ 红；
#      `--no-push-check` 是显式逃生阀，跳过必打 NOTICE —— 防静默假绿）
#   ③ AC3 状态机：合法链（queued→dispatched · qa→qa_fail · qa_fail→working · merged→released）通过；
#      跳级（queued→merged · qa→merged）、终态出边（released→queued）、同态自转 ⇒ 必红并给出允许集
#   ④ AC4 渲染单向：jsonl → tasks-state.md 两个标记区（`<!-- generated -->` 头）· 幂等（连跑两次 effect=0）·
#      手改后 `render --check` 必红 · 再渲染复原 · 标记缺失/重复 ⇒ rc=2 且**不改目标文件** ·
#      改 jsonl 的 state ⇒ 行在两区之间移动（渲染确由数据驱动）
#   ⑤ 真件自洽：本仓 `docs/queue.jsonl` + `docs/tasks-state.md` + `docs/queue/T566.receipt.json` 与渲染/校验一致
#
# 夹具：`$T4_CACHE_DIR` 下的独立目录 + 本地 bare 仓（推送复核走 `git ls-remote <本地路径>`，零网络、零真实远端）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd git

NQ="$T4_ROOT/bin/nao-queue"
LAB="$T4_CACHE_DIR/c46-$$"
Q="$LAB/queue.jsonl"
STATE="$LAB/tasks-state.md"
rm -rf "$LAB"; mkdir -p "$LAB"

# 统一执行封装：c46 <dir> <args...> → T4_RC / T4_OUT / T4_ERR
c46() { local d="$1"; shift; t4_run_in_dir "$d" node "$NQ" "$@"; }

# c46_block <文件> <region> —— 取标记区正文（不含 begin/end 行）
c46_block() {
  awk -v b="<!-- nao-queue:begin $2 -->" -v e="<!-- nao-queue:end $2 -->" '
    $0==b {on=1; next} $0==e {on=0} on {print}' "$1"
}

# c46_mut <src> <dst> <对 o 的 JS 语句>
c46_mut() {
  node - "$1" "$2" "$3" <<'NODE'
const fs = require('fs');
const [src, dst, code] = process.argv.slice(2);
const o = JSON.parse(fs.readFileSync(src, 'utf8'));
new Function('o', code)(o);
fs.writeFileSync(dst, JSON.stringify(o, null, 2) + '\n');
NODE
}

# ---------------------------------------------------------------- 夹具：队列 + 渲染目标
cat > "$Q" <<'JSONL'
{"id":"T700","kind":"feat","title":"待派发样例","state":"queued","prio":"P2","deps":[],"repo":"nao-skills","branch":"feat/t700","owner":"","qa":"","acs":["AC1"],"attempt":0,"created":"2026-11-24","updated":"2026-11-24","blocked_reason":""}
{"id":"T701","kind":"feat","title":"进行中样例","state":"working","prio":"P1","deps":[],"repo":"nao-skills","branch":"feat/t701","owner":"rd-infra","qa":"qa","acs":["AC1","AC2"],"attempt":0,"created":"2026-11-24","updated":"2026-11-24","blocked_reason":""}
{"id":"T702","kind":"fix","title":"阻塞样例","state":"blocked","prio":"P0","deps":["T701"],"repo":"nao-skills","branch":"fix/t702","owner":"rd-be","qa":"qa","acs":["AC1"],"attempt":3,"created":"2026-11-24","updated":"2026-11-24","blocked_reason":"attempt>2"}
JSONL
cat > "$STATE" <<'MD'
# 任务状态（用例 46 夹具）

## 进行中

<!-- nao-queue:begin active -->
<!-- nao-queue:end active -->

## 待派发队列（夹具）

<!-- nao-queue:begin dispatch -->
<!-- nao-queue:end dispatch -->
MD

# ================================================================ ④ AC4 渲染单向
c46 "$LAB" render --queue "$Q" --target "$STATE"
t4_assert_eq 0 "$T4_RC" "④ AC4 渲染 rc=0（$T4_ERR）"
t4_assert_contains "$(c46_block "$STATE" active)" "<!-- generated" "④ 渲染产物带 generated 头（禁手改标记）"
t4_assert_contains "$(c46_block "$STATE" active)" "**T701**" "④ 进行中区含 working 行"
t4_assert_contains "$(c46_block "$STATE" active)" "**T702**" "④ 进行中区含 blocked 行"
t4_assert_contains "$(c46_block "$STATE" active)" "blocked_reason=attempt>2" "④ blocked 行带原因"
t4_assert_contains "$(c46_block "$STATE" dispatch)" "**T700**" "④ 待派发区含 queued 行"
t4_assert_not_contains "$(c46_block "$STATE" active)" "**T700**" "④ 待派发行不进进行中区（两区互斥）"
t4_assert_contains "$(cat "$STATE")" "## 进行中" "④ 标记区外的既有结构原样保留（标题仍在）"

cp "$STATE" "$LAB/state.first"
c46 "$LAB" render --queue "$Q" --target "$STATE"
t4_assert_eq 0 "$T4_RC" "④ 连跑第 2 次 rc=0"
cmp -s "$STATE" "$LAB/state.first" && t4_ok "④ 幂等：第 2 次渲染 effect=0（字节相同）" || t4_bad "④ 幂等失败：第 2 次渲染改动了文件"

c46 "$LAB" render --queue "$Q" --target "$STATE" --check
t4_assert_eq 0 "$T4_RC" "④ 渲染后 --check rc=0（文件与渲染结果一致）"

# 手改生成区（模拟人手写）⇒ --check 必红
awk '{ if ($0 == "<!-- nao-queue:end active -->") print "- **T999** · 手改出来的行"; print }' "$STATE" > "$LAB/state.hand" \
  && mv "$LAB/state.hand" "$STATE"
t4_assert_contains "$(c46_block "$STATE" active)" "T999" "④ 夹具：手改已注入生成区"
c46 "$LAB" render --queue "$Q" --target "$STATE" --check
t4_assert_eq 1 "$T4_RC" "④ 手改后 --check rc=1（AC4 判据咬住）"
t4_assert_contains "$T4_ERR" "不一致" "④ 失败信息点名不一致（不是静默放过）"
c46 "$LAB" render --queue "$Q" --target "$STATE"
t4_assert_eq 0 "$T4_RC" "④ 重渲染 rc=0（覆盖手改）"
cmp -s "$STATE" "$LAB/state.first" && t4_ok "④ 重渲染后与首渲染逐字节相同（手改被覆盖）" || t4_bad "④ 重渲染未复原到首渲染结果"
t4_assert_not_contains "$(c46_block "$STATE" active)" "T999" "④ 手改行已被清除"

# 标记缺失 / 重复 ⇒ rc=2 且**不改目标文件**（不静默追加）
grep -v 'nao-queue:begin active' "$LAB/state.first" > "$LAB/state.nomarker"
before="$(cksum < "$LAB/state.nomarker")"
c46 "$LAB" render --queue "$Q" --target "$LAB/state.nomarker"
t4_assert_eq 2 "$T4_RC" "④ 标记缺失 ⇒ rc=2（用法错误，fail loud）"
t4_assert_contains "$T4_ERR" "nao-queue:begin" "④ 失败信息点名缺失的标记"
t4_assert_eq "$before" "$(cksum < "$LAB/state.nomarker")" "④ 标记缺失时目标文件零改动（不静默追加）"
awk '{ print } /nao-queue:begin dispatch/ { print }' "$LAB/state.first" > "$LAB/state.dup"
c46 "$LAB" render --queue "$Q" --target "$LAB/state.dup"
t4_assert_eq 2 "$T4_RC" "④ 标记重复 ⇒ rc=2"
t4_assert_contains "$T4_ERR" "重复" "④ 失败信息点名标记重复"

# 改 jsonl 的 state ⇒ 行在两区之间移动（证明渲染由数据驱动，非静态文本）
node - "$Q" "$LAB/q.moved" <<'NODE'
const fs = require('fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map((l) => JSON.parse(l));
rows.find((r) => r.id === 'T701').state = 'queued';
rows.find((r) => r.id === 'T701').owner = '';
rows.find((r) => r.id === 'T700').state = 'dispatched';
rows.find((r) => r.id === 'T700').owner = 'rd-fe';
fs.writeFileSync(process.argv[3], rows.map((r) => JSON.stringify(r)).join('\n') + '\n');
NODE
c46 "$LAB" render --queue "$LAB/q.moved" --target "$STATE"
t4_assert_eq 0 "$T4_RC" "④ 改 state 后渲染 rc=0"
t4_assert_contains "$(c46_block "$STATE" dispatch)" "**T701**" "④ working→queued ⇒ 行移入待派发区"
t4_assert_contains "$(c46_block "$STATE" active)" "**T700**" "④ queued→dispatched ⇒ 行移入进行中区"
cp "$LAB/state.first" "$STATE"

# ================================================================ ③ AC3 状态机
for pair in "queued dispatched" "dispatched working" "working qa" "qa qa_pass" "qa qa_fail" "qa_fail working" "qa_pass merging" "merging merged" "merged released"; do
  set -- $pair
  c46 "$LAB" transition --from "$1" --to "$2"
  t4_assert_eq 0 "$T4_RC" "③ 合法转换 $1 → $2 rc=0"
done
c46 "$LAB" transitions
t4_assert_contains "$T4_OUT" "blocked → queued" "③ blocked 有人工恢复出口（重新排队）"

for pair in "queued merged" "qa merged" "dispatched qa_pass" "released queued" "queued queued"; do
  set -- $pair
  c46 "$LAB" transition --from "$1" --to "$2"
  t4_assert_eq 1 "$T4_RC" "③ 非法转换 $1 → $2 rc=1（fail loud）"
  t4_assert_contains "$T4_ERR" "非法状态转换" "③ 失败信息点名「非法状态转换」（$1 → $2）"
done
c46 "$LAB" transition --from queued --to merged
t4_assert_contains "$T4_ERR" "允许：dispatched" "③ 失败信息给出从 queued 的允许集"
c46 "$LAB" transition --from bogus --to queued
t4_assert_eq 2 "$T4_RC" "③ 未知状态 ⇒ rc=2（用法错误，与「非法转换」区分）"

# ================================================================ ① AC1 回执 schema
REC="$LAB/rec"; mkdir -p "$REC"
cat > "$REC/T701.receipt.json" <<'JSON'
{
  "id": "T701",
  "author": "rd-infra",
  "at": "2026-11-24T10:00:00Z",
  "head": "deadbeef",
  "pushed": false,
  "gates": {
    "check": { "rc": 0, "log": "check.log" },
    "full": { "rc": 0, "cases": 42, "pass": 2513, "fail": 0, "note": "" }
  },
  "acs": [
    { "id": "AC1", "how": "case 46 ①", "evidence": "tests/t4/cases/46-queue-receipt.sh:PASS" },
    { "id": "AC2", "how": "case 46 ②", "evidence": "同上" }
  ],
  "blocked": false,
  "artifacts": ["tests/t4/cases/46-queue-receipt.sh"],
  "deviation": ""
}
JSON
c46 "$LAB" validate --queue "$Q" --receipts "$REC"
t4_assert_eq 0 "$T4_RC" "① AC1 完整回执通过（$T4_ERR）"
t4_assert_match "$T4_OUT" "receipts=1 份" "① 校验摘要给出回执份数（不静默 0 份）"

# 逐条变异负控：改坏一处 ⇒ 必红并点名
c46_mut "$REC/T701.receipt.json" "$LAB/r.nodeviation.json" 'delete o.deviation'
mkdir -p "$LAB/rec-m1"; cp "$LAB/r.nodeviation.json" "$LAB/rec-m1/T701.receipt.json"
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m1"
t4_assert_eq 1 "$T4_RC" "① 缺 deviation ⇒ rc=1"
t4_assert_contains "$T4_ERR" "deviation" "① 点名缺失字段 deviation"

c46_mut "$REC/T701.receipt.json" "$LAB/r.nonote.json" 'delete o.gates.full.note'
mkdir -p "$LAB/rec-m2"; cp "$LAB/r.nonote.json" "$LAB/rec-m2/T701.receipt.json"
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m2"
t4_assert_eq 1 "$T4_RC" "① 缺 gates.full.note ⇒ rc=1"
t4_assert_contains "$T4_ERR" "note" "① 点名缺失字段 note"

c46_mut "$REC/T701.receipt.json" "$LAB/r.noevidence.json" 'o.acs[0].evidence = ""'
mkdir -p "$LAB/rec-m3"; cp "$LAB/r.noevidence.json" "$LAB/rec-m3/T701.receipt.json"
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m3"
t4_assert_eq 1 "$T4_RC" "① 空 evidence ⇒ rc=1（空证据 = 未验证）"
t4_assert_contains "$T4_ERR" "evidence" "① 点名 evidence"

c46_mut "$REC/T701.receipt.json" "$LAB/r.selfcontra.json" 'o.gates.full.fail = 3'
mkdir -p "$LAB/rec-m4"; cp "$LAB/r.selfcontra.json" "$LAB/rec-m4/T701.receipt.json"
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m4"
t4_assert_eq 1 "$T4_RC" "① gates.full.rc=0 但 fail>0 ⇒ rc=1（自述与计数矛盾）"

c46_mut "$REC/T701.receipt.json" "$LAB/r.mismatch.json" 'o.id = "T799"'
mkdir -p "$LAB/rec-m5"; cp "$LAB/r.mismatch.json" "$LAB/rec-m5/T701.receipt.json"
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m5"
t4_assert_eq 1 "$T4_RC" "① id 与文件名不一致 ⇒ rc=1"
t4_assert_contains "$T4_ERR" "不一致" "① 点名 id 不一致"

mkdir -p "$LAB/rec-m6"
c46_mut "$REC/T701.receipt.json" "$LAB/rec-m6/T798.receipt.json" 'o.id = "T798"'
c46 "$LAB" validate --queue "$Q" --receipts "$LAB/rec-m6"
t4_assert_eq 1 "$T4_RC" "① 回执脱离队列（无对应行）⇒ rc=1"
c46 "$LAB" validate --queue "$LAB/missing.jsonl" --receipts "$REC"
t4_assert_eq 2 "$T4_RC" "① 队列文件不存在 ⇒ rc=2（用法错误）"

# 机读首行（PRD §四）：gates 转 ok|red、acs=<回执数>/<队列数>
c46 "$LAB" receipt-line "$REC/T701.receipt.json" --queue "$Q"
t4_assert_eq 0 "$T4_RC" "① receipt-line rc=0"
t4_assert_eq "receipt: T701 rd-infra head=deadbeef gates=ok,ok acs=2/2" "$T4_OUT" "① 机读首行逐字（gates=ok,ok · acs=2/2）"

# ================================================================ ② AC2 pushed 复核（本地 bare 仓，零网络）
REMOTE="$LAB/remote.git"
WORK="$LAB/work"
git init -q --bare "$REMOTE"
git init -q "$WORK"
( cd "$WORK" && git config user.email t4@local && git config user.name t4 \
  && printf 'one\n' > f && git add f && git commit -qm one \
  && git remote add origin "$REMOTE" && git push -q origin HEAD:refs/heads/feat/t701 )
SHA1="$(git -C "$WORK" rev-parse HEAD)"
printf 'two\n' > "$WORK/g"; git -C "$WORK" add g; git -C "$WORK" commit -qm two
SHA2="$(git -C "$WORK" rev-parse HEAD)"
t4_assert_ne "$SHA1" "$SHA2" "② 夹具：已推送提交与未推送提交不同 sha"

PUSHED="$LAB/rec-pushed"; mkdir -p "$PUSHED"
c46_mut "$REC/T701.receipt.json" "$PUSHED/T701.receipt.json" "o.head = '$SHA1'; o.pushed = true"
c46 "$LAB" validate --queue "$Q" --receipts "$PUSHED" --remote "$REMOTE"
t4_assert_eq 0 "$T4_RC" "② AC2 pushed:true 且 head 在远端 ⇒ rc=0（$T4_ERR）"
t4_assert_contains "$T4_OUT" "push 复核=on" "② 摘要声明 push 复核已启用"

UNPUSHED="$LAB/rec-unpushed"; mkdir -p "$UNPUSHED"
c46_mut "$REC/T701.receipt.json" "$UNPUSHED/T701.receipt.json" "o.head = '$SHA2'; o.pushed = true"
c46 "$LAB" validate --queue "$Q" --receipts "$UNPUSHED" --remote "$REMOTE"
t4_assert_eq 1 "$T4_RC" "② AC2 pushed:true 与远端不一致 ⇒ rc=1"
t4_assert_contains "$T4_ERR" "ls-remote" "② 点名 git ls-remote 复核失败"
t4_assert_contains "$T4_ERR" "pushed:true" "② 点名是 pushed:true 的断言失败"

c46 "$LAB" validate --queue "$Q" --receipts "$UNPUSHED" --remote "$REMOTE" --no-push-check
t4_assert_eq 0 "$T4_RC" "② --no-push-check 是显式逃生阀（rc=0）"
t4_assert_contains "$T4_ERR" "NOTICE" "② 跳过复核必打 NOTICE（不静默假绿）"

NOTPUSHED="$LAB/rec-false"; mkdir -p "$NOTPUSHED"
c46_mut "$REC/T701.receipt.json" "$NOTPUSHED/T701.receipt.json" "o.head = '$SHA2'; o.pushed = false"
c46 "$LAB" validate --queue "$Q" --receipts "$NOTPUSHED" --remote "$REMOTE"
t4_assert_eq 0 "$T4_RC" "② pushed:false ⇒ 不做远端复核（rc=0）"

git init -q --bare "$LAB/empty.git"
c46 "$LAB" validate --queue "$Q" --receipts "$PUSHED" --remote "$LAB/empty.git"
t4_assert_eq 1 "$T4_RC" "② 远端无任何 head ⇒ rc=1（不把「推不上去」当通过）"
t4_assert_contains "$T4_ERR" "没有任何 head" "② 点名远端为空"

c46 "$LAB" validate --queue "$Q" --receipts "$PUSHED" --remote "$LAB/no-such.git"
t4_assert_eq 1 "$T4_RC" "② 远端不可用 ⇒ rc=1（fail loud，不静默放过 AC2）"

# ================================================================ ⑤ 真件自洽（不碰工作区）
t4_run_in_dir "$T4_ROOT" node "$NQ" render --check
t4_assert_eq 0 "$T4_RC" "⑤ 本仓 docs/tasks-state.md 与 docs/queue.jsonl 渲染一致（提交前必须 render）"
t4_assert_file "$T4_ROOT/docs/queue.jsonl" "⑤ 队列单源在位"
t4_assert_file "$T4_ROOT/docs/queue/T566.receipt.json" "⑤ 本任务回执样例在位（schema 自我践行）"
t4_run_in_dir "$T4_ROOT" node "$NQ" validate --no-push-check
t4_assert_eq 0 "$T4_RC" "⑤ 本仓队列 + 回执校验通过（push 复核由合并前另行联网跑）"

c46 "$LAB" bogus-command
t4_assert_eq 2 "$T4_RC" "⑤ 未知命令 ⇒ rc=2"
t4_assert_contains "$T4_ERR" "未知命令" "⑤ 未知命令点名"

t4_exit
