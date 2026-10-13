#!/usr/bin/env bash
# =============================================================================
# T516 AC8 回归用例 —— close 会话名精确锚定 + 实验场安全清理入口
#
# 判据来源（唯一）：docs/prds/2026-10-13-close-anchor-safe-clean.md §三（AC1–AC6 负向覆盖）
# 依据：docs/reports/2026-10-13-T515-mechanism-bug-hunt.md（V4 正反对照直接固化）
# 被测：<root>/.agents/scripts/nao-fleet.sh（本脚本不修改机制源码）
#
# 覆盖：AC1 status 不误计派生在线 · AC2 精确常驻回收零回退 · AC3 仅派生在场 close 非 0+诊断
#       AC4 派生回收零回退 · AC5 cleanup -S / 无 -S 拒绝 / 默认 socket 防呆 / 幂等 · AC6 --help 纪律
#
# 实验纪律（T515 血训，硬约束）：全程 `env -u TMUX`；tmux 一律 `-S <显式 socket>`；
#   夹具 = sleep 桩（不派生真实 pi）；清理只经 cleanup -S；禁 pkill 宽模式。
#   勿在承载自己会话的 tmux 内直接跑本脚本（清 TMUX_PANE 令 F1 自 pane 闸门失效）；
#   kill-server 目标任何时刻只允许 $SOCK（见下方护栏，与 fleet 内 prod_sock_candidates 独立复算）。
#
# 用法：bash docs/reports/2026-10-13-T516-close-anchor-regression.sh
#   输出：PASS/FAIL 明细 + 末行汇总；FAIL>0 ⇒ exit 1；护栏触发 ⇒ exit 3
# =============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
LAB="${T516_LAB:-/tmp/t516-reg}"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
# AC5e 对偶路径＝生产默认 socket。**常量，不取 TMUX_TMPDIR**：T516 事故（2026-10-13）——
# 夹具设 TMUX_TMPDIR 令 fleet 的「默认 socket」判定漂移，AC5e 曾把真 server 当「非默认」杀掉。
DEFSOCK="/tmp/tmux-$(id -u)/default"
# ===== 硬护栏（先于一切 tmux 操作，exit 3）=====
# 夹具 SOCK 必须 ≠ 全部生产默认候选（$TMUX 句柄 + 常量 + $TMPDIR 变体），且必须落在 $LAB 下。
# 与 fleet 内 prod_sock_candidates 使用同一常量独立复算 ⇒ 任何一侧漏判另一侧仍会拦截。
GUARD=0
TMX="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${TMX%%,*}"; do
  [[ -n "$p" && "$SOCK" == "$p" ]] && GUARD=1
  :
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
if (( GUARD )); then
  echo "护栏触发：夹具 SOCK=$SOCK 与生产默认 socket 候选（$DEFSOCK 等）冲突或不在 \$LAB 下 ⇒ 拒绝运行（exit 3）" >&2
  exit 3
fi
P=0; F=0
ok()  { P=$((P+1)); printf '  PASS  %s\n' "$1"; }
bad() { F=$((F+1)); printf '  FAIL  %s\n' "$1"; }

