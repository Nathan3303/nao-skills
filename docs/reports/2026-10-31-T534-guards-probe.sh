#!/usr/bin/env bash
# 一次性只读探针 —— T534「舰队闸门小批：跨仓残留误报 + 合并前 push 核对 + 探针识别放宽」
#   覆盖：A 项（`status` 残留判定加仓维度：AC1 / AC2 / AC7）
#         B 项（合并前 push 核对文本：AC3）· C 项（旧探针识别放宽的自证：AC4）
#         文档单源与 ADR（AC6）
# 用法: bash docs/reports/2026-10-31-T534-guards-probe.sh
# 输出: 每行 `PASS <id> ...` / `FAIL <id> ...` / `SKIP <id> ...`；末行汇总；rc=0 ⇔ FAIL=0
# 纪律: 真仓库**零写入**（仅 git show / git diff / grep）；夹具全部在 mktemp -d（**不得落在任何 git 仓内**，
#       否则 `rev-parse --show-toplevel` 锚会把「他仓」夹具拉进本仓 ⇒ AC7 断言失真）；
#       tmux 一律**隔离 socket**（禁裸 tmux，不碰生产 server）；输出不含时间戳/临时路径 ⇒ 连跑两次逐字一致。
#       ⚠️ 本探针**不进 tests/**（本批不动常态用例，见 T534-O1）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PASS_N=0; FAIL_N=0; SKIP_N=0

ok()   { PASS_N=$((PASS_N + 1)); printf 'PASS %s\n' "$*"; }
bad()  { FAIL_N=$((FAIL_N + 1)); printf 'FAIL %s\n' "$*"; }
skip() { SKIP_N=$((SKIP_N + 1)); printf 'SKIP %s\n' "$*"; }
have() { printf '%s' "$1" | grep -qF -- "$2"; }

# need_all <id> <file> <kw...> —— 关键词全在位才 PASS（漏一即 FAIL，逐个列出缺失项）
need_all() {
  local id="$1" file="$2" kw miss=""
  shift 2
  [[ -f "$file" ]] || { bad "$id（文件缺失）"; return; }
  for kw in "$@"; do grep -qF -- "$kw" "$file" || miss="$miss [$kw]"; done
  if [[ -z "$miss" ]]; then ok "$id"; else bad "$id 缺失:$miss"; fi
}

# need_region <id> <file> <起行正则> <止行正则(空=文末)> <kw...> —— 只在指定小节正文里找
need_region() {
  local id="$1" file="$2" start="$3" stop="$4" kw body miss=""
  shift 4
  [[ -f "$file" ]] || { bad "$id（文件缺失）"; return; }
  body="$(awk -v s="$start" -v e="$stop" '
    on && e != "" && $0 ~ e { exit }
    on { print }
    $0 ~ s { on = 1 }
  ' "$file")"
  [[ -n "$body" ]] || { bad "$id（小节未命中）"; return; }
  for kw in "$@"; do have "$body" "$kw" || miss="$miss [$kw]"; done
  if [[ -z "$miss" ]]; then ok "$id"; else bad "$id 缺失:$miss"; fi
}

FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
PMC="$ROOT/.agents/checklists/pm.md"
PM="$ROOT/.agents/prompts/product-manager.md"
PMO="$ROOT/.agents/skills/pm-operations.md"
ADR="$ROOT/docs/adr/2026-10-31-fleet-status-repo-attribution.md"
REV="$ROOT/docs/reports/2026-10-31-T534-arch-review.md"
OLD_PROBE="$ROOT/docs/reports/2026-10-28-docs-ride-pr-probe.sh"
RETRO="docs/reports/2026-10-30-T533-retro.md"

# ── 真仓库快照（RO 判据：前后必须逐字一致）────────────────────────────
RO_STATUS_BEFORE="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
RO_HEAD_BEFORE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"

# ============================================================ AC3（B 项 · 合并前 push 核对）
need_region AC3-1-清单合并项 "$PMC" '^## 交付检查清单' '' \
  'git rev-list --count origin/<branch>..HEAD' 'git status --porcelain' 'HEAD == @{u}' \
  '在分支上提交过的**任何角色**' "$RETRO"
need_region AC3-2-卡六指针 "$PM" '^## 六、' '^## 七、' \
  '合并前 push 核对' '@.agents/checklists/pm.md'
