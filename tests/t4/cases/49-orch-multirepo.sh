#!/usr/bin/env bash
# 用例 49 —— AC10 多仓不串仓（T568 · PRD §七 AC10 / PRD §二「三次裸名误投」回归）
#
# 判据（机械可判）：orch 绑一仓（repo_root）⇒ 派单只能用 status --json 里**同时满足**
#   「role+task 命中」且「repo == 本仓」的会话；`to`（通知目标/目标身份）= 该会话 name，并带 cwd。
#   同名跨仓 / repo 不可判定 ⇒ 不猜（fail-closed）：该行 skip + journal 点名，**零 ensure**。
#
# 断言组：
#   ① 本仓 pm(T900) + 他仓 pm ⇒ ensure argv 指向本仓（`pm@<repo>`）+ 以本仓 cwd 调用；`to` 不是裸名
#   ② 只有他仓 pm 在线 ⇒ 零 ensure、row 仍 queued、journal 点名「他仓」、零跨仓通知
#   ③ 同名两条且 repo 都不可判定 ⇒ 零 ensure、row 仍 queued、journal 点名「同名跨仓歧义」
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd git

ORCH="$T4_ROOT/bin/nao-orch"
LAB="$T4_CACHE_DIR/c49-$$"
STUB="$LAB/stub"
REPO="$LAB/repo"
OTHER="$LAB/other"
QUEUE="$REPO/docs/queue.jsonl"
ORCH_DIR="$REPO/docs/queue/.orch"
STATUS="$LAB/status.json"
export STUB_STATUS="$STATUS"
export STUB_LOG="$LAB/fleet.log"
export NOTIFY_LOG="$LAB/notify.log"
mkdir -p "$STUB" "$REPO/docs/queue" "$OTHER"

# ---------------------------------------------------------------- 桩：nao-fleet.sh / 通知器
# 日志首字段 = 调用方 cwd（AC10：ensure 的 cwd 必须锚到本仓根）
cat > "$STUB/nao-fleet.sh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$PWD" "$*" >> "$STUB_LOG"
case "$1" in
  status) cat "$STUB_STATUS"; exit 0 ;;
  ensure) exit 0 ;;
