# 绑定 tmux + pi 的宿主删除面评审报告（T529 · 轻量）

- 状态：已定稿 · 更新：2026-10-28 · Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-27-strict-tmux-pi.md`（§三/§五 BR1–BR8/§七 AC1–AC9）· Issue #48 · 分支 `feat/48-strict-tmux-pi`（评审基线 = 1947 行脚本）· 被取代 ADR `docs/adr/2026-10-12-non-tmux-host-spawn.md`、`docs/adr/2026-10-13-derived-pane-window-addressing.md`
- 范围：轻量评审三件事（删除面完备性 / ADR 取代关系 / rc 语义）。**不重写方案、不写 ADR 正文、不改代码**。

## 一、可行性结论

- **可行（无技术阻塞）**：14 项待删符号**无一被保留路径复用**（`spawn_tmux` / `resolve_host_window` 派生命址 / `close` 双闸门只消费 `find_pane_for*`、`pane_busy`、`intercom_status_for`、`repo_abspath`）。
- **删除面必须扩容**：除 PRD §三 列举的 14 项外，另有 **10 项清单外漏项**（§四）同样只为宿主选择而存在；不补删则 AC2 的 grep 归零与 BR2「删除面最小完备」都不成立。
- **已裁定（PM 2026-10-28，commit `c40830f`）**：AC1 收窄为 `ensure`/`status`/`close` 三者（`cleanup` 豁免、保持 rc=2）· `check` 的 pi 断言失败 = rc=1 聚合 · case 11 整案退役 · 遗留 screen 会话由 release notes 交代。

## 二、逐项删除结论（14 项）

结论分「可删」= 只服务宿主选择；「必须保留」= 被保留路径复用；「需改写」= 可删但须成组连带。计数 = 现存调用点（不含定义与注释）。

1. **`resolve_action`**（1254-1275，调用 1：1283）→ **可删**。整体退化为单一前提闸门「`$TMUX` 非空且 `tmux` 可用」；rc 11/12 分支随删。
2. **`has_tmux_handle`**（1246-1251，调用 1：1596）→ **可删**。绑定后 status 恒有 pane 句柄，`1595-1598` 降级标注成恒假分支，须同步删，不留「永不打印」的死分支。
3. **`xdg_launcher_ok`**（321-326，调用 2：1267/1268）→ **可删**。
4. **`open_xdg_window`**（1154-1161，调用 2：1205/1232）→ **可删**。调用者均在删除面，删净后无残留外部启动点。
5. **`app_class_visible`**（1163-1185，调用 1：1190）→ **可删**。
6. **`wait_for_app_class`**（1187-1199，调用 1：1208）→ **可删**。
7. **`spawn_xdg_window`**（1201-1226，调用 2：1306/1308）→ **可删**。
8. **`spawn_tmux_attach`**（1229-1243，调用 1：1304）→ **可删**。其「attach 后限时 `list-clients` 校验可见性」是「非 tmux 用户也要看得见」的产物；绑定后调用者本身就在 tmux 客户端内。
9. **`wait_for_tmux_client`**（1142-1151，调用 1：1236）→ **可删**（仅上调 8 使用）。
10. **`spawn_screen`**（1127-1140，调用 1：1309）→ **可删**。
11. **`screen_token_for`**（632-642，调用 3：643/1135/1713）→ **需改写（成组连带，见 §三）**。
12. **`screen_present`**（643-644，调用 2：654/1131）→ **需改写（成组连带，见 §三）**。
13. **`spawn_fork_window`**（1112-1124，调用 3：1310-1312）→ **可删**。
14. **`NAO_TERMINAL_ALLOWED`**（317，调用 4：1257/1286/1535/1537）→ **可删**；同段 `NAO_TERMINAL_LIST`（318，纯文案）一并删。

**必须保留项：0**。三项保留路径（`spawn_tmux` 1036-1085 · `resolve_host_window` 976-1033 · `close` 双闸门）与上述 14 项零交集。

## 三、`screen_token_for` / `screen_present` 成组连带（关键判定）

问：是否被 `status`/`close` 在线判定间接依赖 —— **是，两处硬依赖**：

- `status` 在线判定链：`running()`:654 经 `screen_present`（在线 = 名册 ∨ pane 标题 ∨ tmux 会话 ∨ screen 会话）。
- `close` 回收链：`:1713` 直接调 `screen_token_for` 取 `pid.name` 精确令牌（T516 F2 锚定，禁前缀目标）。

但它们**不是通用句柄层**，只是 screen 宿主专属检测；AC2 已把 `screen_present|screen_token_for` 列入 grep 归零清单 ⇒ **不可保留**。删须一次成组，共 6 处：

1. `632-644` 两个函数本体（含 629-631/649-655 注释）。
2. `running():654` 的 screen limb。
3. `offline_verifiable():662` 的 `case tmux|screen` limb（改为「名册可用 ∨ 在 tmux 内」）。
4. `visible_session_names():676-679` 的 `screen -ls` 枚举块（`derived_in_field`/`subagent_in_field` 同源，删后无副作用）。
5. `spawn_screen():1127-1140`。
6. `close:1713-1715` 的 screen 回收分支。

接受代价：≤v0.18.x 用 `--background`/screen 拉起过的会话，本版起 `status`/`close` 均不可见 ⇒ 由 release notes 交代（§七），不在代码内留兼容层。

## 四、清单外漏项（10 项，须补删；PRD §三 未点名但被 BR2/AC2 强制）

1. **`app_client_pid`**（566-585）+ **`pi_descendant_of`**（586-596）+ **`app_pid_for`**（597-605）+ **`close` 的 app-id 分支**（1717-1727）≈ **45 行**：AC2 要求 `hyprctl|swaymsg|xdotool|wmctrl` 归零，非删不可；三函数只服务 ④ 路径句柄。
2. **pid pipe 全套**（`PID_PIPE_FD` 1080 / `open_pid_pipe` 1081-1089 / `close_pid_pipe` 1090-1094 / `wait_for_pid_pipe` 1096-1105 / `pid_pipe_wrapper` 1107）≈ **20 行**：唯一使用者为 `spawn_fork_window` 与 `spawn_xdg_window`，删后全死。
3. **`TMUX_ENV_SCRUB`**（105；连带 102-104 注释）：F2 清 `TMUX/TMUX_PANE` 只对「非 tmux 派生窗口」有意义，tmux 自身 split/new-session 不能剥离。
4. **`NAO_TERMINAL_LIST`**（318）：仅 `die_env` 文案用。
5. **`offline_verifiable`**（658-663）+ **`close` 的 1744-1749 分支**：绑定后名册/`$TMUX` 至少一条恒真 ⇒ 函数恒 0，分支恒不可达；`close` 直接 `log "<名> 未运行（无需回收）"`。
6. **`visible_session_names` 的 screen 块**（676-679）：同 §三 第 4 条（此处只计一次量）。
7. **`--background` / `BACKGROUND`**（解析 1895；判定 1269；文案 13/54/315）：绑定后无合法分支，保留 = 静默无效，建议删并写入 release notes。
8. **`spawn_tmux` 的 `else` 分支**（1062-1066，`new-session -d`）：非 tmux 已不可达，删（`spawn_tmux` 本体按 BR2 保留）。
9. **`check` 宿主阶梯段**（1531-1556）：改为「`tmux` 存在 + `pi` 存在且 ≥1.4.0」断言（§六）。
10. **头注释与段注释**（30 / 48 / 52-54 / 311-316 / 335-337 / 629-631 / 649-655 / 1080 段头）：随删同步改写，禁留 5 档阶梯描述。

**量级核对**：删 ≈255-285 行，新增 ≈15 行（前提闸门 + pi 断言 + 一行提示）⇒ 净减 ≈**240 行**，高于 AC2/§二 ≤1760 目标（净减 ≥180），余量充足。

## 五、ADR 三条硬要求 + 旧 ADR 状态分工

新 ADR `docs/adr/2026-10-27-strict-tmux-pi.md`（作者 RD，本文只给结构）：

1. **结构达标**：必写 5 节逐字（`## 背景` ≤5 行 / `## 决策` 1-3 句 / `## 理由` 四步法每点一行 / `## 对照过的备选模式` / `## 参考来源` 恒末节）+ 头部恰 4 字段（`状态`/`更新`/`Owner`/`指针`）+ 状态取 4 值域之「已接受（待落地）」（合并后改「已接受（已落地 v0.19.0）」）+ 全文 ≤60 行。
2. **对照模式含基线**：≥2 候选，必须含「**维持现状 = 保留 5 档阶梯**」基线，其余建议「只删 screen 保留 xdg」「保留 `NAO_TERMINAL` 单一 tmux 值」「绑死 tmux + pi ≥1.4.0（采纳）」，每项写不采纳理由。
3. **实施类禁写 + 下沉本文**：逐函数删除表（§二/§四）、rc 判定式（§六）、cases 断言差额与用例集一律不进 ADR 正文 ⇒ 落本报告与 QA 报告。

