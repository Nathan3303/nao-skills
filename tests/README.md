# T4 用例集 —— nao-skills 单 SKILL 化 + pi 原生分发（PRD #18）

独立验证 PRD `docs/prds/2026-10-08-nao-skills-pi-package.md` 的 AC1/AC3/AC4/AC6 与
NFR2/NFR3，契约来源另含 §11 D3/D5/D6/D7、§12 闸门 A–D，以及
`docs/reports/2026-10-08-T1-pi-package-verify.md`（pi 1.1.0 实测）。

## 运行

```bash
bash tests/t4/run.sh --list                    # 列用例
bash tests/t4/run.sh --preflight               # 前置探测（不执行用例）
bash tests/t4/run.sh                           # 跑全部（默认严格：T2 产物缺失=FAIL）
bash tests/t4/run.sh --case 03                 # 单跑
T4_ALLOW_MISSING=1 bash tests/t4/run.sh        # 宽松：缺产物=BLOCKED（仅显式 1）
T4_REQUIRE_FULL=1 bash tests/t4/run.sh         # 发布前置：SKIP/DEGRADE>0 或非白名单 NOTE 即 FAIL
npm test                                       # 唯一机械门禁 = test:agents + test:t4
npm run test:t4:full                           # 发布前置双轴（= 上面两个环境变量 · 单环境）
npm run test:t4:full:dual                      # 发布前置**双环境** gate（两组串跑，任一红即红）
```

