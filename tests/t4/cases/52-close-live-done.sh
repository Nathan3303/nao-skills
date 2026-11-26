#!/usr/bin/env bash
# 用例 52 —— close 假成功：会话已结束但终端保活（T574 · Issue #207）
#
# 现象（真机 app 后端）：`close qa` 打印「未发现 app 终端：qa（已不在运行；幂等成功）」，
#   而 `hc ls --all` 里 `qa` 仍是 `live` + `status=done` ⇒ 终端残留占名 ⇒ 下次 ensure 撞 name_taken。
# 根因：真 hc 的 `get` 键序按字母 ⇒ `foreground.name`（= "pi"）先于**顶层** `name`；
#   老抽取「取首个同名键」恒得 "pi" ⇒ 按名定位恒空 ⇒ 回收路径从未被执行（effect 从未发生）。
#
# 判据（机械可判）：
#   ① 单位面（先红后绿）：真 hc 键序的 JSON 上，老抽取必须得 "pi"（必空）、新抽取必须得会话名
#   ② 修前必红：把模块副本回退成老抽取 ⇒ 同一 live+done 夹具上 close 报「未发现 app 终端」且终端仍在
#   ③ 修后真回收：close 后地址从 `hc ls --all` 消失（**effect** 判据，不看 rc 与文案）
#   ④ 不撞 name_taken：回收后 `ensure` 同角色成功，且同名终端恰 1 个（旧地址不在）
#   ⑤ 既有语义不变：live+working 无 --force ⇒ 拒（终端保留）· --force ⇒ 回收 · live+idle ⇒ 直接回收
#   ⑥ 文档：`docs/INSTALL.md` 记了 `--keep` 的 live+done 边界
#   ⑦ 守卫（返修 D8）：effect 复核时 `ls` 读不到 ⇒ **fail loud 保留终端**（不把「读不到」当「已消失」）
#
# 夹具：`tests/t4/fixtures/hc-double`（确定性替身）+ 私有 XDG 根；绝不碰用户真实桌面版 core。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FIXT="$T4_ROOT/tests/t4/fixtures/hc-double"
APP_MOD="$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_app_exec)"
[ -x "$FIXT/hc" ] || { t4_bad "夹具缺失可执行: $FIXT/hc"; t4_exit; }
[ -f "$APP_MOD" ] || { t4_bad "app 模块不可定位（t4_fleet_file_for）"; t4_exit; }
PATH="$FIXT:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab52-$$"
mkdir -p "$LAB" || { t4_bad "无法建 lab"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
be_app_init "$LAB" "lab52-$$" || { t4_bad "be_app_init 失败"; t4_exit; }
be_app_arm_cleanup

APP_RC=0; APP_OUT=""; APP_ERR=""
run_app() {
  local -a envs=(NAO_TERMINAL=app "HC_SCOPE=$BE_SESSION" HC_TERMINAL_ID=t0
    "HC_TERMINAL_SOCKET=$BE_APP_SOCK" "XDG_RUNTIME_DIR=$BE_APP_RT"
    "HC_DOUBLE_STATE=$BE_APP_STATE" "PATH=$FIXT:$PATH"
    "HOME=$LAB/.t4-home" "PI_CODING_AGENT_DIR=$LAB/.t4-home/.pi/agent")
  local script="${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}"
  t4_run_in_dir "$LAB" env "${envs[@]}" timeout "${BE_FLEET_TIMEOUT:-120}" bash "$script" "$@"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
stub_hc() { HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT/hc" "$@"; }
ls_all() { stub_hc ls --all --json 2>/dev/null; }
addrs_named() { # <name> → 命中该名字的地址（走替身 ls，不看 close 的输出）
  local n="$1" a
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    [ "$(head -1 "$BE_APP_STATE/t/$a/name" 2>/dev/null)" = "$n" ] && printf '%s\n' "$a"
  done < <(ls_all | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
}
mk_term() { # <addr> <name> <state> <status.state|-> [cwd]
  local a="$1" d="$BE_APP_STATE/t/$1"
  mkdir -p "$d"
  printf '%s' "$2" > "$d/name"
  printf '%s' "$3" > "$d/state"
  printf '%s' "${5:-$LAB}" > "$d/cwd"
  printf 'pi' > "$d/fg"
  printf '1' > "$d/reported"
  if [ "$4" != "-" ]; then printf 'pi' > "$d/app"; printf '%s' "$4" > "$d/stt"; fi
}
app_reset() {
  find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d ! -name t0 -exec rm -rf {} + 2>/dev/null || true
  : > "$BE_APP_STATE/log"
  printf 'real' > "$BE_APP_STATE/get_order"   # 真 hc 键序（foreground 在顶层 name 之前）
}
printf 'real' > "$BE_APP_STATE/get_order"

# 真 hc（0.1.22 实测）的 `get` 键序：foreground 在顶层 name **之前**（这就是缺陷的触发条件）
REAL_SHAPE='{"address":"t1g","argv":["bash"],"cols":94,"cwd":"/x","foreground":{"argv":["pi","--name","qa"],"name":"pi","pid":7},"identity":"ghostty","labels":{"nao.name":"qa","where":"a / 1"},"name":"qa","state":"live","status":{"app":"pi","msg":"qa","state":"done"}}'

# ================================================================ ① 单位面：老抽取必空 / 新抽取正确
FIELD_FN="$(sed -n '/^_term_app_field()/,/^}/p' "$APP_MOD")"
NAME_FN="$(sed -n '/^_term_app_name()/,/^}/p' "$APP_MOD")"
t4_assert_ne "" "$NAME_FN" "① 模块内存在 _term_app_name（删掉 ⇒ 本组必红）"
OLD_NAME="$(bash -c "source /dev/stdin <<'EOS'
$FIELD_FN
EOS
_term_app_field \"\$1\" name" _ "$REAL_SHAPE" 2>/dev/null)"
NEW_NAME="$(bash -c "source /dev/stdin <<'EOS'
$FIELD_FN
$NAME_FN
EOS
_term_app_name \"\$1\"" _ "$REAL_SHAPE" 2>/dev/null)"
t4_assert_eq "pi" "$OLD_NAME" "① 老抽取（首个同名键）在真 hc 键序上得 foreground.name=pi ⇒ 按名定位必空（先红）"
t4_assert_eq "qa" "$NEW_NAME" "① 新抽取（剔 foreground/labels 后取顶层 name）= qa（后绿）"

# ================================================================ ② 修前必红：回退抽取的副本上 close 假成功
MUT="$LAB/mut"; mkdir -p "$MUT"
cp -r "$LAB/.agents" "$MUT/.agents"
python3 - "$MUT/.agents/scripts/fleet/lib/term-app.sh" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
old='[[ "$(_term_app_name "$g")" == "$name" ]]'
assert old in s, "变异点未找到"
open(p,'w',encoding='utf-8').write(s.replace(old,'[[ "$(_term_app_field "$g" name)" == "$name" ]]',1))
PY
app_reset; mk_term t5 qa live done
OLD_ADDR="$(addrs_named qa)"
t4_assert_eq "t5" "$OLD_ADDR" "② 夹具：live+done 的 qa 终端在位（t5）"
BE_FLEET_SCRIPT="$MUT/.agents/scripts/nao-fleet.sh" run_app close qa
BE_FLEET_SCRIPT=""
t4_assert_contains "$APP_OUT$APP_ERR" "未发现 app 终端" "② 老实现 ⇒ 报「未发现 app 终端」（假成功的原文）"
t4_assert_eq "t5" "$(addrs_named qa)" "② 老实现 ⇒ 终端仍在（残留：本用例的核心红证据）"

# ================================================================ ③ 修后：live+done 必须真回收（effect 判据）
app_reset; mk_term t5 qa live done
APP_RC=""; run_app close qa
t4_assert_eq "0" "$APP_RC" "③ close qa（live+done）rc=0"
t4_assert_contains "$APP_OUT$APP_ERR" "会话已结束" "③ 点名「会话已结束、终端保活」形态（不再是「未运行」）"
t4_assert_not_contains "$(ls_all)" '"address":"t5"' "③ effect：t5 已从 hc ls --all 消失"
t4_assert_eq "" "$(addrs_named qa)" "③ effect：已无名为 qa 的终端"
t4_assert_contains "$(cat "$BE_APP_STATE/log" 2>/dev/null)" "kill t5" "③ 回收走 kill"

# ================================================================ ④ 不撞 name_taken：回收后 ensure 同角色成功
run_app ensure qa
t4_assert_eq "0" "$APP_RC" "④ 回收后 ensure qa 成功（不撞 name_taken）"
t4_assert_eq "1" "$(addrs_named qa | grep -c . || true)" "④ hc ls 里名为 qa 的终端恰 1 个（旧地址未残留）"
t4_assert_ne "t5" "$(addrs_named qa)" "④ 新终端用了新地址（旧的已回收，不是同一个）"

# ================================================================ ⑤ 既有语义不变（working 仍拒 / --force 放行 / idle 直接收）
app_reset; mk_term t6 qa live working
run_app close qa
t4_assert_ne "0" "$APP_RC" "⑤ live+working 无 --force ⇒ 拒（rc≠0）"
t4_assert_eq "t6" "$(addrs_named qa)" "⑤ 拒回收时终端保留（不静默成功）"
run_app close qa --force
t4_assert_eq "0" "$APP_RC" "⑤ --force ⇒ 放行"
t4_assert_eq "" "$(addrs_named qa)" "⑤ --force 后终端已回收"

app_reset; mk_term t7 qa live idle
run_app close qa
t4_assert_eq "0" "$APP_RC" "⑤ live+idle ⇒ 直接回收（既有语义不变）"
t4_assert_eq "" "$(addrs_named qa)" "⑤ idle 终端已回收"

# ================================================================ ⑥ 文档：`--keep` 的 live+done 边界已记
t4_assert_contains "$(cat "$T4_ROOT/docs/INSTALL.md" 2>/dev/null)" "live" "⑥ INSTALL.md 记了 live 形态"
t4_assert_contains "$(cat "$T4_ROOT/docs/INSTALL.md" 2>/dev/null)" "keep" "⑥ INSTALL.md 记了 --keep 保活边界"

# ================================================================ ⑦ D8：effect 复核读不到 ⇒ fail loud（不是「已消失」）
#   注入点 = 替身 `kill` 之后让 `ls` 返 error payload + rc=1（找终端那次 ls 在 kill 前，不受影响）
app_reset; mk_term t8 qa live done
: > "$BE_APP_STATE/ls_fail_after_kill"
APP_RC=""; run_app close qa
rm -f "$BE_APP_STATE/ls_fail_after_kill" "$BE_APP_STATE/ls_fail_now"   # 立刻撤注入，后续断言读得到真相
t4_assert_ne "0" "$APP_RC" "⑦ hc ls 读不到 ⇒ close 不判成功（rc≠0）"
t4_assert_contains "$APP_OUT$APP_ERR" "不可判定" "⑦ fail loud：点名「回收结果不可判定」（不当已消失）"
t4_assert_not_contains "$APP_OUT" "已回收 app 终端" "⑦ 不打印成功行（不假成功）"
t4_assert_eq "" "$(addrs_named qa)" "⑦ 终端实际已被 rm（kill→rm 已成），但仍**不据此宣称成功**：判据 = ls 读得到"

# 正控：同夹具不注入 ⇒ 正常回收（证明⑦的红不是夹具自身坏）
app_reset; mk_term t8 qa live done
APP_RC=""; run_app close qa
t4_assert_eq "0" "$APP_RC" "⑦ 正控：不注入时同一夹具正常回收 rc=0"
t4_assert_eq "" "$(addrs_named qa)" "⑦ 正控：终端已回收（七的红确因注入）"

t4_exit
