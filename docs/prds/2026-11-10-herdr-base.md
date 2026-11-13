# 基座替换：舰队从 tmux 迁到 herdr（三期串行）

> TL;DR
> **做什么**：把舰队基座从 tmux 换成 herdr，pane 身份/归属/就绪判定改用结构化事实而非启发式猜测。
> **给谁**：PM 与 6 个角色会话（本仓 + 下游仓）。
> **成功标准**：三期全部验收后 herdr 为默认后端，tmux 可开关回退；门禁在两种后端都能全绿且数字可互印。
> **不做什么**：不做可见 workspace / 混合形态 · 不修第三方 `pi-intercom` · 不做跨机。
> **依据**：arch spike 实测（2026-11-09/10），报告 `~/.local/share/nao-spike/M20261109-herdr-spike-report.md`（不入仓）。

## 一、问题证据

- **身份靠猜，且猜错过多次**：现在定位会话靠「终端标题契约 → 名册 → 未认领 pane 兜底」三层启发式；PS1 会改写标题，曾致 `cases/19` 负载相关假红（#90 定性的根因）。
- **pane id 是 server 局部命名空间**：跨 server 比较 pane id 会撞号，曾致自面板守卫误拒、并有误杀风险（T530 实测）。
- **归属靠反推**：`status` 用 pane cwd + `repo_contains_path` 三态 fail-closed 反推「这个会话属于哪个仓」，为此写过整套仓维度判定 + ADR，仍踩过他仓误报与同名互串。
- **就绪靠轮询**：`wait_title` 5s 有界重试；arch 实测同类问题在 herdr 侧表现为「已 idle 时 `wait` 6ms 假阳性」，属同一类错误（先等停，没先确认它动过）。
- **多仓并发会静默跳过**：名册全局唯一，两仓同时 `ensure rd-fe` 时第二个被判「已在运行」而**静默跳过**（`nao-fleet.sh:625` 注释有实测记录）。

## 二、目标指标

- **假红归零**：身份/归属/就绪三类 flake 在连续 20 次门禁中 0 次（现状：`cases/19` 型曾单日 5 次）。
- **猜测代码净减**：herdr 分支内 `pane_title` / `display-message` / `list-panes` 调用数 = **0**（grep 门禁，行数不作判据）。
- **静默跳过归零**：多仓并发 `ensure` 不再出现「以为拉起来了其实没有」（改为 fail loud 或按仓分区成功）。
- **双后端可比对（替代原「数字可互印」）**：两后端各跑自己登记的用例集且 rc=0；**共享集**用例 ID 相同、**每例断言标题序列**与 golden 清单逐字一致；后端专有例登记于 `tests/t4/backends/<backend>.txt`（每条写理由 + 到期），未登记用例输出 **PENDING 并点名**，不得静默 SKIP；汇总行打印「共享 N / 本后端专有 M / PENDING K」。
- **口径注**：用例数唯一出处 = `bash tests/t4/run.sh --list | tail -n +2 | wc -l`（当前 **25**，编号 01–10 + 12–26，无 11）。

## 三、范围 / 非范围

**范围内**
- 一期：后端抽象层（新增 `tests/t4/lib-backend.sh`）+ 后端自检例（新增 `27-backend-selftest.sh`）+ 多仓命名空间分区；**D 类 10 例（09/12/15/19/20/21/22/23/24/25）的迁移归二期**（与生产路径同批）。
- 二期：生产路径的身份、归属、就绪、回收四段改用 herdr 结构化事实。
- 三期：布局与多仓形态（workspace/tab 映射），herdr 转默认，tmux 降为 `NAO_TERMINAL=tmux` 回退。
- 文档与前提：`AGENTS.md` 运行前提红线、`README`/`INSTALL` 安装前提、协议脚注。