- **默认严格**：`T4_ALLOW_MISSING` 默认 `0` —— 依赖的 T2 产物缺失即 FAIL；宽松模式**只有显式 `T4_ALLOW_MISSING=1`** 才启用（缺产物记 BLOCKED）。
- **`T4_REQUIRE_FULL=1`**（与上者正交，只管 SKIP/DEGRADE/NOTE 三轴）：汇总层 **SKIP 计数 + DEGRADE 计数必须均为 `0`，且非白名单 NOTE 计数必须为 `0`** —— SKIP 含从用例输出解析的**行首** `[SKIP]` / `SKIP:` 行；DEGRADE 为能力降级标记；NOTE 按 tag 白名单判定（见下节）。发布用 `npm run test:t4:full:dual`（单环境退用 `npm run test:t4:full`）。
- **双环境 gate**：`npm run test:t4:full:dual`（`tests/t4/run-dual.sh`）= 同参数两组串跑 —— 组1 保留 `$TMUX_PANE`（撞号态）/ 组2 `env -u TMUX_PANE`（未设态）；**任一非 0 ⇒ 整体非 0**，输出标明组别与失败组。约 2× 单轮耗时；`npm test` 默认路径**不含** dual（不变慢）。
- **`test:t4:full` 能力要求**：`pi` CLI · tmux · bwrap · strace · npm registry 可达。缺任一即产生 DEGRADE/SKIP ⇒ **full rc≠0**（这正是 full 的意义：要求能力齐备）；默认 `npm test` 不因能力缺失变红。
- **用例 13 的额外能力依赖**：⑥（tmux 内名册可用且为空 ⇒ 「未运行（无需回收）」rc=0）与 ⑦（`--force` 不改末段判定）需要 `tsx`（跑名册探针夹具）；缺失时这两组记 `[DEGRADE]`（默认豁免、`test:t4:full` 计分），其余断言照跑。①–⑤（非 tmux ⇒ exit 3 三条 + `无法确认在线`/宿主阶梯删除面两条静态 grep）只依赖 bash + 本仓脚本，无额外能力。
- **用例 15 的能力与夹具纪律**：T2–T6/T8 需真 `tmux`（缺则整例 `SKIP`）；T1/T7/T9 需 `tsx`（假名册探针；缺则 T1–T9 记 `[DEGRADE]`），T10（`check` 守卫）纯 bash 照跑。夹具 = 真 tmux **隔离 socket**（≠ 生产默认候选；`TMUX_TMPDIR` 指向夹具目录，`env -u TMUX -u TMUX_PANE`）+ 假名册逐字段一行 pretty-print + 桩 `pi` 用**复制**的二进制（保 `comm=pi`）；收尾走机制 `cleanup -S <隔离 socket>`（不裸 `kill-server`）。
- **用例 16 的能力与边界**：只读 **Node 探针**（动态 import pi-subagents 的 `validateIntercomBridgeConfig` / `resolveIntercomBridge` + 桩配置）；`pi-subagents` 缺失（或 `node` 缺失）⇒ 整例 `SKIP`（不 FAIL、不计 DEGRADE）。只断言 **nao 自身契约**（模板存在/含 G1–G3/不含目标占位符 · 安装说明 · 协议小节四条 · 配置 schema 接受与拒绝），**不断言 pi-subagents 自身文案**（防版本脆断）；零 LLM/零网络、不依赖 `pi-intercom`/`tmux`。
- **用例 17 的能力与边界**：只读 **Node 探针**（动态 import pi-subagents 的 `registerRuntimeAgentEventListener` / `listRuntimeAgentConfigs`，桩 `pi.events` 假总线）；`pi-subagents` 缺失（或 `node` 缺失）⇒ 整例 `SKIP`（不 FAIL、不计 DEGRADE）。断言 **nao 自身契约**（逐条定义字节比对，条数 = `roles.yaml` 条数 / 锚点 cross-assert / 命名双向 / schema 与幂等 / 逃生阀 / 三态负控），**不断言 pi-subagents 内部文案**（仅判 ok/throw 与 `unknown fields` 形态，防版本脆断）；零 LLM/零网络、不真跑子代理、不依赖 `pi-intercom`/`tmux`。负控在 `$T4_CACHE_DIR` 夹具副本上做（不触碰仓库工作区）。
- **「子代理不属舰队会话」口径**：由 pi-subagents 拉起的 `subagent-*` 会话（`subagent-<agent>-<id>` / `subagent-chat-<id>`）**不属**舰队会话身份模型 —— `status` 只对其汇总计数（不列名、不参与在线/判重），`close subagent-*` 显式拒绝（生命周期归 pi-subagents 的 stop/retention）。`subagentfoo` / `mysubagent-x` / 裸 `subagent` 不入此面；`qa-subagent-x` 仍是合法派生名。
- **用例 19 的能力与夹具纪律**：需真 `tmux`（缺则整例 `SKIP`）；名册 cwd 镜像断言需 `tsx`（缺则 2 条夹具断言 `[DEGRADE]`，pane/会话名路径照跑）。夹具 = **隔离 socket** + 假名册探针 + 夹具根**不得落在任何 git 仓内**（否则 toplevel 锚会把「他仓」拉回本仓、用例假绿；开跑前硬断言）；收尾走机制 `cleanup -S`。变异 harness 只动 `$T4_CACHE_DIR` 的脚本副本（恒真/恒假各一次，子进程跑本用例必须翻红并点名），真仓库 `md5` 与 `git status` 前后一致，原脚本再跑一遍复绿。零网络、确定性（连跑两次同形）。**AC5① 零回归基线 = 固化 fixture** `tests/t4/fixtures/nao-fleet-baseline-2b4ade3.sh`（该 sha 的脚本原样副本，不从 `main` 动态取 ⇒ 断言数不随「分支 / 已合并」漂移；fixture 缺失 / 为空 / 无来源头 ⇒ 断言失败，不静默跳过）。**有意改动 `status` 输出时需同步更新该 fixture，并在 PR 说明**。
- **用例 20/21/22/23/24 的能力与夹具纪律**：都需真 `tmux`（缺则整例 `SKIP`）。夹具 = **隔离 socket**（≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + 桩 `pi`（20：记录 argv 后长驻，**不拉起真 pi 会话**；21：`--version` 固定输出满足 `check` 前提；22：记录 argv 后长驻）+ `PI_CODING_AGENT_DIR` 指向空目录（tsx 缺失 ⇒ 名册离线），因此**不依赖 `tsx`/网络/真会话**；pane 标题由用例直接 `select-pane -T` 注入（不依赖 pi 自身设标题）。夹具根**不得落在任何 git 仓内**（否则锚根判定被污染；开跑前硬断言），收尾走机制 `cleanup -S`。用例 21 的卡夹具（fifo/目录/超大文件）放在**项目侧** `.agents/prompts/`，机制包侧保持干净（避免 `check` 的交叉引用扫描去 grep fifo 而阻塞）。用例 22 的失败分支用 **tmux 桩**（`NAO_T539_FAIL_SPLIT=<名字>` ⇒ 仅该名字的 `split-window` 返回非 0），**不依赖真实窗口过窄**（不可复现）。用例 23/24 的 tmux 桩把 `split-window` 的**末位实参原样落盘**（断言取 fleet 交给 tmux 的原始字节）；用例 24 的负控是「改回全局 `PROMPT` 回落」（副本两处 sed）⇒ 子进程跑本用例必须翻红并点名 AC1。
- **tmux 采样纪律（#84）**：用例**不得**在命令行位直接调 `tmux`（裸 socket ⇒ 生产 server）取 pane 数或做绝对断言 —— 必须显式 `-S <隔离 socket>`（或包装函数内自带 `-S`），由 `cases/06` 的 `t4_scan_host_pane_refs` 行级守护（人造违规必红）。**覆盖边界**：该 lint 只兜「裸 tmux 采样」入口；真实缺陷类（同一隔离 server 内的累积残留（跨块/跨次）+ 全 server 计数 + `tail -1` 顺序启发式，写法普遍带 `-S`）**不在其覆盖面** —— 那类由用例级解耦承担（`cases/20` 的 `reset_lab` 每块重建隔离 server + 快照 diff）。
- **真 pi 冒烟重试的成本边界（#86 · 转办下批 2026-12-05）**：`cases/02` 的重试上限 = 首次 120s + 重试 180s；**断网/无凭据时最坏每轮 ~300s**，`test:t4:full:dual` 两组合计可 +10min。当前以「无凭据前置（`No API key` 不重试）+ 只在首次超时后才付第二次」收敛；若仍需压低，下批再议「按网络/凭据探测提前短路」。
- **`cases/26` R5 的判据性质（P3-4 · 转办下批）**：两条默认超时断言是**静态文本匹配**（`T4_PI_TIMEOUT:-120` / `T4_PI_RETRY_TIMEOUT:-180`），作为「默认值未被漂移」的可接受**代理**（真正的行为断言由 R1/R1b 的 env 覆盖路径承担）；更严格的实现级断言下批再补。
- **DEGRADE 语义**：环境缺能力但**其余断言继续跑**（不同于 `t4_skip` 会终止用例）；默认模式豁免、`T4_REQUIRE_FULL=1` 时计分。
- **计数可见**：汇总尾部打印 `SKIP=n · DEGRADE=m · NOTE=k` + **NOTE 白名单命中明细**（`用例号:tag` 列表，逐条可解释）；「绿 + N SKIP/DEGRADE」不得表述为「全量通过」。
- **取数命令四条（全仓单源）**：下列四条命令的**正文只在本处**；PM / QA / RD 三侧（`checklists/pm.md`、`checklists/qa.md`、`checklists/rd-infra.md`）**只留指针，不复写命令**。**复核范围 = `.agents/**` + 本文件**；`docs/**` 下的历史文档（PRD / 报告 / 发布说明 / 台账）引用命令串**不计「正文唯一」违规**（PRD BR1 已许作证据）—— 全仓 `grep -r` 会命中这些历史引用，不作判据。
  - **用例数** = `bash tests/t4/run.sh --list | tail -n +2 | wc -l`。何时用：回执「例数」。易错点：`--list` 首行是**表头**，裸 `wc -l` 会多算 1；用例编号不连续（`11` 已于 T529 退役）属正常，**不得以最大编号推断例数**（T536 教训：`19` 曾被误当例数）。
  - **断言数** = `bash tests/t4/run.sh 2>&1 | grep -c '\[PASS\]'`。何时用：回执要「断言数 / 绿数」。易错点：与**例数不同轴**（例数 = 注册项，断言数 = PASS 行），二者不可互替；单跑 `--case` 得到的不是全量断言数。
  - **`files=` 口径** = `check` 输出里的 `files=`；交叉核对用 `find "$NAO_SKILLS/.agents" -type f | wc -l`。易错点：两者**不等须在回执写明原因**（如新增/删除机制文件）；改动前后比 `files=` 必须同口径；`NAO_SKILLS` 未设置时该 `find` 会向 **stderr** 报 `find: "/.agents": 没有那个文件或目录`、而**管道 rc 仍为 0** ⇒ 属于「**计数静默得 0、报错不静默**」（只看数字/退出码的人会被骗）；必先 `export NAO_SKILLS=<包根>`，或同时看 stderr。
  - **变更行数 / 文件数** = `git show --shortstat --oneline <sha>`。何时用：报告里的 `+N −M` 与「k 文件」。易错点：**禁止手数或凭记忆**（`+7 −1` 实为 `+5 −1`、「1 文件」实为 2 文件，两次都是这么错的）；行数与文件数必须取自**同一行输出**。