# BR5 单源：三条命令只在清单出现，卡内不复写
if have "$(awk '/^## 六、/{on=1} /^## 七、/{on=0} on' "$PM")" 'rev-list --count'; then
  bad "AC3-3-单源（PM 卡 §六 复写了命令，违反 BR5 单源）"
else
  ok "AC3-3-单源（PM 卡 §六 只有指针，命令仅存在于清单）"
fi
# 计数口径：清单标题与实计数、卡尾与清单一致（B 项 +1 项后 42 → 43）
ACT_RED="$(awk '/^## 硬性红线/{on=1;next} /^## /&&on{on=0} on&&/^- \[ \]/{c++} END{print c+0}' "$PMC")"
ACT_CHK="$(awk '/^## 交付检查清单/{on=1;next} /^## /&&on{on=0} on&&/^- \[ \]/{c++} END{print c+0}' "$PMC")"
need_all AC3-4-计数口径 "$PMC" "## 硬性红线（完整 34 项）" "## 交付检查清单（完整 43 项）"
if [[ "$ACT_RED" == "34" && "$ACT_CHK" == "43" ]]; then
  ok "AC3-5-实计数（红线=$ACT_RED · 清单=$ACT_CHK）"
else
  bad "AC3-5-实计数（红线=$ACT_RED · 清单=$ACT_CHK；期望 34/43）"
fi
need_all AC3-6-卡尾计数 "$PM" '完整红线（34 项）' '交付检查清单（43 项）'
need_all AC3-7-卡片版本 "$PM" 'version: 30' 'updated: 2026-10-31'

# ============================================================ AC6（文档单源 · ADR · 零改动）
if [[ -f "$ADR" ]]; then
  ADR_LINES="$(wc -l < "$ADR" | tr -d ' ')"
  need_all AC6-1-ADR五节 "$ADR" '## 背景' '## 决策' '## 理由' '## 对照过的备选模式' '## 后果与风险'
  need_all AC6-2-ADR决策要点 "$ADR" 'pane' '名册' 'fail-closed' '组件级' '不可判定'
  if (( ADR_LINES <= 60 )); then ok "AC6-3-ADR行数（${ADR_LINES} ≤ 60）"; else bad "AC6-3-ADR行数（${ADR_LINES} > 60）"; fi
else
  bad "AC6-1-ADR五节（ADR 缺失）"
fi
if [[ -f "$REV" ]]; then ok "AC6-4-评审报告入库"; else bad "AC6-4-评审报告入库（缺失）"; fi
need_all AC6-5-残留自检半句 "$PMO" '他仓会话单列、勿在本仓回收'
# 单源：该半句全仓只在 pm-operations.md 出现（checklists/pm.md 只给指针）
DUPS="$(grep -rlc -- '他仓会话单列、勿在本仓回收' "$PMO" "$PMC" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$DUPS" == "1" ]] && grep -qF -- '他仓会话单列、勿在本仓回收' "$PMO"; then
  ok "AC6-6-单源（半句仅存于 pm-operations.md）"
else
  bad "AC6-6-单源（命中 $DUPS 处，期望 1）"
fi
if grep -qF -- 'pm-operations.md「残留自检」' "$PMC"; then
  ok "AC6-7-清单只给指针"
else
  bad "AC6-7-清单只给指针（未指向 pm-operations.md「残留自检」）"
fi
if git -C "$ROOT" diff --quiet main -- AGENTS.md 2>/dev/null; then
  ok "AC6-8-AGENTS.md 零改动"
else
  bad "AC6-8-AGENTS.md 有改动（本批要求零改动）"
fi

# ============================================================ AC7⑤ 判据抽单行谓词（静态）
PRED_LINES="$(grep -c '^repo_contains_path() {' "$FLEET" || true)"
PRED_LINE="$(grep -m1 '^repo_contains_path() {' "$FLEET" || true)"
if [[ "$PRED_LINES" == "1" ]] && have "$PRED_LINE" '"$2" == "$1"' && have "$PRED_LINE" '"${1%/}"/*'; then
  ok "AC7-5-单行谓词（repo_contains_path 单一定义 + 组件级前缀）"
