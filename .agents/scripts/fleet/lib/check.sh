# =============================================================================
# fleet/lib/check.sh — check 审计面（体检项 + cmd_check）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term/manifest/session（体检读它们的单源）
# 只读审计：任何体检项都不得写盘、不得起后端；warn 计数口径见 cmd_check 顶部注释。
# =============================================================================

# 校验卡片/公共规范/清单中的 @.agents/... 引用均存在（含 checklists/ 子目录；跨仓库会话能解析的关键保障）
check_cross_refs() {
  local rc=0 src ref
  local -a srcs=()
  shopt -s nullglob
  srcs+=("$PROMPTS_DIR"/*.md "$COMMON_DIR"/*.md "$SKILLS_SUB"/*.md "$SKILLS_DIR"/.agents/checklists/*.md)
  shopt -u nullglob
  for src in "${srcs[@]}"; do
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      case "$ref" in
        common/*|skills/*|prompts/*|scripts/*|templates/*|checklists/*) ;;
        *) continue ;;
      esac
      if [[ ! -e "$SKILLS_DIR/.agents/$ref" ]]; then
        printf '  ✗ %s → @.agents/%s 缺失\n' "$(basename "$src")" "$ref"
        rc=1
      fi
    done < <(grep -hoE '@\.agents/(common|skills|prompts|scripts|templates|checklists)/[A-Za-z0-9._/-]+' "$src" | sed 's/^@\.agents\///' | sort -u)
  done
  [[ $rc -eq 0 ]] && echo '  ✓ 全部引用文件存在'
  return $rc
}

# .agents/** 文本文件 EOL 契约：必须全为 LF（出现 CR 即 fail，列出文件）
# 排除 .nao-obsolete/（update 的旧版备份，EOL 不作为契约）
check_eol() {
  local rc=0 n=0 f
  local -a bad=()
  while IFS= read -r -d '' f; do
    n=$((n + 1))
    grep -Iq $'\r' "$f" && bad+=("${f#"$SKILLS_DIR"/}")
  done < <(find "$SKILLS_DIR/.agents" -type f ! -path '*/.nao-obsolete/*' -print0)
  if (( ${#bad[@]} == 0 )); then
    printf '  ✓ %d 个文本文件全 LF\n' "$n"
  else
    rc=1
    printf '  ✗ %d/%d 个文件含 CR（须转 LF；CRLF 会破坏 fleet/awk 解析）:\n' "${#bad[@]}" "$n"
    printf '      %s\n' "${bad[@]}"
  fi
  return $rc
}

# 端前提声明一致性（#124 · AC5/AC6；上游 #118 §八 D4 裁定 = **不加新闸门**，改单点 warn）
#   比对面：机制文本声明的「默认后端」（`.agents/common/intercom-protocol.md` + `AGENTS.md`）
#   vs 实现默认（`NAO_TERMINAL` 唯一赋值点，从本脚本源码解析 —— 不在此重述默认值字面量）。
#   纪律：**只 warn、不改 rc**（BR4）；**一致时零输出**（tests/t4/cases/06 的 golden md5 依赖这一点）。
#   声明写法契约（改文案别破坏）：声明行须含 **`默认 herdr`** 原文（`默认` 与后端名之间只许空格 /
#   `=`/`＝`；不要插 `**` 等标记）。解析不出 ⇒ `nodecl` ⇒ warn（fail loud，不静默放过）。
#   **全部声明行参与判定**（P2-1 · QA 复核）：同文件内多行声明各判各的 —— 只回退其中一个症状行
#   （如 `AGENTS.md:18` 而 `:33` 仍写 herdr）也必须被抓到；旧实现「取第一条可解析行」正是该盲区。
#   输出（每行一条，TAB 分隔）：`<行号>\t<herdr|tmux|nodecl>`；
#   **无输出 = 不适用**（文件不存在 / 存在但无端前提声明行）—— 只 `return 0`，**不打印 `absent`**
#   （P1-1：单 token 会被调用方读成 `行号=absent, 声明=""` ⇒ npm 安装态每次 `check` 常驻假 warn；
#    真实信道 = npm 包根 `files` 不含 `AGENTS.md`，下游 shim 仓也可能没有协议文件）
premise_declared_backend() {
  local f="$1" n line decl
  [[ -f "$f" ]] || return 0
  grep -qE '运行前提|机制只支持|端前提' "$f" 2>/dev/null || return 0
  # 只信「端前提声明行」：其它行的「默认」与后端无关（如「默认 main-row2」布局）
  #   `tmux` 仍被解析（T555/AC10）：声明里残留它 ⇒ 由调用方 warn 点名「已移除」，**不**静默放过。
  while IFS=: read -r n line; do
    [[ -n "${n:-}" ]] || continue
    decl="$(printf '%s\n' "$line" | grep -oE '默认(后端)?[ ]*(=[ ]*)?(herdr|tmux)' | head -1 | grep -oE '(herdr|tmux)$')"
    if [[ -z "$decl" ]]; then
      # 旧口径（v0.23.0 前）：「唯一路径 … tmux」= 声明 tmux 唯一 ⇒ 与现行默认 herdr 不一致
      if printf '%s\n' "$line" | grep -qE '唯一路径.*tmux'; then decl=tmux; else decl=nodecl; fi
    fi
    printf '%s\t%s\n' "$n" "$decl"
  done < <(grep -nE '运行前提|机制只支持|端前提' "$f" 2>/dev/null || true)
}

# warn-only 单点一致性检查（调用点必须 `|| true`）：逐**声明行**一条 `  ! `（进摘要 warn=N，不合并吞行号）
check_backend_premise() {
  local actual f decl n rel
  actual="$(sed -n 's/^NAO_TERMINAL="\${NAO_TERMINAL:-\([A-Za-z][A-Za-z]*\)}"$/\1/p' "$SELF_SH" 2>/dev/null | head -1)"
  if [[ -z "$actual" ]]; then
    printf '  ! 端前提声明比对跳过：无法从 %s 的 NAO_TERMINAL 唯一赋值点解析默认后端\n' "${SELF_SH#"$SKILLS_DIR"/}"
    return 0
  fi
  for f in "$COMMON_DIR/intercom-protocol.md" "$SKILLS_DIR/AGENTS.md"; do
    rel="${f#"$SKILLS_DIR"/}"
    while IFS=$'\t' read -r n decl; do
      [[ -n "${n:-}" ]] || continue                  # 空行/不产生行 ⇒ 不适用（"absent" 不再作为 token 出现）
      [[ "$decl" == "$actual" ]] && continue         # 该行与实现一致 ⇒ 零输出
      if [[ "$decl" == "nodecl" ]]; then
        printf '  ! 端前提行未给出可比对的后端声明：%s:%s（若该行与终端后端无关，可忽略；或在 AGENTS.md 中删去该行的「运行前提」字样以免被纳入比对）—— 实现默认 = %s（%s 的唯一赋值点）\n' \
          "$rel" "$n" "$actual" "nao-fleet.sh"
      elif [[ "$decl" == "tmux" ]]; then
        printf '  ! 端前提声明不一致：%s:%s 声明默认后端 = tmux，而本版**已移除 tmux 后端**（唯一后端程序 = %s，见 %s 的唯一赋值点）—— 改声明为「运行前提（仅 pi · 默认 herdr）」\n' \
          "$rel" "$n" "$actual" "nao-fleet.sh"
      else
        printf '  ! 端前提声明不一致：%s:%s 声明默认后端 = %s，而实现默认 = %s（%s 的唯一赋值点）—— 改声明或改实现，同一事实勿双源\n' \
          "$rel" "$n" "$decl" "$actual" "nao-fleet.sh"
      fi
    done < <(premise_declared_backend "$f")
  done
  return 0
}

# stash 出口机械闸（#126 B2-2 · github-flow BR5「批间收尾」）—— `check` 内**只读**告警，不改 rc。
#   动机（2026-11-14 实测）：3 条滞留 stash（`v0.22.6` 压 7 天 · `M20261113` 压 7.5 小时且其 sha
#   `0863ab2` 在台账 grep = 0）⇒ 合并后事实留在 stash 里 = 终态从未入库。
#   #130 D1（**年龄阈值**）：BR5 的合法用法是「合并后事实 ⇒ 带标签 stash、随下批首提交回填」——
#   当天回填属正常节奏，而「任何 stash 都 warn」会让闸门自己变成常驻噪声（连撞两批）。故只对
#   **最老一条**年龄 > `NAO_STASH_WARN_HOURS`（默认 6 小时）的才 warn；当天回填**静默**。
#   年龄取法：`stash list --format='%ct'` 的**最小值**（= stash 提交的 committer date）。
#     为什么不取 reflog 时间：`%ct` 是「事实被切出来」的时刻 —— `git stash store` 把**旧** stash 导入
#     本仓时它保持原龄，而 reflog 时间会被刷成 now（旧事实被当成新的、永久静默）；且 `%ct` 一次
#     `stash list --format` 即可取值，不必逐条 reflog 子进程。
#   阈值取值口径：正整数 = 小时数；`0` = 立即（关闭年龄豁免，任何 stash 都 warn）；非数字 / 负数 = **非法**
#     ⇒ 按 `0` 处理（配置坏了不得把闸门静默调松，宁可多报），并在文案里点名「取值无效」。
#   时间不可判定（`%ct` 取不到 / 非数字）或**未来时间戳**（age < 0，时钟回拨 / 手工造未来日期）：**不 warn**
#     （时间不可信时不误报；也不得因算术把闸门弄崩）。
#   根（可注入 · 测试纪律）：`NAO_STASH_ROOT` ⇒ 默认 `$SKILLS_DIR`；**根上无 `.git` ⇒ 零输出**，
#   **不向上 walk**（临时目录落在父仓里也不会被误判；npm 安装态 / 非仓目录同样不适用）。
#   只读契约：本闸**绝不** push/pop/apply/drop —— 滞留事实的处置权在提交人。
#   输出：超阈值 ⇒ **一条** `  ! `（进摘要 warn=N、`-v` 可见，不逐条刷屏）；空 / 不适用 / 未超阈值 ⇒ 零输出。
check_stash_residue() {
  local root="${NAO_STASH_ROOT:-$SKILLS_DIR}" n newest oldest now hours threshold age age_h label hint
  [[ -e "$root/.git" ]] || return 0
  command -v git >/dev/null 2>&1 || return 0
  n="$(git -C "$root" stash list 2>/dev/null | grep -c . || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  (( n > 0 )) || return 0
  hours="${NAO_STASH_WARN_HOURS:-6}"
  hint=""
  if [[ "$hours" =~ ^[0-9]+$ ]]; then
    # 前导零必须按**十进制**解释（#130 返修 P2-1）：`08`/`0008` 在算术里会被当八进制 ⇒
    #   `$(( hours * 3600 ))` 直接报「值对于底数而言过大」⇒ check rc=1 且无汇总行（门禁自己崩）；
    #   `010` 则会静默按 8 生效、文案却写 010。凡放行前导零，必须先 `10#`。
    hours=$((10#$hours))
  else
    hint="（NAO_STASH_WARN_HOURS 取值无效 ⇒ 按立即处理）"; hours=0
  fi
  threshold=$(( hours * 3600 ))
  # 最老一条 = 最小 `%ct`；取不到（非数字）⇒ 时间不可判定 ⇒ 不 warn，但必须留**降级注记**
  #   （#130 返修 P2-2）：否则「能力缺失」与「无 stash」在输出上不可区分 ⇒ 闸门可被永久且无痕静默。
  #   注记只走 `  ·`（只在 -v 报告里出现），不计 warn、不改 rc。
  oldest="$(git -C "$root" stash list --format='%ct' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -1 || true)"
  if [[ ! "$oldest" =~ ^[0-9]+$ ]]; then
    printf '  · 暂存滞留检查跳过：`stash list --format=%%ct` 不可解析（%s 条 stash 仍在）⇒ 无法做年龄判定（未 warn，也未据此判「无滞留」）\n' "$n"
    return 0
  fi
  now="$(date +%s 2>/dev/null || true)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 0
  age=$(( now - oldest ))
  (( age < 0 )) && return 0                       # 未来时间戳 ⇒ 不误报（别炸）
  # hours=0（显式 0 或非法值）⇒ 立即：任何年龄都 warn（fresh stash 的 age 可能 0，故不能靠 `> 0` 判）
  (( hours > 0 )) && { (( age > threshold )) || return 0; }
  age_h=$(( age / 3600 ))
  newest="$(git -C "$root" stash list -1 --format='%s' 2>/dev/null || true)"
  label="$root"
  case "$root" in
    "$SKILLS_DIR") label="." ;;
    "$SKILLS_DIR"/*) label="${root#"$SKILLS_DIR"/}" ;;
  esac
  printf '  ! git stash 非空（%s 条 @ %s，最老一条 %s 小时前 > 阈值 %s 小时%s）：合并后事实可能滞留 stash（BR5）⇒ 下批首提交须 pop 或归口（本闸只读，不自动 pop；最新一条=%s）\n' \
    "$n" "$label" "$age_h" "$hours" "$hint" "${newest:-<无消息>}"
  return 0
}

# PRD 结构探针（M20261118-prd-structure · T579 扩扫描面 · **warn-only**：只提示，**不进 warn 计数、不改 rc**）。
#   动机：ADR 有结构契约（checklists §四），PRD 长期无任何门禁 ⇒ 结构漂移只能靠人眼看。
#   扫描面（T579 起两路，**判据与文案同构**）：
#     ① `docs/prds/*.md`（历史类别目录）—— **只查文件名日期 ≥ `NAO_PRD_STRUCT_SINCE`（默认 2026-11-18）**：
#        老 PRD 不追溯（前缀 `YYYY-MM-DD-`；无前缀 / 不可解析 ⇒ 不查，`-v` 给一条跳过注记，**不猜**）。
#     ② `docs/<任务号>-<slug>/prd.md`（一任务一目录，ADR 2026-11-27；路径约定正文见 checklists/deliverable-docs.md §十）—— 目录形态即「已在新布局」的证据
#        ⇒ **不套** `NAO_PRD_STRUCT_SINCE`（该变量只回答「旧 PRD 追溯面」，与此问的不是一件事）。
#   四条判据：① 必含 9 个 `## ` 模块标题（TL;DR + 一…九；`## 附录` 可缺）
#             ② §七 AC 节内 `### ` 组 ≥5（五覆盖：主路径/异常/边界/负向闭环/设计一致性）
#             ③ 全文 ≤150 行（PRD 上限，见 checklists §一）
#             ④ 新布局 `prd.md` 正文禁表格（T580 · §三 表格边界；历史 `docs/prds/` 不追溯）
#   违反 ⇒ **恰一条** `  ! PRD 结构…`（排除计入 warn 的名单见 cmd_check 摘要处）；`-v` 逐文件展开（路径相对仓根）。
#   **防假绿**：文件不可读 / 0 字节 **不算通过** —— 单列「不可读/空」，不得当「结构合格」放行。
#   局限（可接受）：统计按行首标记，不区分数围栏内的示例；warn-only 不阻断，误报代价低。
check_prd_structure() {
  local root="$PWD" since="${NAO_PRD_STRUCT_SINCE:-2026-11-18}"
  [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || { $VERBOSE && printf '  · PRD 结构：NAO_PRD_STRUCT_SINCE=%s 非法（应为 YYYY-MM-DD）⇒ 回落默认 2026-11-18\n' "$since"; since="2026-11-18"; }
  local -a cands=() files=() rels=()
  shopt -s nullglob
  cands=("$root/docs/prds"/*.md "$root"/docs/T*-*/prd.md "$root"/docs/M*-*/prd.md)
  shopt -u nullglob
  (( ${#cands[@]} > 0 )) || return 0
  local f rel base d tdir
  for f in "${cands[@]}"; do
    rel="${f#"$root"/}"
    case "$rel" in
      docs/prds/*)
        base="${f##*/}"
        if [[ ! "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})- ]]; then
          $VERBOSE && printf '  · PRD 结构：跳过 %s（文件名无 `YYYY-MM-DD-` 前缀 ⇒ 无法判定是否追溯面）\n' "$rel"
          continue
        fi
        d="${BASH_REMATCH[1]}"
        [[ "$d" < "$since" ]] && continue        # ISO 日期可直接按字串比较
        ;;
      *)
        # 任务目录（新布局）：目录形态自证「已在新布局」⇒ 不套日期阈值（AC4 · arch TBD-1）
        tdir="${rel#docs/}"; tdir="${tdir%%/*}"
        [[ "$tdir" =~ ^(T[0-9]+|M[0-9]{8}-[a-z0-9-]+)-[a-z0-9-]+$ ]] || {
          $VERBOSE && printf '  · PRD 结构：跳过 %s（目录形态非 `docs/<任务号>-<slug>/`）\n' "$rel"
          continue
        }
        ;;
    esac
    files+=("$f"); rels+=("$rel")
  done
  (( ${#files[@]} > 0 )) || return 0
  local i nlines ac_groups miss h tbl total=0 bad=0 first="" detail=""
  local -a req=("TL;DR" "一、" "二、" "三、" "四、" "五、" "六、" "七、" "八、" "九、")
  for i in "${!files[@]}"; do
    f="${files[$i]}"; rel="${rels[$i]}"
    total=$((total + 1))
    miss=""
    if [[ ! -r "$f" || ! -s "$f" ]]; then
      # 防假绿：读不到 / 空文件 ≠ 合格（否则「删内容凑绿」永不可发现）
      miss="不可读或空文件（拒绝判为合格）"
    else
      nlines="$(wc -l <"$f" 2>/dev/null | tr -d ' ' || echo 0)"
      [[ "$nlines" =~ ^[0-9]+$ ]] || nlines=0
      local -a lack=()
      for h in "${req[@]}"; do
        grep -qE "^##[[:space:]]+${h}" "$f" 2>/dev/null || lack+=("$h")
      done
      (( ${#lack[@]} > 0 )) && miss+="缺模块 ${lack[*]}；"
      # §七 AC 节内的 `###` 组数（到下一个小节标题为止）
      ac_groups="$(awk '
        /^##[[:space:]]/ { if (ins) exit; if ($0 ~ /^##[[:space:]]+七、/) { ins=1; next } }
        ins && /^###[[:space:]]/ { n++ }
        END { print n + 0 }
      ' "$f" 2>/dev/null || echo 0)"
      [[ "$ac_groups" =~ ^[0-9]+$ ]] || ac_groups=0
      (( ac_groups < 5 )) && miss+="AC 分组 ${ac_groups} < 5；"
      (( nlines > 150 )) && miss+="${nlines} 行 > 150；"
      # T580：**新布局** `docs/<任务号>-*/prd.md` 正文禁表格（§三 表格边界）；历史 `docs/prds/` 不追溯
      #   （冻结语料里的既有表格不作违规，否则等于要求追改历史）。
      if [[ "$rel" == docs/*/prd.md && "$rel" != docs/prds/* ]]; then
        tbl="$(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence && /^\|/ { c++ } END { print c + 0 }' "$f" 2>/dev/null || echo 0)"
        [[ "$tbl" =~ ^[0-9]+$ ]] || tbl=0
        (( tbl > 0 )) && miss+="正文含表格 ${tbl} 行（§三：PRD 正文禁表格，改用列表 + 加粗字段名）；"
      fi
      # 防御：读成功但三条全空（含 0 行且标记齐的神文件）⇒ 合格
      miss="${miss%；}"
    fi
    [[ -n "$miss" ]] || continue
    bad=$((bad + 1))
    if [[ -z "$first" ]]; then first="$rel：$miss"; fi
    detail+="  · PRD 结构：$rel —— $miss"$'\n'
  done
  (( bad > 0 )) || return 0
  printf '  ! PRD 结构（warn-only，不计 warn / 不改 rc）：%s 份受检 PRD 中 %s 份缺结构（%s；docs/prds 只查 ≥%s）⇒ -v 看明细（规范：checklists/deliverable-docs.md §三）\n' \
    "$total" "$bad" "$first" "$since"
  $VERBOSE && printf '%s' "$detail"
  return 0
}

# docs 一级索引一致性探针（T579 · **warn-only**：只提示，**不进 warn 计数、不改 rc**）。
#   动机：一任务一目录（ADR 2026-11-27）后 `docs/README.md` 是唯一发现入口 ⇒ 目录 / 版本 / ADR 与表格行
#     必须**双向**一致：忘加一行 = 全仓不可发现；幽灵行 = 指向已删目录；重复版本 = 双源。
#   启用谓词（结构自描述，**不加日期开关**）：`docs/README.md` 存在且三段标题**逐字**齐
#     （`## 一、任务批次` / `## 二、版本` / `## 三、决策时间线`）⇒ 启用。理由见 ADR 决策 3：变量化会让
#     同仓不同会话 / CI 判定不同，且 `git revert` 后残留环境语义。
#   反例防护：已有 `docs/<任务号>-*/` 且含契约产物（prd.md / arch-review.md / qa-verify.md）却没有齐三段
#     ⇒ 单条「半启用」提示（否则「删掉一段索引标题」即静默免责）。
#   断言（三处双向 + 一级唯一）：目录↔行 · 版本↔文件（同版本唯一 / basename 固定 / 文件须在）· ADR↔时间线 ·
#     `docs/*.md` ⊆ {README, tasks-state, tasks-archive, INSTALL, ARCHITECTURE}。
#   解析：**先剥 ``` 围栏**再认表（否则示例表会误报）；逐字表头 / 列数固定 / 单元格禁 `|`，不给 markdown 变体容错。
#   输出：违反项聚合**恰一条** `  ! 索引…`（`-v` 逐项展开）；一致时默认零输出，`-v` 给一行计数 ✓。
check_docs_index() {
  local idx="$PWD/docs/README.md"
  local -a tdirs=() notes=() adrs=() topmd=()
  local f base
  shopt -s nullglob
  for f in "$PWD"/docs/T*-*/ "$PWD"/docs/M*-*/; do
    base="${f%/}"; base="${base##*/}"
    [[ "$base" =~ ^(T[0-9]+|M[0-9]{8}-[a-z0-9-]+)-[a-z0-9-]+$ ]] && tdirs+=("$base")
  done
  for base in "${tdirs[@]}"; do
    for f in "$PWD/docs/$base"/release-notes-v*.md; do notes+=("docs/$base/${f##*/}"); done
    for f in "$PWD/docs/$base"/adr-*.md; do adrs+=("docs/$base/${f##*/}"); done
  done
  for f in "$PWD"/docs/*.md; do [[ -f "$f" ]] && topmd+=("${f##*/}"); done
  shopt -u nullglob

  # 不可读 ≠ 无索引（防「读不到就当没有」的 fail-open）
  if [[ -e "$idx" && ! -r "$idx" ]]; then
    printf '  ! 索引（warn-only，不计 warn / 不改 rc）：docs/README.md 存在但不可读 ⇒ 拒绝判为「无索引」放行（fail loud）\n'
    return 0
  fi
  # 启用谓词：三段标题逐字齐（先剥 ``` 围栏，避免把示例里的标题当锚点）
  local enabled=0 missing="" body="" h
  [[ -r "$idx" ]] && body="$(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence { print }' "$idx")"
  if [[ -r "$idx" ]]; then
    for h in '## 一、任务批次' '## 二、版本' '## 三、决策时间线'; do
      printf '%s\n' "$body" | grep -qxF "$h" || { missing="$h"; break; }
    done
    [[ -z "$missing" ]] && enabled=1
  fi
  if (( ! enabled )); then
    local half=""
    for base in "${tdirs[@]}"; do
      if [[ -e "$PWD/docs/$base/prd.md" || -e "$PWD/docs/$base/arch-review.md" || -e "$PWD/docs/$base/qa-verify.md" ]]; then
        half="$base"; break
      fi
    done
    [[ -n "$half" ]] || return 0          # 老仓（无索引 / 无任务目录）⇒ 零输出、rc=0（AC7）
    if [[ -e "$idx" ]]; then
      printf '  ! 索引（warn-only，不计 warn / 不改 rc）：docs/%s/ 已有契约产物，但 docs/README.md 缺逐字标题 `%s` ⇒ 索引断言停摆（半启用态；补齐三段即恢复，规范：checklists/deliverable-docs.md §十）\n' \
        "$half" "$missing"
    else
      printf '  ! 索引（warn-only，不计 warn / 不改 rc）：docs/%s/ 已有契约产物，但 docs/README.md 不存在 ⇒ 索引断言停摆（半启用态；规范：checklists/deliverable-docs.md §十）\n' \
        "$half"
    fi
    return 0
  fi

  # 列表按 TAB 拼给 awk（空列表传空串，awk 端判 0）
  local s_dirs="" s_notes="" s_adrs="" s_top=""
  (( ${#tdirs[@]} ))  && s_dirs="$(printf 'docs/%s\n' "${tdirs[@]}"  | paste -sd $'\t' -)"
  (( ${#notes[@]} ))  && s_notes="$(printf '%s\n' "${notes[@]}"  | paste -sd $'\t' -)"
  (( ${#adrs[@]} ))   && s_adrs="$(printf '%s\n' "${adrs[@]}"   | paste -sd $'\t' -)"
  (( ${#topmd[@]} ))  && s_top="$(printf '%s\n' "${topmd[@]}"   | paste -sd $'\t' -)"

  local out summary probs cnt p1 p2 p3
  out="$(awk -v tdirs="$s_dirs" -v notes="$s_notes" -v adrs="$s_adrs" -v topmd="$s_top" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function cell(s) { s = trim(s); gsub(/`/, "", s); sub(/\/+$/, "", s); return s }
    function report(m) { np++; P[np] = m }
    function inlist(v, A, n,   k) { for (k = 1; k <= n; k++) if (A[k] == v) return 1; return 0 }
    function num(a, k) { return ((k in a) ? a[k] : 0) }
    BEGIN {
      HDR[1] = "| 任务号 | 目录 | 一句话 | Issue/PR |"; NCOL[1] = 4; SEG[1] = "任务批次"
      HDR[2] = "| 版本 | 权威路径 | 发布日期 |";       NCOL[2] = 3; SEG[2] = "版本"
      HDR[3] = "| 日期 | 决策 | 任务号 | 状态 |";       NCOL[3] = 4; SEG[3] = "决策时间线"
      nD = (tdirs == "" ? 0 : split(tdirs, DL, "\t"))
      nN = (notes == "" ? 0 : split(notes, NL, "\t"))
      nA = (adrs  == "" ? 0 : split(adrs,  AL, "\t"))
      nT = (topmd == "" ? 0 : split(topmd, TL, "\t"))
      split("README.md tasks-state.md tasks-archive.md INSTALL.md ARCHITECTURE.md", OK, " ")
    }
    { if ($0 ~ /^[ \t]*```/) { fence = !fence; next } }
    fence { next }
    $0 == "## 一、任务批次" { sec = 1; next }
    $0 == "## 二、版本" { sec = 2; next }
    $0 == "## 三、决策时间线" { sec = 3; next }
    $0 ~ /^##[ \t]/ { sec = 0; next }
    { if (sec == 0 || $0 !~ /^\|/) next }
    {
      line = trim($0)
      if (!hdr[sec]) {
        hdr[sec] = 1
        if (line != HDR[sec]) { report("第 " FNR " 行：" SEG[sec] " 段表头非逐字（应为 `" HDR[sec] "`）"); bad[sec] = 1 }
        next
      }
      if (bad[sec]) next
      if (line ~ /^[|: -]+$/) next
      row = $0
      sub(/^[ \t]*\|/, "", row); sub(/\|[ \t]*$/, "", row)
      nc = split(row, C, "|")
      if (nc != NCOL[sec]) { report("第 " FNR " 行：" SEG[sec] " 段列数 " nc " ≠ " NCOL[sec] "（表头逐字 + 单元格禁 `|`）"); next }
      for (k = 1; k <= nc; k++) C[k] = trim(C[k])
      if (sec == 1) { nt++; TT[nt] = C[1]; TD[nt] = cell(C[2]) }
      else if (sec == 2) { nv++; VV[nv] = C[1]; VP[nv] = cell(C[2]); VD[nv] = C[3] }
      else { na++; AD[na] = C[1]; ADEC[na] = C[2]; AT[na] = C[3]; AS[na] = C[4] }
    }
    END {
      for (s = 1; s <= 3; s++) if (!hdr[s]) report(SEG[s] " 段缺表格（须逐字表头：" HDR[s] "）")
      # ---- 任务段：目录 ↔ 行（双向）
      for (i = 1; i <= nt; i++) {
        if (TT[i] !~ /^(T[0-9]+|M[0-9]{8}-[a-z0-9-]+)$/) report("任务段第 " i " 行任务号非法：" TT[i])
        else if (index(TD[i], "docs/" TT[i] "-") != 1) report("任务段第 " i " 行目录与任务号不一致：" TD[i] "（应以 `docs/" TT[i] "-` 开头）")
        if (!inlist(TD[i], DL, nD)) report(TD[i] " 指向不存在的目录（幽灵行：删行或建目录）")
        seen[TD[i]]++
      }
      for (k in seen) if (seen[k] > 1) report("目录重复登记 " seen[k] " 次：" k)
      for (j = 1; j <= nD; j++) if (!(DL[j] in seen)) report(DL[j] "/ 未在任务段登记（建目录须同批加一行）")
      # ---- 版本段：版本 ↔ 文件（同版本唯一 / 权威路径存在 / basename 固定）
      for (i = 1; i <= nv; i++) {
        if (VV[i] !~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) { report("版本段第 " i " 行版本号非法：" VV[i] "（版本段只登记 vX.Y.Z；历史说明写正文）"); continue }
        if (VD[i] !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) report("版本段 " VV[i] " 发布日期非法：" VD[i] "（ISO YYYY-MM-DD）")
        n = split(VP[i], PS, "/")
        if (PS[n] != "release-notes-" VV[i] ".md") report("版本段 " VV[i] " 权威路径 basename ≠ `release-notes-" VV[i] ".md`：" VP[i])
        if (!inlist(VP[i], NL, nN)) report("版本段 " VV[i] " 权威路径不存在：" VP[i])
        vseen[VV[i]]++; nseen[VP[i]]++
      }
      for (k in vseen) if (vseen[k] > 1) report("版本重复登记 " vseen[k] " 次：" k "（同一版本只允许一行）")
      for (j = 1; j <= nN; j++) if (!(NL[j] in nseen)) report(NL[j] " 未在版本段登记（发版说明须指向唯一权威份）")
      # ---- 时间线段：ADR ↔ 行（双向）
      for (i = 1; i <= na; i++) {
        if (AD[i] !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) report("时间线段第 " i " 行日期非法：" AD[i] "（ISO YYYY-MM-DD）")
        if (AT[i] !~ /^(T[0-9]+|M[0-9]{8}-[a-z0-9-]+)$/) report("时间线段第 " i " 行任务号非法：" AT[i])
        if (AS[i] !~ /^(提议|已接受|已废弃)/) report("时间线段第 " i " 行状态非法：" AS[i] "（只允许 提议 / 已接受 / 已废弃 前缀）")
        if (match(ADEC[i], /\]\([^)]*adr-[^)]*\.md\)/)) {
          tgt = substr(ADEC[i], RSTART + 2, RLENGTH - 3)
          if (index(tgt, "docs/") != 1) tgt = "docs/" tgt
          if (!inlist(tgt, AL, nA)) report("时间线段第 " i " 行 ADR 链接指向不存在的文件：" tgt)
          else aseen[tgt]++
        } else report("时间线段第 " i " 行决策格缺 `[决策](adr-*.md)` 相对链接")
      }
      for (j = 1; j <= nA; j++) if (!(AL[j] in aseen)) report(AL[j] " 未在决策时间线段登记一行")
      # ---- 一级唯一索引：docs/*.md 白名单
      for (j = 1; j <= nT; j++) {
        ok = 0
        for (k = 1; k <= 5; k++) if (OK[k] == TL[j]) ok = 1
        if (!ok) report("docs/" TL[j] " 不是允许的一级文件（一级只留 README / tasks-state / tasks-archive / INSTALL / ARCHITECTURE）")
      }
      printf "SUMMARY\t%d\t%d\t%d\n", nt, nv, na
      for (i = 1; i <= np; i++) print P[i]
    }
  ' "$idx")"
  summary="${out%%$'\n'*}"
  if [[ "$out" == *$'\n'* ]]; then probs="${out#*$'\n'}"; else probs=""; fi
  p1="$(printf '%s' "$summary" | cut -f2)"; p2="$(printf '%s' "$summary" | cut -f3)"; p3="$(printf '%s' "$summary" | cut -f4)"
  if [[ -z "$probs" ]]; then
    $VERBOSE && printf '  ✓ 索引：任务 %s 行 / 版本 %s 行 / 决策 %s 行 —— 目录↔行、版本↔文件、ADR↔时间线三处双向一致（docs/README.md）\n' \
      "${p1:-0}" "${p2:-0}" "${p3:-0}"
    return 0
  fi
  cnt="$(printf '%s\n' "$probs" | grep -c . || true)"
  printf '  ! 索引（warn-only，不计 warn / 不改 rc）：%s 项不一致（%s）⇒ -v 看明细（规范：checklists/deliverable-docs.md §十）\n' \
    "$cnt" "$(printf '%s\n' "$probs" | head -1)"
  $VERBOSE && printf '%s\n' "$probs" | sed 's/^/  · 索引：/'
  return 0
}

# 台账 / 开工卡结构探针（T580 · **warn-only**：只提示，**不进 warn 计数、不改 rc**）。
#   动机：开工确认卡从对话搬进 `docs/<任务号>-<slug>/kickoff.md`，台账按批次切 `##` 并加「流转状态 / 完成日期」；
#     结构要能机判，否则「完成即收」「有卡无行」全靠人自觉。
#   正文（字段集 / 表头 / 状态值域 / 完成即收 / 归档规则）单源见 checklists/deliverable-docs.md §十一。
#   判据（违反项聚合**恰一条** `  ! 台账…`，`-v` 逐项展开）：
#     ① 主台账 ≤300 行（PRD T580 目标；超了先搬历史批次）
#     ② 「批次索引」段 + 表头 `| 任务号 | 归档锚点 | 状态 | 完成日期 |` 逐字；每行锚点须在归档文件里存在
#     ③ 卡摘要表头逐字 `| 任务号 | 目标 | 角色链 | 状态 | 完成日期 | 卡指针 |`；列数 6
#     ④ 状态值域 = 6 值（待开工/进行中/待验收/已合并/已发布/已关闭）；完成日期 = ISO 或 `—`
#     ⑤ 完成即收：状态进完成态后**不得**再占卡摘要行（只留批次索引一行）
#     ⑥ 有卡无台账行：`docs/<任务号>-*/kickoff.md` ⇒ 台账须有同名 `##` 段（或被索引行点名）
#     ⑦ 卡缺字段：kickoff.md 表头逐字 + 10 字段齐（缺哪项点名哪项）
#   局限（可接受）：只认逐字表头与固定段名；markdown 变体判「结构非法」，不给容错。
check_ledger_structure() {
  local root="$PWD" ledger="${NAO_TASKS_STATE:-$PWD/docs/tasks-state.md}" archive="$PWD/docs/tasks-archive.md"
  [[ -r "$ledger" ]] || return 0            # 无台账（下游仓 / 纯文档仓）⇒ 零输出
  local -a kdirs=() anchors=()
  local f base anchor line
  shopt -s nullglob
  for f in "$root"/docs/T*-*/ "$root"/docs/M*-*/; do
    [[ -f "${f}kickoff.md" ]] || continue
    base="${f%/}"; kdirs+=("${base##*/}")
  done
  if [[ -r "$archive" ]]; then
    while IFS= read -r anchor; do anchors+=("$anchor"); done < <(
      awk 'match($0, /<a id="[A-Za-z0-9._-]+"><\/a>/) { print substr($0, RSTART + 7, RLENGTH - 13) }' "$archive")
  fi
  shopt -u nullglob

  # ⑦ 卡缺字段（bash 侧逐文件，避免把 10 个字段塞进 awk）
  local -a probs=() reqf=("任务号" "目标（一句话）" "角色链" "AC 指针" "门禁" "红线" "待澄清 / 待拍" "设计类" "发布节奏" "用户确认结论")
  local k miss
  for k in "${kdirs[@]}"; do
    f="$root/docs/$k/kickoff.md"
    if ! grep -qxF '| 字段 | 内容 |' "$f"; then
      probs+=("docs/$k/kickoff.md 表头非逐字（应为 \`| 字段 | 内容 |\`）")
      continue
    fi
    miss=""
    for line in "${reqf[@]}"; do
      grep -qF "| $line |" "$f" || miss+="$line；"
    done
    [[ -z "$miss" ]] || probs+=("docs/$k/kickoff.md 缺字段：${miss%；}")
  done

  # ①②③④⑤⑥ 台账结构（awk 解析；批量列表按 TAB 传入）
  local s_k="" s_a="" out summary body cnt
  (( ${#kdirs[@]} )) && s_k="$(printf '%s\n' "${kdirs[@]}" | paste -sd $'\t' -)"
  (( ${#anchors[@]} )) && s_a="$(printf '%s\n' "${anchors[@]}" | paste -sd $'\t' -)"
  out="$(awk -v kdirs="$s_k" -v anchors="$s_a" -v nlines="$(wc -l <"$ledger" | tr -d ' ')" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function report(m) { np++; P[np] = m }
    function inlist(v, A, n,   k) { for (k = 1; k <= n; k++) if (A[k] == v) return 1; return 0 }
    BEGIN {
      HDRIDX = "| 任务号 | 归档锚点 | 状态 | 完成日期 |"
      HDRSUM = "| 任务号 | 目标 | 角色链 | 状态 | 完成日期 | 卡指针 |"
      nD = (kdirs == "" ? 0 : split(kdirs, KD, "\t"))
      nA = (anchors == "" ? 0 : split(anchors, AN, "\t"))
      split("待开工 进行中 待验收 已合并 已发布 已关闭", ST, " ")
    }
    { if ($0 ~ /^[ \t]*```/) { fence = !fence; next } }
    fence { next }
    /^##[ \t]/ { sec = $0; mode = ""; next }
    { if ($0 !~ /^\|/) next }
    {
      line = trim($0)
      if (line ~ /^[|: -]+$/) next
      # 表头识别（逐字判；不匹配 ⇒ 结构非法，后续行不猜）
      if (line ~ /^\| 任务号 \| 归档锚点/) {
        if (line != HDRIDX) report("批次索引段表头非逐字（应为 `" HDRIDX "`）")
        hdrseen["idx"] = 1; mode = "idx"; next
      }
      if (line ~ /^\| 任务号 \| 目标/) {
        if (line != HDRSUM) report("卡摘要表头非逐字（应为 `" HDRSUM "`）")
        mode = "sum"; next
      }
      if (mode == "") next
      row = line; sub(/^\|/, "", row); sub(/\|$/, "", row)
      nc = split(row, C, "|")
      for (k = 1; k <= nc; k++) C[k] = trim(C[k])
      if (mode == "idx") {
        if (nc != 4) { report("批次索引行 " C[1] " 列数 " nc " ≠ 4"); next }
        anc2 = C[2]; gsub(/`/, "", anc2)
        if (anc2 !~ /^docs\/tasks-archive\.md#/) { report("批次索引行 " C[1] " 归档锚点须形如 `docs/tasks-archive.md#<锚点>`：实际 " C[2]) ; next }
        anc = anc2; sub(/.*#/, "", anc)
        if (!inlist(anc, AN, nA)) report("批次索引行 " C[1] " 锚点不存在于 docs/tasks-archive.md：#" anc)
        if (C[3] !~ /^(待开工|进行中|待验收|已合并|已发布|已关闭)$/) report("批次索引行 " C[1] " 状态值域外：" C[3])
        ids[++nI] = C[1]
        next
      }
      # 卡摘要行
      if (nc != 6) { report("卡摘要行 " C[1] " 列数 " nc " ≠ 6") ; next }
      ids[++nI] = C[1]
      if (C[4] !~ /^(待开工|进行中|待验收|已合并|已发布|已关闭)$/) {
        report("卡摘要行 " C[1] " 状态值域外：" C[4] "（应为 6 值之一：待开工 / 进行中 / 待验收 / 已合并 / 已发布 / 已关闭）")
        next
      }
      if (C[5] != "—" && C[5] !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) report("卡摘要行 " C[1] " 完成日期非法：" C[5] "（应为 YYYY-MM-DD 或 —）")
      if (C[4] == "已合并" || C[4] == "已发布" || C[4] == "已关闭")
        report("已完成批次 " C[1] " 仍占卡摘要（状态 " C[4] " ⇒ 完成即收：删摘要行，只留批次索引一行）")
      if (C[6] != "—" && C[6] != "") {
        ptr = C[6]; gsub(/`/, "", ptr)
        if (index(ptr, "docs/") == 1) {
          split(ptr, PP, "/"); kd = PP[2]
          if (!inlist(kd, KD, nD)) report("卡摘要行 " C[1] " 卡指针指向不存在的文件：" ptr)
        }
      }
    }
    END {
      if (nlines + 0 > 300) report("主台账 " nlines " 行 > 300（已完成批次搬 docs/tasks-archive.md，主台账只留活批次 + 批次索引）")
      if (!hdrseen["idx"]) report("缺「批次索引」表（表头 `" HDRIDX "`；每条归档批次一行）")
      for (i = 1; i <= nD; i++) {
        ok = 0
        for (j = 1; j <= nI; j++) if (index(KD[i], ids[j] "-") == 1) ok = 1
        if (!ok) report("docs/" KD[i] "/kickoff.md 有卡但台账无对应段/行（有卡无台账行）")
      }
      printf "SUMMARY\t%d\t%d\t%d\n", nD, nA, np
      for (i = 1; i <= np; i++) print P[i]
    }
  ' "$ledger" 2>/dev/null)" || out=""
  summary="${out%%$'\n'*}"
  if [[ "$out" == *$'\n'* ]]; then body="${out#*$'\n'}"; else body=""; fi
  # 汇总 bash 侧发现的卡缺字段项
  local extra="" p
  for p in "${probs[@]}"; do extra+="$p"$'\n'; done
  local all="${body:+$body$'\n'}$extra"
  all="${all%$'\n'}"
  if [[ -z "${all//[[:space:]]/}" ]]; then
    $VERBOSE && printf '  ✓ 台账：活批次 %s 个 · 归档锚点 %s 个 · 结构齐（docs/tasks-state.md）\n' \
      "$(printf '%s' "$summary" | cut -f2)" "$(printf '%s' "$summary" | cut -f3)"
    return 0
  fi
  cnt="$(printf '%s\n' "$all" | grep -c . || true)"
  printf '  ! 台账（warn-only，不计 warn / 不改 rc）：%s 项不一致（%s）⇒ -v 看明细（规范：checklists/deliverable-docs.md §十一）\n' \
    "$cnt" "$(printf '%s\n' "$all" | head -1)"
  $VERBOSE && printf '%s\n' "$all" | sed 's/^/  · 台账：/'
  return 0
}

# roles.yaml 缩进契约：角色 id 2 空格 / 字段 4 空格 / 禁 Tab（与 load_manifest 解析器同契约，独立报行号）
check_roles_indent() {
  awk '
    BEGIN { in_roles=0; cur=0; bad=0 }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /\t/ { printf "  ✗ 行 %d: 含 Tab（禁止 Tab 缩进）\n", FNR; bad=1; next }
    !in_roles {
      if ($0 ~ /^roles:[[:space:]]*$/) { in_roles=1; next }
      printf "  ✗ 行 %d: 顶层仅允许 roles:（得到: %s）\n", FNR, $0; bad=1; next
    }
    $0 ~ /^  [^ ][^:]*:[[:space:]]*$/ { cur=1; next }
    cur && $0 ~ /^    [a-z_]+:[[:space:]]/ { next }
    { printf "  ✗ 行 %d: 缩进/位置非法（角色 id 须 2 空格、字段须 4 空格且挂在角色下）: %s\n", FNR, $0; bad=1 }
    END { exit (bad ? 1 : 0) }
  ' "$MANIFEST"
}

# 别名解析守卫（#19）：独立重解析 roles.yaml（不依赖可能被写反的 ALIAS_ROLE），校验
#   ① 每个声明的别名可解析为「声明它的角色」（对 ALIAS_ROLE 键值方向敏感）
#   ② 每个角色 canonical id 已登记于 aliases（BR2：canonical 须可解析为自身）
#   ③ 别名不跨角色重名
check_alias_resolution() {
  local rc=0 ga gr
  local -A owner=()
  # T525 BR6/AC7：`subagent-` 前缀保留给 pi-subagents 子代理会话 —— canonical id 与 alias **都不得占用**
  # （否则 status/close 的排除面会吃掉该角色）。折入本函数（唯一枚举点，避第二处遍历漂移），
  # 与缩进/别名唯一性各自累积 rc。
  while IFS=$'\t' read -r ga gr; do
    [[ -n "$ga" && -n "$gr" ]] || continue
    if [[ "$ga" == subagent-* ]]; then
      printf '  ✗ 角色 id/别名 %s 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）\n' "$ga"; rc=1
    fi
    if [[ -n "${owner[$ga]:-}" && "${owner[$ga]}" != "$gr" ]]; then
      printf '  ✗ 别名 %s 跨角色重名：%s 与 %s\n' "$ga" "${owner[$ga]}" "$gr"; rc=1
    fi
    owner["$ga"]="$gr"
    if [[ "${ALIAS_ROLE[$ga]:-}" != "$gr" ]]; then
      printf '  ✗ 别名 %s 解析异常：roles.yaml 声明属 %s，实际解析为 %s（ALIAS_ROLE 键值方向可能反写）\n' \
        "$ga" "$gr" "${ALIAS_ROLE[$ga]:-<未登记>}"; rc=1
    fi
  done < <(awk -F'\t' '
      /^  [^ ][^:]*:[[:space:]]*$/ { c=$0; sub(/^  /,"",c); sub(/:[[:space:]]*$/,"",c); next }
      c!="" && /^    aliases:[[:space:]]*\[/ {
        v=$0; sub(/^    aliases:[[:space:]]*\[/,"",v); sub(/\].*/,"",v)
        n=split(v, a, /,/)
        for (i=1;i<=n;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if(a[i]!="") print a[i] "\t" c }
      }' "$MANIFEST")
  for gr in "${ROLE_ORDER[@]}"; do
    if [[ "$gr" == subagent-* ]]; then
      printf '  ✗ 角色 id/别名 %s 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）\n' "$gr"; rc=1
    fi
    if [[ "${owner[$gr]:-}" != "$gr" ]]; then
      printf '  ✗ 角色 %s 的 canonical id 未登记于 aliases（BR2：canonical 须可解析为自身）\n' "$gr"; rc=1
    fi
  done
  (( rc == 0 )) && printf '  ✓ 别名解析守卫：全部别名可解析且无跨角色重名 + 无 subagent- 保留前缀\n'
  return $rc
}

# CodeGraph 四态检测（T532 · BR1/BR2）—— check / ensure 唯一发射点。
#   codegraph_state <repo> [full] [name]
#   ！（永不计入 rc）所有状态都只是**可观测信号**：不设 rc=1、--strict 亦不升级；
#     理由 = 六会话并发下「索引 pending」是稳态，长期拉红会侵蚀真失败信号（arch A1）。
#   严格短路：① 声明（两份 settings.json 的 packages 含包名）② command -v codegraph
#              ③ <repo>/.codegraph ④ status 文本（**仅 full=1**）
#   full=0（默认 check）：**零 codegraph 调用**（AC11 判据 = codegraph 调用 0 次）——实际新增 2 次 grep fork
#     （settings 声明匹配 + 摘要行抽取）；不 spawn 任何第三方进程
#   full=1（check -v / ensure）：每仓一次 `codegraph status`（实测 0.37–0.42s，不进派发热路径）
#   契约前缀：· 未声明 / ! 已声明但 CLI 不在 PATH / ! 无索引 / ✓ 齐备 / ! pending / ! 不可解析
codegraph_state() {
  local repo="$1" full="${2:-0}" name="${3:-}" f declared=0 pre="" st
  local -a sets=("$PI_AGENT_DIR/settings.json" "$repo/.pi/settings.json")
  [[ -n "$name" ]] && pre="[$name] "
  for f in "${sets[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -qF -- "$CODEGRAPH_PKG" "$f" 2>/dev/null; then declared=1; break; fi
  done
  if (( ! declared )); then
    printf '  · %s%s\n' "$pre" "$CG_MSG_UNDECLARED"; return 0
  fi
  if ! command -v codegraph >/dev/null 2>&1; then
    printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_CLI"; return 0
  fi
  if [[ ! -d "$repo/.codegraph" ]]; then
    printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_INDEX"; return 0
  fi
  if (( ! full )); then
    printf '  ✓ %s%s\n' "$pre" "$CG_MSG_READY_SHORT"; return 0
  fi
  st="$(cd "$repo" 2>/dev/null && codegraph status 2>&1)" || st=""
  # 文本契约（已冻结于 codegraph 1.6.2 实测，见 docs/reports/M20261028-codegraph-followups.md §二 T1）
  case "$st" in
    *"Index is up to date"*) printf '  ✓ %s%s\n' "$pre" "$CG_MSG_READY" ;;
    *"Pending Changes"*)     printf '  ! %s%s\n' "$pre" "$CG_MSG_PENDING" ;;
    *"Not initialized"*)     printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_INDEX" ;;  # 目录在但无 DB（下游常见态）
    *)                       printf '  ! %s%s\n' "$pre" "$CG_MSG_UNPARSABLE" ;;
  esac
  return 0
}

# pi 运行前提（BR4/AC3）：版本源 = `pi --version` 首个 semver token；预发布（含 `-`）视为不满足。
# 输出当前版本（缺失/不可解析也给占位），rc 0 = 满足 ≥ MIN_PI_VERSION；失败只置 rc，由 check 聚合后继续跑完其余体检。
pi_version_check() {
  if ! command -v pi >/dev/null 2>&1; then printf '%s' '<缺失>'; return 1; fi
  local raw cur base c1 c2
  raw="$(pi --version 2>/dev/null || true)"
  cur="$(printf '%s\n' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?' | head -1 || true)"
  if [[ -z "$cur" ]]; then printf '%s' '<无法解析>'; return 1; fi
  printf '%s' "$cur"
  [[ "$cur" == *-* ]] && return 1          # 预发布不满足（BR4）
  base="${cur%%+*}"                        # 忽略 build metadata
  c1="${base%%.*}"; base="${base#*.}"
  c2="${base%%.*}"
  if (( c1 > MIN_PI_MAJOR )); then return 0; fi
  if (( c1 < MIN_PI_MAJOR )); then return 1; fi
  if (( c2 >= MIN_PI_MINOR )); then return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
cmd_check() {
  local strict="${1:-false}"
  local rc=0 f lines d
  local wl_problems=0

  echo "== 目录 =="
  for d in "$PROMPTS_DIR" "$COMMON_DIR" "$SKILLS_SUB" "$SKILLS_DIR"/.agents/checklists; do
    if [[ -d "$d" ]]; then printf '  ✓ %s\n' "$d"
    else printf '  ✗ 缺失: %s\n' "$d"; rc=1; fi
  done

  echo "== 文本契约（roles.yaml 缩进 2/4 · .agents/** EOL 全 LF）=="
  if [[ -f "$MANIFEST" ]]; then
    if check_roles_indent; then
      printf '  ✓ roles.yaml 缩进契约（角色 id 2 空格 / 字段 4 空格 / 无 Tab）\n'
    else
      rc=1
    fi
  else
    printf '  ✗ roles.yaml 缺失: %s\n' "$MANIFEST"; rc=1
  fi
  check_eol || rc=1

  echo "== 角色清单 roles.yaml =="
  load_manifest
  printf '  ✓ 解析成功，%d 个角色: %s\n' "${#ROLE_ORDER[@]}" "${ROLE_ORDER[*]}"
  check_alias_resolution || rc=1

  # D4（T554 迁移）：`.agents/fleet-scope` 只给**弃用信息行**（本版忽略、下一 MINOR 移除）。
  #   文件存在仍是合法状态 ⇒ **不计 warn、不改 rc**（T4 计数口径不变）。
  if [[ -e "$PWD/.agents/fleet-scope" || -L "$PWD/.agents/fleet-scope" ]]; then
    printf '  · 弃用：.agents/fleet-scope 已忽略（本版忽略，下一 MINOR 移除；放置键恒为仓基键）\n'
  fi

  echo "== 常驻角色卡（阈值 ${CARD_MAX_LINES} 行，frontmatter 校验）=="
  local a role version updated max_card="" max_lines=0 pct10=0
  for a in "${ROLE_ORDER[@]}"; do
    f="$PROMPTS_DIR/${ROLE_CARDS[$a]}"
    if [[ ! -f "$f" ]]; then
      printf '  ✗ %-26s 缺失\n' "${ROLE_CARDS[$a]}"; rc=1; continue
    fi
    lines=$(wc -l < "$f")
    if (( lines > max_lines )); then max_lines=$lines; max_card="${ROLE_CARDS[$a]}"; fi
    if (( lines > CARD_MAX_LINES )); then
      printf '  ! %-26s %3d 行（超阈值，建议拆到 skills/）\n' "${ROLE_CARDS[$a]}" "$lines"
    else
      printf '  ✓ %-26s %3d 行\n' "${ROLE_CARDS[$a]}" "$lines"
    fi
    role="$(card_field "$f" role)"
    version="$(card_field "$f" version)"
    updated="$(card_field "$f" updated)"
    if [[ "$role" != "$a" ]]; then
      printf '  ✗ %s frontmatter role=%s 与 manifest 角色 %s 不一致\n' "${ROLE_CARDS[$a]}" "${role:-<缺失>}" "$a"; rc=1
    fi
    if [[ ! "$version" =~ ^[0-9]+$ ]]; then
      printf '  ✗ %s frontmatter version=%s 缺失或非整数\n' "${ROLE_CARDS[$a]}" "${version:-<缺失>}"; rc=1
    fi
    if [[ -z "$updated" ]]; then
      printf '  ✗ %s frontmatter updated 缺失（应如 2026-09-21）\n' "${ROLE_CARDS[$a]}"; rc=1
    fi
  done
  # #128 E1：卡预算基线（`-v` 可见；只观测，不进 rc —— 不设硬限，超阈值仍有逐卡 `!`）
  if (( max_lines > 0 )); then
    pct10=$(( max_lines * 1000 / CARD_MAX_LINES ))
    printf '  · 卡预算基线：最大 %s %d 行 / 阈值 %d 行（%d.%d%%）\n' "$max_card" "$max_lines" "$CARD_MAX_LINES" "$((pct10 / 10))" "$((pct10 % 10))"
  fi

  echo "== prompts/ 孤儿检查 =="
  local cf found c2 orphan=0
  shopt -s nullglob
  for cf in "$PROMPTS_DIR"/*.md; do
    found=0
    for c2 in "${ROLE_ORDER[@]}"; do
      [[ "$(basename "$cf")" == "${ROLE_CARDS[$c2]}" ]] && found=1
    done
    if (( ! found )); then printf '  ! %s 未登记于 roles.yaml\n' "$(basename "$cf")"; orphan=1; fi
  done
  shopt -u nullglob
  (( orphan )) || echo '  ✓ 无孤儿卡'

  echo "== 下游角色卡（若存在）=="
  check_downstream_cards || rc=1

  echo "== pi 扩展声明（T527：声明 + 文件存在，防「声明漏写 ⇒ 静默无 agent」）=="
  if [[ ! -f "$SKILLS_DIR/package.json" ]]; then
    # 非包根（legacy 仓内真脚本 / 夹具只有 .agents）：无 manifest 可核，跳过不判 FAIL
    echo '  · package.json 缺失（非包根/legacy：跳过 pi.extensions 校验）'
  elif ! command -v node >/dev/null 2>&1; then
    printf '  ✗ node 缺失，无法校验 pi.extensions 声明\n'; rc=1
  else
    local ext_list="" ext_bad=0 e
    if ext_list="$(node -e '
      const p=require(process.argv[1]); const pi=p.pi||{};
      const ex=pi.extensions;
      if(!Array.isArray(ex)||ex.length===0) process.exit(3);
      process.stdout.write(ex.join("\n"));
    ' "$SKILLS_DIR/package.json" 2>/dev/null)"; then
      while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        if [[ ! -e "$SKILLS_DIR/$e" ]]; then
          printf '  ✗ pi.extensions 声明条目不存在: %s\n' "$e"; ext_bad=1; rc=1
        fi
      done <<< "$ext_list"
      if (( ext_bad == 0 )); then
        printf '  ✓ pi.extensions 声明 %d 条且文件存在\n' "$(printf '%s\n' "$ext_list" | grep -c .)"
      fi
    else
      printf '  ✗ pi.extensions 未声明或非法（package.json）\n'; rc=1
    fi
  fi

  echo "== 公共规范 =="
  for f in output-format.md intercom-protocol.md; do
    if [[ -f "$COMMON_DIR/$f" ]]; then printf '  ✓ %s\n' "$f"
    else printf '  ✗ %s 缺失\n' "$f"; rc=1; fi
  done

  echo "== PR 模板（GitHub Flow）=="
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo '  · 非 git 仓库（跳过）'
  else
    local remote_url prtpl="" cand
    remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
      echo '  · 无 remote.origin（跳过）'
    elif [[ "$remote_url" != *github.com* ]]; then
      echo '  · 远端非 GitHub（跳过；PR 模板不适用）'
    else
      shopt -s nullglob
      for cand in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
                  .github/PULL_REQUEST_TEMPLATE \
                  pull_request_template.md PULL_REQUEST_TEMPLATE.md \
                  docs/pull_request_template.md docs/PULL_REQUEST_TEMPLATE.md; do
        [[ -e "$cand" ]] && { prtpl="$cand"; break; }
      done
      shopt -u nullglob
      if [[ -n "$prtpl" ]]; then
        printf '  ✓ PR 模板已就位：%s\n' "$prtpl"
      else
        echo '  ! 未找到 PR 模板（GitHub 远端）：PM 立项时从 .agents/templates/github/pull_request_template.md.example 复制为 .github/pull_request_template.md（见 skills/github-flow.md）'
      fi
    fi
  fi

  # #126 B2-2：stash 滞留机械闸（单点 · warn-only ⇒ 不改 rc；无 stash / 不适用 ⇒ 零输出）
  check_stash_residue || true

  # M20261118：PRD 结构探针（warn-only ⇒ 不计 warn、不改 rc；无新 PRD / 结构合格 ⇒ 零输出）
  check_prd_structure || true

  # T579：docs 一级索引一致性探针（warn-only ⇒ 不计 warn、不改 rc；老仓 / 一致 ⇒ 零输出）
  check_docs_index || true

  # T580：台账 / 开工卡结构探针（warn-only ⇒ 不计 warn、不改 rc；无台账 / 结构齐 ⇒ 零输出）
  check_ledger_structure || true

  echo "== 按需技能 =="
  if [[ -d "$SKILLS_SUB" ]]; then
    shopt -s nullglob
    for f in "$SKILLS_SUB"/*.md; do printf '  · %s\n' "$(basename "$f")"; done
    shopt -u nullglob
  fi

  echo "== 交叉引用（@.agents/common|skills|prompts|scripts/... 均须存在）=="
  check_cross_refs || rc=1

  echo "== CodeGraph（四态检测：全部 warn，永不计入 rc；默认不调用 CLI）=="
  local cgfull=0
  if $VERBOSE; then cgfull=1; fi
  codegraph_state "$PWD" "$cgfull"

  echo "== pi 插件（业界调研能力）=="
  local piset="$PI_AGENT_DIR/settings.json"
  if [[ -f "$piset" ]]; then
    if grep -q 'pi-web-access' "$piset" 2>/dev/null; then
      echo '  · pi-web-access ✓ 已装（PM/arch 业界调研可用）'
    else
      echo '  ! pi-web-access 未装（业界调研不可用；nao-skill plugins install web-access）'
    fi
  else
    echo "  · 未找到 $piset（跳过插件检测）"
  fi

  echo "== 模型白名单 =="
  if [[ -z "$MODEL_WHITELIST" ]]; then
    echo "  （未设置 NAO_MODEL_WHITELIST，-m 不校验）"
  else
    local entry s dup kind tag
    local entries=() seen=()
    IFS=',' read -ra entries <<< "$MODEL_WHITELIST"
    for entry in "${entries[@]}"; do
      entry="${entry#"${entry%%[![:space:]]*}"}"
      entry="${entry%"${entry##*[![:space:]]}"}"
      if [[ -z "$entry" ]]; then
        printf '  ! 空条目被忽略\n'
        wl_problems=$((wl_problems + 1))
        continue
      fi
      dup=0
      for s in "${seen[@]}"; do [[ "$s" == "$entry" ]] && { dup=1; break; }; done
      seen+=("$entry")
      case "$entry" in
        *'*'*|*'?'*|*'['*) kind="glob" ;;
        *)                 kind="字面量" ;;
      esac
      tag=""
      if (( dup )); then tag=" [重复]"; wl_problems=$((wl_problems + 1)); fi
      if [[ "$entry" == "*" ]]; then tag+=" [过宽!]"; wl_problems=$((wl_problems + 1)); fi
      printf '  · %-32s (%s)%s\n' "$entry" "$kind" "$tag"
    done
  fi

  if [[ "$(term_label)" == "app" ]]; then
    echo "== 运行前提（端前提 = herdr desktop app 终端 + pi ≥$MIN_PI_VERSION；app 后端）=="
    echo '  · 生效后端 NAO_TERMINAL=app（第二后端；status/ensure/close/cleanup 走门面；core 由 desktop app 管理；session-start 不适用）'
    # T565/#175 AC4：app 端前提是 **warn-only**（`|| true`）—— 用户实机报阻碍时，这些提示是证据，
    #   但不该把一个静态体检变成 rc 阻塞（需要阻塞的地方 ensure 自己 exit 3）。
    term_check_premise || true
  else
  echo "== 运行前提（端前提 = herdr pane + pi ≥$MIN_PI_VERSION；AC1/AC3）=="
  # rc 口径（P3-4 订正）：**缺 herdr 可执行文件** ⇒ rc=1（明确错配，不能装没看见）；
  #   缺 `HERDR_SESSION`（未在 herdr pane 内，CI 常见）⇒ 只提示不置红（静态体检照跑）；
  #   `protocol≠22` ⇒ rc=1（唯一可置红的机械项）。
  echo '  · 生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app；#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
  if command -v herdr >/dev/null 2>&1; then
    printf '  ✓ herdr 可用\n'
    if [[ -n "${HERDR_SESSION:-}" && "${HERDR_SESSION}" != "default" ]]; then
      printf '  ✓ HERDR_SESSION=%s\n' "$HERDR_SESSION"
      local hschema hproto
      if hschema="$(term_api_schema 2>/dev/null)"; then
        hproto="$(printf '%s\n' "$hschema" | sed -n 's/^protocol:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
        if [[ "$hproto" == "$TERM_HERDR_PROTOCOL" ]]; then
          printf '  ✓ herdr protocol=%s\n' "$hproto"
        else
          printf '  ✗ herdr protocol=%s ≠ %s（破坏性变更 ⇒ fail loud）\n' "${hproto:-<未知>}" "$TERM_HERDR_PROTOCOL"
          rc=1
        fi
      else
        printf '  · herdr api schema 不可用（status 将 exit 3）—— 核对 herdr ≥0.9.1 / server 状态后重试\n'
      fi
    else
      echo '  · 未在 herdr pane 内（HERDR_SESSION 空）：status 将 exit 3；default 已放行（仅破坏性动作需 --force）；纯静态体检可照跑'
    fi
  else
    printf '  ✗ herdr 缺失（status 将 exit 3）—— 装 herdr ≥0.9.1 后重试\n'; rc=1
  fi
  # T565/#175 AC4：**在 app 终端内但 NAO_TERMINAL 未设**（用户实机形态）⇒ 也体检 app 端前提。
  #   仍然 warn-only（`|| true`）且不谎报生效后端（生效后端仍是上面那行 herdr）。
  term_check_premise || true
  fi
  local pi_cur
  if pi_cur="$(pi_version_check)"; then
    printf '  ✓ pi 版本 %s ≥ %s\n' "$pi_cur" "$MIN_PI_VERSION"
  else
    printf '  ✗ pi 版本 %s < %s\n' "$pi_cur" "$MIN_PI_VERSION"; rc=1
  fi
  # #124：端前提声明（协议 / AGENTS.md）vs 实现默认后端 —— **单点 warn，不进 rc**；
  #   一致时零输出（不同后端、不同仓都不改既有输出形态；见函数注释与 tests/t4/cases/34）。
  check_backend_premise || true

  if [[ "$strict" == "true" && $wl_problems -gt 0 ]]; then
    warn "strict 模式：白名单发现 $wl_problems 项问题（空条目/重复/过宽）"
    rc=1
  fi

  return $rc
}

# check 新增节：下游角色卡（若存在）—— D7 分级
#   内容类（缺 role/description、CRLF、超限、含 name: 双用）⇒ `  ! ` warn（不红 rc）
#   机制类（与常驻 id/别名或前缀冲突、卡集前缀嵌套、命名契约越界）⇒ `  ✗ ` error（rc=1，运行期必拒）
#   overlay 兼容（AC8③）：扫描目录 realpath == $PROMPTS_DIR realpath ⇒ 该根整体跳过（否则常驻卡被误报冲突）
#   机制常驻卡的项目内副本（legacy 全量安装）按「同名卡文件」识别 ⇒ 跳过冲突检查（不红）；
#   真正的下游卡（不同文件名）才纳入校验。
check_downstream_cards() {
  local rc=0 root f role desc bytes n=0 why base r
  local -a roots=() scan=() files=() roles=()
  local skipped=0
  mapfile -t roots < <(repo_anchor_roots)
  for root in "${roots[@]}"; do
    [[ -d "$root/.agents/prompts" ]] || continue
    if [[ "$(nao_phys_path "$root/.agents/prompts")" == "$(nao_phys_path "$PROMPTS_DIR")" ]]; then
      skipped=$((skipped + 1)); continue
    fi
    scan+=("$root")
  done
  if (( ${#scan[@]} == 0 )); then
    if (( skipped > 0 )); then
      echo '  · 下游卡扫描目录即机制包 prompts（overlay 生效）：本节跳过'
    else
      echo '  · 未发现下游角色卡目录（<repo>/.agents/prompts/ 不存在）：跳过'
    fi
    return 0
  fi
  shopt -s nullglob
  local -a nonreg=()
  for root in "${scan[@]}"; do
    for f in "$root/.agents/prompts"/*.md; do
      if [[ -f "$f" ]]; then files+=("$f"); else nonreg+=("$f"); fi
    done
  done
  shopt -u nullglob
  # 非常规文件（fifo/目录/设备）：ensure --card 运行期必拒（且 cat 会挂死）⇒ 机制类 error
  for f in "${nonreg[@]:-}"; do
    [[ -n "$f" ]] || continue
    printf '  ✗ %s 不是常规文件（fifo/目录/设备）：ensure --card 必拒，且读取会挂死\n' "$(basename -- "$f")"
    rc=1
  done
  if (( ${#files[@]} == 0 )); then echo '  · 下游角色卡目录为空：跳过'; return 0; fi
  for f in "${files[@]}"; do
    base="$(basename -- "$f")"
    role="$(card_field "$f" role)"
    desc="$(card_field "$f" description)"
    if [[ -z "$role" ]]; then
      printf '  ! %s 缺 frontmatter role（退化用文件名 %s）\n' "$base" "$(basename -- "$f" .md)"
      role="$(basename -- "$f" .md)"
    fi
    local resident=0
    for r in "${ROLE_ORDER[@]}"; do
      if [[ "$base" == "${ROLE_CARDS[$r]}" ]] && [[ "$role" == "$r" || "${ALIAS_ROLE[$role]:-}" == "$r" ]]; then
        resident=1; break
      fi
    done
    if (( resident )); then
      printf '  · %s 机制常驻卡副本（role=%s）：跳过冲突检查\n' "$base" "$role"
      continue
    fi
    n=$((n + 1))
    roles+=("$role")
    printf '  · %s role=%s\n' "$base" "$role"
    [[ -n "$desc" ]] || printf '  ! %s 缺 frontmatter description（建议补一行用途说明）\n' "$base"
    if grep -q $'\r' "$f" 2>/dev/null; then
      printf '  ! %s 含 CRLF（须转 LF；CRLF 会破坏 frontmatter 解析）\n' "$base"
    fi
    bytes="$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')"; bytes="${bytes:-0}"
    (( bytes <= CARD_MAX_BYTES )) \
      || printf '  ! %s %s 字节 > %s（256 KiB；建议拆到 skills/）\n' "$base" "$bytes" "$CARD_MAX_BYTES"
    [[ -z "$(card_field "$f" name)" ]] \
      || printf '  ! %s 含 name: —— 同时被 pi-subagents 视作 agent（其路径无 ## 环境锚点，@.agents 引用不可解析）\n' "$base"
    if ! why="$(card_name_problem "$role")"; then
      printf '  ✗ %s role=%s 不可用：%s（运行期 ensure --card 必拒 ⇒ 闸门提前红）\n' "$base" "$role" "$why"
      rc=1
    fi
  done
  local i j
  for i in "${!roles[@]}"; do
    for j in "${!roles[@]}"; do
      (( i == j )) && continue
      [[ "${roles[$i]}" == "${roles[$j]}-"* ]] || continue
      printf '  ✗ 卡集前缀嵌套：%s 与 %s（后者会抢走前者的 status/close 枚举；须改名）\n' "${roles[$j]}" "${roles[$i]}"
      rc=1
    done
  done
  (( rc != 0 )) || printf '  ✓ 下游角色卡 %d 张，无机制冲突\n' "$n"
  return $rc
}
