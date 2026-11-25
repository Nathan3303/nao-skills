#!/usr/bin/env bash
# 用例 50 —— AC11 board（T568 · PRD §七 AC11「数值与 queue.jsonl 一致（同 tick 快照）」）
#
# 判据（机械可判）：
#   · 数据源 = `docs/queue.jsonl` + `docs/queue/*.receipt.json`；`--json` 字段 = 长期契约（写进 568 报告）
#   · **一次运行只读一次队列**：本次运行中途改队列文件（`board-after-queue` 钩子）⇒ 输出数值**不得混合**
#   · 禁落盘 / 禁缓存：board 不建 `.orch`、不写任何文件（queue sha 不变）、不生成第二事实源
#   · 人读面：按 state 分区计数 + 阻塞项（带 blocked_reason）+ 在飞项 + 最近回执摘要
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd git

ORCH="$T4_ROOT/bin/nao-orch"
LAB="$T4_CACHE_DIR/c50-$$"
REPO="$LAB/repo"
QUEUE="$REPO/docs/queue.jsonl"
RDIR="$REPO/docs/queue"
ORCH_DIR="$REPO/docs/queue/.orch"
mkdir -p "$REPO/docs/queue"

git -C "$REPO" init -q 2>/dev/null || true

run_orch() { t4_run_in_dir "$REPO" node "$ORCH" "$@"; }
sha() { sha256sum "$QUEUE" | cut -d' ' -f1; }
j() { node -e "const j=JSON.parse(process.argv[1]);process.stdout.write(String($1))" "$T4_OUT"; }

mk_fixture() {
  node -e '
const fs = require("fs");
const [queue, rdir] = process.argv.slice(1);
const row = (o) => JSON.stringify({
  id: o.id, kind: "feat", title: o.title || "board 夹具", state: o.state, prio: "P1",
  deps: [], repo: "nao-skills", branch: `feat/${String(o.id).toLowerCase()}`,
  owner: o.owner || "rd-infra", qa: "qa", acs: ["AC11"], attempt: o.attempt || 0,
  created: "2026-11-24", updated: o.updated || "2026-11-25",
  blocked_reason: o.blocked_reason || "",
});
const rows = [
  row({ id: "T900", state: "queued", updated: "2026-11-25T09:00:00Z" }),
  row({ id: "T901", state: "blocked", blocked_reason: "no_ack", updated: "2026-11-25T08:00:00Z" }),
  row({ id: "T902", state: "dispatched", updated: "2026-11-25T09:30:00Z" }),
  row({ id: "T566", state: "merged", updated: "2026-11-24T12:00:00Z" }),
];
fs.writeFileSync(queue, rows.join("\n") + "\n");
fs.writeFileSync(`${rdir}/T566.receipt.json`, JSON.stringify({
  id: "T566", author: "rd-infra", at: "2026-11-25T12:00:00Z", head: "abcdef1234567",
  pushed: true, gates: { check: { rc: 0, log: "docs/reports/x.log" }, full: { rc: 0, cases: 43, pass: 43, fail: 0, note: "" } },
  acs: [{ id: "AC1", how: "x", evidence: "y" }, { id: "AC2", how: "x", evidence: "y" }],
  blocked: false, artifacts: [], deviation: "",
}));
fs.writeFileSync(`${rdir}/T902.receipt.json`, JSON.stringify({
  id: "T902", author: "qa", at: "2026-11-25T09:40:00Z", head: "0123456abcdef",
  pushed: false, gates: { check: { rc: 1, log: "docs/reports/y.log" } }, acs: [],
}));
fs.writeFileSync(`${rdir}/broken.receipt.json`, "{ not json");
' "$QUEUE" "$RDIR"
}

mk_fixture
BEFORE="$(sha)"