else
  bad "AC7-5-单行谓词（定义行数=$PRED_LINES，需 1 行且含组件级前缀 \${1%/}/*）"
fi
if grep -q 'nao_phys_path' "$FLEET" && grep -q 'pane_cwd_snapshot' "$FLEET" \
   && grep -q 'list-panes -a -F "#{pane_id}"' "$FLEET"; then
  ok "AC7-5b-物理归一 + pane cwd 一次快照（list-panes -a）"
else
  bad "AC7-5b-物理归一 + pane cwd 一次快照（缺 nao_phys_path / pane_cwd_snapshot）"
fi

# ============================================================ 动态夹具（A 项 AC1/AC2/AC7）
CACHE=""; SOCKA=""; SOCKB=""
cleanup() {
  [[ -n "$SOCKA" ]] && { tmux -S "$SOCKA" kill-server >/dev/null 2>&1 || true; }
  [[ -n "$SOCKB" ]] && { tmux -S "$SOCKB" kill-server >/dev/null 2>&1 || true; }
  [[ -n "$CACHE" ]] && rm -rf -- "$CACHE"
  return 0
}
trap cleanup EXIT

if ! command -v tmux >/dev/null 2>&1; then
  skip "DYN 环境缺 tmux（A 项动态断言 AC1/AC2/AC7 未执行）"
