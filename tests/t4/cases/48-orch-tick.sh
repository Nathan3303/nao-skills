#!/usr/bin/env bash
# 用例 48 —— 编排器阶段 2 tick（T567-B · PRD §七 AC5–AC8 · ADR D4/D6）
#
# 可机械测的两个注入面（本批最大设计点）：
#   · **时钟**：`tick --now <ISO>`（或 `NAO_ORCH_NOW`）—— 15m 判据一律走注入时钟，全程零 `sleep` 等真实时间
#   · **fleet 走 PATH 桩**：`nao-fleet.sh` 桩返回可控 `status --json`、记录 `ensure`/`close`/`session-start` 调用
#     ⇒「不投递」「只派一次」「不重复派」都能用**调用次数**断言，不靠副作用猜测
#
# 断言组（编号 ↔ AC）：
#   ⓪ AC5：两个 orch 并发 ⇒ 第二个 rc=1 + 点名持锁 pid；`ensure` 总调用数 = 1（flock 生效）
#   ① AC6：目标角色 working / absent(unknown) ⇒ **零 ensure**，row 不动，只记等待
#   ② AC7：派单后 15m（注入时钟）⇒ blocked(no_ack) + 追问一次；attempt 不递增；再 tick 不重复追问
#   ③ AC8：intent 后、提交前被 kill -9 ⇒ row 仍 queued、WAL 有 intent+ensured；
#           下 tick 用 WAL 的 session_id+cwd 探：命中 ⇒ 补提交 dispatched（零重复 ensure）；未命中 ⇒ blocked(dispatch_unknown)
#   ④ CAS：提交前队列被外部改 ⇒ rc=1 **零写入**（不覆盖人的编辑）
#   ⑤ 队列非法 ⇒ rc=1 零写入（WAL 一个字节都不加）；board/dispatch/reap 与 queue.jsonl 同快照
#   ⑥ systemd：install 幂等（连装两次 diff -r 为空 + 幂等不重复 daemon-reload/enable）· doctor 失败 ⇒ rc=3 不 enable 不落单元 · uninstall 幂等
#   ⑦ AC1 保护：真 `status --json`（herdr 替身）契约 schema:1 + 文本路径逐字不变
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
t4_require_cmd git

ORCH="$T4_ROOT/bin/nao-orch"
LAB="$T4_CACHE_DIR/c48-$$"
STUB="$LAB/stub"
REPO="$LAB/repo"
QUEUE="$REPO/docs/queue.jsonl"
ORCH_DIR="$REPO/docs/queue/.orch"
mkdir -p "$STUB" "$REPO/docs/queue" "$LAB/xdg"
export STUB_STATUS="$LAB/status.json"
export STUB_LOG="$LAB/fleet.log"
export STUB_FAIL="$LAB/fail-status"
export NOTIFY_LOG="$LAB/notify.log"

# ---------------------------------------------------------------- 桩：nao-fleet.sh / 通知器 / systemctl / herdr / pi
cat > "$STUB/nao-fleet.sh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1" in
  status)
    [ -f "$STUB_FAIL" ] && { printf 'herdr: 前提不满足（桩）\n' >&2; exit 3; }
    [ "${SLOW_STATUS:-0}" = "1" ] && sleep 1.2
    cat "$STUB_STATUS"; exit 0 ;;
  ensure|close|session-start) exit 0 ;;
