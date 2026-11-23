# PRD · 支持 herdr desktop app 作为第二后端 · T562

- 立项：2026-11-24 · 通道 `feat` · 目标版本 **v0.30.0 MINOR** · Issue [#168](https://github.com/Nathan3303/nao-skills/issues/168)
- 来源：用户 2026-11-22「舰队机制配合 herdr desktop app」+ 2026-11-23 三次拍板（先跑三步验证 / T555 收尾后立刻开 / **形态 = 双后端并存**）
- 前置：可行性笔记 `docs/research/2026-11-22-herdr-desktop-app.md`（2026-11-23 已按实测订正）

## TL;DR（≤5 行）

让舰队能跑在 **herdr desktop app**（非 TUI）里：`NAO_TERMINAL=app` 时用 `hc` 起会话、用 `herdr.space/tab` 标签做放置、用 OSC 7501 的 `state` 判忙闲。TUI 后端**照旧**（默认不变）。两套程序**不共享 agent**，所以这是「新后端」而不是「同一个舰队换个窗口看」。

## 一、问题与证据

用户实际诉求：在桌面版里工作，希望舰队机制可用。当前**明确不支持**：在桌面版终端里跑 `ensure` 会 fail loud（`HERDR_ENV=1` 缺失，`exit 3`）——这是设计内的闸门，不是 bug。

**2026-11-23 PM 实测三步（已通过，构成可行性硬证据）**：

1. `hc run --bg --keep -- pi --name probe` ⇒ 终端 `t4`，`agent=pi`。
2. `hc get t4 --json` ⇒ `status={"app":"pi","state":"idle"}`（**OSC 7501**，即 TUI `agent_status` 的等价物）+ `turn`。
3. 放置：带 `--label herdr.space=<id> --label herdr.tab=<id>` 起终端 ⇒ `hc ls --json` 的 `where` = `nao-skills / 1`（真落进目标 space/tab）；**未知 id 会新建 space/tab**（名字按首终端 cwd）。

**身份 env 同构**（实测，`hc` 起的终端）：

```
HC_SCOPE=…  HC_TERMINAL_ID=t3  HC_TERMINAL_SOCKET=/run/user/1000/herdr-core/default.sock
```

对照 TUI 的 `HERDR_ENV=1` / `HERDR_SESSION` / `HERDR_SOCKET_PATH` ⇒ 闸门可以照同一套形状写，只是键名与语义不同。

**可行性笔记里「放置无 CLI」的旧判断已作废**（那是漏读桌面版 `AGENTS.md`「标签收养」一节得出的错判）。

## 二、目标指标

- `NAO_TERMINAL=app` 时 `ensure` / `status` / `close` / `cleanup` 四个子命令可用（`check` 增加 app 侧前提探测）。
- **默认后端仍 = herdr TUI**：不设 `NAO_TERMINAL` 的既有用户零行为变化（AC1 逐字一致口径沿用 T555 的 D5 形状）。
- 放置断言以「`hc ls --json` 的 `where` 真的到了目标 space/tab」为准，**不以「JSON 写成功」为准**（笔记 R3 的否定条件）。

## 三、范围 / 非范围

**范围**

- **M1 后端抽象第二实现**：新增 `term-impl-app` 区间（门面 `_term_*` 的 app 臂），`term_backend()` 允许 `app`，`check` 增加 app 前提节；**默认仍 herdr（TUI）**。
- **M2 身份闸门**：`HC_SCOPE` + `HC_TERMINAL_ID` + `HC_TERMINAL_SOCKET` 三件套；缺任一 ⇒ `exit 3` + 一行指路（形状照 TUI 版）。
- **M3 放置**：space = 仓（读该仓现有终端 label 得 space id；没有则用新 id 让 app 自建）、tab = 角色/任务（label = 会话名）；标签写入走 `hc run --label`。
- **M4 就绪与忙闲**：`hc get <t> --json` 的 `status.state`（working / idle / blocked / done）对齐 `agent_status`；**`state_change_seq` 无等价物**（`turn` 只在 `done` 时 +1，不能当变化证据）⇒ **就绪门 = `status.app=pi ∧ state=idle`**（辅以 `status_ms`），忙闲闸门用 `state ∈ {working, blocked}`。**不照搬 TUI 的 `state_change_seq` 判据**。
- **M5 回收**：`hc kill` + `hc rm`；`keep` 语义显式处理（`keep:true` 时程序退出 pane 不关 ⇒ 回收必须显式 kill）。
- **M6 文档**：README 前置环境加「两种终端：herdr TUI（默认）/ herdr desktop app」+ `docs/INSTALL.md` 新节「desktop app 后端（`NAO_TERMINAL=app`）」；**必须写死「两套程序不共享 agent」**（同一仓在 TUI 起的舰队，app 里看不到）。
- **M7 测试**：用例要能**不碰用户真实 app** 地验证（隔离手段见 §六 R1）；新增 `cases/44`（app 后端契约：身份闸门三态 / 放置 where 断言 / 就绪与忙闲 / 回收）。

**非范围**

- 不做「TUI → app 自动迁移 / 双跑同步」（两套程序不共享 agent，技术上不可行）。
- 不做跨机（`hc --on <machine>`）；不做 mod/layout 生成（本方案只用 label 收养）。
- 不改默认后端（默认仍 herdr TUI）。
- 不引入 `oil-ui` 之类第三方文本（与本批无关，仅提醒）。

## 四、用户场景

1. **桌面版用户**：桌面版里开一个终端 → `export NAO_TERMINAL=app` → `ensure pm rd-fe…` ⇒ 每个角色一个 tab，落在该仓的 space 里；`status` 显示在线与忙闲。
2. **TUI 用户**：什么都不改，行为与 v0.29.0 逐字一致。
3. **两者并存**：同一台机器上，TUI 的舰队与 app 的舰队**互相看不见**（各自 `status` 只列自己的）；文档必须显式说明，避免「装了 app 却看不到现有舰队」的误解。

## 五、业务规则

- **BR1**：`NAO_TERMINAL` 取值集合 = `herdr`（TUI，默认）/ `app`；其他值（含 `tmux`）⇒ `rc=2` 用法守卫（沿用 T555 D2）。
- **BR2**：放置断言必须先写、后验：写标签 → 读 **`doc.get herdr-app`（`version:10`）** 判「终端地址是否在目标 tab 的 root 树」→ 不匹配 ⇒ **fail loud 并回滚**（kill 自己刚建的终端），禁止「写成功就算放置成功」。
  - **订正（arch 实测 2026-11-24）**：**不`where` 当结构判据** —— `where` 是 app 写的展示 label，实测已与 doc 的 space folder 不一致（`t2` 即例）。`hc ls` 的 `where` 降为**辅助显示**，不进断言。
- **BR3**：身份不可判定（三件套缺、socket 不落在 app core 下）⇒ `exit 3`，**不猜**。
- **BR4**：`keep` 语义**按实测订正**：`--keep` **不保 pane** —— 程序退出 ⇒ 终端 `finished` + pane 关闭（`hc ls` 隐藏、`--all` 可见）；keep 的真实语义 = **core 丢失后原地换 shell（labels 保留）** ⇒ 会留「幽灵 pane」，**身份判据不得只用 label**。`close` 顺序固定 = **`hc kill` → `hc rm`**（对 live 终端直接 `rm` 会 `rc=1 kind:live`）；`kill` 会连带子终端。
- **BR5**：两套程序不共享 agent ⇒ 文档、`status` 输出、错误文案都不得暗示可以互见。

## 六、NFRs / 风险

- **R1 测试隔离 = ③ 部分隔离（arch 2026-11-24 实测定论，见 `docs/reports/168-arch-review.md`）**：
  - **核心面可自动化**：`XDG_RUNTIME_DIR=/tmp/apr XDG_STATE_HOME=/tmp/aps HC_SESSION=nao-t4-x hc …` ⇒ 起**私有 core**（pid/socket/state 全在私有根），默认 `hc ls` 逐字不变。
  - **放置/收养不可自动化**：app 窗口不在跑时，带 `herdr.space/tab` 标签起终端 ⇒ `where` 恒 `None`、`doc.get` 不含该终端（kill+rm 后零残留）⇒ **收养是 app 写的，core 只存标签**。`HERDR_APP_HOME` 只换窗口控制 socket、不换 core（仍写用户布局）⇒ **不是沙箱**。
  - **用例形态**：真 `hc` + 私有 core 测三件套闸门 / 往返 / `status` 状态机（OSC 7501 小脚本，不必真 pi）；`hc` 桩测 `--label/--no-parent/--keep` 与「写 → 读 doc → 回滚」；**真实收养、ensure/close 的 UI 效果 = `[SKIP]` + 转人工验收**（`cases/44` 里逐条注明理由）。
- **R2 契约非稳定 API**：`labels` / `where` / `status` 是 app 的文档契约但不是版本化 API ⇒ 需**能力探测 + fail loud**（例如 `hc get --json` 无 `labels.herdr.space` ⇒ 明确报「app 版本不支持放置」）。
- **R3 命名与空间语义差**：TUI 1 workspace = 1 仓；app 的 space 名字随首个终端 cwd 变 ⇒ 必须用**显式 label id** 而不是名字匹配。
- **否定条件**：若 `hc` 无任何方式在不污染用户界面的前提下被测试 ⇒ 本批**只做「可读面」（status/就绪/忙闲）+ 明确标注 ensure/close 属人工验收**，不硬塞自动化。

## 六之二、实施护栏（arch 实测，硬性）

- `hc run` **必须 `--no-parent`**：默认会被记为父终端的子终端，父会话一结束就带走子终端（实测 kill 父 ⇒ 子同死）。
- app 臂连接**用 `HC_SOCKET=$HC_TERMINAL_SOCKET`**：`HC_TERMINAL_SOCKET` **不参与路由**，`HC_SESSION` 拼错会静默新建一个空 core（假成功）。
- **失败判据看 JSON `error` 字段，不看 rc**（`hc` 有些错误路径 rc=0）。
- 未验项 **R-b**（app 关闭期间起的终端，开窗后是否补收养）：因 AC3b 已禁止「窗口没开就 ensure」，此路径对本批**无影响**；登记为观察项（到期 2027-05-24）。

## 七、AC

### 主路径

- **AC1** `NAO_TERMINAL` 未设/`herdr` 时，`ensure`/`status`/`close`/`cleanup` 输出与 v0.29.0 **逐字一致**（同夹具两树 diff 空；允许面沿用 T555 D5 四类）。
- **AC2** `NAO_TERMINAL=app` + 三件套齐 ⇒ `ensure` 能在 app 里起会话并落进目标 space/tab（`hc ls --json` 的 `where` 断言），`status` 能列出并显示忙闲，`close` 能回收且不留僵尸。

### 异常

- **AC3** 三件套缺任一 / socket 不在 app core 下 ⇒ `exit 3` + 恰一行指路；`NAO_TERMINAL=<其他值>` ⇒ `rc=2`（不回归 T555）。
- **AC3b（新增 · arch 实测）** **app 窗口不在跑**（`herdr-app status` 无窗口）⇒ `ensure` **`exit 3` + 恰一行指路**（「桌面版没开 / 打开后重试」），**不得**先起终端再回滚（窗口未开时收养永不成 ⇒ 必然空转）。
- **AC4** 放置失败（标签写了但 `where` 没到）⇒ **fail loud + 回滚自己建的终端**，不静默留孤儿。

### 边界

- **AC5** `keep` 语义（订正后）：core 丢失留下的「换壳」终端**不得**被判成「真在跑」（不得只凭 label）；`status` 必须区分「真在跑 / 残留」，`close` 走 `kill` → `rm` 且清理干净。
- **AC6** 两套程序不共享：TUI 起的舰队在 `NAO_TERMINAL=app` 下 `status` **不得**列出（反之亦然）；文档写死。

### 负向闭环

- **AC7** 静态 lint：app 臂不得裸调 `hc`（必须走唯一入口 `_term_app_exec`），仿 `t4_scan_term_herdr_forbidden`；正控必红。
- **AC8** 契约缺失时 fail loud：桩 `hc` 返回无 `labels`/`status` 的 JSON ⇒ 明确报「app 版本不支持」+ 指路，不得退化成「当作空闲」。

### 设计一致性

- **AC9** ADR `docs/adr/2026-11-24-herdr-app-backend.md`（新增第二后端 = 结构性决策），含否定条件与回退路径；`docs/research/2026-11-22-herdr-desktop-app.md` 保留为证据。
- **AC10** 文档：README 前置环境 + `docs/INSTALL.md` 新节 + `AGENTS.md` 端前提行同步；`check` 端前提一致性 warn 覆盖新表述（两种后端）；`npm test` 全量 + `check` rc=0。

## 八、上线闭环

- arch-designer：ADR + R1 测试隔离定论（必过）。
- rd-infra：M1–M7 实现；qa：一轮（重点 AC1 零回归 + AC3/AC4 异常面）。
- 合并后发 **v0.30.0 MINOR**（新增后端能力）。
- 三出口：app 侧的 mod/layout 生成、跨机、自动迁移 均登记为非范围或接受含到期。

## 九、变更治理

- 若实现期发现 `hc` 契约与笔记不符 ⇒ **先实测再改 PRD**，不按记忆写。
- 本批不改卡（`ensure`/`status` 语义未变，只多一个后端）；若必须改卡 ⇒ bump + 广播。