- **不符即打回**：计数类数字一律「**命令 + 输出**」，**禁「我数了 N」**；与命令输出不一致时以命令为准并当场订正；缺命令 / 缺输出 / 缺 HEAD 任一 ⇒ 打回重报（三件套见 @.agents/common/output-format.md「回执硬性」）。
- **安装包内不适用**：`tests/` 不入 npm tarball，在消费者机器上 `npm test` 因缺 `tests/t4` 而 rc≠0，属预期（见 `docs/releases/v0.18.0.md`）。

退出码：`0` 全 PASS/SKIP（DEGRADE 默认豁免）· `1` 有 FAIL / 参数错误 / 未识别状态（MISSING、NOT_RUN） / (full) 有 SKIP 或 DEGRADE · `2` 有 BLOCKED（仅宽松模式）。
参数错误（`--case` 缺值 / `--case` 无匹配 / 裸位置参数）一律 rc=1，不得静默全跑。

## 用例

| ID | 场景 | AC/NFR | 依赖 T2 产物 |
| :-- | :-- | :-- | :-- |
| 01 | 主路径足迹 + `check` exit=0 | AC1 | `init` + shim |
| 02 | 注册 skill 数==2 且无 collision | AC1/AC6 · D3 | `pi` manifest（动态另需 pi 凭据） |
| 03 | 未物化 exit 2 + `DEGRADED:` + 恢复命令；D7 防重入；D6 解析序 | AC3/NFR3 · D5/D6/D7 | `init` + shim |
| 04 | 零网络 `check` exit=0 + strace 无 AF_INET | NFR2 · 闸门B | `init` + shim |
| 05 | 迁移精准删除 + `.nao-obsolete` 备份 + 共享目录保留 | AC4 · §12-C/D | `migrate`（或 `init` 自动迁移） |
| 06 | 契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态 + 测试基建 helper 级正反断言（`t4_cli_supports` 命中/未命中）+ `lib.sh` 同型管道 0 处恒量护栏（T536）+ **真清单断言**（#82 A：核真 `roles.yaml` 的角色集/别名/`card`↔`roles` 双向，夹具副本摘条目 ⇒ 必翻红并点名；#84 B：**负控夹具自包含**（固定清单字面量，真清单漂移时只报该漂移自身）+ **tmux 采样行级 lint**（`t4_scan_host_pane_refs`：命令行位裸 `tmux` 必须 `-S`，人造两条违规 ⇒ 必红并点名；累积残留类不在此覆盖面，见 `cases/20` 的 `reset_lab`）；同时留痕 `check` 在该漂移上 rc=0 仅 warn=1 = 假绿根因） | AC2/AC6/AC8 · T536/BR4 · #82 AC1 | 无（读 manifest + 机制脚本） |
| 07 | 真实 `pi install` 与 tarball 布局对照 | AC1/NFR2 | `pi` + npm registry |
| 08 | 评审修复回归：F1 lock 保缩进 + F2 init --force 走 migrate 防混装 | AC4 · BR5 | `migrate` / `init` |
| 09 | T509 别名解析 / check 守卫 / close 跨仓回收 | AC3 · #19 | `init` + shim |
| 10 | T510 migrate 收尾：shim 判定式 / 开关 / 单行 lock 去重 | AC4 · BR5 · #21 | `migrate` / `init` |
| 12 | 派生会话 tmux 落点：宿主窗口显式寻址（含幂等/同源） | AC1–AC7 · T517 | 无（真 tmux 隔离 socket + 桩 pi；无 tmux 则 SKIP） |
| 13 | `close` 前提与末段：非 tmux ⇒ exit 3 单行提示且无副作用；tmux 内名册离线 ⇒ 「未运行」rc=0；`--force` 不改末段；`无法确认在线` 静态归零 | AC1/AC4 · T529 | `tsx`（名册探针夹具，缺则 ⑥⑦ DEGRADE）；①–⑤ 无依赖 |
| 14 | 夹具缓存生命周期：成功清理 / 失败保留 / 用户目录永不删（守卫负控 + 早退净增 0） | AC4–AC7 · T524 | 无（私有 `TMPDIR` 内纯本地，不依赖 tmux/tsx/网络） |
| 15 | 子代理会话（`subagent-*`）在 `status`/`close` 的显式识别与排除（汇总计数 / 显式拒绝且父 pane 存活 / E2 孤儿 pane 告警回归 / 前缀边界 / `check` 守卫） | AC2–AC8 · T525 | `tmux`（缺则 SKIP）· `tsx`（名册注入，缺则 T1–T9 DEGRADE）；T10 纯 bash |
| 16 | 子代理桥口径：模板 G1–G3 契约 + 无目标占位符 + 安装说明 + 协议小节四条 + pi-subagents 配置 schema 接受/拒绝 | AC2–AC7 · T526 | `pi-subagents`（缺则 SKIP）；纯 Node 只读探针，不依赖 tmux/tsx/网络 |
| 17 | 角色→子代理 agent 单一事实：装配字节比对（卡正文去 frontmatter）· 锚点 cross-assert · 命名双向 · 假总线注册 ×6 + 幂等 + 逃生阀 + 三态负控 | AC2–AC7 · T527 | `pi-subagents`（缺则 SKIP）；纯 Node 只读探针 + 夹具副本，零 LLM/零网络，不依赖 tmux/tsx |
| 18 | codegraph 四态检测（四态：默认取其一回显 / `-v` 六态全展开）：四态前缀 + 默认零 codegraph 调用（AC11）+ warn 口径（codegraph 任态不计入、真 warn 不掩蔽）+ `--strict` 不升级 + 两条变异负控（摘插件条目 / 摘 `.codegraph`，md5 还原）+ 包名等值 + 遥测字面量 + 副产物静态面 + 技能/卡口径 | AC1/AC2/AC3/AC4/AC7/AC8/AC11 · T532 | 无（纯 bash + 夹具 stub，零 daemon）；真 CLI 原文缺能力 ⇒ `[NOTE] static-contract` |
| 19 | 派生会话归属三态常态回归：本仓行含可执行 `close --task`（`!`/`·` 分支）· 他仓行 `~` 且整行无可执行 `close --task` · 不可判定行 `?` 且无可执行 `close --task` · 单仓零 `~`/`?`；`repo_contains_path` 单行谓词**恒真/恒假双向变异必红并点名**（临时副本，真仓库 md5/git status 前后一致，还原复绿） | AC1/AC2 · BR1–BR3/BR5 · T535 | `tmux`（隔离 socket，缺则 SKIP）· `tsx`（名册 cwd 镜像，缺则 2 条夹具断言 DEGRADE） |
| 20 | 下游仓自定义角色会话 `ensure --card`（#84 A：**每块前 reset_lab 重建隔离 server** + 一律快照 diff 挑 pane，块间/残留不累积）：主路径（宿主窗口 / `--name <卡role>-<task>` / 提示文件 = 卡正文 + 锚点行且与常驻角色逐字相同）· 反冒充（常驻前缀/`subagent-`/`nao-`/字符集/长度）· 语法绑定（目标级 `--card`·悬挂与跨子命令用法错·两相执行零副作用）· 托管三接线（status 一次性行 / close 不弹常驻警告 / A–D 四段分叉 / 回收后双清） | AC1/AC3/AC4/AC6/AC7 · T537 | `tmux`（隔离 socket，缺则 SKIP）；桩 `pi`（只记 argv，不拉真会话）+ 名册空化 ⇒ 不依赖 `tsx` |
| 21 | 下游卡零副作用边界 + `check` 分级 + `status` 未识别节：八种失败输入（不存在/空/无 role 且不可退化/越目录/symlink 逃逸/fifo 或目录/超 256 KiB/缺参数）逐个断言 rc·单行·pane 与 session 不变·无提示文件残留；内容类 warn 不红 rc、机制类 error 红 rc、overlay 整节跳过、卡集前缀嵌套 + 最长匹配 | AC2/AC5⑤/AC8 · T537 | `tmux`（隔离 socket，缺则 SKIP）；桩 `pi`（`--version` 供 check 前提）+ 名册空化 ⇒ 不依赖 `tsx` |
| 22 | `ensure` 输出三态互斥：成功恰 1 行 `[tmux] 已拉起 …`（逐字不变）· 跳过/失败 **0 假行**（诊断 warn 保留不合并）· 摘要恰一行且给出「成功 N / 跳过 M / 失败 K」· 混合批次 1/1/1 计数守恒（和 = 目标数）· 失败分支 rc 仍 0（BR4） | AC1–AC4 · BR1–BR6 · T539 | `tmux`（隔离 socket，缺则 SKIP）；桩 `pi` + **tmux 桩选择性令 `split-window` 失败** ⇒ 不依赖真实窗口几何/`tsx` |
| 23 | `ensure pm` 下游版本自检注入：注入常量六要素可 grep（pin+5s / `gh release view` 两句话 / 一行询问 / 五种降级 / 硬约束「未获我同意前不要改任何文件」/ 同意后序列+重开）· 命令行形态（`--append-system-prompt` 之后 `--` 再常量全文，整体 `printf %q`）· 真 pi argv 侧「`--` 恰 1 次 + 之后恰 1 参数 = 常量全文」· `rd-be` 与 `NAO_UPDATE_ON_ENSURE=0` 两条路径命令行**逐字重建 diff 为空** · 常量块外无 `npm view`/`gh release`/`curl`/`wget` | AC1–AC7 · R1–R6 · M20261103 | `tmux`（隔离 socket，缺则 SKIP）；桩 `pi`（记 argv+END 后长驻）+ 桩 `tmux`（把 `split-window` 命令串原样落盘后转发）⇒ 不依赖真实 pi 会话/`tsx`/网络 |
| 24 | `ensure` 多目标**每 pane 用其目标自己的卡**（Issue #75）：`arch rd-fe rd-infra` 与 `rd-be qa` 两组逐 pane 断言「会话名 = 目标」+「提示文件 = 该目标卡正文逐字 + 锚点」+「文件名由该卡 stem 生成」+ 三个提示文件互不相同；单目标 / `--card` 完整路径 / 同批混合三条路径命令行**逐字重建 diff 为空**（override 与相对名两条通道不混用）；负控 = 改回全局 `PROMPT` 回落（副本两处 sed）⇒ 本用例翻红并点名 AC1，还原复绿 | AC1–AC4 · #75 | `tmux`（隔离 socket，缺则 SKIP）；桩 `pi`（记 argv+END 后长驻）+ 桩 `tmux`（`split-window` 命令串落盘后转发）⇒ 不依赖真实 pi 会话/`tsx`/网络 |
| 25 | 布局守卫容量判据（#82 B · #84 C：`pct`/`min` **从脚本 `*_DEFAULT` 常量抽取**，副本改默认值 ⇒ 公式断言仍绿、拍板表自跳过）：从**真脚本**抽取 `main_row2_geom`/`main_row2_min_col` 实跑边界（n=7/8/9/10 ⇒ 137/184/184/230 + 阈值两侧逐值）· 语义断言 n = 宿主窗口实际 pane 数（`list-panes`，非 `ROLE_ORDER`）· 活体 7 目标 = 8 pane（183 列 warn / 184 列零 warn）· 变异负控把守卫实参改 `n-1`（模拟「按角色数」）⇒ 判定改变，断言可捕获 | #82 AC2 | `tmux`（隔离 socket；缺则 SKIP）+ 桩 `pi`；零网络（`NAO_UPDATE_ON_ENSURE=0`） |
| 26 | 真 `pi` 冒烟受限重试护栏（#86 A）：`t4_pi_smoke` 只在**首次 rc=124 或 0 字节**时重试一次（首次 120s / 重试 180s，可 env 覆盖）；info 行恒含**两次 attempt 的 rc + 字节数**（`pi-smoke:` 可 grep）；负控按**实际调用次数**证「非超时失败不重试」（`fail` 桩 exit 7 + 20B 输出 ⇒ 1 次）、「No API key 不重试」、以及「两次超时仍返回 4（调用方 SKIP，full 轴照旧计分）」；末组断言 `cases/02` 真跑路径确实经该护栏（防空转） | #86 AC1–AC3 | 无（纯 bash 桩；不跑真 pi / 不联网 / 不依赖 tmux，~4s） |