esac
exit 0
STUBEOF
cat > "$STUB/notifier" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
exit 0
STUBEOF
cat > "$STUB/systemctl" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_SYSCTL_LOG"
exit 0
STUBEOF
for b in herdr pi; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/$b"
done
chmod +x "$STUB"/*
export NAO_ORCH_NOTIFY="$STUB/notifier"
export STUB_SYSCTL_LOG="$LAB/systemctl.log"
PATH="$STUB:$PATH"; export PATH

# 桩 GO：herdr/pi 也走桩（doctor 只判可达）
t4_require_cmd herdr

run_orch() { t4_run_in_dir "$REPO" node "$ORCH" "$@"; }

# 生成可控 status.json：<role> <agent> <online:0|1> [name] [task] [cwd]
mk_status() {
  node -e '
const [role, agent, online, name, task, cwd] = process.argv.slice(1);
const nm = name || role;
const s = {
  name: nm, kind: task ? "derived" : "resident", role, task: task || "",
  pane_id: online === "1" ? "w1:p1" : "", cwd: online === "1" ? (cwd || "") : "",
  repo: online === "1" ? (cwd || "") : "", own: online === "1",
  online: online === "1", agent: online === "1" ? agent : "unknown",
  busy: agent === "working", deliverable: online === "1" && agent === "idle",
  verdict: online === "1" ? "local" : "unknown",
};
// pm 恒在线（通知目标；PRD §十.3：消息带会话 id + cwd）
const pm = {
  name: "pm", kind: "resident", role: "pm", task: "", pane_id: "w1:p0",
  cwd: cwd || "", repo: cwd || "", own: true, online: true, agent: "idle",
  busy: false, deliverable: true, verdict: "local",
};
const sessions = role === "pm" ? [s] : [s, pm];
const roles = [{ role, online: online === "1", sessions: [nm] }];
if (role !== "pm") roles.push({ role: "pm", online: true, sessions: ["pm"] });
const out = { schema: 1, backend: "herdr", repo_root: cwd || "", sessions, roles };
process.stdout.write(JSON.stringify(out) + "\n");
' "$@" > "$STUB_STATUS"
}

mk_queue() { # <state> <owner> <attempt> [updated]
  local id="T900"
  printf '{"id":"%s","kind":"feat","title":"tick 夹具","state":"%s","prio":"P1","deps":[],"repo":"nao-skills","branch":"feat/t900","owner":"%s","qa":"qa","acs":["AC5"],"attempt":%s,"created":"2026-11-25","updated":"%s","blocked_reason":""}\n' \
    "$id" "$1" "$2" "$3" "${4:-2026-11-25}" > "$QUEUE"
}

reset_state() { rm -rf "$ORCH_DIR"; : > "$STUB_LOG"; : > "$NOTIFY_LOG"; }
qstate() { node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean)[0]);console.log(r.state)' "$QUEUE"; }
qfield() { node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean)[0]);console.log(String(r[process.argv[2]]))' "$QUEUE" "$1"; }
qreason() { node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean)[0]);console.log(r.blocked_reason||"")' "$QUEUE"; }
set_qstate() { node -e 'const fs=require("fs"),p=process.argv[1];const ls=fs.readFileSync(p,"utf8").split("\n").filter(Boolean);ls[0]=JSON.stringify({...JSON.parse(ls[0]),state:process.argv[2]});fs.writeFileSync(p,ls.join("\n")+"\n")' "$QUEUE" "$1"; }
calls() { grep -cE "^$1 " "$STUB_LOG" 2>/dev/null || true; }
wal_type() { grep -cE "\"type\":\"$1\"" "$ORCH_DIR/wal.jsonl" 2>/dev/null || true; }
notify_n() { grep -c . "$NOTIFY_LOG" 2>/dev/null || true; }

git -C "$REPO" init -q 2>/dev/null || true
# HEAD 判据（90m stalled）需要非空 HEAD ⇒ 夹具仓先落一个空提交（`git rev-parse HEAD` 才有值）
git -C "$REPO" -c user.name=t4 -c user.email=t4@example.invalid commit -q --allow-empty -m init 2>/dev/null || true

# 整例唯一退出路径（herdr 替身段要保证 server 收场）
t48_exit() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t48_exit EXIT

# ================================================================ ⓪ AC5 并发只派一次
# 慢桩（status 睡 1.2s）制造真实重叠窗口；不 sleep 等业务时间，只等「锁文件出现持锁人」这一事实。
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
( cd "$REPO" && SLOW_STATUS=1 node "$ORCH" tick --now 2026-11-25T09:00:00Z > "$LAB/tick1.out" 2>&1 ) &
BG1=$!
for _i in $(seq 1 100); do [ -s "$ORCH_DIR/lock" ] && break; sleep 0.05; done
t4_assert_file "$ORCH_DIR/lock" "⓪ 首个 tick 已持锁（锁文件出现持锁人）"
run_orch tick --now 2026-11-25T09:00:01Z
t4_assert_eq "1" "$T4_RC" "⓪ AC5 第二个 orch ⇒ rc=1（flock 拒第二实例）"
t4_assert_contains "$T4_ERR" "持锁 pid=" "⓪ AC5 点名持锁 pid/起始时刻（可定位是谁在跑）"
t4_assert_contains "$T4_ERR" "$(cut -d' ' -f1 "$ORCH_DIR/lock")" "⓪ AC5 报的 pid == 锁文件里的持锁 pid"
wait "$BG1"
t4_assert_eq "0" "$?" "⓪ AC5 首个 tick 完成且 rc=0（$(cat "$LAB/tick1.out")）"
t4_assert_eq "1" "$(calls ensure)" "⓪ AC5 并发下 ensure **总调用数 = 1**（只派一次）"
t4_assert_eq "dispatched" "$(qstate)" "⓪ AC5 派单只落一次（row = dispatched）"
t4_assert_eq "1" "$(wal_type intent)" "⓪ AC5 WAL 只一条 intent（幂等键唯一）"

# ================================================================ ① AC6 零 ensure
mk_queue queued rd-infra 0
mk_status rd-infra working 1 rd-infra "" "$REPO"
reset_state
run_orch tick --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "① AC6 working：tick rc=0（$T4_ERR）"
t4_assert_eq "0" "$(calls ensure)" "① AC6 working ⇒ **零 ensure**（只记等待）"
t4_assert_eq "queued" "$(qstate)" "① AC6 working ⇒ row 不动（仍 queued）"
t4_assert_contains "$T4_OUT" "waiting=1" "① AC6 等待计入 journald 单行（waiting=1）"

mk_status rd-infra idle 0
reset_state
run_orch tick --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$(calls ensure)" "① AC6 absent/unknown ⇒ 同样零 ensure（fail-closed，不猜空闲）"
t4_assert_eq "queued" "$(qstate)" "① AC6 absent ⇒ row 不动"

mk_status rd-infra unknown 1 rd-infra "" "$REPO"
reset_state
run_orch tick --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$(calls ensure)" "① AC6 agent=unknown（在线但状态不可判）⇒ 零 ensure"

# ================================================================ ② AC7 15m 无回执
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
run_orch tick --now 2026-11-25T10:00:00Z
t4_assert_eq "0" "$T4_RC" "② 派单 tick rc=0（$T4_ERR）"
t4_assert_eq "dispatched" "$(qstate)" "② 派单后 row = dispatched"
t4_assert_eq "2026-11-25T10:00:00Z" "$(qfield updated)" "② 注入时钟生效（updated = --now，非墙钟）"
t4_assert_eq "1" "$(calls ensure)" "② 派单 ensure 恰 1 次"

run_orch tick --now 2026-11-25T10:14:00Z
t4_assert_eq "dispatched" "$(qstate)" "② 14m（<15m）⇒ 仍 dispatched（不误判）"
run_orch tick --now 2026-11-25T10:16:00Z
t4_assert_eq "blocked" "$(qstate)" "② 16m ⇒ blocked"
t4_assert_eq "no_ack" "$(qreason)" "② blocked_reason=no_ack"
t4_assert_eq "0" "$(qfield attempt)" "② attempt **不递增**（仍是 0）"
t4_assert_eq "1" "$(wal_type nudge)" "② 追问一次（WAL 恰 1 条 nudge）"
t4_assert_eq "1" "$(grep -c 'no_ack' "$NOTIFY_LOG" || true)" "② intercom 追问恰 1 次（带会话 id + cwd）"
t4_assert_contains "$(grep 'no_ack' "$NOTIFY_LOG")" "pm=" "② 追问消息带 pm 会话 id（禁裸名派单的同一口径）"
t4_assert_eq "1" "$(calls ensure)" "② AC7 全程不重复 ensure（仍 1 次）"
run_orch tick --now 2026-11-25T10:40:00Z
t4_assert_eq "1" "$(wal_type nudge)" "② 再 tick 不重复追问（nudge 仍 1）"
t4_assert_eq "1" "$(grep -c 'no_ack' "$NOTIFY_LOG" || true)" "② 再 tick 不重复追问通知（no_ack 仍 1）"

# ================================================================ ②b 90m stalled（HEAD 未变判据 · PRD §六「已实现」）
# 派单时 WAL intent 记 `head`；working 行 now - intent.at ≥90m 且 HEAD 未变 ⇒ blocked(stalled)。
# 全程注入时钟 + 夹具仓真 git（不 sleep 90 分钟）。三态：+89m 不动 / +91m 且 HEAD 未变 ⇒ blocked / +91m 但 HEAD 变了 ⇒ 不 blocked。
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
run_orch tick --now 2026-11-25T09:00:00Z
t4_assert_eq "dispatched" "$(qstate)" "②b 派单成功（stalled 场景起点）"
t4_assert_contains "$(grep '"type":"intent"' "$ORCH_DIR/wal.jsonl")" '"head":"' "②b WAL intent 记 head（派单时的 HEAD）"
set_qstate working
run_orch tick --now 2026-11-25T10:29:00Z
t4_assert_eq "working" "$(qstate)" "②b +89m（<90m）⇒ 仍 working（不误判）"
t4_assert_eq "0" "$(wal_type stalled)" "②b +89m ⇒ 无 stalled 记录"
run_orch tick --now 2026-11-25T10:31:00Z
t4_assert_eq "blocked" "$(qstate)" "②b +91m 且 HEAD 未变 ⇒ blocked"
t4_assert_eq "stalled" "$(qreason)" "②b blocked_reason=stalled"
t4_assert_eq "1" "$(wal_type stalled)" "②b WAL 记 stalled（可观测）"
t4_assert_eq "0" "$(qfield attempt)" "②b attempt 不递增"
t4_assert_eq "1" "$(grep -c 'stalled' "$NOTIFY_LOG" || true)" "②b 通知 PM（与 no_ack 同口径）"
# 反例：+91m 但 HEAD 变了 ⇒ 不判 stalled（仓有进展迹象）
mk_queue queued rd-infra 0
reset_state
run_orch tick --now 2026-11-25T12:00:00Z
t4_assert_eq "dispatched" "$(qstate)" "②b HEAD 变化场景：派单成功"
set_qstate working
git -C "$REPO" -c user.name=t4 -c user.email=t4@example.invalid commit -q --allow-empty -m progress
run_orch tick --now 2026-11-25T13:31:00Z
t4_assert_eq "working" "$(qstate)" "②b +91m 但 HEAD 已变 ⇒ **不** blocked（仍 working）"
t4_assert_eq "0" "$(wal_type stalled)" "②b HEAD 变化 ⇒ 无 stalled 记录"
t4_assert_contains "$T4_ERR" "HEAD 已变" "②b 点名「HEAD 已变 ⇒ 不判 stalled」（不是静默）"

# ================================================================ ③ AC8 kill -9 后 WAL 恢复
cat > "$LAB/hook-kill.sh" <<'HOOK'
#!/usr/bin/env bash
[ "$1" = "before-commit" ] || exit 0
kill -9 "$NAO_ORCH_TICK_PID"
HOOK
chmod +x "$LAB/hook-kill.sh"
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
NAO_ORCH_HOOK="$LAB/hook-kill.sh" run_orch tick --now 2026-11-25T11:00:00Z
t4_assert_ne "0" "$T4_RC" "③ 崩溃注入：tick 非 0 退出（rc=$T4_RC）"
t4_assert_eq "queued" "$(qstate)" "③ 崩在「intent 后、提交前」⇒ row 仍 queued"
t4_assert_eq "1" "$(calls ensure)" "③ 崩溃前 ensure 已执行 1 次"
t4_assert_eq "1" "$(wal_type intent)" "③ WAL 有 intent（append-only 第一段已落盘）"
t4_assert_eq "1" "$(wal_type ensured)" "③ WAL 有 ensured（真实会话身份 session_id+cwd 已在账上）"
t4_assert_contains "$(grep '"type":"intent"' "$ORCH_DIR/wal.jsonl")" '"session_id":"rd-infra(T900)"' "③ intent 记 session_id（禁裸名探针）"
t4_assert_contains "$(grep '"type":"intent"' "$ORCH_DIR/wal.jsonl")" "\"cwd\":\"$REPO\"" "③ intent 记 cwd（探针双要素）"

# 下 tick：用 WAL 的 session_id + cwd 探到 ⇒ 补提交 dispatched，**零重复 ensure**
mk_status rd-infra working 1 "rd-infra(T900)" T900 "$REPO"
run_orch tick --now 2026-11-25T11:05:00Z
t4_assert_eq "0" "$T4_RC" "③ 恢复 tick rc=0（$T4_ERR）"
t4_assert_eq "dispatched" "$(qstate)" "③ 探到会话 ⇒ 补提交 dispatched（不重派）"
t4_assert_eq "1" "$(wal_type recovered)" "③ WAL 记 recovered"
t4_assert_eq "1" "$(calls ensure)" "③ **零重复 ensure**（仍 1 次）"

# 未命中变体：WAL 有 intent、行仍 queued、探不到会话 ⇒ blocked(dispatch_unknown)，绝不重派
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
NAO_ORCH_HOOK="$LAB/hook-kill.sh" run_orch tick --now 2026-11-25T12:00:00Z
t4_assert_ne "0" "$T4_RC" "③ 未命中变体：先崩溃（rc=$T4_RC）"
run_orch tick --now 2026-11-25T12:05:00Z
t4_assert_eq "0" "$T4_RC" "③ 未命中变体：恢复 tick rc=0"
t4_assert_eq "blocked" "$(qstate)" "③ 探不到 ⇒ blocked"
t4_assert_eq "dispatch_unknown" "$(qreason)" "③ blocked_reason=dispatch_unknown"
t4_assert_eq "1" "$(calls ensure)" "③ **零重复 ensure**（绝不自动重派）"
t4_assert_eq "1" "$(wal_type dispatch_unknown)" "③ WAL 记 dispatch_unknown 供人核对"
t4_assert_ge 1 "$(notify_n)" "③ blocked 通知 PM（留证 + 唤醒，PRD §十.3）"

# ================================================================ ④ CAS 零写入
cat > "$LAB/hook-cas.sh" <<'HOOK'
#!/usr/bin/env bash
[ "$1" = "before-commit" ] || exit 0
printf '%s\n' '{"id":"T901","kind":"fix","title":"人工插入","state":"queued","prio":"P0","deps":[],"repo":"nao-skills","branch":"fix/t901","owner":"rd-fe","qa":"qa","acs":["AC5"],"attempt":0,"created":"2026-11-25","updated":"2026-11-25","blocked_reason":""}' >> "$NAO_CAS_QUEUE"
HOOK
chmod +x "$LAB/hook-cas.sh"
mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
NAO_ORCH_HOOK="$LAB/hook-cas.sh" NAO_CAS_QUEUE="$QUEUE" run_orch tick --now 2026-11-25T13:00:00Z
t4_assert_eq "1" "$T4_RC" "④ CAS 冲突 ⇒ rc=1"
t4_assert_contains "$T4_ERR" "sha 不符" "④ 失败信息点名 sha 不符（不是静默）"
t4_assert_eq "queued" "$(qstate)" "④ 零写入：T900 仍 queued（不覆盖人的编辑）"
t4_assert_eq "2" "$(grep -c . "$QUEUE")" "④ 人工插入的行被保留（未被整表重写吞掉）"

# ================================================================ ⑤ 非法队列 + board/dispatch/reap
printf '%s\n' '{"id":"T902","kind":"feat","title":"缺字段的行"}' > "$QUEUE"
reset_state
run_orch tick --now 2026-11-25T14:00:00Z
t4_assert_eq "1" "$T4_RC" "⑤ 队列非法 ⇒ rc=1"
t4_assert_contains "$T4_ERR" "缺少必需字段" "⑤ 点名缺失字段（fail loud）"
t4_assert_absent "$ORCH_DIR/wal.jsonl" "⑤ 零写入：WAL 一个字节都没加"

mk_status rd-infra idle 1 rd-infra "" "$REPO"
mk_queue queued rd-infra 0
reset_state
run_orch board --json
t4_assert_eq "0" "$T4_RC" "⑤ board --json rc=0"
t4_assert_eq "1" "$(node -e 'console.log(JSON.parse(process.argv[1]).schema)' "$T4_OUT")" "⑤ board --json schema=1"
t4_assert_contains "$T4_OUT" '"queued":1' "⑤ board 计数与 queue.jsonl 一致（queued=1）"
run_orch dispatch T900 --now 2026-11-25T15:00:00Z
t4_assert_eq "0" "$T4_RC" "⑤ dispatch（人工单发）rc=0"
t4_assert_eq "dispatched" "$(qstate)" "⑤ dispatch 走同一闸门（row = dispatched）"
t4_assert_eq "1" "$(calls ensure)" "⑤ dispatch 只 ensure 1 次"
run_orch reap
t4_assert_eq "0" "$T4_RC" "⑤ reap 只读 rc=0"
t4_assert_contains "$T4_OUT" "wal_records=" "⑤ reap 报 WAL 记录数（可观测）"

# ================================================================ ⑥ systemd 安装/卸载（幂等 + doctor 闸门）
SYSREPO="$LAB/sysrepo"
mkdir -p "$SYSREPO/.agents"
git -C "$SYSREPO" init -q 2>/dev/null || true
cp -r "$T4_ROOT/.agents/systemd" "$SYSREPO/.agents/systemd"
mkdir -p "$SYSREPO/docs/queue"
printf '%s\n' '{"id":"T950","kind":"feat","title":"安装夹具","state":"queued","prio":"P3","deps":[],"repo":"sysrepo","branch":"feat/t950","owner":"","qa":"","acs":["AC5"],"attempt":0,"created":"2026-11-25","updated":"2026-11-25","blocked_reason":""}' > "$SYSREPO/docs/queue.jsonl"
SYS_XDG="$LAB/xdg-sys"; rm -rf "$SYS_XDG"; mkdir -p "$SYS_XDG"
mk_status rd-infra idle 1 rd-infra "" "$REPO"
: > "$STUB_SYSCTL_LOG"
run_sys() { t4_run_in_dir "$SYSREPO" env XDG_CONFIG_HOME="$SYS_XDG" STUB_FAIL="$STUB_FAIL" node "$ORCH" "$@"; }
run_sys install-systemd --interval 1m
t4_assert_eq "0" "$T4_RC" "⑥ install-systemd rc=0（$T4_ERR）"
UNITD="$SYS_XDG/systemd/user"
t4_assert_file "$UNITD/nao-orch.service" "⑥ 落 service 单元"
t4_assert_file "$UNITD/nao-orch.timer" "⑥ 落 timer 单元"
t4_assert_contains "$(cat "$UNITD/nao-orch.service")" "Type=oneshot" "⑥ service = Type=oneshot（无常驻进程）"
t4_assert_contains "$(cat "$UNITD/nao-orch.service")" "TimeoutStartSec=120" "⑥ 整 tick 硬超时 120s"
t4_assert_contains "$(cat "$UNITD/nao-orch.service")" "WorkingDirectory=$SYSREPO" "⑥ WorkingDirectory 锚定安装时解析的 git 顶层"
t4_assert_contains "$(cat "$UNITD/nao-orch.service")" "ExecStart=$(command -v node) $SYSREPO/bin/nao-orch tick" "⑥ ExecStart = 绝对 node + 安装仓的绝对 nao-orch 路径 + tick"
t4_assert_contains "$(cat "$UNITD/nao-orch.timer")" "OnCalendar=*:0/1" "⑥ timer 日历式 + --interval 1m 生效"
t4_assert_contains "$(cat "$UNITD/nao-orch.timer")" "Persistent=true" "⑥ Persistent=true（错过的 tick 补跑）"
t4_assert_contains "$(cat "$UNITD/nao-orch.timer")" "RandomizedDelaySec=15s" "⑥ RandomizedDelaySec=15s"
t4_assert_contains "$(cat "$UNITD/nao-orch.service")" "Environment=NAO_ORCH_NOTIFY=$STUB/notifier" \
  "⑥ 安装时已设的通知器写进 unit Environment=（否则 timer 内通知只剩 journald + 队列留证）"
t4_assert_eq "0" "$(grep -c 'enable' "$STUB_SYSCTL_LOG" || true)" "⑥ 默认**不 enable**（阶段 2 默认关闭）"
cp -r "$UNITD" "$LAB/units-first"
run_sys install-systemd --interval 1m
t4_assert_eq "0" "$T4_RC" "⑥ 连装第二次 rc=0"
t4_assert_eq "" "$(diff -r "$LAB/units-first" "$UNITD" || true)" "⑥ 幂等：连装两次 diff -r 为空（effect=0）"
t4_assert_eq "1" "$(grep -c 'daemon-reload' "$STUB_SYSCTL_LOG" || true)" "⑥ 幂等：内容未变 ⇒ 不重复 daemon-reload"
: > "$STUB_SYSCTL_LOG"
run_sys install-systemd --interval 1m --enable
t4_assert_eq "0" "$T4_RC" "⑥ --enable 显式启用 rc=0"
t4_assert_eq "1" "$(grep -c 'enable --now nao-orch.timer' "$STUB_SYSCTL_LOG" || true)" "⑥ --enable 才 enable timer（默认路径不动）"

# doctor 失败 ⇒ 不落单元、不 enable、exit 3
SYS_XDG2="$LAB/xdg-sys-fail"; rm -rf "$SYS_XDG2"; mkdir -p "$SYS_XDG2"
touch "$STUB_FAIL"
: > "$STUB_SYSCTL_LOG"
t4_run_in_dir "$SYSREPO" env XDG_CONFIG_HOME="$SYS_XDG2" STUB_FAIL="$STUB_FAIL" node "$ORCH" install-systemd --enable
t4_assert_eq "3" "$T4_RC" "⑥ doctor 失败 ⇒ install rc=3（exit 3）"
t4_assert_contains "$T4_ERR" "doctor 未过" "⑥ 失败信息点名 doctor 未过"
t4_assert_absent "$SYS_XDG2/systemd/user/nao-orch.timer" "⑥ doctor 失败 ⇒ 不落单元"
t4_assert_eq "0" "$(grep -c 'enable' "$STUB_SYSCTL_LOG" || true)" "⑥ doctor 失败 ⇒ **不 enable**"
rm -f "$STUB_FAIL"
run_sys uninstall-systemd
t4_assert_eq "0" "$T4_RC" "⑥ uninstall-systemd rc=0"
t4_assert_absent "$UNITD/nao-orch.timer" "⑥ 卸载后 timer 不在"
t4_assert_absent "$UNITD/nao-orch.service" "⑥ 卸载后 service 不在"
run_sys uninstall-systemd
t4_assert_eq "0" "$T4_RC" "⑥ uninstall 幂等（再跑仍 rc=0）"
t4_assert_contains "$T4_OUT" "removed=0" "⑥ 幂等可观测（removed=0）"

# ================================================================ ⑦ 真 status --json（herdr 替身）+ 文本逐字不变
LAB3="$LAB/lab3"
mkdir -p "$LAB3"
cp -r "$T4_ROOT/.agents" "$LAB3/.agents" || t4_bad "夹具复制 .agents 失败"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB3" "lab48" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }
be_run_fleet "$LAB3" ensure pm; t4_assert_eq "0" "$BE_RC" "⑦ 替身场景：ensure pm rc=0"
be_run_fleet "$LAB3" status --json
t4_assert_eq "0" "$BE_RC" "⑦ status --json rc=0（${BE_ERR_ANSI}）"
JS="$BE_OUT"
t4_assert_eq "1" "$(node -e 'console.log(JSON.parse(process.argv[1]).schema)' "$JS")" "⑦ 契约：schema=1"
t4_assert_eq "herdr" "$(node -e 'console.log(JSON.parse(process.argv[1]).backend)' "$JS")" "⑦ 契约：backend 字段"
for fld in name kind role task pane_id cwd repo own online agent busy deliverable verdict; do
  t4_assert_contains "$JS" "\"$fld\":" "⑦ sessions[] 字段清单含 $fld"
done
t4_assert_eq "pm" "$(node -e '
const j = JSON.parse(process.argv[1]);
const s = j.sessions.find((x) => x.name === "pm");
console.log(s ? s.name : "MISSING");' "$JS")" "⑦ 在线会话 pm 出现在 sessions[]（agent=$(node -e 'const j=JSON.parse(process.argv[1]);console.log(j.sessions.find(x=>x.name==="pm").agent)' "$JS")）"
t4_assert_eq "idle" "$(node -e 'const j=JSON.parse(process.argv[1]);console.log(j.sessions.find(x=>x.name==="pm").agent)' "$JS")" "⑦ agent 三态之一（idle）"
t4_assert_eq "true" "$(node -e 'const j=JSON.parse(process.argv[1]);console.log(String(j.sessions.find(x=>x.name==="pm").online))' "$JS")" "⑦ online=true"
t4_assert_contains "$(node -e 'const j=JSON.parse(process.argv[1]);console.log(j.roles.map(r=>r.role).join(","))' "$JS")" "rd-infra" "⑦ roles[] 含缺席常驻角色（无会话也要出现 ⇒ orch 能判 absent）"
t4_assert_eq "unknown" "$(node -e 'const j=JSON.parse(process.argv[1]);console.log(j.sessions.find(x=>x.name==="qa").agent)' "$JS")" "⑦ 缺席角色 agent=unknown（fail-closed）"
# 文本路径不变：同一场景下 `status` 仍是旧文本（不含 JSON 首字符、含既有分节标题）
be_run_fleet "$LAB3" status
t4_assert_eq "0" "$BE_RC" "⑦ status（文本）rc=0"
t4_assert_contains "$BE_OUT" "== 角色会话在线状态" "⑦ 文本路径逐字保留（AC1：--json 只增不改）"
t4_assert_not_contains "$BE_OUT" '{"schema":1' "⑦ 文本输出不含 JSON（两条输出面互不污染）"

t4_exit
