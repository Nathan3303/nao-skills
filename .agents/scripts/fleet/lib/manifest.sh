# =============================================================================
# fleet/lib/manifest.sh — roles.yaml / fleet.yaml / 命名契约 / 角色卡
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core（路径谓词/日志）；term 无直接依赖
# roles.yaml 解析是**唯一**角色事实入口（load_manifest）；会话名契约 v2 的构造/解析/校验单点在此。
# =============================================================================


# ---------------------------------------------------------------------------
# roles.yaml 解析（严格子集：顶层 roles:，2 空格角色条目 / 4 空格字段，禁 Tab）
# 填充 ROLE_ORDER / ROLE_CARDS / ROLE_WS / ALIAS_ROLE；解析失败即 die
load_manifest() {
  local f="$MANIFEST" out
  [[ -f "$f" ]] || die "角色清单缺失: $f（请创建 .agents/roles.yaml）"
  out="$(awk -F'\t' '
    function die(msg) { print "ERR: " FNR ": " msg; bad=1 }
    BEGIN { bad=0; in_roles=0; cur=""; n=0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if ($0 ~ /\t/) { die("禁止 Tab 缩进"); next }
      if (!in_roles) {
        if ($0 ~ /^roles:[[:space:]]*$/) { in_roles=1; next }
        die("顶层仅允许 roles:，得到: " $0); next
      }
      if ($0 ~ /^  [^ ][^:]*:[[:space:]]*$/) {
        cur=$0; sub(/^  /, "", cur); sub(/:[[:space:]]*$/, "", cur)
        if (cur !~ /^[a-z0-9][a-z0-9-]*$/) { die("非法角色 id: " cur); next }
        card[cur]=""; ws[cur]="."; na[cur]=0; order[++n]=cur; next
      }
      if (cur != "" && $0 ~ /^    [a-z_]+:[[:space:]]/) {
        key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
        val=$0; sub(/^    [a-z_]+:[[:space:]]*/, "", val)
        if      (key=="card")      { card[cur]=val }
        else if (key=="workspace") { ws[cur]=val }
        else if (key=="aliases") {
          if (val !~ /^\[[^]]*\]$/) { die(cur ".aliases 须为 [a, b] 列表: " $0); next }
          gsub(/^\[|\]$/, "", val); m=split(val, arr, /,/)
          for (i=1; i<=m; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i]); if (arr[i]!="") alias[cur,++na[cur]]=arr[i] }
          if (na[cur]==0) die(cur ".aliases 为空")
        }
        else die(cur " 未知字段: " key)
        next
      }
      die("无法解析: " $0)
    }
    END {
      if (bad) exit 1
      if (!in_roles) { print "ERR: 缺少 roles: 顶层键"; exit 1 }
      for (i=1; i<=n; i++) { c=order[i]; if (card[c]=="") { print "ERR: " c " 缺少 card"; bad=1 } if (na[c]==0) { print "ERR: " c " 缺少 aliases"; bad=1 } }
      if (bad) exit 1
      for (i=1; i<=n; i++) { c=order[i]; print "ROLE\t" c "\t" card[c] "\t" ws[c]; for (j=1; j<=na[c]; j++) print "ALIAS\t" c "\t" alias[c,j] }
    }
  ' "$f")" || { printf '%s\n' "$out" >&2; die "roles.yaml 解析失败: $f"; }
  local k v w rest
  while IFS=$'\t' read -r k v w rest; do
    case "$k" in
      ROLE)  ROLE_ORDER+=("$v"); ROLE_CARDS["$v"]="$w"; ROLE_WS["$v"]="$rest" ;;
      ALIAS) ALIAS_ROLE["$w"]="$v" ;;   # 别名 → 角色 id（消费方 resolve_role/close 按此方向取值）
    esac
  done <<< "$out"
}

# 读取卡片 frontmatter 字段（--- 与 --- 之间）
card_field() {
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && $0 ~ "^" k ":" { sub("^" k ": *", ""); print; exit }
  ' "$1"
}

# ---------------------------------------------------------------------------
resolve_role() {
  local id="${ALIAS_ROLE[$1]:-}"
  [[ -n "$id" ]] || die "未知角色: $1（可用: ${ROLE_ORDER[*]}）"
  NAME="$id"
  PROMPT="${ROLE_CARDS[$id]}"
}

# 弃用告警**单源**（D7）：`--fleet` / `--scope` / `fleet.yaml` 的 `slug:` / `.agents/fleet-scope`
#   命中 ⇒ 本函数打**恰一行** warn（本版忽略，下一 MINOR 移除），不校验、不 fail、不影响放置。
#   调用点每来源只调一次（flag 在 argv 解析处；文件在 ensure 相位 0 每目标仓一次）。
_fleet_deprecated_warn() {  # <--fleet|--scope|fleet-scope|slug>
  local src="${1-}"
  case "$src" in
    --fleet)      printf '[fleet] 弃用：--fleet 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    --scope)      printf '[fleet] 弃用：--scope 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    fleet-scope)  printf '[fleet] 弃用：.agents/fleet-scope 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    slug)         printf '[fleet] 弃用：fleet.yaml 的 slug 字段本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    *)            printf '[fleet] 弃用：%s 本版忽略（下一 MINOR 移除）\n' "$src" >&2 ;;
  esac
  return 0
}

