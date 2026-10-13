# ADR：舰队 pane 创建与布局的显式目标寻址（派生宿主窗口）

- 状态：**已接受** · 日期：2026-10-13 · 出具：arch-designer（T517-arch 终签）· 落地：rd-infra
- 指针：PRD `docs/prds/2026-10-13-t517-derived-pane-window.md`（§三/§五/§七 AC8·§九 D1–D4）· Issue #33 · 分支 `feat/33-derived-pane-window`
- 修订对象：`2026-10-12-non-tmux-host-spawn.md` 决策 1 阶梯②「当前窗口分屏」与其「D5 的坑」中「跨窗口需改目标寻址」的挂账；本文落地该挂账。**为何另立一篇**：被修订篇已 80 行（超 ADR ≤60 行上限），且本决策含独立不变量与对照表，另立可保两篇各自可读、旧篇只留指针不双写。

## 背景

- 现象：用户切到其他 window 后 `ensure`（含 `--task` 派生）把新 pane 建到用户视图所在 window，并对该 window 写布局 / `main-pane-width`。
- 根因：`spawn_tmux` 的 `tmux split-window -h` 与整条布局链**全部无 `-t`**；tmux 无 `-t` 时目标 = 当前窗口（有 attached client ⇒ 用户视图），与调用者 pane 无关；窗口选项同样外溢。
- 实测（本机 tmux 3.7c，隔离 server，2026-10-13）：`split-window -h -t @W` 落指定 window 且**不改变任何 session 的 current window**；`set-window-option -t @W` / `select-layout -t @W` 仅作用于 @W。

## 决策

1. **目标显式化不变量**：凡「创建 pane / 应用布局 / 写窗口选项」的操作**必须带显式目标**，禁止依赖 tmux「当前窗口」隐式解析。
2. **目标 = 派生宿主窗口**（调用者 pane 所在 window），非「用户当前视图」。`-t` 贯穿 `split-window`、`select-layout`、`set-window-option`，以及尺寸 / pane 数读取（窄列守卫按**宿主窗宽**生效）。
3. **定位链**（入口 `resolve_host_window()` 一次性解析为 `@<window_id>`，多角色复用，新增 ≤1 次 tmux 调用）：
   `NAO_TMUX_HOST_WINDOW`（显式覆盖，`display-message -t` 探测归一化）> `$TMUX_PANE` → `#{window_id}` > 名册唯一命中（`list-panes -a` 建 pane→window 表 + 本仓 cwd 过滤 + 活 pane + 窗口去重后唯一）> **warn + skip**。
4. **L4 = warn + skip（不创建该 pane）**，禁止「无 `-t` 续建」（后者即拆用户视图）；降级不 `die`（不劣化 rc、其余角色继续），每级 warn 带原因且可区分。
5. 单窗口 / 调用者即宿主 ⇒ 与修前逐值零回归；本决策只改 `$TMUX` 分支（②）；非 tmux 阶梯 ③④⑤、`new-session -d`、`status`/`close` 定位均不动。

## 对照过的备选模式（含不采纳理由）

| 方式 | 条件 | 代价 | 结论 |
| :-- | :-- | :-- | :-- |
| 维持现状（无 `-t`，依赖当前窗口） | — | 拆用户窗口 + 选项泄漏 | **不采纳**（T517 缺陷根因） |
| 派生宿主窗口寻址（决策 2/3） | 有调用者 pane | 全链贯穿 `-t`；L4 可能不建 | **采纳** |
| 调用者 pane 精确寻址（`-t $TMUX_PANE`） | 需更细粒度 | 布局/选项仍须 window 级 ⇒ 两套寻址 | 不采纳：收益不抵复杂度、语义不统一 |
| 先 `select-window` 切宿主再操作 | — | 移动用户视图 + 竞态 | 不采纳：违 NFR「不得移动用户视图」 |
| 每角色独立 window / session | — | 失同屏协同 | 不采纳（既有结论，同 T513 §D5 坑） |

## 实施闸门（给 RD 的判定式）

```text
② $TMUX 分支：
  HOST_WINDOW = NAO_TMUX_HOST_WINDOW ─probe→ 空? → TMUX_PANE→#{window_id} → roster(cwd+live+唯一窗) → 空
  空  ⇒ warn（完整原因链 + 提示设 NAO_TMUX_HOST_WINDOW）+ skip（禁止无 -t 续建）
  非空 ⇒ split-window -h -t HOST_WINDOW；布局/选项/尺寸/list-panes 全部 -t HOST_WINDOW
        split 失败（含宿主窗已关竞态）⇒ 既有 serr warn + skip，rc 不劣化
```
- 显式覆盖非法（关窗 / 垃圾值）⇒ warn + 沿链降级，**不 die**（die 会吞掉其余角色）。

## 后果与风险

- 正面：新 pane / 布局 / 选项只作用于宿主窗口；单窗口零回归；降级链可观测、不静默。
- 风险：① L3 名册推断可能命中错窗（T513 曾见 `tmuxPane` 错注册）⇒ 已用「活 pane + 唯一窗 + warn 标来源」收窄；② 批次内宿主窗被关 ⇒ 逐角色 skip（可接受）；③ `NAO_TMUX_HOST_WINDOW` 用裸窗口名跨 session 有歧义 ⇒ 文档建议用 `@id`；④ 一次性解析不重解析 ⇒ 用户中途切窗不影响（符合语义）。

## 待 PM 拍板

- D-A：L4 采「warn + skip」是否确认——PRD §五「不回退污染」已含此意，但 §九 D1 / AC5b 沿用「warn + legacy」措辞；建议按本文把 PRD 措辞改为「warn + skip」。
- D-B：L3「唯一窗即采信」的证据级别是否接受；或降为「只 warn、不采用」。
- D-C：`NAO_TMUX_HOST_WINDOW` 是否允许跨 session（D4 已允许派生宿主跨 session；显式覆盖是否同样放开）。

## 参考来源

- tmux(1)：`-t target-pane`（`split-window` / `select-layout` / `display-message`）、`list-panes -t target`（缺省 = 当前窗口）、window id `@N`（`session:window` 目标形式）。https://man.openbsd.org/tmux.1 · 访问 2026-10-13
- 本机实测（2026-10-13，tmux 3.7c，隔离 socket）：`split-window -h -t @W` 不改 current window；`set-window-option -t @W` 不外溢；跨 session `-t @W` 生效。
- rd-infra 勘查回执（[T517] done(full)，2026-10-13）：5 组隔离实验 + 真实 server 旁证；根因与证据由 PRD §一 收录。

- 修订：2026-10-13 首版（T517-arch 终签）