旧 ADR 分工：

- `2026-10-12-non-tmux-host-spawn.md`：状态改 `已废弃（被 2026-10-27-strict-tmux-pi 取代）`（值域第 4 值，slug 不带 `.md`）；**正文零改动**（不追溯改写归档）；`docs/adr/README.md` 该行状态同步。
- `2026-10-13-derived-pane-window-addressing.md`：**不标废弃**。其不变量（创建/布局/选项全链显式 `-t` 目标寻址，决策 1-5）在新架构下是**唯一路径且完全有效**，标废弃会让读者误以为寻址规则失效。推荐零 diff；取代范围写在新 ADR 的决策/相关指针：「取代 2026-10-12 全篇 + 2026-10-13 决策 5 中『非 tmux 阶梯 ③④⑤』一句」。若 RD 坚持就地修订：只允许加一行「修订：…」+ 决策 1/5 各一句括注，禁删段落。

## 六、rc 语义定稿

- **rc=3 = 前提不满足 ⇒ 命令未执行**：仅 `ensure`/`status`/`close`；实现 = `die_env` 由 `exit 2` 改 `exit 3`，输出一行可操作提示（含 `tmux new -s nao`），且发生在 `load_manifest` 与任何副作用之前（BR3）。
- **`cleanup` 豁免**：不做 tmux 闸门（其正常用法就是 `env -u TMUX … cleanup -S <隔离socket>`），保持 `无 -S`/命中生产默认 socket ⇒ rc=2、无 socket ⇒ 幂等 rc=0。
- **rc=2 剩余语义**：仅 `cleanup` 用法守卫，与新 3 不冲突。
- **11/12 退役**：二者从来只是 `resolve_action` 的**内部 return 码**，进程实际 exit 只有 0/1/2 ⇒ ADR 写一句「随 `resolve_action` 一并退役，**无任何已发布的外部可见退出码消失**」，避免下游误判为破坏码契约。
- **`check` 的 pi 断言失败 = rc=1（聚合），不复用 3**：`check` 语义是「已执行并给出完整报告」（3 是「未执行」）；全仓门禁只判 `check rc=0`，第三码会诱发下游按码分支。实现：pi 缺失/版本低置 rc=1 后**继续跑完其余体检**（一次看全），输出指名当前版本与要求版本；版本源取 `pi --version` 首个 semver token，预发布视为不满足。

## 七、legacy 影响（迁移指引）

- 旧版 `--background`/screen 自动拉起的会话，本版起 `status` 不可见、`close` 不可回收（§三 代价）。
- 因此 `docs/releases/v0.19.0.md` 首屏需在「必须 tmux + pi ≥1.4.0」之后补一句：**「若旧版用 `--background`/screen 拉起过会话，先 `screen -ls` 手工清理一次」**。

## 八、明确不做与转办

- 不做：不改 PRD 指标、不重写方案、不跑门禁复跑、不写 ADR 正文、不动下游三仓。
- 转办 QA：case 11 整案退役（断言实体 `docs/reports/2026-10-12-T513-verify.sh`，971 行 / 39 处 `NAO_TERMINAL` / 大量 rc=2 断言，QA 冻结口径「只挂载不改断言」⇒ 由 QA 执行退役并给新旧断言基线）。