esac
exit 0
STUBEOF
cat > "$STUB/notifier" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
exit 0
STUBEOF
chmod +x "$STUB"/*
export NAO_ORCH_NOTIFY="$STUB/notifier"
PATH="$STUB:$PATH"; export PATH

git -C "$REPO" init -q 2>/dev/null || true
git -C "$REPO" -c user.name=t4 -c user.email=t4@example.invalid commit -q --allow-empty -m init 2>/dev/null || true

run_orch() { t4_run_in_dir "$REPO" node "$ORCH" "$@"; }
mk_queue() { printf '{"id":"T900","kind":"feat","title":"多仓归属夹具","state":"queued","prio":"P1","deps":[],"repo":"nao-skills","branch":"feat/t900","owner":"pm","qa":"qa","acs":["AC10"],"attempt":0,"created":"2026-11-25","updated":"2026-11-25","blocked_reason":""}\n' > "$QUEUE"; }
qstate() { node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean)[0]);console.log(r.state)' "$QUEUE"; }
calls() { awk -F'\t' '$2 ~ /^ensure( |$)/ {n++} END{print n+0}' "$STUB_LOG" 2>/dev/null || true; }
ensure_argv() { awk -F'\t' '$2 ~ /^ensure( |$)/ {print $2; exit}' "$STUB_LOG"; }
ensure_cwd() { awk -F'\t' '$2 ~ /^ensure( |$)/ {print $1; exit}' "$STUB_LOG"; }
reset_state() { rm -rf "$ORCH_DIR"; : > "$STUB_LOG"; : > "$NOTIFY_LOG"; }

# 生成 status --json（sessions 由 JSON 规格文件给出；repo 空 = 归属不可判定）
mk_status() { # <spec.json>
  node -e '
const fs = require("fs");
const spec = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const sessions = spec.map((s) => ({
  name: s.name, kind: s.kind || "resident", role: s.role, task: s.task || "",
  pane_id: "w1:p1", cwd: s.cwd || "", repo: s.repo || "", own: !!s.repo,
  online: s.online !== false, agent: s.agent || "idle",
  busy: (s.agent || "idle") === "working",
  deliverable: s.deliverable !== false && (s.agent || "idle") === "idle",
  verdict: s.repo ? "local" : "unknown",
}));
const byRole = new Map();
for (const s of sessions) {
  if (!byRole.has(s.role)) byRole.set(s.role, { role: s.role, online: false, sessions: [] });
  const r = byRole.get(s.role);
  r.sessions.push(s.name);
  if (s.online) r.online = true;
}
process.stdout.write(JSON.stringify({
  schema: 1, backend: "herdr", repo_root: process.env.REPO_ROOT || "",
  sessions, roles: [...byRole.values()],
}) + "\n");
' "$1" > "$STATUS"
}

# ================================================================ ① 本仓 pm(T900) + 他仓 pm
cat > "$LAB/a.json" <<EOF
[
  {"name":"pm(T900)","role":"pm","task":"T900","cwd":"$REPO","repo":"$REPO","agent":"idle"},
  {"name":"pm","role":"pm","task":"","cwd":"$OTHER","repo":"$OTHER","agent":"idle"}
]
EOF
REPO_ROOT="$REPO" mk_status "$LAB/a.json"
mk_queue
reset_state
run_orch tick --now 2026-11-25T09:00:00Z
t4_assert_eq "0" "$T4_RC" "① 多仓在线：tick rc=0（$T4_ERR）"
t4_assert_eq "dispatched" "$(qstate)" "① 本仓有 role+task 命中 ⇒ 派单成功"
t4_assert_eq "1" "$(calls)" "① ensure 恰 1 次（不因他仓同名会话多派）"
t4_assert_contains "$(ensure_argv)" "ensure --task T900 pm@$REPO" "① AC10 ensure argv 指向**本仓**（pm@<repo_root>）"
t4_assert_not_contains "$(ensure_argv)" "$OTHER" "① AC10 ensure argv 不含他仓路径"
t4_assert_eq "$REPO" "$(ensure_cwd)" "① AC10 ensure 调用 cwd = 本仓根（子进程仓归属锚点）"
t4_assert_contains "$(cat "$NOTIFY_LOG")" "--to pm(T900)" "① AC10 to = 本仓会话 name（pm(T900)，不是裸名 pm）"
t4_assert_eq "0" "$(grep -c -- '--to pm --text' "$NOTIFY_LOG" || true)" "① AC10 不存在裸名 --to pm 的投递"
t4_assert_contains "$(cat "$NOTIFY_LOG")" "cwd=$REPO" "① AC10 通知带 cwd=<repo_root>（T559：to + cwd）"
t4_assert_contains "$(grep '"type":"ensured"' "$ORCH_DIR/wal.jsonl")" "\"session_id\":\"pm(T900)\"" "① WAL ensured 记本仓目标会话 name"
t4_assert_contains "$(grep '"type":"ensured"' "$ORCH_DIR/wal.jsonl")" "\"cwd\":\"$REPO\"" "① WAL ensured 记目标 cwd"

# ================================================================ ② 只有他仓 pm 在线 ⇒ 零 ensure
cat > "$LAB/b.json" <<EOF
[
  {"name":"pm","role":"pm","task":"","cwd":"$OTHER","repo":"$OTHER","agent":"idle"}
]
EOF
REPO_ROOT="$REPO" mk_status "$LAB/b.json"
mk_queue
reset_state
run_orch tick --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "② 仅他仓会话：tick rc=0（不 crash）"
t4_assert_eq "queued" "$(qstate)" "② row 仍 queued（不投他仓）"
t4_assert_eq "0" "$(calls)" "② **零 ensure**（本仓无可用 pm，绝不跨仓拉起）"
t4_assert_contains "$T4_OUT" "skipped=1" "② journal 记 skipped=1（可观测）"
t4_assert_contains "$T4_ERR" "他仓" "② journal 点名「仅在他仓在线」"
t4_assert_eq "0" "$(grep -c . "$NOTIFY_LOG" 2>/dev/null || true)" "② 零跨仓通知（不把状态发给外仓 pm）"

# ================================================================ ③ 同名两条且 repo 不可判定 ⇒ skip + 点名
cat > "$LAB/c.json" <<'EOF'
[
  {"name":"pm","role":"pm","task":"T900","agent":"idle"},
  {"name":"pm2","role":"pm","task":"T900","agent":"idle"}
]
EOF
REPO_ROOT="$REPO" mk_status "$LAB/c.json"
mk_queue
reset_state
run_orch tick --now 2026-11-25T11:00:00Z
t4_assert_eq "0" "$T4_RC" "③ repo 不可判定：tick rc=0"
t4_assert_eq "queued" "$(qstate)" "③ row 仍 queued（不猜）"
t4_assert_eq "0" "$(calls)" "③ **零 ensure**（同名跨仓不猜）"
t4_assert_contains "$T4_OUT" "skipped=1" "③ journal 记 skipped=1"
t4_assert_contains "$T4_ERR" "同名跨仓歧义" "③ journal 点名「同名跨仓歧义」"
t4_assert_contains "$T4_ERR" "pm/pm2" "③ 点名冲突的会话（可定位）"

t4_exit
