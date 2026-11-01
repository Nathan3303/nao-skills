#!/usr/bin/env bash
# =============================================================================
# T537 零回归探针（AC5③）—— 不带 --card 时 6 常驻角色的 ensure / status / close 逐字等价
#
# 用法
#   bash docs/reports/2026-11-01-T537-probe.sh            # 跑全部三段 + D6 对照
#   bash docs/reports/2026-11-01-T537-probe.sh --keep     # 保留夹具（排查用）
#   T537_BASE=<ref> bash docs/reports/2026-11-01-T537-probe.sh   # 基线 ref（默认 main）
#
# 判据（PRD AC5③ · arch §五 D6）
#   ① status：6 角色行 + 派生会话行（含任务归档/进行态标签）**逐字相同**；
#   ② ensure：6 个角色逐个拉起，stdout/stderr **逐字相同**；
#   ③ close：6 个角色逐个回收，stdout/stderr **逐字相同**（pane id 归一化）；
#   ④ 唯一例外 D6：任务号含 `-`（M20261014-pi-ext-update）时，旧版 `${dname%-*}` 会把角色名截错，
#      新版 `${dname%-"$id"}` 修好 —— 探针**打印「旧 → 新」对照**，并断言该差异**只**出现在该行。
#
# 纪律：只读仓库（基线脚本 `git show` 出到临时目录）；两套夹具（旧/新）**同名同构**（basename 均为 lab，
#   路径在比对前归一化）；隔离 tmux socket + `env -u TMUX -u TMUX_PANE` + 桩 `pi`（不拉真会话）+
#   假名册探针（cwd 由用例注入 ⇒ 归属判定同源）；零网络、零真会话接触、零状态写入。
#   退出码：0 = 全部等价（含 D6 唯一差异）；1 = 有非预期差异；77 = 环境缺 tmux（跳过）。
# =============================================================================
set -uo pipefail

REPO="${T537_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BASE_REF="${T537_BASE:-main}"
NEW_SCRIPT="$REPO/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
KEEP="${T537_KEEP:-0}"
[[ "${1:-}" == "--keep" ]] && KEEP=1