TX() { tmux -S "$SOCK" "$@"; }
OUT=""; RC=0
run_fleet() {  # 在 lab 仓内以隔离 socket 跑 fleet；OUT=stdout+stderr，RC=退出码
  OUT="$(cd "$LAB" && env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$SOCKDIR" \
         bash .agents/scripts/nao-fleet.sh "$@" 2>&1)"; RC=$?
}
setup_lab() {
  rm -rf "$LAB"
  # 注意：tmux 对 `-S <自定义路径>` **不自动创建父目录**（默认形态 socket 的 tmux-<uid> 目录
  # 只在无 -S 的默认解析时才自建）。若只 mkdir $SOCKDIR，首个 fixture 会绑定失败（AC1 假 FAIL），
  # 目录反而要等 fleet 内部裸 tmux 调用才被创建 ⇒ 必须先建到 tmux-<uid> 这一层。
  mkdir -p "$SOCKDIR/tmux-$(id -u)" "$LAB/.agents/prompts" "$LAB/.agents/scripts"
  # tmux 3.7+ 对默认解析的 socket 目录做权限校验：必须 0700 且属主为调用者，否则
  # 「directory ... has unsafe permissions」拒绝连接 —— fleet 内部裸 tmux 靠 TMUX_TMPDIR 落到夹具，
  # 目录权限必须与 tmux 自建的默认目录（0700）一致。
  chmod 700 "$SOCKDIR/tmux-$(id -u)"
  cp "$FLEET" "$LAB/.agents/scripts/"
  cat > "$LAB/.agents/roles.yaml" <<'EOF'
roles:
  bugz:
    card: bugz.md
    aliases: [big, bugz]
EOF
  printf -- '---\nrole: bugz\nversion: 1\nupdated: 2026-10-13\n---\n# bugz\n' > "$LAB/.agents/prompts/bugz.md"
}
# 夹具会话：keeper 占首 pane id（防跨 server 与调用者 pane %0 撞号 → F1 假阳性，T515 V4 插曲）
fixture() {  # $1=exact(0/1) $2=derived(0/1)
  TX kill-server 2>/dev/null || true
  TX new-session -d -s keeper 'sleep 600' >/dev/null 2>&1
  if [[ "${1:-0}" == 1 ]]; then
    TX new-session -d -s nao-bugz 'sleep 600' >/dev/null 2>&1
    TX select-pane -t nao-bugz -T 'π - bugz - lab'
  fi
  if [[ "${2:-0}" == 1 ]]; then
    TX new-session -d -s nao-bugz-T2 'sleep 600' >/dev/null 2>&1
    TX select-pane -t nao-bugz-T2 -T 'π - bugz-T2 - lab'
  fi
}
sess_names() { TX list-sessions -F '#{session_name}' 2>/dev/null | sort | tr '\n' ' '; echo; }

setup_lab
echo "AC1 常驻缺席+仅派生在场：status 报未运行、不误计在线"
fixture 0 1
run_fleet status
if [[ "$RC" == 0 && "$OUT" == *'bugz           未运行'* && "$OUT" != *'✓ bugz'* ]]; then
  ok "AC1 status：bugz=未运行 且 无 ✓ bugz 误报（T515 V4-1a 曾误报）"
else bad "AC1 status（rc=$RC）输出：$(printf '%s' "$OUT" | grep bugz | head -2)"; fi
if TX list-sessions 2>/dev/null | grep -q nao-bugz-T2; then ok "AC1 派生会话未被 status 波及"; else bad "AC1 派生会话丢失"; fi

echo "AC2 精确常驻在场：close <别名> 照常回收（零回退；双在场只杀精确）"
fixture 1 1
run_fleet close bugz
if [[ "$RC" == 0 && "$OUT" == *'已回收 bugz'* ]]; then ok "AC2a close bugz rc=0 已回收（精确 pane）"; else bad "AC2a（rc=$RC）$OUT"; fi
if ! TX list-sessions -F '#{session_name}' 2>/dev/null | grep -qx 'nao-bugz' && TX list-sessions -F '#{session_name}' 2>/dev/null | grep -qx 'nao-bugz-T2'; then
  ok "AC2b 精确 nao-bugz 被杀、派生 nao-bugz-T2 存活（双在场不误杀）"
else bad "AC2b 会话状态：$(sess_names)"; fi

echo "AC3 常驻缺席+仅派生在场：close <常驻名> 非 0 + 诊断，派生存活（禁静默谎报）"
fixture 0 1
run_fleet close bugz
if [[ "$RC" != 0 ]]; then ok "AC3a close bugz 非 0（rc=$RC；修复前 rc=0 谎报已回收）"; else bad "AC3a rc=0 静默谎报：$OUT"; fi
if [[ "$OUT" == *'拒绝回收'* && "$OUT" == *'bugz-T2'* ]]; then ok "AC3b 诊断指名歧义与派生名"; else bad "AC3b 诊断缺失：$OUT"; fi
if TX list-sessions 2>/dev/null | grep -q nao-bugz-T2; then ok "AC3c 派生会话存活"; else bad "AC3c 派生被误杀：$(sess_names)"; fi

