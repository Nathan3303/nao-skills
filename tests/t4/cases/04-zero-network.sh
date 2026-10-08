#!/usr/bin/env bash
# 用例 04 —— 零网络可执行断言（PRD NFR2 / §12 闸门B）
#
# 4a 网络命名空间隔离下 `check` exit=0（bwrap --unshare-net）
# 4b strace 追踪 connect(2)：无 AF_INET/AF_INET6（nao 机制零网络调用）
# 4c 闸门B 反向：删 .pi/npm 后 exit 2 + DEGRADED:（同用例 03，此处绑定零网语境）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
t4_require_cli init

fx="$(t4_fixture)"
t4_materialize "$fx"
t4_run_init "$fx" >/dev/null 2>&1
t4_require_shim "$fx"

# --- 4a bwrap 网络隔离 ------------------------------------------------------
if t4_bwrap_available; then
  of="$(mktemp)"; ef="$(mktemp)"
  bwrap --unshare-net --ro-bind / / --dev-bind /dev /dev --proc /proc --bind /tmp /tmp \
        --chdir "$fx" /bin/bash -c 'bash .agents/scripts/nao-fleet.sh check' >"$of" 2>"$ef"
  rc=$?
  out="$(cat "$of")"; err="$(cat "$ef")"; rm -f "$of" "$ef"
  t4_info "4a rc=$rc out=$(printf '%s' "$out" | head -1)"
  t4_assert_eq "0" "$rc" "4a 无网（unshare-net）下 check exit=0"
  t4_assert_contains "$out" "check: OK" "4a 无网下 check 输出 OK"
else
  t4_note "bwrap 不可用，4a 降级为代理黑洞环境（弱证据，4b 仍为强证据）"
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$fx" && env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
        ALL_PROXY=http://127.0.0.1:9 npm_config_offline=true PI_OFFLINE=1 \
        bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
  rc=$?; out="$(cat "$of")"; rm -f "$of" "$ef"
  t4_assert_eq "0" "$rc" "4a(降级) 代理黑洞下 check exit=0"
  t4_assert_contains "$out" "check: OK" "4a(降级) check 输出 OK"
fi

# --- 4b strace：无 AF_INET 连接 --------------------------------------------
if t4_strace_available; then
  st="$T4_CACHE_DIR/strace-net.txt"
  ( cd "$fx" && strace -f -e trace=connect -o "$st" bash .agents/scripts/nao-fleet.sh check ) >/dev/null 2>&1
  inet="$(grep -E 'connect\(.*(AF_INET|AF_INET6)' "$st" 2>/dev/null | grep -v EINPROGRESS || true)"
  t4_info "4b connect 总数=$(grep -c 'connect(' "$st" 2>/dev/null || echo 0) · AF_INET 命中=$(printf '%s\n' "$inet" | grep -c . || true)"
  t4_assert_eq "" "$inet" "4b 全程无 AF_INET/AF_INET6 connect（nao 零网络）"
else
  t4_note "strace 不可用，4b 跳过（保留 4a 环境隔离证据）"
fi

# --- 4c 闸门B 反向：未物化 ⇒ exit 2 + DEGRADED ------------------------------
empty_home="$(mktemp -d "$T4_CACHE_DIR/home.XXXXXX")"
rm -rf "$fx/.pi/npm/node_modules"
of="$(mktemp)"; ef="$(mktemp)"
( cd "$fx" && env -u NAO_SKILLS -u NAO_SHIM_ENTERED "HOME=$empty_home" \
      timeout 60 bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
rc=$?; out="$(cat "$of")"; err="$(cat "$ef")"; rm -f "$of" "$ef"
joined="$(printf '%s\n%s\n' "$out" "$err")"
t4_info "4c rc=$rc"
t4_assert_eq "2" "$rc" "4c 未物化 exit=2"
t4_assert_eq "1" "$(printf '%s\n' "$joined" | grep -cE '^DEGRADED:')" "4c 单行 DEGRADED:"

t4_exit