**非范围**
- 不做可见 workspace（形态 A）与混合形态（形态 C）：用户 2026-11-10 已定为「专用 session 后台」，理由：不污染桌面且隔离已实测可行。
- 不修 `pi-intercom` 的 `herdrLocation`：它只是位置标签，调度用的 `idle/thinking` 来自 pi 生命周期事件；且属第三方 npm 包，本地补丁会被 `pi update --extensions` 覆盖。
- 不做 `--machine` 跨机舰队：本机单机场景无需求，跨机会引入远端状态一致性问题。
- 不改 pi 本身、不为其他 Agent 宿主适配：本仓红线（仅 pi 宿主）。
- 不改下游仓 `AGENTS.md`：用户 2026-11-02 口径「各仓自行升级」。
- 不承诺 herdr 0.x 内部 API 稳定：pre-1.0 阶段，用回退开关与 fail loud 兜。

## 四、用户场景

- **PM 起舰队**：PM 在专用 herdr session 里 `ensure` 七角色，用户桌面不被占用；需要看时 `herdr session attach`。
- **多仓并行**：两个仓同时起舰队，会话名按仓分区，各自 `status` 只看到自己的会话，不互相跳过。
- **派活与回执**：PM 用 intercom 派发；忙闲闸门依据 agent 状态（`idle`/`done` 可投递，`working`/`blocked` 不可，`unknown` 保守不可）。
- **回收**：`close` 仍按「在跑 turn / 台账未推进」闸门拒绝；实验场必须 stop+delete，避免回放上一轮布局。
- **下游仓升级**：下游 PM 按 README 装 herdr 后即可起舰队，无需改自己的 `AGENTS.md`。

## 五、业务规则

- **BR1 零回归优先**：tmux 后端在每期验收时逐字等价；三期验收通过前不得削弱它。**三期改写（2026-11-11 PM 裁定）**：B1 立的「未设 == `=tmux` 两种拼写同 md5」在默认翻转后**按设计失效** ⇒ 改为「显式 `=tmux` ⇒ 对**旧** golden；未设 ⇒ 对**新 herdr golden**；**并新增反向断言「两者必须不同」**」（防 flip 未生效仍全绿）。涉及断言：`cases/06`（默认字面量 / 未设零字样 / 空串）与 `cases/28`（双拼写相等）必须同步改写。
- **BR2 禁读终端标题**：herdr 后端不得用终端标题做身份或就绪判定。
- **BR3 身份只取结构化字段（2026-11-10 按 herdr 0.9.1 实测订正）**：会话名取 `pane.label`（spawn 前写入，交叉校验 `process-info.argv --name`）；仓归属取 `pane.cwd` / `foreground_cwd` + 现有 `repo_contains_path`（谓词不变）；跨系统同人取 `agent_session.value`；存活取 `process-info.foreground_processes[].name=="pi"` ∧ `agent list` 有条目。**`workspace.identity_cwd` 在 0.9.1 API 中不存在**（仅出现在持久化 snapshot 结构），原表述作废；`pane_id` / `terminal_id` 均为 **server 局部** ⇒ 所有 key 必须是 `(session, pane_id)`。
- **BR4 实验场必须 stop+delete**：只 `stop` 会回放上一轮 pane 布局（spike 实测）。
- **BR5 不跨会话隐式操作**：不得从 herdr 外部控制聚焦会话；跨会话必须显式 `--session`。
- **BR6 清环境渗透（含反向护栏）**：起 server 前 `env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR` 并**枚举清除** `HERDR_*`（`for v in $(env | grep -o '^HERDR_[A-Z_]*'); do unset "$v"; done`）。四条可执行判据：① pane 内 `env | grep -c '^TMUX'` == 0；② pane 内 `HERDR_SESSION` == 期望名 且 `HERDR_SOCKET_PATH` 前缀 == 实验根下该会话目录；③ 实验根只隔离 `XDG_CONFIG_HOME`（**不得**指 `XDG_STATE_HOME`，mise 等工具会写它）；④ 任何 herdr 调用缺 `--session` ⇒ **FAIL**（实测无 `--session` 时会静默读到用户 `default`）；**唯一白名单 = `herdr --version`**（纯元数据、不触会话，QA P3-3 实测无用户文件改动），其余调用点必须在唯一入口内。
- **BR7 状态映射（含权威源）**：`idle`/`done` = 可投递；`working`/`blocked` = 不可投递；`unknown` = 保守不可投递。**权威源 = `agent list`/`pane list` 的 `agent_status` + `state_change_seq`**；`agent explain` 仅诊断、不得作判据（实测与 `agent list` 双源矛盾）。`done` **对 pi 不可达**（2026-11-10 实测：herdr 集成只发 `idle|working|blocked`，`PaneAgentState` 枚举无 `done`）⇒ 保留该分支但标注「**无 pi 路径，死分支**」，**禁止在用例里伪造 `done` 当验收**。**状态合成口径（2026-11-10 B3 QA 裁决，条件式）**：`pane report-agent` 对**已接 `full_lifecycle_hook_authority` 的 pi pane 是静默 no-op**（rc=0、空输出、`agent_status`/`state_change_seq` 不变）；仅**未接 authority 的桩 pane** 可合成 `idle|working|blocked|unknown`。判据 = `agent list[].screen_detection_skipped` / `explain` 的 `skip_reason`。**后果**：已接 authority 的 pi 会话只能用**真 turn** 验忙闲，桩只适用于无 authority 的 pane。
- **BR8 命名空间按仓分区（命名契约单一函数）**：多仓并发时会话名/agent 名带仓标识，禁全局同名；同仓重复 `ensure` 仍按「已在运行」判重。命名格式抽**单一函数**（二期重写同批函数时须逐字保持契约，避免返工）。
- **BR9 不碰用户 default session**：测试与生产一律使用独立 session，`default` 的快照在实验前后必须逐字一致。