elif ! command -v node >/dev/null 2>&1 || [[ ! -f "$REAL_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ]]; then
  skip "DYN 环境缺 node/tsx（名册夹具无法注入，A 项动态断言未执行）"
else
  CACHE="$(mktemp -d "${TMPDIR:-/tmp}/nao-t534-probe.XXXXXX")"
  FX="$CACHE/fx"; SIB="$CACHE/fx-sibling"; OTHER="$CACHE/other-repo-nao-todo"; LINK="$CACHE/link-fx"
  mkdir -p "$FX/.agents" "$SIB" "$OTHER" "$CACHE/bin" \
    "$CACHE/sockA/tmux-$(id -u)" "$CACHE/sockB/tmux-$(id -u)"
  chmod 700 "$CACHE/sockA/tmux-$(id -u)" "$CACHE/sockB/tmux-$(id -u)"
  SOCKA="$CACHE/sockA/tmux-$(id -u)/default"
  SOCKB="$CACHE/sockB/tmux-$(id -u)/default"

  # 夹具纪律：缓存根不得落在任何 git 仓内（否则 toplevel 锚会把 OTHER/SIB 拉进本仓）
  if git -C "$CACHE" rev-parse --show-toplevel >/dev/null 2>&1; then
    bad "FX-0 夹具缓存落在 git 仓内（ARCH 夹具纪律：临时根不得在仓内）"
  else
    ok "FX-0 夹具缓存不在任何 git 仓内"
  fi

  cp -r "$ROOT/.agents/." "$FX/.agents/"
  # 名册假探针（只读 env；逐字段一行 pretty-print —— 紧凑 JSON 会被名册解析贪婪匹配只取末条）
  cat > "$FX/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
  git init -q "$FX" >/dev/null 2>&1            # AC7③：子目录锚需要 toplevel
  mkdir -p "$FX/docs"
  printf '# 任务状态\n\n## 已归档\n\n| 编号 | 状态 |\n| :--- | :--- |\n| T534 | 已归档 |\n' \
    > "$FX/docs/tasks-state.md"
  ln -s "$FX" "$LINK"                          # AC7④：软链归一
  cp "$(command -v sleep)" "$CACHE/bin/pi" && chmod +x "$CACHE/bin/pi"   # 桩 pi（复制二进制保 comm=pi）

  # AC7①：旧版（main）逐字对照
  OLD="$FX/.agents/scripts/nao-fleet-old.sh"
  git -C "$ROOT" show main:.agents/scripts/nao-fleet.sh > "$OLD" 2>/dev/null \
    && ok "FX-1 旧版脚本取自 main（git show main:.agents/scripts/nao-fleet.sh）" \
    || bad "FX-1 旧版脚本取自 main（git show 失败）"

  tx() { tmux -S "$SOCKA" "$@"; }
  # 桩 pi pane：命令用 sleep 副本（无 shell 改标题）+ 关 automatic-rename/allow-rename（标题不被改写）
  mkpane() {  # <sock> <会话名> <cwd> → pane_id
    local sock="$1" name="$2" cwd="$3" p
    tmux -S "$sock" set-option -g automatic-rename off >/dev/null 2>&1 || true
    tmux -S "$sock" set-option -g allow-rename off >/dev/null 2>&1 || true
    tmux -S "$sock" new-session -d -s "p$$-$RANDOM$RANDOM" -x 200 -y 50 -c "$cwd" \
      "$CACHE/bin/pi" 600 >/dev/null 2>&1 || return 1
    p="$(tmux -S "$sock" list-panes -a -F '#{pane_id}' | tail -1)"
    [[ -n "$p" ]] || return 1
    tmux -S "$sock" select-pane -t "$p" -T "π - $name - $(basename "$cwd")" >/dev/null 2>&1 || true
    printf '%s' "$p"
  }
  mk_session() { printf '{"name":"%s","cwd":"%s","tmuxPane":"%s","status":"idle"}' "$1" "$2" "$3"; }
  roster() { local s="[" e; for e in "$@"; do s="$s$e,"; done; printf '%s' "${s%,}]"; }

  RUN_RC=0; RUN_OUT=""
  st_run() {  # <脚本> <cwd> <sockdir> <roster-json> → $RUN_RC / $RUN_OUT
    local script="$1" dir="$2" sdir="$3" roster_json="$4" of="$CACHE/st.$$"
    ( cd "$dir" && env -u TMUX -u TMUX_PANE \
        TMUX="$sdir/tmux-$(id -u)/default,0,0" TMUX_TMPDIR="$sdir" \
        NAO_SKILLS="$FX" NAO_TASKS_STATE="$FX/docs/tasks-state.md" \
        PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER="$roster_json" \
        PATH="$CACHE/bin:$PATH" bash "$script" status ) >"$of" 2>&1
    RUN_RC=$?
    RUN_OUT="$(cat "$of")"; rm -f "$of"
  }
  NEW="$FX/.agents/scripts/nao-fleet.sh"

  # ---- S1（SOCKA）：本仓 / 他仓 / 前缀陷阱 / 名册兜底 / 软链 / 不可判定 ----
  P_L="$(mkpane "$SOCKA" qa-T534 "$FX")"
  P_O="$(mkpane "$SOCKA" qa-T596 "$OTHER")"
  P_S="$(mkpane "$SOCKA" qa-T597 "$SIB")"
  tmux -S "$SOCKA" new-session -d -s nao-qa-T590 >/dev/null 2>&1 || true   # 无 pane 标题、无名册 ⇒ 不可判定
  ROSTER_S1="$(roster \
    "$(mk_session qa-T534 "$FX" "$P_L")" \
    "$(mk_session qa-T596 "$OTHER" "$P_O")" \
    "$(mk_session qa-T597 "$SIB" "$P_S")" \
    "$(mk_session rd-be-T599 "$OTHER" "")" \
    "$(mk_session rd-fe-T588 "$LINK" "")")"
  sleep 0.3
  SIG_BEFORE="$(tx list-panes -a -F '#{pane_id}:#{pane_pid}' 2>/dev/null | sort)"
  TS_BEFORE="$(sha256sum "$FX/docs/tasks-state.md" | cut -d' ' -f1)"

  st_run "$NEW" "$FX" "$CACHE/sockA" "$ROSTER_S1"
  S1="$RUN_OUT"
  [[ "$RUN_RC" == "0" ]] && ok "AC1-0 status rc=0（夹具主场景）" || bad "AC1-0 status rc=$(printf '%s' "$RUN_RC")（期望 0）"

  # AC1①：本仓派生会话仍按原样报残留并可 close（cls tag 逐字不变）
  if have "$S1" '  · qa-T534  ! 残留（T534 已归档）→ close --task T534 qa'; then
    ok "AC1-1 本仓会话仍报残留且给可执行 close（cls tag 逐字不变）"
  else
    bad "AC1-1 本仓会话未按原样报残留（或 cls tag 文案漂移）"
  fi
  # AC1②：他仓会话必须标注「他仓」且整行无可执行 close 命令（BR2 / D5）
  if have "$S1" '  ~ qa-T596（他仓 @ other-repo-nao-todo）他仓会话，勿在本仓回收'; then
    ok "AC1-2 他仓会话标注「他仓 @ <仓名>」"
  else
    bad "AC1-2 他仓会话未按要求标注（期望 ~ qa-T596（他仓 @ other-repo-nao-todo）…）"
  fi
  if grep -qE 'close --task (T596|T597|T599)' <<< "$S1"; then
    bad "AC1-3 他仓会话行出现可执行 close 命令（BR2 违反）"
  else
    ok "AC1-3 他仓会话行无可执行 close 命令（grep -cE 'close --task (T596|T597|T599)' = 0）"
  fi
  # AC7②：`<夹具根>-sibling` 裸字符串前缀会误判本仓 ⇒ 必须判他仓
  if have "$S1" '  ~ qa-T597（他仓 @ fx-sibling）他仓会话，勿在本仓回收'; then
    ok "AC7-2 前缀陷阱（<夹具根>-sibling 判他仓，组件级前缀生效）"
  else
    bad "AC7-2 前缀陷阱（<夹具根>-sibling 被判本仓 ⇒ 裸字符串前缀缺陷）"
  fi
  # 名册兜底（无 pane ⇒ 用名册 cwd）
  if have "$S1" '  ~ rd-be-T599（他仓 @ other-repo-nao-todo）他仓会话，勿在本仓回收'; then
    ok "AC1-4 名册兜底（无 pane 的会话按名册 cwd 判他仓）"
  else
    bad "AC1-4 名册兜底（无 pane 会话未按名册 cwd 判他仓）"
  fi
  # AC7④：名册 cwd 为指向夹具根的软链 ⇒ 物理归一后判本仓
  if have "$S1" 'close --task T588 rd-fe'; then
    ok "AC7-4 软链归一（名册 cwd = symlink→夹具根 判本仓）"
  else
    bad "AC7-4 软链归一（symlink 未被物理归一 ⇒ 判他仓）"
  fi
  # 不可判定 ⇒ fail-closed：只标注、不给命令
  if have "$S1" '  ? qa-T590（归属不可判定）→ 人工核对（勿在本仓回收）'; then
    ok "AC1-5 不可判定 fail-closed（只标注不给命令）"
  else
    bad "AC1-5 不可判定行缺失或文案不符（期望 ? qa-T590（归属不可判定）…）"
  fi
  OTH_LINES="$(printf '%s\n' "$S1" | grep -E '^  (~|\?) ' || true)"
  if [[ -n "$OTH_LINES" ]] && ! grep -q 'close' <<< "$OTH_LINES"; then
    ok "AC1-6 他仓/不可判定行整体不含 close 形态（BR2）"
  else
    bad "AC1-6 他仓/不可判定行含 close 形态或两类行缺失"
  fi

  # AC2①：status 只读（pane 集合/pid 与 tasks-state 前后全等）
  SIG_AFTER="$(tx list-panes -a -F '#{pane_id}:#{pane_pid}' 2>/dev/null | sort)"
  TS_AFTER="$(sha256sum "$FX/docs/tasks-state.md" | cut -d' ' -f1)"
  if [[ "$SIG_BEFORE" == "$SIG_AFTER" ]] && [[ "$TS_BEFORE" == "$TS_AFTER" ]]; then
    ok "AC2-1 零副作用（pane id/pid 集合与 tasks-state 哈希前后全等）"
  else
    bad "AC2-1 status 产生副作用（pane 集合或 tasks-state 变化）"
  fi
  if tmux -S "$SOCKA" list-panes -a -F '#{pane_id}' | grep -qxF -- "$P_O"; then
    ok "AC2-1b 他仓 pane 存活（改动只读，未回收任何他仓 pane）"
  else
    bad "AC2-1b 他仓 pane 已被回收（误杀）"
  fi

  # AC7③：子目录锚（在 <夹具根>/.agents 内跑，本仓 pane 仍判本仓）
  st_run "$NEW" "$FX/.agents" "$CACHE/sockA" "$ROSTER_S1"
  if have "$RUN_OUT" 'close --task T534 qa'; then
    ok "AC7-3 子目录锚（cwd=<夹具根>/.agents 时本仓 pane 仍判本仓）"
  else
    bad "AC7-3 子目录锚（子目录跑 status 时本仓 pane 落入他仓桶）"
  fi

  # AC7④b：锚侧软链（从 symlink→夹具根 跑 status，本仓 pane 仍判本仓）
  st_run "$NEW" "$LINK" "$CACHE/sockA" "$ROSTER_S1"
  if have "$RUN_OUT" 'close --task T534 qa'; then
    ok "AC7-4b 锚侧软链（cwd=symlink→夹具根 时本仓 pane 仍判本仓）"
  else
    bad "AC7-4b 锚侧软链（symlink 锚未物理归一）"
  fi

  # AC2②：单行变异两个方向（恒真 / 恒假）
  MUT_T="$FX/.agents/scripts/mut-true.sh"
  MUT_F="$FX/.agents/scripts/mut-false.sh"
  sed -E 's/^repo_contains_path\(\) \{.*$/repo_contains_path() { return 0; }/' "$NEW" > "$MUT_T"
  sed -E 's/^repo_contains_path\(\) \{.*$/repo_contains_path() { return 1; }/' "$NEW" > "$MUT_F"
  if grep -qxF 'repo_contains_path() { return 0; }' "$MUT_T" && grep -qxF 'repo_contains_path() { return 1; }' "$MUT_F"; then
    ok "AC2-2a 变异自检（两方向各命中 1 行 repo_contains_path）"
  else
    bad "AC2-2a 变异未命中（谓词不是单行可变异形态）"
  fi
  st_run "$MUT_T" "$FX" "$CACHE/sockA" "$ROSTER_S1"
  if grep -qF 'close --task T596' <<< "$RUN_OUT"; then
    ok "AC2-2b 变异「恒真」⇒ AC1 首句 FAIL（他仓会话被报本仓残留并给 close）"
  else
    bad "AC2-2b 变异「恒真」未翻转为误杀提示（判据未真正生效）"
  fi
  st_run "$MUT_F" "$FX" "$CACHE/sockA" "$ROSTER_S1"
  if have "$RUN_OUT" 'close --task T534'; then
    bad "AC2-2c 变异「恒假」未生效（本仓残留仍可见）"
  else
    ok "AC2-2c 变异「恒假」⇒ 本仓残留检测失效（close --task T534 消失）· 契约失效面点名：tests/t4/cases/13-close-guards.sh、tests/t4/cases/15-subagent-isolation.sh 的残留/回收路径"
  fi

  # AC7①：仅本仓 pane 夹具下，旧版 vs 新版 status 逐字相同
  P_B="$(mkpane "$SOCKB" qa-T534 "$FX")"
  ROSTER_B="$(roster "$(mk_session qa-T534 "$FX" "$P_B")")"
  sleep 0.3
  st_run "$OLD" "$FX" "$CACHE/sockB" "$ROSTER_B"; OLD_OUT="$RUN_OUT"
  st_run "$NEW" "$FX" "$CACHE/sockB" "$ROSTER_B"; NEW_OUT="$RUN_OUT"
  if [[ -n "$OLD_OUT" && "$OLD_OUT" == "$NEW_OUT" ]]; then
    ok "AC7-1 兼容机械证明（旧版 vs 新版 status 在同一「仅本仓 pane」夹具下逐字相同）"
  else
    bad "AC7-1 旧版 vs 新版 status 差异（diff 非空或输出为空）"
  fi
  if have "$NEW_OUT" 'close --task T534 qa'; then
    ok "AC7-1b 兼容夹具本身有效（新版仍报本仓残留并给 close）"
  else
    bad "AC7-1b 兼容夹具无效（新版未报本仓残留，逐字相同无意义）"
  fi
fi

# ============================================================ AC4（C 项 · 旧探针识别放宽的自证）
TMPC="$(mktemp -d "${TMPDIR:-/tmp}/nao-t534-c.XXXXXX")"
cleanup_c() { rm -rf -- "$TMPC"; return 0; }

OLD_PASS_IDS=0
if [[ -f "$OLD_PROBE" ]]; then
  bash "$OLD_PROBE" > "$TMPC/base.out" 2>&1; BASE_RC=$?
  BASE_SUM="$(grep -m1 '^探针汇总:' "$TMPC/base.out" || true)"
  BASE_PASS="$(printf '%s' "$BASE_SUM" | sed -n 's/.*PASS=\([0-9]*\).*/\1/p')"
  BASE_FAIL="$(printf '%s' "$BASE_SUM" | sed -n 's/.*FAIL=\([0-9]*\).*/\1/p')"
  if [[ "$BASE_RC" == "0" && "${BASE_FAIL:-x}" == "0" && -n "${BASE_PASS:-}" ]]; then
    ok "AC4-0 旧探针基线 rc=0（PASS=$BASE_PASS FAIL=$BASE_FAIL）"
  else
    bad "AC4-0 旧探针基线 rc=$BASE_RC（PASS=${BASE_PASS:-?} FAIL=${BASE_FAIL:-?}，期望 rc=0/FAIL=0）"
  fi
  OLD_PASS_IDS="$(grep -c '^PASS AC4-' "$TMPC/base.out" || true)"

  # 未覆盖声明必须出现在输出（BR6：不得让未覆盖看起来像通过）
  if grep -qF '未覆盖：任务提交完全无 docs' "$TMPC/base.out"; then
    ok "AC4-5 输出含「未覆盖：任务提交完全无 docs」声明"
  else
    bad "AC4-5 输出缺「未覆盖：任务提交完全无 docs」声明（BR6 违反）"
  fi

  # 变异 A：收窄正则 + 去全角归一（退回旧口径）⇒ 四种写法里至少 2 种翻为漏判
  sed -E \
    -e "s/^DOCS_SUBJECT_NORM=.*/DOCS_SUBJECT_NORM='s\/^\/\/'/" \
    -e "s/^DOCS_ERE=.*/DOCS_ERE='^docs\\\\([^)]*\\\\):'/" \
    "$OLD_PROBE" > "$TMPC/mut-regex.sh"
  bash "$TMPC/mut-regex.sh" > "$TMPC/mut-regex.out" 2>&1 || true
  MUT_PASS_IDS="$(grep -c '^PASS AC4-' "$TMPC/mut-regex.out" || true)"
  FLIPPED=$(( ${OLD_PASS_IDS:-0} - ${MUT_PASS_IDS:-0} ))
  if (( FLIPPED >= 2 )); then
    ok "AC4-6 变异「收窄正则」⇒ ${FLIPPED} 种写法翻为漏判（基线 PASS=$OLD_PASS_IDS → 变异 PASS=$MUT_PASS_IDS）"
  else
    bad "AC4-6 变异「收窄正则」只翻转 ${FLIPPED} 种写法（期望 ≥2；基线 PASS=$OLD_PASS_IDS → 变异 PASS=$MUT_PASS_IDS）"
  fi

  # 变异 B：删「未覆盖」声明行 ⇒ 专项断言（上面的 AC4-5 判据）FAIL
  sed -E "/^printf '未覆盖：任务提交完全无 docs/d" "$OLD_PROBE" > "$TMPC/mut-decl.sh"
  bash "$TMPC/mut-decl.sh" > "$TMPC/mut-decl.out" 2>&1 || true
  if grep -qF '未覆盖：任务提交完全无 docs' "$TMPC/mut-decl.out"; then
    bad "AC4-7 变异「删声明行」未生效（声明仍在，专项断言无法证明）"
  elif grep -qF '未覆盖：任务提交完全无 docs' "$TMPC/base.out"; then
    ok "AC4-7 变异「删声明行」⇒ 专项断言（AC4-5）取向 FAIL（声明在基线有、在变异体无）"
  else
    bad "AC4-7 基线亦无声明（对照无效）"
  fi
else
  bad "AC4-0 旧探针缺失（$OLD_PROBE）"
fi
cleanup_c

# ── RO：真仓库零写入 ──────────────────────────────────────────────────
RO_STATUS_AFTER="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
RO_HEAD_AFTER="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
if [[ "$RO_STATUS_BEFORE" == "$RO_STATUS_AFTER" && "$RO_HEAD_BEFORE" == "$RO_HEAD_AFTER" ]]; then
  ok "RO-1 真仓库零写入（status/HEAD 前后一致）"
else
  bad "RO-1 真仓库被改动（status 或 HEAD 前后不一致）"
fi

printf -- '---\n探针汇总: PASS=%d FAIL=%d SKIP=%d\n' "$PASS_N" "$FAIL_N" "$SKIP_N"
(( FAIL_N == 0 )) || exit 1