## NOTE 白名单（T531 · `t4_note <tag> <msg>`）

NOTE = 用例产出的**事实性说明**（合法的能力/前提说明，不是通过证据）。为避免「能力缺失时用 NOTE 跳过断言而不阻断」，NOTE 改为**白名单制**并分轴判定：

- **签名**：`t4_note <tag> <msg>`；`tag` 必须是下列四个之一（枚举**单点定义**于 `tests/t4/lib.sh` 的 `T4_NOTE_TAGS`）。
- **合法 tag（4 个）**：
  - `static-contract` —— 用**静态断言**替代动态证据（如真 `pi` 加载需凭据，改判 manifest/文档契约）。
  - `pin-fallback` —— pin 版本尚未发布，改用已发布 `latest` 只做**布局**对照（内容差异不计）。
  - `migrate-fallback` —— CLI 未提供 `migrate`，改用 `init` 的自动迁移路径。
  - `baseline-selfequiv` —— 用例 19 AC5① 检出「fixture 正文 == 被测脚本正文」：本轮逐字等价对照是**自等价（恒绿同义反复）**，不得当零回归证据；不能用 `t4_degrade`（不是能力缺失）也不能 `t4_skip`（其余断言照跑），故用 NOTE 如实标注。
- **判定单点**：合法性只在 `run.sh` 汇总层判定（`t4_note` 只打印、从不 `exit`）。非 full ⇒ 只计数 + 未登记 tag 打 `WARN`（不阻断，日常 `npm test` 不因旧式调用变红）；`T4_REQUIRE_FULL=1` ⇒ **未登记 tag 或无 tag ⇒ `RESULT: FAIL` + rc≠0**，输出点名 `用例号:tag`。
- **旧式调用**（`t4_note "msg"`，无 tag）：打印为 `  [NOTE] (untagged) msg`；非 full 仍跑（仅警告），full 下 FAIL —— 兼容旧分支但不放纵。
- **新增 tag 的流程**：① 在 `tests/t4/lib.sh` 的 `T4_NOTE_TAGS` 加一项 ② 在本节写清「什么情况下允许、为什么不能改用 `t4_degrade`/`t4_skip`」③ 提交信息说明新增理由。两处缺一不可（`run.sh` 复用常量，不会漏判）。
- **优先用 `t4_degrade`/`t4_skip`**：真正的「能力缺失」应显式降级（full 计分）或跳过（计 SKIP），**不要**用 NOTE 掩盖断言未执行。