## 六、NFRs（业务基线，技术指标由 arch 转译）

- **可回退**：任一期的失败都能单条 revert，或切 `NAO_TERMINAL=tmux` 回到改动前行为。
- **可复现（替代原「数字可互印」）**：共享集用例 ID 相同且每例断言标题序列与 golden 逐字一致；专有例登记 + 到期；PENDING 点名；差异必须可解释。**不比断言总数**（数相等 ≠ 语义等价，且可用填充断言凑数）。
- **依赖边界**：herdr ≥ 0.9.1 / protocol 22；协议或 API 破坏性变更必须 fail loud，不得静默降级。
- **时延不劣化**：就绪判定不得劣于现状（tmux 侧 5s 有界）。
- **隐私**：不得把用户 `default` session 的 pane 内容或结构写入仓库、日志或报告。
- **离线可用（口径订正）**：`check` / `npm test` 在无网环境仍可跑。注意 herdr **自身**会 `curl herdr.dev`（更新检查 / agent 检测），离线时只多几行失败日志、不中断（QA P3-5 实测），且拆场后这些 curl 可能比 server 多活约 20s（`--max-time` 上限自行退出）⇒ **不得声称「herdr 实验场零网络」**，只承诺「用例判据不依赖网络」。

## 七、AC（分三期，逐条 Given/When/Then）

**一期：后端抽象层 + 后端自检 + 命名空间分区（两步走）**
- AC1.1 Given `NAO_TEST_TERMINAL=herdr`，When 跑 `npm test`，Then **登记集**（`tests/t4/backends/herdr.txt`）全部执行且 rc=0、SKIP=0；未登记用例输出 **PENDING 并点名**（不得静默 SKIP）。
- AC1.2 Given 未设置 `NAO_TEST_TERMINAL`（默认 tmux），When 跑 `npm test`，Then 输出与改动前**逐字 diff 空**（含每例断言标题序列；旧会话名在 tmux 后端逐字不变）。
- AC1.3 Given herdr 实验场跑完，When 检查，Then 实验根内 `sessions/` 为空 + 无残留 herdr/pi 进程 + 用户 `default` 在本次实验视角**不可见**（快照与 tmux pane 表 diff 空）。
- AC1.4 Given 两个用例并发跑在各自 herdr 实验场，When 同时执行，Then 互不可见（`terminal_id` 交集为空）且会话名唯一化（含 `$$`）、各自 `HERDR_SESSION` 不同、起 server 前已清 env。
- AC1.5 Given herdr 不可用，When `NAO_TEST_TERMINAL=herdr`，Then 分两类：**协议/版本不兼容**（判据 `herdr api schema` 的 `protocol: 22` + `herdr --version`）⇒ SKIP 并给原因；**stale `HERDR_SESSION` / 会话名冲突 / 实验根不在 cache 下** ⇒ **FAIL**（fail loud，不得 SKIP）。
- AC1.6 Given 两个仓同时 `ensure rd-fe`，When 第二仓拉起，Then 不撞名（按仓分区）且各自 `status` 都能看到自己的会话；负控：并发 `ensure` 必须「按仓分区成功」，不得走「已在运行」静默跳过。
- AC1.7 Given 后端抽象层，When 连跑 2 次，Then `NAO_TEST_TERMINAL` 两后端均 rc=0 且 effect=0（幂等），server 就绪用轮询（50×100ms、5s 上限、超时 fail loud），禁固定 sleep。