# legacy scope 合法性（只读面 + manifest code 共用）：合法 0；否则 echo 单行原因 + 1。
#   D-1（2026-11-17 用户拍板 A）：保留前缀 subagent- / nao- **只管 role**，不拒 scope。
#   新形不再产生 scope；本函数只服务旧形解析与 manifest `code` 校验。
fleet_scope_problem() {
  local s="${1-}"
  [[ -n "$s" ]] || { printf 'fleet/scope 为空（空值的语义是「未给」，不得写成裸 @）\n'; return 1; }
  (( ${#s} <= 16 )) || { printf 'fleet/scope 过长（%d > 16 字符）\n' "${#s}"; return 1; }
  [[ "$s" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
    || { printf 'fleet/scope 含非法字符（须 ^[a-z0-9][a-z0-9_-]*$：小写字母/数字/-/_，首字符非 -/_；禁 @ . : 空白）\n'; return 1; }
  [[ "$s" != *- ]] || { printf 'fleet/scope 不得以 - 结尾\n'; return 1; }
  return 0
}

# 放置键 = **仓基键**（单一实现；原 fleet_scope_slug 改名）：
#   git 仓 = `basename(dirname(realpath(git --git-common-dir)))`（防 worktree 分裂）；
#   非 git 仓 = realpath(repo) 的 basename；归一 = lowercase / 非 [a-z0-9] → - / 压缩 - / 去首尾 /
#   截 16 / 空则 `repo`。stdout 恰 1 行；空输出 = 实现缺陷（调用方 die，禁用 rc/空行承载不可知）。
place_key_label() {
  local repo="${1-}" phys="" common="" base="" slug="" d=""
  [[ -n "$repo" ]] || return 0
  phys="$(_fleet_phys "$repo")"
  if command -v git >/dev/null 2>&1; then
    common="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null || true)"
  fi
  if [[ -n "$common" ]]; then
    case "$common" in
      /*) ;;
      *) common="$phys/${common#./}" ;;      # --git-common-dir 可返回相对仓根的路径
    esac
    common="$(_fleet_phys "$common")"
    d="$(dirname -- "$common")"
    base="${d##*/}"
  fi
  [[ -n "$base" ]] || base="${phys%/}"
  base="${base##*/}"
  slug="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  slug="${slug:0:16}"
  while [[ "$slug" == *- ]]; do slug="${slug%-}"; done
  [[ -n "$slug" ]] || slug="repo"
  printf '%s\n' "$slug"
}

# ⓪ 名字主体构造（**唯一构造点** · 命名契约 v3）：<role> [<num>] → `<role><num>`
#   num 空 = 槽位 1（不出现数字）；num 非空必须是单字符 2..9（N>9 结构上不可解析 ⇒ fail loud）。
#   **v3 起不再接受 task**：task 只进元数据（app label / herdr sidecar），严禁编进身份；
#   多传参数（含空串）即 fail loud —— 不静默忽略（ADR 2026-11-25 决策一）。
fleet_core_build() {
  local role="${1-}" num="${2-}"
  if (( $# > 2 )); then
    printf 'fleet_core_build：命名契约 v3 不再接受 task 参数（task 只进元数据；多传即拒）\n' >&2
    return 1
  fi
  [[ -n "$role" ]] || { printf 'fleet_core_build：role 为空\n' >&2; return 1; }
  [[ "$role" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] \
    || { printf 'fleet_core_build：role 含非法字符（仅字母/数字/-/_）：%s\n' "$role" >&2; return 1; }
  if [[ -n "$num" ]]; then
    [[ "$num" =~ ^[2-9]$ ]] \
      || { printf 'fleet_core_build：槽位号非法（只接受单字符 2..9；空 = 槽位 1）：%s\n' "$num" >&2; return 1; }
  fi
  printf '%s%s\n' "$role" "$num"
}

# ① 名字构造（kind 只做契约自证）：<kind> <role> [<num>] → stdout 名字
#   v3 起签名去掉 task（多传即 fail loud）；kind 仍限 resident|derived|card（调用方语义标签）。
#   旧签名第 3 参 scope / 第 4 参 task 均已删除 ⇒ 传旧语义值即 rc≠0（防调用点静默残留）。
fleet_name_build() {
  local kind="${1-}" role="${2-}" num="${3-}"
  if (( $# > 3 )); then
    printf 'fleet_name_build：命名契约 v3 不再接受 task 参数（task 只进元数据；多传即拒）\n' >&2
    return 1
  fi
  case "$kind" in
    resident|derived|card) ;;
    *) printf 'fleet_name_build：未知 kind=%s（只能是 resident|derived|card）\n' "${kind:-<空>}" >&2; return 1 ;;
  esac
  fleet_core_build "$role" "$num"
}

# ①-b 后端合法名映射（ADR 2026-11-25 决策一）：nao 名 → herdr desktop app 的 `hc run --name` 合法名。
#   规则：小写化 + 非 [a-z0-9-_.] → `-` + 首字符补齐（非字母数字 ⇒ 前缀 `s-`）+ 截 32 位
#   （**保留槽位后缀**）+ 空 ⇒ `session`。纯函数；同 scope 冲突的 `-<4hex>` 由调用方（app spawn）追加。
#   为什么需要：v3 正常名天然合法；此映射只兜卡名 / 旧 `--as` 边界（括号/大写/其它字符）。
fleet_backend_name() {  # <raw> → 合法名（1..32）
  local raw="${1-}" low="" out="" num="" core=""
  low="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  out="$(printf '%s' "$low" | sed -e 's/[^a-z0-9._-]/-/g')"
  # 槽位后缀属于**语义**（v3 用槽位区分同 role 多会话）⇒ 截断时保留尾部的单字符 2..9
  if [[ "$out" =~ ^(.*[^2-9])([2-9])$ ]]; then
    core="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"
  else
    core="$out"
  fi
  core="${core:0:$(( 32 - ${#num} ))}"
  out="${core}${num}"
  [[ -n "$out" ]] || out="session"
  [[ "$out" =~ ^[a-z0-9] ]] || out="s-${out}"
  out="${out:0:32}"
  printf '%s\n' "$out"
}

# ② 名字解析（**全函数**：任何输入都有定义结果；非法一律 ERR，禁猜）
#   分派顺序：含 `(` ⇒ 新形；否则含 `@` ⇒ legacy scope；否则旧形（`-` 任务分隔）。
#   角色 = 事实表**最长匹配**；旧形 task 必须由 `-` 引导（故 `pm1` / `pm10` / `pm2x` 均 ERR）。
fleet_name_parse() {
  local name="${1-}" pre="" task="" scope="" role="" kind="" best="" bestnum="" num="" rest="" c=""
  [[ -n "$name" ]] || { printf 'ERR\n'; return 0; }
  (( ${#name} <= 48 )) || { printf 'ERR\n'; return 0; }        # 总名长预算

  # ---- v2 只读形：<role>[<N>](<task>) ----
  if [[ "$name" == *'('* ]]; then
    [[ "$name" == *')' ]] || { printf 'ERR\n'; return 0; }    # 反例①：不以 `)` 结尾 ⇒ ERR
    pre="${name%%(*}"
    rest="${name#*(}"
    [[ "$pre" != *'('* ]] || { printf 'ERR\n'; return 0; }     # 只允许一个 `(`
    [[ "$rest" == *')' ]] || { printf 'ERR\n'; return 0; }
    task="${rest%)}"
    [[ "$task" != *')'* ]] || { printf 'ERR\n'; return 0; }    # 只允许一个 `)`（且必须在末尾）
    [[ -n "$task" && "$task" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'ERR\n'; return 0; }
    (( ${#FLEET_ROLE_KIND[@]} )) || { printf 'ERR\n'; return 0; }
    for c in "${!FLEET_ROLE_KIND[@]}"; do
      if [[ "$pre" == "$c" ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum=""
      elif [[ "$pre" == "$c"[2-9] ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum="${pre:${#c}}"
      fi
    done
    [[ -n "$best" ]] || { printf 'ERR\n'; return 0; }
    role="$best"; num="$bestnum"
    case "$role" in subagent-*|nao-*) printf 'ERR\n'; return 0 ;; esac
    kind="${FLEET_ROLE_KIND[$role]:-}"
    [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
    if [[ "$kind" == "card" ]] && (( ${#role} + ${#num} > 32 )); then printf 'ERR\n'; return 0; fi
    if [[ "$kind" == "resident" ]]; then kind="derived"; fi
    printf 'OK %s,%s,%s,%s\n' "$kind" "$role" "$task" "$num"
    return 0
  fi

  # ---- 新形常驻（无括号）：<role>[<N>]（裸 <role> 与旧形裸名同串 ⇒ 归新形；旧形裸名行为不变）----
  if [[ "$name" != *@* ]]; then
    best=""; bestnum=""
    for c in "${!FLEET_ROLE_KIND[@]}"; do
      if [[ "$name" == "$c" ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum=""
      elif [[ "$name" == "$c"[2-9] ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum="${name:${#c}}"
      fi
    done
    if [[ -n "$best" ]]; then
      case "$best" in subagent-*|nao-*) printf 'ERR\n'; return 0 ;; esac
      kind="${FLEET_ROLE_KIND[$best]:-}"
      [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
      if [[ "$kind" == "card" ]] && (( ${#best} + ${#bestnum} > 32 )); then printf 'ERR\n'; return 0; fi
      printf 'OK %s,%s,,%s\n' "$kind" "$best" "$bestnum"
      return 0
    fi
  fi

  # ---- 旧形（只读）：<core>[@<scope>] ----
  case "$name" in
    *@*@*) printf 'ERR\n'; return 0 ;;                          # 多 @（歧义，无定义）
    *@*)
      pre="${name%@*}"; scope="${name##*@}"
      [[ -n "$pre" ]] || { printf 'ERR\n'; return 0; }
      fleet_scope_problem "$scope" >/dev/null || { printf 'ERR\n'; return 0; }
      ;;
    *) pre="$name" ;;
  esac
  case "$pre" in
    subagent-*|nao-*) printf 'ERR\n'; return 0 ;;              # 保留前缀不属舰队命名空间
  esac
  (( ${#FLEET_ROLE_KIND[@]} )) || { printf 'ERR\n'; return 0; }
  best=""
  for c in "${!FLEET_ROLE_KIND[@]}"; do
    if [[ "$pre" == "$c" ]]; then best="$c"; break; fi
    [[ "$pre" == "$c"-?* ]] || continue
    if [[ -z "$best" ]] || (( ${#c} > ${#best} )); then best="$c"; fi
  done
  [[ -n "$best" ]] || { printf 'ERR\n'; return 0; }
  role="$best"
  if [[ "$pre" == "$role" ]]; then task=""; else task="${pre:${#role}+1}"; fi
  if [[ -n "$task" ]]; then
    [[ "$task" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'ERR\n'; return 0; }
  fi
  kind="${FLEET_ROLE_KIND[$role]:-}"
  [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
  if [[ "$kind" == "resident" && -n "$task" ]]; then kind="derived"; fi
  if [[ "$kind" == "card" ]] && (( ${#pre} > 32 )); then printf 'ERR\n'; return 0; fi
  # v2：卡会话不再有 scope 形态（一次性语义）⇒ `sec-review@todo` 属非法旧形
  if [[ "$kind" == "card" && -n "$scope" ]]; then printf 'ERR\n'; return 0; fi
  printf 'LEGACY OK %s,%s,%s,%s\n' "$kind" "$role" "$task" "$scope"
}
# <<< fleet-name-contract END

# ===========================================================================
# 联动仓 manifest（`.agents/fleet.yaml` · T554 降级为「仓代号 → 路径」映射）
#
# 数据通道（单一读点在本节）：
#   fleet_manifest_load <repo_phys> → stdout 记录流，rc 承载「合法 / 非法」：
#     NONE                             无 manifest（**合法事实**，不是错误）
#     ROOT<TAB><repo_phys>              manifest 所在仓根（`@main` 的目标）
#     REPO<TAB><code><TAB><path_phys>  ×N
#   rc=1 ⇒ stderr 单行 `<文件>:<行号> <字段> <原因>`（fail loud）。
#   禁：用 rc / 空行承载「不可知」· 空输出当 NONE（那是实现缺陷，调用方 die）· 落盘缓存
#   （AC8 由「每命令一次、无落地」构造性满足）。
#   manifest 源 = 调用方仓根（不做向上查找、不自动发现联动仓 —— 已知边界见 ADR §限制）。
# 受限 YAML 子集（零新依赖、零网络）：顶层键 repos（`slug:` 为弃用键：恰一行 warn 后忽略）；
#   项键只 code / path；缩进用空格（整行 `#` 注释）、值单双引号可省可留；
#   锚点/别名/流式/多文档/制表符/未知键 ⇒ 非法。
# ===========================================================================
FLEET_MANIFEST_SLUG_SEEN=0; FLEET_MANIFEST_WARNED=0
fleet_manifest_root() {  # <dir> → 仓根物理路径（git toplevel；非 git 仓 = 该目录物理路径）
  local d="${1-}" top=""
  [[ -n "$d" ]] || d="$PWD"
  if command -v git >/dev/null 2>&1; then
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -n "$top" ]] || top="$d"
  _fleet_phys "$top"
}

fleet_manifest_load() {  # <repo_phys> → 记录流（见上）· rc=1 非法（stderr 点名文件:行号 字段 原因）
  local repo="${1-}" f="" line="" indent="" rest="" key="" val="" sec=""
  local slug_seen=0 in_item=0 istart=0 icode="" ipath="" icno=0 ipno=0
  local no=0 why="" i=0 j=0 pp="" need_in=0
  local -a codes=() cpaths=() cnos=() plits=() istarts=()

  [[ -n "$repo" ]] || { printf 'fleet_manifest_load：缺仓路径\n' >&2; return 1; }
  repo="$(_fleet_phys "$repo")"
  f="$repo/.agents/fleet.yaml"
  if [[ ! -e "$f" && ! -L "$f" ]]; then printf 'NONE\n'; return 0; fi
  if [[ ! -f "$f" ]]; then
    printf '%s:1 fleet.yaml 不是常规文件（目录 / fifo / socket 一律拒绝）\n' "$f" >&2; return 1
  fi
  [[ -r "$f" ]] || { printf '%s:1 fleet.yaml 不可读\n' "$f" >&2; return 1; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    no=$((no + 1))
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" == *$'\t'* ]]; then
      printf '%s:%d 缩进/值 含制表符（本子集只接受空格缩进）\n' "$f" "$no" >&2; return 1
    fi
    indent="${line%%[![:space:]]*}"; rest="${line#"$indent"}"
    [[ "$rest" == \#* ]] && continue
    if [[ -z "$indent" ]]; then
      case "$rest" in
        ---|...) printf '%s:%d 多文档分隔 %s 不受支持（只接受单文档）\n' "$f" "$no" "$rest" >&2; return 1 ;;
      esac
      [[ "$rest" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:(.*)$ ]] \
        || { printf '%s:%d %s 无法解析（期望 `键: 值`；本子集只接受 repos）\n' "$f" "$no" "${rest%% *}" >&2; return 1; }
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
      if (( ${#val} >= 2 )); then
        case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
      fi
      case "$key" in
        slug)
          # D7：弃用键 —— 本版**不校验、不 fail、不影响放置**；warn 由调用方统一触发（见下函数），
          #   避免 status/close 的 `2>/dev/null` 把单源告警吞掉。
          FLEET_MANIFEST_SLUG_SEEN=1
          (( ! slug_seen )) && slug_seen=1
          sec=""
          ;;
        repos)
          [[ -n "$val" ]] && { printf '%s:%d repos 只接受缩进列表（值必须为空）\n' "$f" "$no" >&2; return 1; }
          sec="repos"
          ;;
        *)
          printf '%s:%d 未知键 %s（本子集只接受 repos；slug 为弃用键）\n' "$f" "$no" "$key" >&2; return 1
          ;;
      esac
      continue
    fi
    # ---- 缩进项：只允许位于 repos: 之下 ----
    [[ "$sec" == "repos" ]] || { printf '%s:%d 缩进项必须位于 `repos:` 之下\n' "$f" "$no" >&2; return 1; }
    if [[ "$rest" == -* ]]; then
      if (( in_item )); then
        codes+=("$icode"); cpaths+=("$ipath"); cnos+=("$icno"); plits+=("$ipno"); istarts+=("$istart")
      fi
      in_item=1; istart=$no; icode=""; ipath=""; icno=0; ipno=0
      rest="${rest#-}"; rest="${rest#"${rest%%[![:space:]]*}"}"
      [[ -n "$rest" ]] || { printf '%s:%d 列表项为空（期望 `- code: <短代号>`）\n' "$f" "$no" >&2; return 1; }
    elif (( ! in_item )); then
      printf '%s:%d 缩进项必须跟在 `- ` 列表项之后\n' "$f" "$no" >&2; return 1
    fi
    [[ "$rest" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:(.*)$ ]] \
      || { printf '%s:%d %s 无法解析（期望 `code: <短代号>` / `path: <路径>`）\n' "$f" "$no" "${rest%% *}" >&2; return 1; }
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    if (( ${#val} >= 2 )); then
      case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
    fi
    case "$val" in
      ''|'&'*|'*'*|'{'*|'['*|'|'*|'>'*|'!'*|'%'*)
        printf '%s:%d %s 值不受支持（空值 / 锚点 / 别名 / 流式 / 块标量 ⇒ 非法）\n' "$f" "$no" "$key" >&2; return 1 ;;
    esac
    case "$key" in
      code)
        [[ -n "$icode" ]] && { printf '%s:%d code 重复声明\n' "$f" "$no" >&2; return 1; }
        icode="$val"; icno=$no ;;
      path)
        [[ -n "$ipath" ]] && { printf '%s:%d path 重复声明\n' "$f" "$no" >&2; return 1; }
        ipath="$val"; ipno=$no ;;
      *)
        printf '%s:%d 未知键 %s（repos 项只接受 code / path）\n' "$f" "$no" "$key" >&2; return 1 ;;
    esac
  done < "$f"
  if (( in_item )); then
    codes+=("$icode"); cpaths+=("$ipath"); cnos+=("$icno"); plits+=("$ipno"); istarts+=("$istart")
  fi

  # ---- 全量校验（错误一律点名 文件:行号 字段 原因；slug 不参与）----
  for i in "${!codes[@]}"; do
    if [[ -z "${codes[$i]}" ]]; then
      printf '%s:%d repos 项缺 code\n' "$f" "${istarts[$i]}" >&2; return 1
    fi
    if [[ -z "${cpaths[$i]}" ]]; then
      printf '%s:%d repos 项缺 path\n' "$f" "${istarts[$i]}" >&2; return 1
    fi
    if ! why="$(fleet_scope_problem "${codes[$i]}")"; then
      printf '%s:%d code 不可用（%s）\n' "$f" "${cnos[$i]}" "$why" >&2; return 1
    fi
    [[ "${codes[$i]}" == "main" ]] && { printf '%s:%d code 不能用保留代号 main（`@main` 指 manifest 所在仓）\n' "$f" "${cnos[$i]}" >&2; return 1; }
    for j in "${!codes[@]}"; do
      (( j < i )) || break
      [[ "${codes[$j]}" == "${codes[$i]}" ]] && { printf '%s:%d code 重复（%s，首次声明在第 %d 行）\n' "$f" "${cnos[$i]}" "${codes[$i]}" "${cnos[$j]}" >&2; return 1; }
    done
    case "${cpaths[$i]}" in
      /*|..|../*) need_in=0 ;;
      *) need_in=1 ;;
    esac
    pp="$(_fleet_phys "$repo/${cpaths[$i]}")"
    if (( need_in )) && ! repo_contains_path "$repo" "$pp"; then
      printf '%s:%d path 经 symlink 逃出仓根（%s → %s；显式 ../ 或绝对路径才允许出仓）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1
    fi
    [[ -e "$pp" ]] || { printf '%s:%d path 不存在（%s → %s）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1; }
    [[ -d "$pp" ]] || { printf '%s:%d path 不是目录（%s → %s）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1; }
  done

  (( slug_seen )) && printf 'DEPRECATED\tslug\n'
  printf 'ROOT\t%s\n' "$repo"
  for i in "${!codes[@]}"; do
    printf 'REPO\t%s\t%s\n' "${codes[$i]}" "$(_fleet_phys "$repo/${cpaths[$i]}")"
  done
  return 0
}

# manifest 弃用键的单源告警（**所有读入口**调用；同一命令只打一次）。
#   为什么不在 load 内直接 warn：status/close 用 `2>/dev/null` 捕获记录流，会连告警一起吞掉。
fleet_manifest_warn_deprecated() {  # <记录流>：含 DEPRECATED 行 ⇒ 恰一行 warn（同一命令只打一次）
  local stream="${1-}"
  [[ "$stream" == *$'DEPRECATED\tslug'* ]] || return 0
  [[ "${FLEET_MANIFEST_WARNED:-0}" == "1" ]] && return 0
  FLEET_MANIFEST_WARNED=1
  _fleet_deprecated_warn slug
  return 0
}

# `@` 段解析（T554 · 唯一顺序）：`@main` ⇒ manifest 所在仓；code 命中 ⇒ 联动仓；
#   否则既有仓路径语义；两者同时命中且物理路径不同 ⇒ fail loud；都未命中 ⇒ fail loud 列 code + 「@<仓路径>」。
#   纯函数：输入 = 段 + stdin 记录流；输出单行 `OK<TAB>main|linked|path<TAB>repo_phys`
#   （path 分支 = legacy 仓路径语义）。`@` **只选目标仓，不进名字**（AC/判据 §一.5）。
fleet_repo_resolve() {  # <段>（stdin = manifest 记录流）
  local seg="${1-}" kind="" a="" b="" root="" cpath="" pp="" i=0
  local -a codes=() cpaths=()
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      ROOT) root="$a" ;;
      REPO) codes+=("$a"); cpaths+=("$b") ;;
    esac
  done
  [[ -n "$root" ]] \
    || { printf 'fleet_repo_resolve：manifest 记录流缺 ROOT 行（实现缺陷，不得猜）\n' >&2; return 1; }
  pp="$(_fleet_phys "$seg")"; [[ -d "$pp" ]] || pp=""
  for i in "${!codes[@]}"; do
    [[ "${codes[$i]}" == "$seg" ]] || continue
    cpath="${cpaths[$i]}"
    if [[ -n "$pp" && "$pp" != "$cpath" ]]; then
      printf 'fleet_repo_resolve：@%s 同时命中联动仓 code（%s）与仓路径（%s）且物理路径不同 ⇒ 不猜（该怎么办：二者只能取一个，改 code 或在 manifest 里指到同一物理路径）\n' \
        "$seg" "$cpath" "$pp" >&2
      return 1
    fi
    printf 'OK\tlinked\t%s\n' "$cpath"
    return 0
  done
  if [[ "$seg" == "main" ]]; then
    if [[ -n "$pp" && "$pp" != "$root" ]]; then
      printf 'fleet_repo_resolve：@main 同时命中主仓（%s）与仓路径（%s）且物理路径不同 ⇒ 不猜\n' "$root" "$pp" >&2
      return 1
    fi
    printf 'OK\tmain\t%s\n' "$root"
    return 0
  fi
  if [[ -n "$pp" ]]; then printf 'OK\tpath\t%s\n' "$pp"; return 0; fi
  printf 'fleet_repo_resolve：@%s 未命中（可用 code：%s；也可写 @main 指主仓，或 @<仓路径>）\n' \
    "$seg" "${codes[*]:-无}" >&2
  return 1
}

# 角色事实表灌入（每 run 一次）。--cards ⇒ 并入锚根下的下游卡 role（status/close 用；
#   ensure 不读卡集，避免为 parse 引入额外 glob/IO 与 CARD_SET_MAX 告警）。
fleet_roles_init() {
  local r cr a b
  FLEET_ROLE_KIND=()
  for r in "${ROLE_ORDER[@]}"; do [[ -n "$r" ]] && FLEET_ROLE_KIND["$r"]=resident; done
  [[ "${1:-}" == "--cards" ]] || return 0
  while IFS=$'\t' read -r cr a b; do
    [[ -n "$cr" ]] || continue
    [[ -n "${FLEET_ROLE_KIND[$cr]:-}" ]] || FLEET_ROLE_KIND["$cr"]=card
  done < <(card_role_set)
  return 0
}

# ---------------------------------------------------------------------------
# T537 · 下游仓自定义角色会话（ensure --card）—— ADR 2026-11-01-downstream-card-sessions
#   定位：卡（= 系统提示）来自**下游项目仓** <repo>/.agents/prompts/<file>.md；会话属派生/一次性
#   语义（与常驻同等的 pane 托管 / status 可见 / close 可回收），但不登记 roles.yaml、不算常驻。
#   三条机制不变量（BR9）：① 卡 role 与常驻 id/别名**相等或前缀相交**即拒（防抢 status 枚举）；
#   ② 卡集内部前缀反链（check 报 error，status/close 用最长匹配兜底）；③ 字符集/长度契约。
#   这三条是「status 能在既有 ROLE_ORDER 循环之后追加枚举而不改既有行」的前提（arch Q2）。
#   定性：卡限定目录是**可审计边界，不是权限边界** —— 卡正文 = 完全可信输入（能写该仓者
#   即定义角色）；这里只做一致性校验（目录/常规文件/大小/命名），不做也不该做内容安全校验。

# 命名契约（BR9 · AC3②③ · AC6）：echo 单行原因并返回 1；合法返回 0（无输出）
# P9（BR8）：校验对象改为 **core**（≤32 / 字符集 / 尾 - / 保留前缀 / 撞常驻）+ scope（字符集 /
#   ≤16 / 尾 - / 禁 @ . : 空白）+ 总长 ≤48 单判。带 scope 的全名并不由 `--as` 产生（P10 只给 core），
#   但 status/close 的校验面必须能说清「带 scope 的名字合不合法」——两条口径共用本函数。
card_name_problem() {
  local n="$1" core="$1" num="" r rp
  [[ -n "$n" ]] || { echo "名字为空"; return 1; }
  (( ${#n} <= 48 )) || { echo "名字过长（总名 ${#n} > 48 字符）"; return 1; }
  case "$n" in
    *@*) echo "名字不得含 @（v2 名字不含位置；目标仓用 ensure <role>@<code>）"; return 1 ;;
    *'('*|*')'*) echo "名字不得含括号（派生 task 只走 --task，如 ensure --task T554 <角色>）"; return 1 ;;
  esac
  # 常驻槽位号：<role><N>（N 单字符 2..9；`pm1`/`pm0`/`pm10` 结构上不可解析）
  if [[ "$n" =~ ^(.*[^-])([2-9])$ ]]; then core="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"; fi
  (( ${#core} + ${#num} <= 32 )) || { echo "名字过长（role 段 ${#core}+${#num} > 32 字符）"; return 1; }
  [[ "$core" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
    || { echo "名字含非法字符（只允许小写字母/数字/-/_，且首字符须为字母或数字）"; return 1; }
  [[ "$core" != *- ]] || { echo "名字不得以 - 结尾"; return 1; }
  for rp in $CARD_RESERVED_PREFIXES; do
    [[ "$core" != "$rp"* ]] || { echo "名字不得以保留前缀 $rp 开头（$rp 归 pi-subagents / nao 机制）"; return 1; }
  done
  if [[ -n "${ALIAS_ROLE[$core]:-}" ]]; then
    echo "名字与常驻角色/别名 $core 同名（该怎么办：改卡内 frontmatter role —— fleet 按前缀识别身份，--as 也须保留卡 role 前缀，绕不过同名冲突）"; return 1
  fi
  for r in "${ROLE_ORDER[@]}" "${!ALIAS_ROLE[@]}"; do
    [[ "$core" != "$r"-* ]] \
      || { echo "名字以常驻前缀 $r- 开头（会抢走 status/close 对 $r 的枚举；该怎么办：改卡内 role，使其不以任何常驻 id/别名为 <x>- 前缀）"; return 1; }
  done
  return 0
}

# 卡集（status/close 的识别集 · Q2）：锚根全集下 <root>/.agents/prompts/*.md 的 frontmatter role（退化文件名）。
#   输出：role<TAB>卡路径<TAB>锚根。**只收合法且非常驻的 role** —— 安装副本/常驻卡不进卡集
#   （BR9 保证二者不相交；非法卡 ensure 必拒，其历史会话落 status 的「角色未识别」节，不静默）。
#   运行时读、不落状态文件（守「不新增配置」）；每 run 一次 glob + frontmatter 读，不新增后端/node 调用。
card_role_set() {
  local root f role phys n=0
  local -a roots=() files=()
  mapfile -t roots < <(repo_anchor_roots)
  (( ${#roots[@]} )) || return 0
  shopt -s nullglob
  for root in "${roots[@]}"; do
    # 非常规文件（fifo/目录/设备）不入卡集：否则每次 status/close 都要打开它（fifo 会挂死）
    for f in "$root/.agents/prompts"/*.md; do [[ -f "$f" ]] && files+=("$f"); done
  done
  shopt -u nullglob
  local -A seen=()
  for f in "${files[@]}"; do
    phys="$(nao_phys_path "$f")"
    [[ -z "${seen[$phys]:-}" ]] || continue
    seen["$phys"]=1
    role="$(card_field "$f" role)"
    [[ -n "$role" ]] || role="$(basename -- "$f" .md)"
    [[ -z "$(card_name_problem "$role")" ]] || continue
    n=$((n + 1))
    printf '%s\t%s\t%s\n' "$role" "$f" "${f%/.agents/prompts/*}"
  done
  if (( n > CARD_SET_MAX )); then
    warn "下游角色卡 $n 张 > 上限 $CARD_SET_MAX：status/close 只做名字匹配，建议精简本仓 .agents/prompts/"
  fi
  return 0
}

# 卡校验（BR3 六条 · AC2 八种失败输入）：通过则设 CARD_PATH / CARD_ROLE / CARD_REPO（均 realpath）。
#   失败一律 die（单行「原因 + 该怎么办」），且**必在建 pane 之前**（cmd_ensure 两相执行 ⇒ BR6 零副作用）。
#   ① 基准 = <repo> realpath；② 显式拒 `..` 与非 .md；③ 常规文件（fifo/目录会让 cat 挂死）；
#   ④ 256 KiB 上限；⑤ 文案含「该怎么办」；⑥ 定性见上（可审计边界）。
resolve_card() {  # $1=卡路径 · $2=仓（可空 ⇒ $PWD）
  local arg="$1" repo_arg="${2:-}" repo cand card_phys parent_phys prompts_phys role bytes why
  repo="${repo_arg:-$PWD}"
  case "/$arg/" in
    */../*) die "角色卡路径不得含 '..'：$arg（该怎么办：用 <repo>/.agents/prompts/<name>.md 的相对/绝对路径，不要用 .. 回退）" ;;
  esac
  case "$arg" in
    *.md) ;;
    *) die "角色卡须为 .md 文件：${arg:-<空>}（该怎么办：把卡放在 <repo>/.agents/prompts/<name>.md）" ;;
  esac
  [[ -d "$repo" ]] || die "工作区不存在：$repo（该怎么办：--card <卡>@<仓> 指定仓，或先 cd 到目标仓）"
  local repo_phys
  repo_phys="$(nao_phys_path "$repo")"
  # BR3②：相对路径按 realpath(repo) 解析（不是 $PWD；否则 --card <卡>@<他仓> 时两者分歧）
  case "$arg" in
    /*) cand="$arg" ;;
    *)  cand="$repo_phys/$arg" ;;
  esac
  [[ -e "$cand" ]] || die "角色卡不存在：$arg（期望 $repo_phys/.agents/prompts/；该怎么办：在目标仓 .agents/prompts/ 下创建该卡，或用 @<仓> 指向正确仓）"
  # BR3③：常规文件 —— fifo/设备/目录会让 cat 永久挂死，必须**在打开之前**拒
  [[ -f "$cand" ]] || die "角色卡不是常规文件（目录/fifo/设备）：$arg（该怎么办：换成 <repo>/.agents/prompts/<name>.md 常规文件）"
  card_phys="$(nao_phys_path "$cand")"
  prompts_phys="$(nao_phys_path "$repo_phys/.agents/prompts")"
  parent_phys="$(nao_phys_path "$(dirname -- "$card_phys")")"
  [[ "$parent_phys" == "$prompts_phys" ]] \
    || die "角色卡不在 <repo>/.agents/prompts/ 内：$arg → $card_phys（符号链接逃逸也算越界；该怎么办：把卡放进 $repo_phys/.agents/prompts/）"
  bytes="$(wc -c < "$card_phys" | tr -d '[:space:]')"
  (( bytes <= CARD_MAX_BYTES )) \
    || die "角色卡过大：$bytes 字节 > $CARD_MAX_BYTES（提示会整段塞进 system prompt；该怎么办：拆到 skills/ 或精简卡）"
  [[ -s "$card_phys" ]] || die "角色卡为空：$arg（该怎么办：至少写 frontmatter role 与一段角色说明）"
  role="$(card_field "$card_phys" role)"
  role="$(printf '%s' "$role" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
  [[ -n "$role" ]] || role="$(basename -- "$card_phys" .md)"    # 退化：文件名（AC2「无 role 且无可退化文件名」由命名契约拦下）
  if ! why="$(card_name_problem "$role")"; then
    die "角色卡 role 不可用：$role —— $why（该怎么办：改卡内 frontmatter role，或在 ensure 时加 --as <合规名字>）"
  fi
  CARD_PATH="$card_phys"; CARD_ROLE="$role"; CARD_REPO="$repo_phys"
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# ensure 相位 1 的「槽位/放置」判据（T554 · 判据 §一.4 / §二）
#   · 槽位占用的单一判据：目标 workspace 内、名字经 parse 后 (role,num) 相同者占位
#     （v2：slot = 第 4 段，空 = 槽位 1；旧形不占 v2 槽位 —— 旧会话只读、可并存）。
#   · 本批预留：同批两个 pm ⇒ pm / pm2（`_T_RSV_*` 只服务本命令，禁全局状态跨命令泄漏）。
#   · 数据源：本命令快照（≤1 workspace list + ≤1 pane list）。
# ---------------------------------------------------------------------------
declare -a _T_RSV_WS=() _T_RSV_NAME=() _T_RSV_ROLE=() _T_RSV_NUM=()
declare -A _DEP_SCOPE_WARNED=()

# 目标 repo 存在弃用文件 `.agents/fleet-scope` ⇒ 恰一行 warn（每 repo 一次；本版忽略）
_dep_warn_scope_file() {  # <repo_phys>
  local repo="${1-}" phys
  [[ -n "$repo" ]] || return 0
  phys="$(_fleet_phys "$repo")"
  [[ -e "$phys/.agents/fleet-scope" || -L "$phys/.agents/fleet-scope" ]] || return 0
  [[ -n "${_DEP_SCOPE_WARNED[$phys]:-}" ]] && return 0
  _DEP_SCOPE_WARNED["$phys"]=1
  _fleet_deprecated_warn fleet-scope
  return 0
}