## 夹具缓存纪律

- **成功清理**：跑批 `rc=0` 且缓存目录是本进程自建 ⇒ 退出时删除该目录（含 `case-<id>.log`）。
- **失败保留**：`rc≠0`（FAIL / BLOCKED / MISSING / NOT_RUN，含 `T4_REQUIRE_FULL=1` 因 SKIP/DEGRADE 判 FAIL）⇒ 目录保留并打印路径，便于查看 `case-<id>.log`。
- **用户目录永不删**：显式传入 `T4_CACHE_DIR=<dir>` ⇒ 无论成败都不删，也不清理其中任何文件。
- **逃生口**：`T4_KEEP_CACHE=1`（env-only）⇒ 成功/失败两情形均恒保留。
- **只读命令不建目录**：`--list` / `--preflight` / 参数错误（`--case` 缺值 / 无匹配 / 裸位置参数）不创建缓存目录（零净增）。
- **单点实现**：清理逻辑只在 `tests/t4/lib.sh` 的 `t4_cache_cleanup` 一处（`run.sh` 复用），删除前五道守卫：仅自建归属（`T4_CACHE_OWNED=1`，不导出）· 前缀匹配创建时捕获的 `$T4_CACHE_PARENT/nao-t4.*` · 仅一层（禁 glob 穿越）· 是目录且非软链 · 非 `/`。
- **打印与实况一致**：汇总尾部 `缓存目录: …` 后随三态（`已清理` / `已保留：失败证据` / `用户提供 · 不删`，或 `已保留（T4_KEEP_CACHE=1）`）。

## 设计要点

- **不改仓库**：只读仓库，夹具全部在临时目录；`npm pack --ignore-scripts` 构造被测包，
  模拟 `pi install --local` 的落盘布局（`.pi/npm` + `.pi/settings.json`，T1 §2 实测）。
- **BLOCKED vs FAIL**：T2 产物缺失默认即 FAIL；只有显式 `T4_ALLOW_MISSING=1` 才降级为 BLOCKED(78)。
  汇总用白名单（仅 `PASS`/`SKIP` 通过），`MISSING`/`NOT_RUN`/未知态一律 rc≠0 —— 避免「用例未跑」被误读为「通过」。
- **可追溯**：每条断言前缀 `[PASS]/[FAIL]`，用例头注释给出 Given/When/Then 与 AC 映射。
- **零网络证据**：`bwrap --unshare-net` 环境隔离（强）+ `strace connect(2)` 无
  AF_INET/AF_INET6（直接证据）。