**二期：生产身份、归属、就绪、回收**
- AC2.1 Given herdr 后端，When `ensure` 起七角色，Then 每个 pane 的会话身份取 `pane.label`（+ `process-info.argv --name` 交叉校验）、仓归属取 `pane.cwd`/`foreground_cwd`，**不读终端标题**；label 在而 agent 无（幽灵 pane）⇒ 不判在线；`agent_session=null`（集成缺失）⇒ 点名 fail loud，不得退化成 unknown 静默。
- AC2.2 Given 某会话完成一轮，When `status` 判在线与忙闲，Then 按 BR7 映射给出可投递/不可投递，`unknown` 判不可投递。
- AC2.3 Given 等待就绪，When pi 启动，Then 先观测到离开 `idle` 再等 `idle`（禁假阳性），超时有界并 fail loud。
- AC2.4 Given `close` 一个在跑 turn 的会话且未加 `--force`，When 执行，Then 拒绝并给可执行指路（语义与现状等价）。
- AC2.5 Given 在 tmux 内起的 herdr server（环境渗透），When 跑舰队，Then 清 `HERDR_*`/`TMUX*` 或显式 `--session`，身份判定不受污染。
- AC2.6 Given `NAO_TERMINAL=tmux`，When 跑全部命令，Then 与改动前逐字等价（零回归硬判据）。
- AC2.7 Given D 类 10 例，When 二期完成，Then **5 例迁 shared（19/20/21/23/24）** + **3 例迁 own（09/15/22，到期 2027-06-30 且逐条写理由）** + **12/25 不迁（tmux 专有：12 = 派生落点/宿主窗口属三期布局，25 = tmux 宽度算式）**，并在 `herdr.txt` 注释区写明「tmux 专有，三期重判」；命名契约**逐字保持**（一期 BR8 单一函数，不得改名）。**2026-11-10 订正：原「10 例全迁」不可达，PM 未核实即写入，作废。**

