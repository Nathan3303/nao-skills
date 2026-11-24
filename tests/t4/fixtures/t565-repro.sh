#!/usr/bin/env bash
# T565 (#175) 先红后绿复现台 —— **手动取证用**（不进 `npm test`，也不被任何用例引用）。
#
# 用法（任何时候都能重放这次的证据）:
#   git show 1567991:.agents/scripts/nao-fleet.sh > /tmp/head-fleet.sh
#   bash tests/t4/fixtures/t565-repro.sh /tmp/head-fleet.sh     # ⇒ rc=1 + 用户实机那句报错
#   bash tests/t4/fixtures/t565-repro.sh .agents/scripts/nao-fleet.sh   # ⇒ rc=0 + 陈旧 id 不沿用
#
# 夹具形态（= app 重启后的真实状态）：
#   · 布局文档里**没有** spstale 这个 space（app 重启后 id 换了一批）
#   · 一个 live 终端仍带着旧标签 herdr.space=spstale
#   · app 也不认这个 id（stale_ids）⇒ 它自己新建 space，请求的旧 id 无处可去
# 修复前：写标签后一次读回就判死 ⇒ 「终端 tN 不在目标 tab 的 root 树里（space=spstale…）⇒ 回滚」。
# 修复后：陈旧 id 不沿用（一条 warn）+ 新建 space + 轮询等到收养 ⇒ rc=0。
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"   # fixtures → t4 → tests → 仓根
FIXT="$HERE/hc-double"
SCRIPT="${1:?用法: t565-repro.sh <nao-fleet.sh>}"
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/nao-t4.repro.XXXXXX")"
LAB="$CACHE/lab"; ST="$CACHE/appstate"; RT="$CACHE/apprt"
mkdir -p "$LAB" "$ST/t" "$ST/spaces" "$RT/herdr-core"
cp -r "$ROOT/.agents" "$LAB/.agents"
cp -- "$SCRIPT" "$LAB/.agents/scripts/nao-fleet.sh"
SOCK="$RT/herdr-core/s.sock"
node -e 'const net=require("net");const s=net.createServer();s.on("error",()=>process.exit(1));s.listen(process.argv[1])' "$SOCK" &
NODEPID=$!
for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
mkdir -p "$ST/t/t0"; printf 't0' > "$ST/t/t0/name"; printf '%s' "$RT/self" > "$ST/t/t0/cwd"
printf live > "$ST/t/t0/state"; printf pi > "$ST/t/t0/fg"
STALE_SP="spstale000000000000000000000000a"; STALE_TB="tbstale000000000000000000000000a"
HC_DOUBLE_STATE="$ST" "$FIXT/hc" run --bg --no-parent --keep --name rd-be --cwd "$LAB" \
  --label "herdr.space=$STALE_SP" --label "herdr.tab=$STALE_TB" -- true >/dev/null
rm -f "$ST/spaces/$STALE_SP"       # app 重启后该 space 已不存在（doc 里查无此 id）
printf '%s\n' "$STALE_SP" > "$ST/stale_ids"
cd "$LAB" || exit 3
env NAO_TERMINAL=app HC_SCOPE=reprosess HC_TERMINAL_ID=t0 HC_TERMINAL_SOCKET="$SOCK" \
  XDG_RUNTIME_DIR="$RT" HC_DOUBLE_STATE="$ST" PATH="$FIXT:$PATH" HOME="$LAB/home" \
  bash "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
rc=$?
echo "=== ensure rc=$rc ==="
echo "=== 终端 labels（t0 = 当前终端，跳过）==="
for a in $(find "$ST/t" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | grep -v '^t0$'); do
  printf '%s name=%s space=%s tab=%s\n' \
    "$a" "$(head -1 "$ST/t/$a/name")" "$(head -1 "$ST/t/$a/space")" "$(head -1 "$ST/t/$a/tab")"
done
kill "$NODEPID" 2>/dev/null || true
rm -rf -- "$CACHE"
exit "$rc"