# ================================================================ ① --json 契约（字段清单）
run_orch board --json --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "① board --json rc=0（$T4_ERR）"
t4_assert_eq "1" "$(j 'j.schema')" "① 契约 schema=1"
t4_assert_eq "2026-11-25T10:00:00Z" "$(j 'j.tick_at')" "① 契约 tick_at = 注入时钟（同快照时刻可复现）"
t4_assert_eq "$REPO" "$(j 'j.repo')" "① 契约 repo = 本仓根"
t4_assert_eq "1" "$(j 'j.digits.queued')" "① digits.queued=1（与 queue.jsonl 一致）"
t4_assert_eq "1" "$(j 'j.digits.blocked')" "① digits.blocked=1"
t4_assert_eq "1" "$(j 'j.digits.dispatched')" "① digits.dispatched=1"
t4_assert_eq "1" "$(j 'j.digits.merged')" "① digits.merged=1"
t4_assert_eq "0" "$(j 'j.digits.working')" "① digits 形状稳定：缺席状态补 0（working=0）"
t4_assert_eq "4" "$(j 'j.tasks.length')" "① tasks 行数 = 队列行数（4）"
t4_assert_contains "$T4_OUT" '"blocked_reason":"no_ack"' "① tasks 带 blocked_reason（阻塞可定位）"
t4_assert_eq "2" "$(j 'j.receipts.total')" "① receipts.total=2（docs/queue/*.receipt.json）"
t4_assert_eq "1" "$(j 'j.receipts.unreadable')" "① receipts.unreadable=1（坏 JSON 只计数，不改 rc）"
t4_assert_eq "T566" "$(j 'j.receipts.latest[0].id')" "① 最近回执按 at 倒序（latest[0]=T566）"
t4_assert_eq "0" "$(j 'j.receipts.latest[0].gates.check')" "① 回执 gates.check rc 透出"
t4_assert_eq "2" "$(j 'j.receipts.latest[0].acs')" "① 回执 acs 计数透出"

# ================================================================ ② 人读面（分区 / 阻塞 / 在飞 / 回执）
run_orch board --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "② board（人读）rc=0"
t4_assert_contains "$T4_OUT" "分区" "② 人读面有「分区」计数段"
t4_assert_contains "$T4_OUT" "queued=1" "② 分区计数与队列一致（queued=1）"
t4_assert_contains "$T4_OUT" "阻塞 1：" "② 阻塞项单独成段（1 条）"
t4_assert_contains "$T4_OUT" "reason=no_ack" "② 阻塞项带 blocked_reason"
t4_assert_contains "$T4_OUT" "在飞 1：" "② 在飞项单独成段（dispatched=1）"
t4_assert_contains "$T4_OUT" "回执 2（最近 2）：" "② 最近回执摘要段"

# ================================================================ ③ 禁落盘 / 禁缓存
t4_assert_absent "$ORCH_DIR" "③ board 不建 .orch（不落盘、不缓存）"
t4_assert_eq "$BEFORE" "$(sha)" "③ board 不改 queue.jsonl（sha 不变）"
t4_assert_absent "$ORCH_DIR/wal.jsonl" "③ board 不写 WAL"

# ================================================================ ④ 抗「混合快照」：读一次就够
# 钩子 = 队列读完之后、任何后续计算之前：把队列改成「4 行全 merged」。
# 若实现重读队列（或分两次读），digits 必出现混合值 ⇒ 本组必红。
cat > "$LAB/hook-mutate.sh" <<'HOOK'
#!/usr/bin/env bash
[ "$1" = "board-after-queue" ] || exit 0
printf 'ran\n' > "$NAO_BOARD_MARKER"
node -e '
const fs = require("fs");
const p = process.env.NAO_BOARD_QUEUE;
const rows = fs.readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => {
  const r = JSON.parse(l); r.state = "merged"; r.blocked_reason = ""; return JSON.stringify(r);
});
fs.writeFileSync(p, rows.join("\n") + "\n");
' 
HOOK
chmod +x "$LAB/hook-mutate.sh"
mk_fixture
BEFORE2="$(sha)"
NAO_ORCH_HOOK="$LAB/hook-mutate.sh" NAO_BOARD_QUEUE="$QUEUE" NAO_BOARD_MARKER="$LAB/hook.marker" \
  run_orch board --json --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "④ 注入中途改队列：board rc=0"
t4_assert_file "$LAB/hook.marker" "④ 钩子确已在「读完队列后」执行（否则本组不构成证据）"
t4_assert_ne "$BEFORE2" "$(sha)" "④ 队列文件确已被改写（钩子生效）"
t4_assert_eq "1" "$(j 'j.digits.queued')" "④ 同快照：queued 仍 =1（未混入改写后的 0）"
t4_assert_eq "1" "$(j 'j.digits.blocked')" "④ 同快照：blocked 仍 =1（未混入改写后的 0）"
t4_assert_eq "1" "$(j 'j.digits.merged')" "④ 同快照：merged 仍 =1（未混入改写后的 4）"
t4_assert_eq "4" "$(j 'j.tasks.length')" "④ tasks 仍是同一次读到的 4 行"
# 对照：去掉钩子再跑 ⇒ 数值随新文件变（证明上面的「不变」不是夹具无效）
run_orch board --json --now 2026-11-25T10:00:00Z
t4_assert_eq "4" "$(j 'j.digits.merged')" "④ 对照：无钩子时 merged=4（新文件确实被读到）"
t4_assert_eq "0" "$(j 'j.digits.queued')" "④ 对照：无钩子时 queued=0"

t4_exit