**三期：布局与多仓形态，herdr 转默认**
- AC3.1 Given 七角色（herdr 后端），When `ensure`，Then 布局 = **1 workspace/仓（label=scope）+ 1 tab/角色（tab label=角色），每 tab 恰 1 pane**；判据（结构，非几何）：每角色 tab `pane_count == 1` ∧ `pane_id` 唯一（`tab list`/`pane list` 的 `tab_id` 字段）；**迁移无损**：`pane move <pane> --tab <tid> --split right` 后 `pane_id` 不变、被搬空的 tab 自动关闭、`status` 仍在线。
- **AC3.1 口径偏差（2026-11-13 · Issue [#112](https://github.com/Nathan3303/nao-skills/issues/112)，不改原文）**：「1 workspace/仓」不变，但 **label 取值规则已被 ADR `docs/adr/2026-11-13-herdr-workspace-scope-key.md` 取代** —— `label` = 已声明 scope，否则**仓 slug**；原「无 scope ⇒ `HERDR_SESSION`」回退删除（实测会把跨仓会话落进调用方 workspace）。其余结构性判据（每 tab 恰 1 pane、`pane_id` 唯一、迁移无损）继续有效。
- AC3.2 Given 空间不足，When `ensure`，Then 按 J1–J5 判：**J1** 放置后 `pane layout` 量测每 pane `rect.width ≥ TERM_MIN_COLS` ∧ `height ≥ TERM_MIN_ROWS`（默认 60×10，常量可覆盖）⇒ 不足只 **warn 不 die**（rc 保持 0，沿用 D3）；**J2** 结构判据见 AC3.1；**J3** 静态证明：herdr 实现区 `grep -c 'TMUX_MIN_PANE_WIDTH|main_row2_min_col|137|184'` == 0；**J4** 小空间可注入（私有根 + `[server] headless_cols/headless_rows`，实测 60×20 生效）⇒ warn + 指路 + **无 0 尺寸 pane**；**J5** 失败文案三件套：哪个 pane 多少列/行 < 阈值 → 三个可执行动作（调 `[server] headless_*` / attach 后重排 / 切布局）→ 文档指针；且**不半启动**。**「0 行 pane」这类不可用态计 `SPAWN_FAIL`**（否则摘要说「成功 7」而实际读不了）。
- AC3.3 Given 未设 `NAO_TERMINAL`，When 跑全部门禁，Then **herdr 为默认**且全绿；`NAO_TERMINAL=tmux` 仍全绿。**不自动回落**（PM 裁定 D2）：herdr 未装 / protocol≠22 / 非 herdr pane 内 ⇒ **fail loud（exit 3）**；**6 条 exit 3 文案必须全部含 `NAO_TERMINAL=tmux` 指路**（现状只有 2/6 条有 ⇒ 三期必改，静态断言全扫）；`check` 在「默认 herdr 且缺可执行」⇒ **置红**并打同一组命令（装 herdr / `export NAO_TERMINAL=tmux`）。
- AC3.4 Given 一个下游仓，When 按 README 升级，Then 无需改其 `AGENTS.md` 即可起舰队（前提 herdr 已装）。
- AC3.5 Given 真 herdr（私有 `XDG_CONFIG_HOME` + `HOME` + `PI_CODING_AGENT_DIR` + `TMPDIR` 四件全私有），When 跑新增 own 用例 `32-real-herdr-roundtrip.sh`，Then `session-start` → **2 角色**（pm + rd-fe，控时长）→ 就绪七条件 → `status` 双在线 → `close` 一个 → `cleanup` → 断言 `sessions/` 空 + 零残留 + 用户 `default` 不可见；缺 herdr ⇒ 按 AC1.5 SKIP 给原因（不 FAIL）；造价 wall clock 3–6s；**不写用户 `~/.pi`**（`herdr integration install pi` 尊重 `PI_CODING_AGENT_DIR`，实测）。

## 八、上线闭环

- **每期**：分支 → Draft PR → QA 非作者复核 → PM 验收 → RD squash 合并；台账与文档随该期 PR。
- **版本**：一期/二期 PATCH；三期 MINOR（herdr 转默认属行为变更），release notes 必须写清「如何回退到 tmux」。
- **回退**：切 `NAO_TERMINAL=tmux`（保留至少一个大版本）或单条 squash revert。
- **下游**：三期发布后由各仓自行升级（不改其 `AGENTS.md`）；本仓提供一行升级说明与回退说明。
- **完成判据**：三期全绿 + 连续 20 次门禁 0 假红 + 多仓并发无静默跳过。

## 九、变更治理

- **任何一期延期**：按三出口处理（关闭 / 接受含到期 / 转办），记 `docs/tasks-state.md`，不静默挂起。
- **herdr 破坏性变更**：fail loud + 记观察项；不得为兼容而静默降级。
- **不夹带**：形态 A/C、`--machine`、`pi-intercom` 补丁一律另立项；发现即拒收。
- **AC 变更**：需 PM + arch 双签（涉及技术指标时由 arch 转译后再改）。

## 附：优先级

- **战略筛子**：直接服务「PM 单一调度 + 门禁可复现」✓；引入 pre-1.0 依赖（用回退开关 + fail loud 兜）✓；可分期 ✓。
- **MoSCoW**：一期 Must（安全网）· 二期 Must（收益主体）· 三期 Should（布局与默认切换）。
- **RICE**：Reach 28（4 仓 × 7 会话）· Impact 2 · Confidence 0.7（隔离/身份/就绪已实测，布局未验）· Effort 5（三期）⇒ **RICE ≈ 7.8**。
- **Kano**：不 flake = 基本型；attach 看进度 = 期望型；worktree 绑定 workspace = 兴奋型。

## 附三：三期设计评审与 PM 裁定（2026-11-11）

- **结论**：有条件可行。**布局 = A**（1 workspace/仓 + 1 tab/角色，每 tab 1 pane）：零几何算式、迁移无损（`pane move` 后 `pane_id` 不变）、`status` 零改动。不采 B（单 tab 平铺 = 把列宽算式换个形态搬回，且 60×10 对 pi TUI 偏小、attach 尺寸变化会重排）与 C（分组映射表 = 双源，违单一事实）。
- **默认切换 = fail loud，不自动回落**：回落会让默认变**双稳态**（同命令不同机器不同后端）⇒ 破 NFR 可复现，并引入「误判回落 ⇒ 跨后端串台」缺陷类。降痛三件：可复制的两条命令 · release notes 置顶 · `check` 分级置红。
- **回退承诺**：`NAO_TERMINAL=tmux` 保留 **≥2 MINOR 且 ≥90 天**；退役另立项并先发弃用说明；**文档不写死移除日期**。
- **P2 实施补充（2026-11-11 PM 拍板）**：① **测试基座后端默认同步翻 herdr**（`NAO_TEST_TERMINAL` 未设 = herdr，与生产默认一致；`NAO_TERMINAL=tmux npm test` 为回退通道）—— 否则 AC3.3「未设跑全部门禁 ⇒ herdr」在门禁上不可达；发布前置仍须**两后端各跑一次**（显式）。② exit 3 站点实测 **7 条**（herdr 侧，含 `cmd_status` 的「需要 herdr server」），全扫断言逐条含 `NAO_TERMINAL=tmux`。③ `check` 全输出 md5 只在「codegraph 齐备态」断言（该行随环境变，无条件钉会跨机假红）；硬断言 = 首行逐字 + 行数（herdr 3 行 / tmux 2 行）。
- **herdr 不报空间不足**（实测 split 从不失败、pane 可被压到 0 行且无 warn、`pane resize` 静默无效）⇒ 空间判据必须**自测**（J1–J5），**rc 不可作判据**。
- **真机整轮可固化**（订正 B4 的推断）：`herdr integration install pi` **尊重 `PI_CODING_AGENT_DIR`**，实测装到私有目录、不写 `~/.pi`；全新私有 agent dir 无 `lastChangelogVersion` ⇒ **天然不触发 What's New 遮罩**。
- **未验**：attach 客户端尺寸变化后的重排（仅文档口径）· pi TUI 真实最小可用行列 · `pane move` 迁移后 pi 会话长稳（只到 `pane_id`/即时 status 级）。

## 附二：二期设计评审与 PM 裁定（2026-11-10）

- **结论**：有条件可行。二期拆 **4 步**（B1 门面 + `status` 只读判定面 → B2 `ensure`/spawn + 就绪 → B3 `close`/`cleanup` 回收 → B4 D 类迁移 + 登记集 + `check` 终端前提）。
- **模式**：门面 + 双实现并存，**默认 tmux 保持到三期**。BR1 六条机械保证：默认值唯一（grep 恰好 1 处）· 后端差异只允许出现在 `term_*` 门面（业务区禁裸调用，扩 lint）· 未设与 `=tmux` 两种拼写都对 C2 golden md5 · 双向 PATH 桩负控 · 三期只改那 1 行 · `check` 打印生效后端（仅 herdr 模式加行）。
- **PM 六项裁定**：D1 AC2.7 按 5 shared / 3 own / 2 不迁订正 · D2 二期只做最小放置（专用 session 现有 workspace 内起 pane + 写 label），workspace/tab 拓扑留三期 · D3 就绪超时计入 `SPAWN_FAIL` + warn + 摘要，**rc 保持 0**（跨后端 rc 语义必须一致；rc 统一另立观察项）· D4 集成缺失 ⇒ `status` warn + 不可投递，`ensure` die · D5 herdr 模式不保留 `NAO_CLOSE_BUSY_PATTERN` · D6 BR3 按实测字段订正。
- **反假阳性硬判据**：**禁用 `agent wait --until idle` 作就绪门**（实测已 idle 时 6ms 返回、working 时也 rc=0）⇒ 就绪门 = 全条件与（pane 存在 ∧ `foreground==pi` ∧ `argv --name` 匹配 ∧ `agent_session≠null` ∧ `status==idle` ∧ `state_change_seq ≥ 1` ∧ `screen_detection_skipped`），50×100ms + 5s 上限 + 超时 fail loud 逐条报缺。
- **新增缺陷类（herdr 特有）**：**幽灵 pane** —— `stop→restart` 回放后 label 仍在但 `agent_session=None`、`agent list` 空（实测）⇒ `label 命中 ≠ same`，否则 `ensure` 会静默跳过。
- **生产路径环境渗透**：herdr server 若从 tmux shell 起会把 `TMUX/TMUX_PANE` 传给 pane ⇒ ① 蒙过 `require_tmux` ② pi 的 intercom 注册写入伪 `tmuxPane`，反过来让 tmux 侧舰队定位到它（跨后端串台/误 kill）⇒ BR6 扩到生产 + herdr 分支源码禁出现 `TMUX`/`TMUX_PANE`（grep 门禁）。
- **未验**：`blocked` 态真机触发 · label ≤48 上限 · 三期 worktree 下 `cwd` 归属 · herdr 长期稳定性 · `pane close` 对 `blocked` 会话行为。

## 附一：arch 评审结论与 PM 裁定（2026-11-10）

- **结论档**：有条件可行。评审要点已写回上文 §二/§三/§五/§六/§七（11 条必改项全采纳）。
- **PM 四项裁定**：① AC1.1 采「登记集 + PENDING 点名」窄口径（全用例 herdr 绿在一期不可达，强达标只能靠 SKIP 掩盖）；② 原「旧名兼容」AC 删除（herdr 后端无旧会话，tmux 侧由 AC1.2 零回归覆盖，留着是自造永久债）；③ `done` 保留在映射内并标注「不可合成，二期用真 turn 验」，权威源钉 `agent list`/`pane list` 的 `agent_status` + `state_change_seq`；④ 双后端比对改 golden 断言标题序列，不比总数。
- **一期两步走（2026-11-10 订正：D 类 10 例迁移归二期，以 §三 范围与 AC2.7 为准；一期步 2 = BR8 命名分区 + herdr lint 扩全目录）**：步 1 = 后端抽象层 `tests/t4/lib-backend.sh`（`be_start_server` / `be_ready` / `be_panes` / `be_pane_pid` / `be_run` / `be_teardown`，`NAO_TEST_TERMINAL=tmux|herdr|auto`，**`nao-fleet.sh` 零改动**）+ 自检例 `27-backend-selftest.sh`（隔离 / 零渗透 / stop+delete 幂等 / 零残留 / `default` 不可达）；步 2 = D 类迁移 + BR8 命名分区（迁移主要落二期）。
- **最易引 flake 的两处（必须按此实现）**：① **server 就绪**禁用固定 sleep（实测 API 就绪仅 69ms）⇒ 50×100ms 轮询 + 5s 上限 + 超时 fail loud；② **拆场**：`stop` 非幂等（第二次 rc=1）且只 stop 不 delete 会回放上一轮布局 ⇒ 会话名带 `$$`+随机、stop 容忍非 0、delete 幂等、断言一律断 **effect** 不断 rc。
- **三期三条硬判据**：① 实验根走私有 `XDG_CONFIG_HOME`，把「不碰用户 default」变成「碰不到」；实验前后 `api snapshot` 与 `tmux list-panes -a` 双快照 diff 空。② 双侧显式性 lint（tmux 裸调用必带 `-S`；herdr 裸调用必带 `--session`），各带人造违规负控。③ 所有 herdr 调用经唯一 helper，硬条件 `--session` 非空且 ≠ `default`、`HERDR_SOCKET_PATH` 前缀在实验根内，违反即 FAIL。
- **口径纠错（PM 认账）**：本 PRD 初稿写「27 用例」无出处，实际 **25**（`run.sh --list`）；此后一切用例数以此命令为准。