FAIL=0
ok()   { printf '  ✓ %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$*"; }
info() { printf '  · %s\n' "$*"; }

command -v tmux >/dev/null 2>&1 || { printf 'SKIP: 环境缺 tmux（零回归探针需隔离 tmux）\n'; exit 77; }
command -v git  >/dev/null 2>&1 || { printf 'SKIP: 环境缺 git\n'; exit 77; }

WORK="$(mktemp -d /tmp/t537probe.XXXXXX)" || { printf 'FAIL: mktemp 失败\n'; exit 1; }
if [ -n "$(git -C "$WORK" rev-parse --show-toplevel 2>/dev/null || true)" ]; then
  printf 'FAIL: 夹具根落在 git 仓内（%s）⇒ 锚根判定会被污染\n' "$WORK"; exit 1
fi
git -C "$REPO" show "$BASE_REF:.agents/scripts/nao-fleet.sh" > "$WORK/nao-fleet-old.sh" 2>/dev/null \
  || { printf 'FAIL: 取基线脚本失败（git show %s:.agents/scripts/nao-fleet.sh）\n' "$BASE_REF"; exit 1; }
info "基线 = $BASE_REF（$(git -C "$REPO" rev-parse --short "$BASE_REF" 2>/dev/null || echo '?')）· 新版 = 工作区"
info "夹具 = $WORK"

pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
tsx_ok=0
if [ -f "$pi_agent_dir/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then tsx_ok=1; fi

# ---------------------------------------------------------------- 夹具构造
mk_lab() { # <variant: old|new> → echo lab 路径（结构完全同构，basename 均为 lab）
  local v="$1" root="$WORK/$1" lab="$WORK/$1/lab" sockdir="$WORK/$1/lab/sock"
  mkdir -p "$root" "$lab" "$sockdir/tmux-$(id -u)" "$lab/bin"
  chmod 700 "$sockdir/tmux-$(id -u)"
  cp -r "$REPO/.agents" "$lab/.agents" || return 1
  if [ "$v" = "old" ]; then cp "$WORK/nao-fleet-old.sh" "$lab/.agents/scripts/nao-fleet.sh"
  else cp "$NEW_SCRIPT" "$lab/.agents/scripts/nao-fleet.sh"; fi
  cat > "$lab/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
  cat > "$lab/bin/pi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
exec sleep 900
SH
  chmod +x "$lab/bin/pi"
  cat > "$lab/tasks.md" <<'MD'
# T537 探针 tasks-state 夹具（只读）

## 进行态

| 任务 | 状态 |
| :-- | :-- |
| T9002 | 进行中 |

## 已归档

| 任务 | 状态 |
| :-- | :-- |
| T9001 | v1 |
| M20261014-pi-ext-update | v0.20.4 |
MD
  printf '%s' "$lab"
}

OLD_LAB="$(mk_lab old)" || { printf 'FAIL: 旧版夹具构造失败\n'; exit 1; }
NEW_LAB="$(mk_lab new)" || { printf 'FAIL: 新版夹具构造失败\n'; exit 1; }
OLD_SOCK="$OLD_LAB/sock/tmux-$(id -u)/default"
NEW_SOCK="$NEW_LAB/sock/tmux-$(id -u)/default"
OLD_TMUX="$OLD_SOCK,0,0"
NEW_TMUX="$NEW_SOCK,0,0"

tmux -S "$OLD_SOCK" new-session -d -s lab -x 240 -y 60 -c "$OLD_LAB" >/dev/null 2>&1
tmux -S "$NEW_SOCK" new-session -d -s lab -x 240 -y 60 -c "$NEW_LAB" >/dev/null 2>&1
sleep 0.4
tmux -S "$OLD_SOCK" setenv -g PATH "$OLD_LAB/bin:$PATH" >/dev/null 2>&1
tmux -S "$NEW_SOCK" setenv -g PATH "$NEW_LAB/bin:$PATH" >/dev/null 2>&1
OLD_CALLER="$(tmux -S "$OLD_SOCK" list-panes -t lab -F '#{pane_id}' | head -1)"
NEW_CALLER="$(tmux -S "$NEW_SOCK" list-panes -t lab -F '#{pane_id}' | head -1)"

teardown() {
  ( env -u TMUX "$BASH_BIN" "$OLD_LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$OLD_SOCK" >/dev/null 2>&1 ) || true
  ( env -u TMUX "$BASH_BIN" "$NEW_LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$NEW_SOCK" >/dev/null 2>&1 ) || true
  [ "$KEEP" = "1" ] || rm -rf "$WORK"
}
trap teardown EXIT

# ---------------------------------------------------------------- 调用 / 归一化
ROSTER_OLD='[]'; ROSTER_NEW='[]'
mk_roster() { # <repo> <name>... → JSON（cwd=<repo>，status=idle；保持给定顺序）
  local repo="$1" s="[" e; shift
  for e in "$@"; do s="$s{\"name\":\"$e\",\"cwd\":\"$repo\",\"status\":\"idle\"},"; done
  printf '%s' "${s%,}]"
}
run_old() { # <args...> → OUT / ERR / RC
  local of ef; of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$OLD_LAB" && env -u TMUX -u TMUX_PANE TMUX="$OLD_TMUX" TMUX_PANE="$OLD_CALLER" \
      TMUX_TMPDIR="$OLD_LAB/sock" NAO_SKILLS="$OLD_LAB" PI_CODING_AGENT_DIR="$pi_agent_dir" \
      NAO_QA_FAKE_ROSTER="$ROSTER_OLD" NAO_TASKS_STATE="$OLD_LAB/tasks.md" PATH="$OLD_LAB/bin:$PATH" \
      timeout 90 bash "$OLD_LAB/.agents/scripts/nao-fleet.sh" "$@" ) >"$of" 2>"$ef"
  RC=$?; OUT="$(cat "$of")"; ERR="$(cat "$ef")"; rm -f "$of" "$ef"
}
run_new() {
  local of ef; of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$NEW_LAB" && env -u TMUX -u TMUX_PANE TMUX="$NEW_TMUX" TMUX_PANE="$NEW_CALLER" \
      TMUX_TMPDIR="$NEW_LAB/sock" NAO_SKILLS="$NEW_LAB" PI_CODING_AGENT_DIR="$pi_agent_dir" \
      NAO_QA_FAKE_ROSTER="$ROSTER_NEW" NAO_TASKS_STATE="$NEW_LAB/tasks.md" PATH="$NEW_LAB/bin:$PATH" \
      timeout 90 bash "$NEW_LAB/.agents/scripts/nao-fleet.sh" "$@" ) >"$of" 2>"$ef"
  RC=$?; OUT="$(cat "$of")"; ERR="$(cat "$ef")"; rm -f "$of" "$ef"
}
norm() { # <lab> → 去锚点差异：lab 绝对路径、pane id、ANSI 色码
  local lab="$1"
  sed -e "s#$lab#<LAB>#g" \
      -e 's/tmux pane %[0-9]\+/tmux pane %N/g' \
      -e 's/%[0-9]\+/<PANE>/g' \
      -e 's/\x1b\[[0-9;]*m//g'
}
set_title() { # <variant> <pane_id> <session-name>
  local sock="$1" pane="$2" name="$3"
  tmux -S "$sock" select-pane -t "$pane" -T "π - $name - lab" >/dev/null 2>&1 || true
}

ROLES=(pm arch-designer rd-fe rd-be qa rd-infra)
export tsx_ok

# ============================================================ ① status（6 角色 + 派生 + 任务标签）
printf '\n== ① status：6 角色行 + 派生会话行逐字等价 ==\n'
if [ "$tsx_ok" = "1" ]; then
  DERIVED=(rd-be-T9001 qa-T9002 rd-infra-M20261014-pi-ext-update)
  ROSTER_OLD="$(mk_roster "$OLD_LAB" "${ROLES[@]}" "${DERIVED[@]}")"
  ROSTER_NEW="$(mk_roster "$NEW_LAB" "${ROLES[@]}" "${DERIVED[@]}")"
else
  info "缺 tsx ⇒ 名册 cwd 不可镜像，归属一律「不可判定」（两版同源，仍可逐字比对）"
fi
# 6 角色 pane（标题契约；旧/新同构）
for r in "${ROLES[@]}"; do
  tmux -S "$OLD_SOCK" new-session -d -s "fx-$r" -x 200 -y 50 -c "$OLD_LAB" >/dev/null 2>&1
  tmux -S "$NEW_SOCK" new-session -d -s "fx-$r" -x 200 -y 50 -c "$NEW_LAB" >/dev/null 2>&1
done
sleep 0.5
for r in "${ROLES[@]}"; do
  set_title "$OLD_SOCK" "$(tmux -S "$OLD_SOCK" list-panes -t "fx-$r" -F '#{pane_id}' | head -1)" "$r"
  set_title "$NEW_SOCK" "$(tmux -S "$NEW_SOCK" list-panes -t "fx-$r" -F '#{pane_id}' | head -1)" "$r"
done
run_old status; O="${OUT}"; run_new status; N="${OUT}"
O_N="$(printf '%s\n' "$O" | norm "$OLD_LAB")"
N_N="$(printf '%s\n' "$N" | norm "$NEW_LAB")"
# 除 D6 例外行外必须逐字等价（D6 行在下一节单独对照）
D6_EXCLUDED_O="$(printf '%s\n' "$O_N" | grep -vF 'M20261014-pi-ext-update')"
D6_EXCLUDED_N="$(printf '%s\n' "$N_N" | grep -vF 'M20261014-pi-ext-update')"
if [ "$D6_EXCLUDED_O" = "$D6_EXCLUDED_N" ]; then
  ok "status 输出逐字等价（$(printf '%s\n' "$D6_EXCLUDED_O" | grep -c .) 行：6 角色行 + 派生行 + 任务标签）"
else
  bad "status 输出有非 D6 差异"
  diff <(printf '%s\n' "$D6_EXCLUDED_O") <(printf '%s\n' "$D6_EXCLUDED_N") | sed 's/^/      /'
fi
if [ "$O_N" = "$N_N" ]; then
  ok "status 全量逐字相同（含任务号含 '-' 的行）"
fi

# ------- D6 例外：任务号含 '-' 时旧版截错角色名（唯一允许的差异）
printf '\n== ④ D6 对照：任务号含 - 时 status 命令构造（旧 → 新）==\n'
D6_OLD="$(printf '%s\n' "$O_N" | grep -F 'M20261014-pi-ext-update' | head -1)"
D6_NEW="$(printf '%s\n' "$N_N" | grep -F 'M20261014-pi-ext-update' | head -1)"
if [ -z "$D6_OLD" ] || [ -z "$D6_NEW" ]; then
  bad "D6 行未出现（旧=「$D6_OLD」新=「$D6_NEW」）；名册/标题夹具可能未生效"
else
  printf '  旧: %s\n' "$D6_OLD"
  printf '  新: %s\n' "$D6_NEW"
  if printf '%s' "$D6_OLD" | grep -qF 'close --task M20261014-pi-ext-update rd-infra-M20261014'; then
    ok "旧版确有缺陷：命令把角色名截成 rd-infra-M20261014"
  else
    bad "旧版未复现截错（夹具或基线 ref 不符预期）"
  fi
  if printf '%s' "$D6_NEW" | grep -qF 'close --task M20261014-pi-ext-update rd-infra'; then
    ok "新版修好：命令给出正确角色名 rd-infra（AC5③ 唯一例外）"
  else
    bad "新版未给出正确角色名 rd-infra"
  fi
fi
if [ "$D6_EXCLUDED_O" = "$D6_EXCLUDED_N" ]; then
  ok "差异仅此一处（剔除 D6 行后与基线逐字等价）"
else
  bad "除 D6 行外仍有差异（见 ① 节 diff）"
fi

# ============================================================ ② ensure（6 角色逐个）
printf '\n== ② ensure：6 角色逐个拉起，输出逐字等价 ==\n'
ROSTER_OLD='[]'; ROSTER_NEW='[]'   # 清空名册：让 ②③ 只走 pane 路径（避免派生条目触发目标歧义分支）
for r in "${ROLES[@]}"; do
  run_old ensure "$r"; O="$OUT$ERR"
  run_new ensure "$r"; N="$OUT$ERR"
  O_N="$(printf '%s\n' "$O" | norm "$OLD_LAB")"
  N_N="$(printf '%s\n' "$N" | norm "$NEW_LAB")"
  if [ "$O_N" = "$N_N" ]; then ok "ensure $r 逐字等价"; else
    bad "ensure $r 有差异"; diff <(printf '%s\n' "$O_N") <(printf '%s\n' "$N_N") | sed 's/^/      /'
  fi
  sleep 0.3
done
# 给每个角色 pane 打上标题契约（ensure 起的是桩 pi，不设标题）
for r in "${ROLES[@]}"; do
  for pair in "OLD_SOCK:$OLD_LAB" "NEW_SOCK:$NEW_LAB"; do
    sock_var="${pair%%:*}"; lab="${pair#*:}"; sock="${!sock_var}"
    while IFS=$'\t' read -r p t; do
      [[ "$t" == "π - $r - lab" ]] && continue
      cwd="$(tmux -S "$sock" display-message -p -t "$p" '#{pane_current_path}' 2>/dev/null || true)"
      caller="$OLD_CALLER"; [ "$sock" = "$NEW_SOCK" ] && caller="$NEW_CALLER"
      # 跳过调用者 pane 与已打标的 fixture pane（fx-*）：close 目标必须唯一且非调用者自身
      [ "$p" = "$caller" ] && continue
      [ "$cwd" = "$lab" ] && set_title "$sock" "$p" "$r"
    done < <(tmux -S "$sock" list-panes -a -F '#{pane_id}'$'\t''#{pane_title}' 2>/dev/null || true)
  done
done

# ============================================================ ③ close（6 角色逐个）
printf '\n== ③ close：6 角色逐个回收，输出逐字等价 ==\n'
for r in "${ROLES[@]}"; do
  run_old close "$r"; O="$OUT$ERR"
  run_new close "$r"; N="$OUT$ERR"
  O_N="$(printf '%s\n' "$O" | norm "$OLD_LAB")"
  N_N="$(printf '%s\n' "$N" | norm "$NEW_LAB")"
  if [ "$O_N" = "$N_N" ]; then
    ok "close $r 逐字等价（rc 旧=$RC 新=$RC）"
  else
    bad "close $r 有差异 旧(rc=$RC) 新(rc=$RC)"
    diff <(printf '%s\n' "$O_N") <(printf '%s\n' "$N_N") | sed 's/^/      /'
  fi
done

# ============================================================ 汇总
printf '\n==================== T537 零回归探针 ====================\n'
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAIL（%d 处非预期差异）\n' "$FAIL"
  exit 1
fi
printf 'RESULT: PASS（6 角色 ensure/status/close 逐字等价；差异仅 D6 任务号含 - 的 status 命令构造）\n'
exit 0
