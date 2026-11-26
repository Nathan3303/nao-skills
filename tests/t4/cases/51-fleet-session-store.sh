#!/usr/bin/env bash
# 用例 51 —— 舰队 session 记录治理（T573 · Issue #206）：
#   ① 独立目录：**全部**舰队会话（常驻 + `--task` 派生）的 Pi session **不落** `~/.pi/agent/sessions/`，
#      落 `state/sessions/--<编码 cwd>--/`（一仓一子目录、无日期层），目录由 ensure 建好
#   ② 查看入口：`logs <role>` 出 turn 摘要（user 首行 + assistant 首行 + 工具名）· `--list` 列
#      仓 + 日期 + 角色 + 大小 + 路径 · `--raw` 原文
#   ③ 仓维度：默认只看**当前仓**；`--repo <仓名>` 跨仓；同名角色两仓记录**互不串**；
#      `--purge` 只清当前仓，`--repo all` 才全清
#   ④ 分级清理：正常交付（有 done 回执）24h 删 · 异常（无回执）7 天留 + state 目录 `.retention.log` 点名
#      （T573 返修 D2：机制状态**不写**仓内 `docs/tasks-state.md`）
#   ⑤ 幂等：连跑两次 purge，第二次零删除 + rc=0
#   ⑥ 无记录 ⇒ rc=0 + 一行提示
#   ⑦ 跨代（返修 D1）：同名两代（旧代崩溃 / 新代正常）⇒ 各按自己的代次判，旧代留 7 天 + 点名
#   ⑧ 跨仓（返修 D1）：他仓 `done` 不得升级本仓记录的分级
#   ⑨ 全清（--repo all --days 0）· ⑩ 无记录 ⇒ rc=0 + 一行提示
#
# 口径（判据来源）：
#   · 落盘面 = 命令行参数（`--session-dir <root>/--<编码 cwd>--`，替身 `pane run` 的原始串）+ 目录实建
#   · 分级面 = 记录 jsonl（header `cwd` + `session_info.name`）+ 该仓目录 `.ledger`（spawn/done/force）
#             + `<cwd>/docs/queue/<task>.receipt.json`；done/force 必须落在**该代窗口**
#             （本代 spawn 之后、下一同名 spawn 之前）且只认**本仓**台账
#   · 时间面 = 夹具把 mtime 拨到 3 天前（正常项 > 24h 且异常项 < 7 天）
# 夹具：`tests/t4/fixtures/herdr-double`（不执行真 pi）+ 隔离 HOME；不碰用户 `~/.pi/agent/sessions`
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node

PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab51-$$"
OTHER="$LAB/other"
mkdir -p "$LAB" "$LAB/docs/queue" "$OTHER"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

CALL_LOG="$T4_CACHE_DIR/c51-calls-$$.log"; : > "$CALL_LOG"
SPAWN_LOG="$T4_CACHE_DIR/c51-spawn-$$.log"; : > "$SPAWN_LOG"
export T4_HERDR_CALL_LOG="$CALL_LOG" T4_HERDR_SPAWN_LOG="$SPAWN_LOG"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }

# 隔离 HOME（与 be_isolated_env 同源）⇒ state 根可预测
ISHOME="$LAB/.t4-home"
SESS_ROOT="$ISHOME/.local/state/nao-fleet/sessions"
DEFAULT_SESS="$ISHOME/.pi/agent/sessions"   # Pi 主目录（本用例判据：**不得**出现）
sess_dir_for() { # <repo> → <root>/--<编码 cwd>--（与 lib/sessions.sh::_fleet_sessions_dir_name 同形）
  local p; p="$(cd "$1" 2>/dev/null && pwd -P)" || p="$1"
  printf '%s/--%s--' "$SESS_ROOT" "$(printf '%s' "${p#/}" | sed -e 's#[/\\:]#-#g')"
}
SESS_DIR="$(sess_dir_for "$LAB")"
OTHER_DIR="$(sess_dir_for "$OTHER")"
LAB_KEY="$(basename "$LAB" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"

t51_teardown() { [ -n "${LAB:-}" ] && [ -d "$LAB" ] && be_teardown >/dev/null 2>&1 || true; return 0; }
t51_exit() {
  local rc=$?; t51_teardown; trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t51_exit EXIT

run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR
  be_run_fleet "$LAB" "$@"
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT"; T4_ERR="$BE_ERR"; T4_OUT_ANSI="$BE_OUT_ANSI"; T4_ERR_ANSI="$BE_ERR_ANSI"
}

# 起场（替身 server；先把状态落一份，避免就绪探测空转 50×100ms）
be_herdr "$BE_SESSION" server >/dev/null 2>&1 || true
be_start_server >/dev/null || { t4_bad "起场：be_start_server 失败"; t4_exit; }
t4_ok "夹具：herdr 替身 server 就绪（$BE_SESSION）"

# ================================================================ ① 独立目录（常驻 + 派生都落这里）
t4_assert_absent "$DEFAULT_SESS" "① 起跑前：Pi 主 session 目录不存在（${DEFAULT_SESS#"$LAB"/}）"
run_fleet ensure --task T573 rd-infra
t4_assert_eq "0" "$T4_RC" "① ensure --task T573 rd-infra rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_file "$SPAWN_LOG" "① 替身记录到 pane run 命令（判据载体）"
t4_assert_eq "1" "$(grep -cF -- "--session-dir $SESS_DIR" "$SPAWN_LOG" || true)" \
  "① 派生会话命令行含 --session-dir <state>/--<编码 cwd>--（$SESS_DIR）"
t4_assert_dir "$SESS_DIR" "① 一仓一子目录已建（不存在则建）"
t4_assert_eq "0" "$(grep -v 'pane run' "$CALL_LOG" 2>/dev/null | grep -cF -- '--session-dir' || true)" \
  "① --session-dir 只随 pane run 的命令串走（不进 workspace/tab 等其它 api 调用）"

# 常驻会话同口径（范围 = 全部舰队会话，不只 worker）
run_fleet ensure qa
t4_assert_eq "0" "$T4_RC" "① ensure qa（常驻）rc=0"
t4_assert_eq "1" "$(grep -F -- '--name qa' "$SPAWN_LOG" | grep -cF -- "--session-dir $SESS_DIR" || true)" \
  "① 常驻会话命令行同样含 --session-dir（不只 --task 派生）"
t4_assert_absent "$DEFAULT_SESS" "① 两次 ensure 后 Pi 主目录仍不存在（新增 0 条）"
t4_assert_eq "2" "$(grep -cF -- "--session-dir $SESS_DIR" "$SPAWN_LOG" || true)" \
  "① 同名仓子目录只有一个（两条 ensure 复用同一目录，不按日期/角色再分层）"
t4_assert_eq "2" "$(grep -cF -- '--session-dir' "$SPAWN_LOG" || true)" \
  "① 两条会话的 --session-dir 各一次（不重复拼参）"
t4_assert_eq "2" "$(grep -c . "$SESS_DIR/.ledger" 2>/dev/null || true)" \
  "① 台账两条 spawn（派生 T573 + 常驻 qa）"
t4_assert_contains "$(cat "$SESS_DIR/.ledger" 2>/dev/null)" "T573" "① 台账带 task=T573（role/task 绑定）"
t4_assert_contains "$(cat "$SESS_DIR/.ledger" 2>/dev/null)" "spawn" "① 台账 kind=spawn"

# ================================================================ ② 查看入口（turn 摘要 / --list / --raw）
t51_mk_record() { # <file> <name> <cwd> <iso> <user 首行>
  local f="$1" name="$2" cwd="$3" iso="$4" txt="$5"
  {
    printf '{"type":"session","version":3,"id":"s","timestamp":"%s","cwd":"%s"}\n' "$iso" "$cwd"
    printf '{"type":"session_info","id":"a","parentId":null,"timestamp":"%s","name":"%s"}\n' "$iso" "$name"
    printf '{"type":"message","id":"b","parentId":"a","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$iso" "$txt"
    printf '{"type":"message","id":"c","parentId":"b","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"先看仓库结构。\\n第二行不入摘要"},{"type":"toolCall","id":"t1","name":"bash"},{"type":"toolCall","id":"t2","name":"read"}]}}\n' "$iso"
  } > "$f"
}

ISO_OK="$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-3d +%Y-%m-%dT%H:%M:%S.000Z)"
ISO_BAD="$(date -u -d '3 days ago 2 hours ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-3d -v-2H +%Y-%m-%dT%H:%M:%S.000Z)"
t51_ledger() { # <dir> <iso> <kind> <name> <task> <repo>
  local e; e="$(date -u -d "$2" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "${2%%.*}" +%s)"
  printf '%s\t%s\t%s\t-\t%s\t%s\n' "$e" "$3" "$4" "$5" "$6" >> "$1/.ledger"
}

t51_mk_record "$SESS_DIR/2026-11-23T01-00-00-000Z_ok.jsonl"  rd-infra "$LAB"   "$ISO_OK"  "[T900] 正常交付的派单"
t51_mk_record "$SESS_DIR/2026-11-23T03-00-00-000Z_bad.jsonl" rd-infra "$LAB"   "$ISO_BAD" "[T901] 没有回执的派单"
t51_ledger "$SESS_DIR" "$ISO_OK"  spawn rd-infra T900 "$LAB"
t51_ledger "$SESS_DIR" "$ISO_BAD" spawn rd-infra T901 "$LAB"
# 另一仓：同名角色 `pm`（放在它自己的仓子目录里）
mkdir -p "$OTHER/docs/queue" "$OTHER_DIR"
t51_mk_record "$OTHER_DIR/2026-11-23T05-00-00-000Z_pm.jsonl" pm "$OTHER" "$ISO_OK" "[T800] 他仓 pm 的派单"
t51_ledger "$OTHER_DIR" "$ISO_OK" spawn pm T800 "$OTHER"
printf '{ "schema": 1, "id": "T800" }\n' > "$OTHER/docs/queue/T800.receipt.json"
touch -d '3 days ago' "$SESS_DIR"/*.jsonl "$OTHER_DIR"/*.jsonl
printf '{ "schema": 1, "id": "T900" }\n' > "$LAB/docs/queue/T900.receipt.json"
: > "$LAB/docs/tasks-state.md"

run_fleet logs rd-infra
t4_assert_eq "0" "$T4_RC" "② logs rd-infra rc=0（无记录也不是错误）"
t4_assert_contains "$T4_OUT_ANSI" "[T900] 正常交付的派单" "② 摘要含 user 首行（T900）"
t4_assert_contains "$T4_OUT_ANSI" "[T901] 没有回执的派单" "② 摘要含 user 首行（T901）"
t4_assert_contains "$T4_OUT_ANSI" "先看仓库结构。" "② 摘要含 assistant 首行"
t4_assert_contains "$T4_OUT_ANSI" "[bash,read]" "② 摘要含工具名（bash,read）"
t4_assert_not_contains "$T4_OUT_ANSI" "第二行不入摘要" "② 摘要只取首行（不刷全文）"

run_fleet logs rd-infra --list
t4_assert_eq "0" "$T4_RC" "② logs --list rc=0"
t4_assert_contains "$T4_OUT_ANSI" "$SESS_DIR/2026-11-23T01-00-00-000Z_ok.jsonl" "② --list 列出正常项路径"
t4_assert_contains "$T4_OUT_ANSI" "$SESS_DIR/2026-11-23T03-00-00-000Z_bad.jsonl" "② --list 列出异常项路径"
t4_assert_contains "$T4_OUT_ANSI" "2026-11-23" "② --list 含日期列（记录起始日）"
t4_assert_contains "$T4_OUT_ANSI" "$LAB_KEY" "② --list 含仓列（仓基键 $LAB_KEY）"
t4_assert_contains "$T4_OUT_ANSI" "rd-infra" "② --list 含角色名列（读 session_info.name）"
t4_assert_contains "$T4_OUT_ANSI" "K" "② --list 含大小列"

run_fleet logs rd-infra --raw
t4_assert_contains "$T4_OUT" "第二行不入摘要" "② --raw 原样输出（全文可见）"

# ================================================================ ③ 仓维度（同名角色两仓互不串）
run_fleet logs pm
t4_assert_eq "0" "$T4_RC" "③ logs pm rc=0"
t4_assert_contains "$T4_OUT_ANSI" "无记录" "③ 本仓无 pm 记录 ⇒ 不列他仓的 pm（互不串）"
t4_assert_not_contains "$T4_OUT_ANSI" "[T800]" "③ 本仓视图不含他仓记录"
run_fleet logs pm --repo other
t4_assert_eq "0" "$T4_RC" "③ logs pm --repo other rc=0"
t4_assert_contains "$T4_OUT_ANSI" "[T800] 他仓 pm 的派单" "③ --repo 指定仓 ⇒ 看得到他仓 pm"
run_fleet logs pm --repo all
t4_assert_contains "$T4_OUT_ANSI" "[T800] 他仓 pm 的派单" "③ --repo all ⇒ 跨仓可见"

# ================================================================ ④ 分级清理（默认只清当前仓）
run_fleet logs --purge
t4_assert_eq "0" "$T4_RC" "④ logs --purge rc=0（清理失败也不改 rc）"
t4_assert_contains "$T4_OUT_ANSI" "删除 1 条" "④ 本仓正常交付（有 done 回执，>24h）被删除 = 1 条"
t4_assert_absent "$SESS_DIR/2026-11-23T01-00-00-000Z_ok.jsonl" "④ 本仓正常项记录已删"
t4_assert_file "$SESS_DIR/2026-11-23T03-00-00-000Z_bad.jsonl" "④ 本仓异常项（无回执，<7 天）仍在"
t4_assert_file "$OTHER_DIR/2026-11-23T05-00-00-000Z_pm.jsonl" "④ 他仓记录不被本仓 purge 波及（作用域=当前仓）"
RETLOG="$SESS_DIR/.retention.log"
t4_assert_file "$RETLOG" "④ 异常点名落 **state 目录**（$(basename "$SESS_DIR")/.retention.log）"
t4_assert_contains "$(cat "$RETLOG" 2>/dev/null)" "T901" "④ 点名含任务编号"
t4_assert_contains "$(cat "$RETLOG" 2>/dev/null)" "rd-infra" "④ 点名含角色"
t4_assert_contains "$(cat "$RETLOG" 2>/dev/null)" "2026-11-23T03-00-00-000Z_bad.jsonl" \
  "④ 点名含记录路径"
t4_assert_eq "0" "$(grep -cF -- '[session-retention]' "$LAB/docs/tasks-state.md" 2>/dev/null || true)" \
  "④ D2：仓内交付台账 docs/tasks-state.md 零写入（点名不污染业务仓）"

# ================================================================ ⑤ 幂等（第二次零删除）+ --repo all 才全清
BEFORE_LIST="$(ls "$SESS_DIR"/*.jsonl 2>/dev/null | sort || true)"
run_fleet logs --purge
t4_assert_eq "0" "$T4_RC" "⑤ 连跑第二次 purge rc=0"
t4_assert_contains "$T4_OUT_ANSI" "删除 0 条" "⑤ 第二次零删除（幂等）"
t4_assert_eq "$BEFORE_LIST" "$(ls "$SESS_DIR"/*.jsonl 2>/dev/null | sort || true)" "⑤ 记录集合逐字不变"
t4_assert_eq "1" "$(grep -cF -- '[session-retention]' "$RETLOG" 2>/dev/null || true)" \
  "⑤ 异常点名不重复写（.retention.log 仍 1 行）"

# ================================================================ ⑦ 跨代：同名两代各按自己的代次判（返修 D1）
#   旧代（3 天前崩溃、无 close）⇒ 异常（7 天，留）；新代（30h 前 normal close）⇒ 正常（24h，删）
#   旧实现按**名字**匹配 done（无代次上界）⇒ 旧代被新代的 done 判成正常 ⇒ 24h 删且不点名（假绿）
ISO_G1="$(date -u -d '3 days ago 5 hours ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-3d -v-5H +%Y-%m-%dT%H:%M:%S.000Z)"
ISO_G2="$(date -u -d '30 hours ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-30H +%Y-%m-%dT%H:%M:%S.000Z)"
ISO_G2D="$(date -u -d '29 hours ago' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-29H +%Y-%m-%dT%H:%M:%S.000Z)"
G1="$SESS_DIR/2026-11-23T00-00-00-000Z_gen1.jsonl"; G2="$SESS_DIR/2026-11-23T06-00-00-000Z_gen2.jsonl"
t51_mk_record "$G1" qa3 "$LAB" "$ISO_G1" "[T700] 旧代崩溃无 close"
t51_mk_record "$G2" qa3 "$LAB" "$ISO_G2" "[T701] 新代正常收尾"
t51_ledger "$SESS_DIR" "$ISO_G1"  spawn qa3 T700 "$LAB"
t51_ledger "$SESS_DIR" "$ISO_G2"  spawn qa3 T701 "$LAB"
t51_ledger "$SESS_DIR" "$ISO_G2D" done  qa3 T701 "$LAB"
touch -d '3 days ago'  "$G1"
touch -d '30 hours ago' "$G2"
run_fleet logs --purge
t4_assert_eq "0" "$T4_RC" "⑦ 跨代 purge rc=0"
t4_assert_file "$G1" "⑦ 同名旧代（崩溃无 close）仍在 —— 不被新代 done 升级（留 7 天）"
t4_assert_absent "$G2" "⑦ 同名新代（done，>24h）已删 —— 两代各按自己的代次判"
t4_assert_contains "$(cat "$RETLOG" 2>/dev/null)" "2026-11-23T00-00-00-000Z_gen1.jsonl" \
  "⑦ 旧代被点名（判不出 = 异常）"
t4_assert_not_contains "$(cat "$RETLOG" 2>/dev/null)" "2026-11-23T06-00-00-000Z_gen2.jsonl" \
  "⑦ 新代不被点名（done 命中本代窗口）"

# ================================================================ ⑧ 跨仓 done 不得升级本仓记录（返修 D1）
#   本仓记录（3 天前、本仓有 spawn 无 done）+ 他仓同名 done ⇒ 仍判异常（留 + 点名）
G3="$SESS_DIR/2026-11-23T02-00-00-000Z_xrepo.jsonl"
t51_mk_record "$G3" qa4 "$LAB" "$ISO_G1" "[T702] 本仓跨仓判据"
t51_ledger "$SESS_DIR" "$ISO_G1" spawn qa4 T702 "$LAB"
t51_ledger "$OTHER_DIR" "$ISO_G2D" done qa4 T702 "$OTHER"
touch -d '3 days ago' "$G3"
run_fleet logs --purge
t4_assert_eq "0" "$T4_RC" "⑧ 跨仓 purge rc=0"
t4_assert_file "$G3" "⑧ 他仓 done 不影响本仓分级 ⇒ 本仓记录仍留（7 天）"
t4_assert_contains "$(cat "$RETLOG" 2>/dev/null)" "2026-11-23T02-00-00-000Z_xrepo.jsonl" \
  "⑧ 本仓记录被点名（不被他仓 done 升级成正常）"

run_fleet logs --purge --repo all --days 0
t4_assert_eq "0" "$T4_RC" "⑨ --repo all --days 0 rc=0"
t4_assert_absent "$OTHER_DIR/2026-11-23T05-00-00-000Z_pm.jsonl" "⑨ --repo all 才清到他仓（--days 0 全清）"

# ================================================================ ⑩ 无记录 ⇒ rc=0 + 一行提示（不是错误）
run_fleet logs qa
t4_assert_eq "0" "$T4_RC" "⑩ logs 无记录 rc=0"
t4_assert_contains "$T4_OUT_ANSI" "无记录" "⑩ 无记录给一行提示"
t4_exit