echo "AC4 派生回收零回退：close <派生名> 与 close --task <编号> <别名>"
fixture 0 1
run_fleet close bugz-T2
if [[ "$RC" == 0 && "$OUT" == *'已回收 bugz-T2'* ]]; then ok "AC4a close bugz-T2 rc=0"; else bad "AC4a（rc=$RC）$OUT"; fi
if ! TX list-sessions 2>/dev/null | grep -q nao-bugz-T2; then ok "AC4b 派生会话已回收"; else bad "AC4b 派生仍在：$(sess_names)"; fi
fixture 0 1
run_fleet close --task T2 bugz
if [[ "$RC" == 0 && "$OUT" == *'已回收 bugz-T2'* ]]; then ok "AC4c close --task T2 bugz rc=0"; else bad "AC4c（rc=$RC）$OUT"; fi
if ! TX list-sessions 2>/dev/null | grep -q nao-bugz-T2; then ok "AC4d 派生会话已回收"; else bad "AC4d 派生仍在：$(sess_names)"; fi

echo "AC5 cleanup 安全清理入口：-S 终结 / 无 -S 拒绝 / 默认 socket 防呆 / 幂等"
fixture 0 1
run_fleet cleanup -S "$SOCK"
if [[ "$RC" == 0 && "$OUT" == *'已终结实验场'* ]]; then ok "AC5a cleanup -S rc=0 已终结"; else bad "AC5a（rc=$RC）$OUT"; fi
if ! TX ls 2>/dev/null | grep -q .; then ok "AC5b 夹具 server 已消失"; else bad "AC5b server 仍在：$(sess_names)"; fi
run_fleet cleanup -S "$SOCK"
if [[ "$RC" == 0 && ( "$OUT" == *'幂等清理'* || "$OUT" == *'已清除'* ) ]]; then
  ok "AC5c 二次清理幂等 rc=0（socket 不存在或残留已清除）"; else bad "AC5c（rc=$RC）$OUT"; fi
run_fleet cleanup
if [[ "$RC" == 2 && "$(printf '%s\n' "$OUT" | grep -c .)" == 1 && "$OUT" == *'拒绝'* ]]; then
  ok "AC5d 无 -S ⇒ exit 2 + 单行拒绝"
else bad "AC5d（rc=$RC / 行数 $(printf '%s\n' "$OUT" | grep -c .)）$OUT"; fi
run_fleet cleanup -S "$DEFSOCK"
if [[ "$RC" == 2 && "$OUT" == *'默认 socket'* ]]; then ok "AC5e -S 指向默认 socket ⇒ exit 2 防呆"; else bad "AC5e（rc=$RC）$OUT"; fi
if [[ ! -e "$DEFSOCK" ]] || tmux -S "$DEFSOCK" list-sessions >/dev/null 2>&1; then
  ok "AC5f 真 server（默认 socket）不受影响"
else bad "AC5f 默认 socket 被波及"; fi

echo "AC6 --help 含 cleanup 用法与实验纪律"
OUT="$(env -u TMUX bash "$FLEET" --help 2>&1)"
if [[ "$OUT" == *'cleanup -S'* && "$OUT" == *'env -u TMUX'* ]]; then
  ok "AC6 --help：cleanup -S 用法 + env -u TMUX 纪律均在"
else bad "AC6 --help 缺 cleanup/纪律文案"; fi

rm -rf "$LAB"
printf '== T516 AC8 回归汇总：PASS=%d FAIL=%d ==\n' "$P" "$F"
(( F == 0 )) || exit 1
