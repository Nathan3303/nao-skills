# T566 实现报告：编排器阶段 1（队列与回执契约）

- 状态：待验收 · 更新：2026-11-24 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-11-24-orchestrator.md`（§四 契约 / §七 AC1–AC4）· Issue #177 · 分支 `feat/566-queue-receipt`（二轮已 rebase 到 `origin/main` `49ce447`）

## TL;DR

- **交付**：`bin/nao-queue`（render / validate / transition / transitions / receipt-line）· 单源 `docs/queue.jsonl`（1 行）·
  回执 schema 实例 `docs/queue/T566.receipt.json` · `docs/tasks-state.md` 两区渲染标记 · 用例 `tests/t4/cases/46-queue-receipt.sh`（二轮后 96 断言）。
- **AC**：① 回执缺字段/空证据/自述矛盾/脱离队列 ⇒ 红；② `pushed:true` 用 `git ls-remote` 复核（未推送 ⇒ 红）；③ 跳级/终态出边/自转 ⇒ 红；
  ④ jsonl → md 单向渲染 · 幂等 · 手改后 `--check` ⇒ 红 · 标记缺失 ⇒ rc=2 且不改盘。
- **门禁**：`check` rc=0 ×2 逐字一致（roles=7 · files=53）· 目标用例 `06` / `36` / `46` 全 **RESULT: PASS**（`46` = 96 PASS / 0 FAIL；`--list` = 43 例）。
- **待办（PM）**：全量 `npm test` 由 PM 合并前跑（加速令）；阶段 2/3 未碰。

## 选型：为什么用 Node 而不是 shell

- 契约核心是 **JSONL 解析 + 字段/类型校验 + 状态机 + 幂等文本拼接**：shell 要拼 `jq`（本机/下游不保证）或手写解析（假绿风险高）。
- 仓内已有 Node（`bin/nao-skill.js`、`engines >=18`），**零依赖零网络**：只用 `node:fs` / `node:path` / `node:child_process`；
  唯一外部调用是 `pushed:true` 时的 `git ls-remote`（可用 `--no-push-check` 显式跳过，跳过必打 NOTICE）。
- 退出码三分：`0` 通过 · `1` 契约违规/非法转换 · `2` 用法错误（缺标记/缺文件/未知状态），便于阶段 2 的 tick 直接复判。

## 契约落点（PRD §四 逐项）

- **队列**：`docs/queue.jsonl` 一行一任务，15 字段与 PRD 逐字一致；id 唯一、`deps` 必须指向本队列内任务、`attempt>2 ⇒ blocked`、
  `blocked ⇔ blocked_reason` 双向校验。**PRD 未给值域的字段（`kind`/`prio`）只校验类型与非空，不自造枚举**。
- **状态机**：单表 `TRANSITIONS`（`bin/nao-queue:26`）；`blocked` 入口 = dispatched/working/qa/qa_fail/qa_pass/merging（no_ack / stalled / attempt>2）；
  PRD 未定义 `blocked` 出边，取**最小可恢复出口** `blocked → queued`（人工复核后重新排队），单点在本表，可一处改。
- **回执**：`docs/queue/<id>.receipt.json`，字段 `id/author/at/head/pushed/gates{check{rc,log},full{rc,cases,pass,fail,note}}/acs[{id,how,evidence}]/blocked/artifacts/deviation`
  （另允许 `schema:1`，PRD §八 建议）。交叉判据：`id` == 文件名且必须在队列里；`acs[].id` ⊆ 队列行 `acs`；`gates.full.rc=0 但 fail>0` ⇒ 矛盾红；
  `evidence`/`how` 空串 ⇒ 红（空证据不算验证）。
- **机读首行**：`nao-queue receipt-line` 由回执 JSON 生成 `receipt: <id> <role> head=<sha> gates=<ok|red>,<ok|red> acs=<n>/<n>`，格式不合 schema 不生成。
- **渲染**：`docs/tasks-state.md` 内两个标记区（`active` = 进行中 · `dispatch` = 待派发），只替换标记之间内容；标记缺失/重复 ⇒ rc=2 且**不写盘**。
  渲染产物首行 `<!-- generated: … 禁手改 -->`；`render --check` = AC4 的机械判据（手改 ⇒ rc=1 + 逐行差异）。

## 与 PRD 的两处事实对齐（需复核）

1. **PRD 结构**（机械，非语义）：原 PRD 不满足 `.agents/checklists/deliverable-docs.md §三`（缺 `## TL;DR`；AC 在 §五；§七 无 5 个 `###` 覆盖组）
   ⇒ `check_prd_structure` 多打 1 行 ⇒ 基线 `bc98f81` 上 `cases/06` 与 `cases/36` **本来就红**（与本次实现无关，已复跑证实）。
   已按规范重排：加 TL;DR · 「五、验收」移到 `## 七、验收（AC）` 并按五覆盖拆组 · 原六/七顺移为五/六。**AC1–AC11 文本逐字保留、编号不变**；
   `§四`（队列/回执契约）与 `§十`（三问拍板）**编号未动**。
2. **用例编号**：PRD AC1 原写 `cases/50`，派单指定 `tests/t4/cases/46-queue-receipt.sh`，已按派单改指（事实对齐，非新增 AC）。

## 门禁与证据（rebase 后二轮 · 原始日志见本文附录）

- 基线：`feat/566-queue-receipt` 已 rebase 到 `origin/main`（`49ce447`）；`tests/t4/run.sh` 三处冲突按**并集**解 ⇒ 用例 **43**
  （分支 42 + main 上 T565 的 `45`），`run.sh --list` 实测 = 43。
- `check` rc=0 ×2 逐字一致（`cmp` IDENTICAL；roles=7 · files=53）。
- `bash tests/t4/run.sh --case 46` **96 PASS / 0 FAIL** · `--case 06` **331 PASS / 0 FAIL**（NOTE=2 白名单）·
  `--case 36` **31 PASS / 0 FAIL** · `--list` = **43 例**。
- 守卫失败演练（各改坏一处 ⇒ 必红 ⇒ 按 md5 还原复绿，全部实跑）：
  移走 `bin/nao-queue` ⇒ **67 FAIL**；短路状态机允许集 ⇒ **3 FAIL**（红点全在 ③）；
  回填「receipt-line 静默跳过 pushed」⇒ **5 FAIL**（P2-1 新断言）；回填同态自转不回显允许集 ⇒ **2 FAIL**（P3-1）；
  回填硬编码 `T566` 默认回执 ⇒ **3 FAIL**（P3-3）。还原后 `bin/nao-queue` md5 = `957a88d7d965b27eeed332da3ab903b1`。
- `render --check` rc=0 · `validate --no-push-check` rc=0（queue=1 行 · receipts=1 份）。
- **全量 `npm test` 仍由 PM 合并前跑**（本批按派单只跑 `check` + `46/06/36` + `--list`）；回执 `gates.full` 如实标注 pass 待 PM 回填。

## 边界遵守

- 未实现 tick / 定时器 / systemd（阶段 2）· 未改 `nao-fleet.sh` 调度行为 · 未动 `.agents/prompts/**` / 发布说明 / `package.json`。
- `tasks-state.md` 结构不变：只加两对标记 + 各一行说明；**既有手写台账一行未删**（迁移到 jsonl 属 PM 台账动作，本批不做）。
- 未把 `bin/nao-queue` 注册进 `package.json`（派单禁改）；当前调用 = `node bin/nao-queue <cmd>`，`bin` 已随包发布。

## 修订

- 2026-11-24 首版（阶段 1 交付）。
- 2026-11-24 二轮（QA 裁定 P1-1 / P2-1 / P3-1–P3-3）：rebase 到 `origin/main`（`49ce447`）⇒ 用例并集 **43**；
  `receipt-line` 拒绝 `pushed:false`/缺字段且默认做 `git ls-remote` 复核（P2-1）· 同态自转也回显允许集（P3-1）·
  PRD §六 失败模式行按 PM 裁定逐字替换（P3-2）· 删硬编码 `T566` 默认回执，改「位置参数 或 `--id`」且缺则 fail loud（P3-3）。

## 附录：门禁原始日志（二轮 · 全文照抄）

采集：2026-11-24 · 工作树 `/tmp/infra566`（rebase 后）· 日志原件另存 `/tmp/566-evidence-infra/`（长期权威副本 = 本附录）。

### check

`NAO_SKILLS=/tmp/infra566 bash .agents/scripts/nao-fleet.sh check`（连跑 2 次，`cmp` 逐字节相同；第 2 次日志同文，故只留 1 份）

```text
check: OK · roles=7 · files=53
  ! codegraph 已就绪但当前仓无索引（codegraph init；索引后每会话约 +70–90MB PSS）
  · 生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app；#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）
```

### run.sh --list

`bash tests/t4/run.sh --list`（表头 1 行 + 用例 43 行）

```text
T4 用例清单（PRD #18）
  01  主路径足迹 + check exit=0（AC1）
  02  设计一致性：注册 skill 数==2 且无 collision（AC1/AC6）
  03  异常/边界：未物化 exit 2 + DEGRADED + 恢复命令；D7 防重入（AC3/NFR3/D5/D6/D7）
  04  零网络可执行断言：无网 check exit=0（NFR2/闸门B）
  05  迁移精准删除 + .nao-obsolete 备份 + 共享 skills 保留（AC4/§12-C/D）
  06  契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态替代
  07  真实 pi install -l --approve 与 tarball 布局对照
  08  评审修复回归：F1 lock 保缩进 + F2 init --force 走 migrate 防混装
  09  T509 别名解析 / check 守卫 / close 跨仓回收（#19）
  10  T510 migrate 收尾：shim 判定式 / 开关 / 单行 lock 去重 / B2（#21）
  13  close 前提与末段（T555 纯 herdr）：旧后端变量 ⇒ rc=2 单行 fail loud；herdr 空场 ⇒ 「未运行」rc=0（T529 AC1/AC4）
  14  夹具缓存生命周期：成功清理 / 失败保留 / 用户目录永不删（T524 · BR3–BR10）
  15  子代理会话（subagent-*）在 status/close 的显式识别与排除（T525 · AC2–AC8；T555：tmux 名册/孤儿面退役）
  16  子代理桥口径：模板 G1–G3 + 协议条款 + 配置 schema（T526 · AC2–AC7）
  17  角色→子代理 agent 单一事实：装配字节比对 + 锚点 cross-assert + 命名双向 + 幂等 + 三态负控（T527 · AC2–AC7）
  18  codegraph 四态检测 / 默认零 codegraph 调用 / warn 口径 / 遥测注入 / 契约文案 + 变异负控（T532 · AC1/AC2/AC7/AC11）
  19  派生会话归属三态（本仓/他仓/不可判定）+ 单行谓词双向变异必红（T535 · AC1/AC2）
  20  下游仓自定义角色会话 ensure --card：主路径/反冒充/语法绑定/托管三接线（T537 · AC1/AC3/AC4/AC6/AC7）
  21  下游卡零副作用边界 + check 分级 + status 未识别节（T537 · AC2/AC5⑤/AC8）
  22  ensure 三态输出互斥 + 摘要三类计数（成功/跳过/失败）+ 桩构造失败分支（T539 · AC1–AC4）
  23  ensure pm 就绪后投递下游版本自检（仅提示）+ 两通道送达/幂等/失败语义 + 命令行逐字不变 + 零网络（T548 · AC1–AC5）
  24  ensure 多目标每 pane 用目标自己的角色卡（含 --card 完整路径通道）+ 全局 PROMPT 负控（#75）
  26  真 pi 冒烟受限重试护栏（#86 A）：超时才重试 / 非超时失败不重试（按调用次数证）/ 无凭据不重试
  27  后端抽象层自检（#96 一期步 1）：两场隔离 / 零渗透 / 拆场幂等 / 零残留 / default 不可达 + 护栏变异自证
  28  舰队命名契约（BR8 · #96 步 2a + T547）：C1 codec + M1–M5 负控 / herdr golden + 默认值反向断言 + C3 单写点 lint（T555：tmux golden 组退役）
  29  herdr 就绪门反假阳性（#96 B4）：已 idle 但 state_change_seq 不动 ⇒ 超时 fail loud（全败 ⇒ rc=1）
  30  herdr 幽灵 pane（#96 B4）：label 在、agent 无 ⇒ 不判在线 / ensure 不判已在运行（复用重跑）
  31  herdr 集成缺失 fail loud（#96 B4）：agent_session 空 / 钩子权威缺 ⇒ 点名不可投递，不退化 idle
  32  真机整轮 herdr（#96 三期 P1 · AC3.5/AC3.1/AC3.2）：四件私有 env + 布局 A + 迁移无损 + 小空间 J1/J4
  33  舰队身份单一来源（T547 · ADR 2026-11-17）：AC1–AC12（含 legacy 等价/名长双态/D4 体检行）+ N1/N2 变异负控
  34  端前提声明一致性单点 warn（#124 · AC5/AC6）：一致零输出 / 协议与 AGENTS.md 双向负控 / warn 不改 rc
  35  stash 滞留机械闸（#126 · B2-2）：无 stash 零输出 / 有 stash 恰 1 条 warn + warn=1 且 rc 仍 0 / pop 双向 / 只碰临时仓
  36  PRD 结构探针（Q8 · warn-only）：缺 AC 组 / 超行数 / 老日期不追溯 / 空文件拒判合格 / SINCE 非法回落 / warn= 不污染 / 本仓输出与探针关闭逐字一致 + 三条变异负控
  37  close 裸名解析的仓来源（#146 · T551）：五态 a/b/b2/c/c2/d/d2/d3/e + 卡目标子目录 f + 锚过滤与「按名唯一 cwd」三态 + 探针 ≤1 次 + 六向变异负控 + 动态作用域守卫自证
  38  close 全名解析的仓来源（#151 · T552）：唯一命中 a/b + 不退化 b3/a2 + 多命中 c/d/m（die 零回收；m = 重复条目 + 另一路径）+ 同仓重复去重 g1/g2（g2-herdr 绑拒绝理由）+ 0 命中 e + 名册不可用 f + 探针 ≤1 次 + 七向变异负控
  39  联动仓 manifest（#139 · T553）：A 无 manifest 逐字旧行为 + B/C/D 派生与同 workspace + tab 组前缀 + E 未命中 + F 11 项字段非法 + G/H 放置来源一致性 + I 三预算 + J close 回落 + K 并列不猜 + L 无缓存 + AC10 单源
  40  舰队模型 v2（T554）：13 态（S1–S13）—— 放置键=仓 / 槽位名 / @code / default 放行 / 弃用 warn / status ego
  41  纯 herdr 化（T555）：fail loud 三态（旧后端变量 / cleanup -S / NAO_TEST_TERMINAL）+ 旧面静态 lint 双向 + 退役面不存在
  42  设计循环静态契约（T557 · AC1–AC7）：M1 七节 + 路由/循环/外视/验收关键词 + 零第三方原句 3 条 + 双卡 bump 与指针 + qa 四项 + 两向变异负控
  43  ensure 空 ws 判据护栏（#160 P0 · T558）：访问器空字段不左移 + 静态闸两向正控 + 不关用户 ws 三向自证 + 真空 ws 可关 + 判重/槽位/仓归属同族断言
  44  herdr desktop app 第二后端（T562 · #168）：静态闸两向 + 三件套闸门 + AC3b 不建终端 + 放置读回/回滚/就绪/回收 + keep 残留 + AC1 逐字 + 真 hc 私有 core
  45  app 后端放置验证失败（T565 · #175）：doc 校验陈旧 space + 异步收养轮询 + 三句分类报错 + check 前提 warn-only + 变异必红
  46  编排器阶段 1 队列与回执（T566 · AC1–AC4）：回执 schema 五变异 + pushed 与 ls-remote 双向（本地 bare 仓）+ 状态机跳级必红 + 渲染幂等/手改必红/标记缺失不改盘
```

### case 46

`bash tests/t4/run.sh --case 46`

```text

===== 用例 46: 编排器阶段 1 队列与回执（T566 · AC1–AC4）：回执 schema 五变异 + pushed 与 ls-remote 双向（本地 bare 仓）+ 状态机跳级必红 + 渲染幂等/手改必红/标记缺失不改盘 =====
  [PASS] ④ AC4 渲染 rc=0（）
  [PASS] ④ 渲染产物带 generated 头（禁手改标记）
  [PASS] ④ 进行中区含 working 行
  [PASS] ④ 进行中区含 blocked 行
  [PASS] ④ blocked 行带原因
  [PASS] ④ 待派发区含 queued 行
  [PASS] ④ 待派发行不进进行中区（两区互斥）
  [PASS] ④ 标记区外的既有结构原样保留（标题仍在）
  [PASS] ④ 连跑第 2 次 rc=0
  [PASS] ④ 幂等：第 2 次渲染 effect=0（字节相同）
  [PASS] ④ 渲染后 --check rc=0（文件与渲染结果一致）
  [PASS] ④ 夹具：手改已注入生成区
  [PASS] ④ 手改后 --check rc=1（AC4 判据咬住）
  [PASS] ④ 失败信息点名不一致（不是静默放过）
  [PASS] ④ 重渲染 rc=0（覆盖手改）
  [PASS] ④ 重渲染后与首渲染逐字节相同（手改被覆盖）
  [PASS] ④ 手改行已被清除
  [PASS] ④ 标记缺失 ⇒ rc=2（用法错误，fail loud）
  [PASS] ④ 失败信息点名缺失的标记
  [PASS] ④ 标记缺失时目标文件零改动（不静默追加）
  [PASS] ④ 标记重复 ⇒ rc=2
  [PASS] ④ 失败信息点名标记重复
  [PASS] ④ 改 state 后渲染 rc=0
  [PASS] ④ working→queued ⇒ 行移入待派发区
  [PASS] ④ queued→dispatched ⇒ 行移入进行中区
  [PASS] ③ 合法转换 queued → dispatched rc=0
  [PASS] ③ 合法转换 dispatched → working rc=0
  [PASS] ③ 合法转换 working → qa rc=0
  [PASS] ③ 合法转换 qa → qa_pass rc=0
  [PASS] ③ 合法转换 qa → qa_fail rc=0
  [PASS] ③ 合法转换 qa_fail → working rc=0
  [PASS] ③ 合法转换 qa_pass → merging rc=0
  [PASS] ③ 合法转换 merging → merged rc=0
  [PASS] ③ 合法转换 merged → released rc=0
  [PASS] ③ blocked 有人工恢复出口（重新排队）
  [PASS] ③ 非法转换 queued → merged rc=1（fail loud）
  [PASS] ③ 失败信息点名「非法状态转换」（queued → merged）
  [PASS] ③ 非法转换 qa → merged rc=1（fail loud）
  [PASS] ③ 失败信息点名「非法状态转换」（qa → merged）
  [PASS] ③ 非法转换 dispatched → qa_pass rc=1（fail loud）
  [PASS] ③ 失败信息点名「非法状态转换」（dispatched → qa_pass）
  [PASS] ③ 非法转换 released → queued rc=1（fail loud）
  [PASS] ③ 失败信息点名「非法状态转换」（released → queued）
  [PASS] ③ 非法转换 queued → queued rc=1（fail loud）
  [PASS] ③ 失败信息点名「非法状态转换」（queued → queued）
  [PASS] ③ 失败信息给出从 queued 的允许集
  [PASS] ③ 同态自转也回显允许集（P3-1 · queued → queued）
  [PASS] ③ 同态自转也回显允许集（P3-1 · working → working）
  [PASS] ③ 未知状态 ⇒ rc=2（用法错误，与「非法转换」区分）
  [PASS] ① AC1 完整回执通过（）
  [PASS] ① 校验摘要给出回执份数（不静默 0 份）
  [PASS] ① 缺 deviation ⇒ rc=1
  [PASS] ① 点名缺失字段 deviation
  [PASS] ① 缺 gates.full.note ⇒ rc=1
  [PASS] ① 点名缺失字段 note
  [PASS] ① 空 evidence ⇒ rc=1（空证据 = 未验证）
  [PASS] ① 点名 evidence
  [PASS] ① gates.full.rc=0 但 fail>0 ⇒ rc=1（自述与计数矛盾）
  [PASS] ① id 与文件名不一致 ⇒ rc=1
  [PASS] ① 点名 id 不一致
  [PASS] ① 回执脱离队列（无对应行）⇒ rc=1
  [PASS] ① 队列文件不存在 ⇒ rc=2（用法错误）
  [PASS] ① receipt-line 缺回执路径与 --id ⇒ rc=2（不再内置 T566 默认）
  [PASS] ① 失败文案指路 --id（不静默回落到某个固定回执）
  [PASS] ① receipt-line 遇 pushed:false ⇒ rc=1（拒绝机读首行）
  [PASS] ① 点名 pushed:true 是机读首行的前提
  [PASS] ① pushed:false 时零机读行产出（不产假机读行）
  [PASS] ① receipt-line 遇缺 pushed 字段 ⇒ rc=1
  [PASS] ① 缺 pushed 字段被点名
  [PASS] ① 缺 pushed 字段时零机读行产出
  [PASS] ② 夹具：已推送提交与未推送提交不同 sha
  [PASS] ② AC2 pushed:true 且 head 在远端 ⇒ rc=0（）
  [PASS] ② 摘要声明 push 复核已启用
  [PASS] ① receipt-line pushed:true 且 head 在远端 ⇒ rc=0（）
  [PASS] ① 机读首行逐字（gates=ok,ok · acs=2/2）
  [PASS] ① receipt-line --id 拼 --receipts/<id>.receipt.json ⇒ rc=0（P3-3）
  [PASS] ① --id 形态的机读首行逐字
  [PASS] ② AC2 pushed:true 与远端不一致 ⇒ rc=1
  [PASS] ② 点名 git ls-remote 复核失败
  [PASS] ② 点名是 pushed:true 的断言失败
  [PASS] ② receipt-line 遇假 pushed（head 未推送）⇒ rc=1
  [PASS] ② 假机读行零产出（stdout 无机读行）
  [PASS] ② receipt-line --no-push-check 是显式逃生阀（需人显式加旗标）
  [PASS] ② receipt-line 跳过复核必打 NOTICE（不静默）
  [PASS] ② --no-push-check 是显式逃生阀（rc=0）
  [PASS] ② 跳过复核必打 NOTICE（不静默假绿）
  [PASS] ② pushed:false ⇒ 不做远端复核（rc=0）
  [PASS] ② 远端无任何 head ⇒ rc=1（不把「推不上去」当通过）
  [PASS] ② 点名远端为空
  [PASS] ② 远端不可用 ⇒ rc=1（fail loud，不静默放过 AC2）
  [PASS] ⑤ 本仓 docs/tasks-state.md 与 docs/queue.jsonl 渲染一致（提交前必须 render）
  [PASS] ⑤ 队列单源在位
  [PASS] ⑤ 本任务回执样例在位（schema 自我践行）
  [PASS] ⑤ 本仓队列 + 回执校验通过（push 复核由合并前另行联网跑）
  [PASS] ⑤ 未知命令 ⇒ rc=2
  [PASS] ⑤ 未知命令点名
RESULT: PASS

==================== T4 汇总 ====================
  46  PASS         编排器阶段 1 队列与回执（T566 · AC1–AC4）：回执 schema 五变异 + pushed 与 ls-remote 双向（本地 bare 仓）+ 状态机跳级必红 + 渲染幂等/手改必红/标记缺失不改盘
  ---
  SKIP=0 · DEGRADE=0 · NOTE=0
  （SKIP 含用例内 [SKIP]/SKIP: 行；DEGRADE=能力降级，默认豁免、full 计分；NOTE 按白名单分轴）
  NOTE 白名单命中（0 条）：无
缓存目录: /tmp/nao-t4.dWlJM8（已清理）
RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=0 · NOTE白名单=0）
```

### case 06

`bash tests/t4/run.sh --case 06`

```text

===== 用例 06: 契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态替代 =====
  -- manifest: has_prompts=0 refs_prompts=0 skills=["./.agents/skills/nao-fleet/SKILL.md","./.agents/skills/frontend-design/SKILL.md"]
  [PASS] AC8: manifest 无 pi.prompts
  [PASS] AC8: manifest 未引用 .agents/prompts/*.md
  [PASS] AC8: fleet 仍以 --append-system-prompt 常驻注入角色卡（BR2）
  -- check rc=0 · check: OK · roles=7 · files=53
  [PASS] AC6: 机制 check（含交叉引用校验）exit=0
  [PASS] AC6: check 输出 OK
  [PASS] AC6: 无指向废弃路径 .agents/skills/checklists 的 live 引用
  -- NAO_SKILLS 引用 3 条 · 不可达: 无
  [PASS] AC6: 全部 $NAO_SKILLS/.agents 引用在包内可达
  [NOTE] static-contract AC6 文档侧（README / ARCHITECTURE / 模板对齐）→ T3 关闭，本轮不判
  [PASS] AC2: nao-fleet SKILL.md 存在
  [PASS] AC2: description/正文含触发条件（何时加载）
  [PASS] AC2: 含「拉起舰队」指引
  [PASS] AC2: nao-fleet 的 name == 父目录名
  [PASS] AC2: frontend-design 的 name == 父目录名
  [NOTE] static-contract AC2 动态发现（真 pi 加载）见 T4-02；无凭据时以本条静态断言为替代证据
  -- scripts: test=[npm run test:agents && npm run test:t4] full=[T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1 bash tests/t4/run.sh] prepack=[npm run test:agents]
  [PASS] T522 BR1: scripts.test 串联 npm run test:t4
  [PASS] T522 BR4: test:t4:full 同时含两严格轴 A(T4_ALLOW_MISSING=0)+R(T4_REQUIRE_FULL=1)
  [PASS] T522 BR5: scripts.prepack 仅 test:agents（无直连 test:t4 亦无 npm test 间接引入）
  [PASS] T522: 全部用例（43 例）以 t4_exit|t4_skip|exec 收尾
  [PASS] T536: helper 正向 —— t4_cli_supports init 命中 nao-skill 已有子命令
  [PASS] T536: helper 负向 —— 不存在的子命令不命中
  [PASS] T536 BR4: lib.sh 内 printf…| grep 同型管道 0 处
  [PASS] A: 期望常量文件存在（tests/t4/expected-roles.txt）
  -- 真清单 vs 期望（角色数期望 7）：problems=无
  [PASS] A: 真 roles.yaml + 真卡集与期望文件一致（角色集 / 别名 / card↔roles）
  [PASS] A: 存在 check 汇总行（check: OK · roles=…）
  [PASS] A: check **汇总行**报 roles=7（与期望文件一致）
  [PASS] A 负控: 自包含夹具基线一致（与真清单状态无关）
  [PASS] A 负控(摘条目): 漂移 ⇒ 断言翻红
  [PASS] A 负控(摘条目): 精确点名（清单缺少: qa）
  [PASS] A 负控(摘条目): 文案含可执行指路
  [PASS] A 负控(摘条目): 复位后与**变异前快照**一致
  [PASS] A 负控(加未登记卡): 漂移 ⇒ 断言翻红
  [PASS] A 负控(加未登记卡): 精确点名（probe-role.md：卡存在但 roles.yaml 未登记（孤儿卡））
  [PASS] A 负控(加未登记卡): 文案含可执行指路
  [PASS] A 负控(加未登记卡): 复位后与**变异前快照**一致
  [PASS] A 负控(删别名): 漂移 ⇒ 断言翻红
  [PASS] A 负控(删别名): 精确点名（uiux-designer：别名 [uiux] 与期望 [uiux,ui-designer,uiux-designer]）
  [PASS] A 负控(删别名): 文案含可执行指路
  [PASS] A 负控(删别名): 复位后与**变异前快照**一致
  [PASS] A 负控(卡文件缺失): 漂移 ⇒ 断言翻红
  [PASS] A 负控(卡文件缺失): 精确点名（qa：卡文件不存在（test-engineer.md））
  [PASS] A 负控(卡文件缺失): 文案含可执行指路
  [PASS] A 负控(卡文件缺失): 复位后与**变异前快照**一致
  [PASS] A 负控(frontmatter role 不一致): 漂移 ⇒ 断言翻红
  [PASS] A 负控(frontmatter role 不一致): 精确点名（qa：卡 frontmatter role=qa-mutated 与清单 id 不一致）
  [PASS] A 负控(frontmatter role 不一致): 文案含可执行指路
  [PASS] A 负控(frontmatter role 不一致): 复位后与**变异前快照**一致
  [PASS] A: 期望文件与真清单不一致 ⇒ 断言必红（防自洽空转）
  [PASS] A: 点名期望里写错的角色名（清单缺少: rd-infraX）
  [PASS] A: 同时点名真清单多出的（清单多出: rd-infra）
  [PASS] AC2 护栏: 用例集无命令行位裸 tmux 调用（行级 lint；累积残留类由 cases/20 的 reset_lab 覆盖）
  [PASS] AC2 护栏负控: 人造违规被命中（非空转）
  [PASS] AC2 护栏负控: 点名直接命令行位违规文件
  [PASS] AC2 护栏负控: 点名包装函数内违规文件
  [PASS] AC2 护栏负控: 恰 2 条命中（不漏判也不误判）
  [PASS] AC2 护栏: 合规调用（tmux -S）不计入违规
  [PASS] AC2 #93: 缺陷 fixture 存在（fixtures/93-all-server-tail1/defect.sh）
  [PASS] AC2 #93: 负控 fixture 存在（fixtures/93-all-server-tail1/controls.sh）
  [PASS] AC1 #93: pre-#93 旧 lint 快照存在（fixtures/pre93-host-pane-refs.sh）
  [PASS] AC2 #93: fixture 标注来源（Issue #93）
  [PASS] AC2 #93: fixture 标注日期（2026-11-09）
  [PASS] P3-3 #93: 旧 lint 快照标注来源 sha（main@2497d87）
  [PASS] P3-3 #93: 旧 lint 快照标注日期（2026-11-09）
  [PASS] AC1 #93: 同一份缺陷输入 ⇒ 新语义 lint 必红（补上旧 lint 的零覆盖）
  [PASS] AC2 #93: 恰 2 条命中（包装函数调用 + 显式 -S 直调）
  [PASS] AC2 #93: 点名包装函数调用形态
  [PASS] AC2 #93: 点名显式 -S 直调形态
  [PASS] AC4 #93 负控: 会话定向采样 + 挑尾不纳管（不是全 server 计数）
  [PASS] AC4 #93 负控: 全 server 计数但不挑尾不纳管
  [PASS] AC4 #93 负控: 全 server 计数但取首行不纳管
  [PASS] AC4 #93 负控: 跨行写法不纳管（行级 lint 不拼接续行，已知漏判）
  [PASS] AC4 #93 负控: 两行变量拼装不纳管（行级静态不追数据流，已知漏判）
  [PASS] P3-1 #93 负控: 分号后接无关 tail -1 不得命中（跳语句假阳）
  [PASS] P3-1 #93 负控: 逻辑与后接无关 tail -1 不得命中（跳语句假阳）
  [PASS] P3-2 #93 负控: 缩进注释先 trim 再判注释符（不得命中）
  [PASS] AC1 #93: **pre-#93 快照版**对同一份缺陷输入仍绿（历史事实；live 旧 lint 被增强不再假红）
  [PASS] AC1 #93 常态护栏: 用例集 0 处「全 server 计数 + 顺序挑尾」组合
  [PASS] AC5 #93 变异(恒假): 复刻断言翻红（rc=1，不静默通过）
  [PASS] AC5 #93 变异(恒假): 点名翻红的 AC2 断言
  [PASS] AC5 #93 变异(丢 -a 判据): 复刻断言翻红（rc=1，不静默通过）
  [PASS] AC5 #93 变异(丢 -a 判据): 点名计数断言翻红（命中了不纳管类）
  [PASS] #96 护栏: 全 cases 目录 0 处命令位 herdr 绕过唯一入口或缺 --session（白名单除外）
  [PASS] #96 护栏: 含 lib-backend.sh 的同判据也 0 命中（唯一入口体内两条均带 --session，非靠函数体豁免兜住）
  [PASS] P3-3 负控①: 裸调用 + 行尾注释伪造白名单（herdr workspace list # herdr --version）⇒ 必红
  [PASS] P3-3 负控①: 点名该违规文件（不是笼统失败）
  [PASS] P3-3 负控②: herdr --version 之后接 ; 裸调用 ⇒ 必红（不是「行内出现即豁免」）
  [PASS] P3-3 负控②: 点名该违规文件
  [PASS] P3-3 正控: 整行只有 herdr --version ⇒ 放行（白名单命中即跳）
  [PASS] #96 护栏负控: 人造违规被命中（非空转）
  [PASS] #96 护栏负控: 恰 6 条命中（不漏判也不误判）
  [PASS] #96 护栏负控: 点名裸调用（命令行位缺 --session）
  [PASS] #96 护栏负控: 点名绕过唯一入口（函数体外即使带 --session 也算旁路）
  [PASS] #96 护栏负控: 点名唯一入口体内缺 --session（不做函体豁免）
  [PASS] #96 护栏负控: 点名 herdr --help（白名单不是「所有 -- 旗标」）
  [PASS] #96 护栏负控: 点名「注释伪造白名单」（与 P3-3 负控① 同形态）
  [PASS] #96 护栏负控: 点名「白名单片段后接裸调用」（与 P3-3 负控② 同形态）
  [PASS] #96 护栏: 唯一入口体内带 --session ⇒ 放行（合规形态不误判）
  [PASS] P3-4 护栏: 函数体写法「_be_herdr_exec () {」（括号前带空格）同样识别 ⇒ 体内合规行仍放行
  [PASS] #96 护栏正控: 仅 herdr --version ⇒ 白名单放行
  [PASS] #96 护栏: herdr --version + 行尾注释 ⇒ 剥注释后整行等值 ⇒ 放行
  [PASS] #96 护栏: 注释行（含缩进注释）不纳管
  [PASS] #96 护栏正控: 只 herdr --version ⇒ 判据放行（白名单命中即跳）
  [PASS] #96 变异自证(允许裸调用): 复刻断言翻红（rc=1，不静默通过）
  [PASS] #96 变异自证(允许裸调用): 点名翻红的是「人造违规必红」断言
  [PASS] #96 变异自证(丢白名单): 复刻断言翻红（rc=1）
  [PASS] #96 变异自证(丢白名单): 点名翻红的是「常态目录 0 命中」（白名单承重，不是摆设）
  [PASS] MIN_PI_VERSION 可从脚本抽出且为 x.y.z（得到「1.4.0」）
  [PASS] MIN_PI_VERSION 在脚本内仅出现 1 次（文案/判据一律派生，无双源）
  [PASS] 比较判据用派生 MIN_PI_MINOR（无魔术数 4）
  [PASS] 旧魔术数「c2 >= 4」已不存在
  [PASS] major 阈值同源派生（c1 > MIN_PI_MAJOR）
  [PASS] 运行前提小节标题插值常量
  [PASS] ✓/✗ 两行文案均插值常量
  [PASS] 正控: 桩 pi == 常量 1.4.0 ⇒ check rc=0（恰好达标的边界）
  [PASS] 正控: 达标边界仍 PASS，且 ✓ 行阈值 = 常量值
  [PASS] 负控: 夹具副本阈值已抬到 9.9.9
  [PASS] 负控: 阈值抬到 9.9.9 ⇒ check rc≠0（聚合）
  [PASS] 负控: ✗ 行「实际」=桩版本、「阈值」=常量（两段都随源走）
  [PASS] 负控: 小节标题同源插值（9.9.9）
  [PASS] 负控: 无「1.4.0 < 1.4.0」——实际==常量时文案与判据仍自洽
  [PASS] P3-2: 变异副本确与负控副本不同（✗ 行阈值已硬编码 1.4.0）
  [PASS] P3-2 变异: 硬编码 ✗ 行后仍 rc≠0（不是靠 rc 绊住，靠文案）
  [PASS] P3-2 变异: 旧缺陷如实复现（文案回头 1.4.0 < 1.4.0）
  [PASS] P3-2 变异: 「✗ 行阈值==常量」判据在变异上必红（断言非空转）
  [PASS] P3-2 变异: 「无矛盾文案」判据在变异上计数 1（断言非空转）
  [PASS] 全段结束后真脚本未被改动（阈值仍为 1.4.0，只在副本里变异）
  [PASS] E2-1 基准：脚本单源 MIN_PI_VERSION = 1.4.0（x.y.z）
  [PASS] E2-1 扫描面非空：现行文档 *.md ≥ 40 个（git ls-files 可用；否则下面「全绿」会无对象空转）
  [PASS] E2-1① 现仓全绿：文档面 pi 下限 == 脚本单源（漂移 0 · 未归类 0）
  [PASS] E2-1① 扫描非空转：声明**处数** ≥ 9（实测 13；留裕度，防正常收敛假红）
  [PASS] E2-1① 扫描非空转：声明**文件数** ≥ 6（实测 9；留裕度）
  [PASS] E2-1④ 历史时点不参与下限比对：codegraph.md 无「≥/低于」声明（as-of 行按「截至」标注归类）
  [PASS] E2-1④ codegraph.md:21 确在完备性扫描面内（靠「截至」被放过 —— 机制承重，不是文件名白名单）
  [PASS] E2-1 夹具自证：未变异副本同样全绿（基准不是只有真仓能过）
  [PASS] E2-1② 变异锚点：副本单源已抬到 9.9.9
  [PASS] E2-1② 脚本常量抬 9.9.9（副本）⇒ 断言必红并点名 README.md:行（文档未动）
  [PASS] E2-1② 同轮点名另一处（不是只报首个就收工）
  [PASS] E2-1③ 变异锚点：副本 README 已改为 9.9.9（脚本未动）
  [PASS] E2-1③ 文档改 9.9.9（副本）⇒ 同样必红（脚本→文档、文档→脚本两个方向都能抓）
  [PASS] E2-1④ 变异锚点：副本 codegraph.md 的「截至」已摘掉
  [PASS] E2-1④ 摘掉「截至」⇒ 完备性判据必红（历史时点豁免是标注机制，不是按文件名硬编码）
  [PASS] B1: 被测脚本存在
  [PASS] B1: 5 个 lint helper 均已定义（缺任一 ⇒ 其负控断言会因 127/空输出假绿）
  [PASS] B1: 门面台账存在（tests/t4/fixtures/term-legacy-allowlist.txt）
  [PASS] B1① NAO_TERMINAL 赋值点恰 1 处（默认值唯一；三期只改这一行）
  [PASS] P2① 唯一赋值点 = 默认 **herdr**（未设/空串两种拼写走同一处）
  [PASS] P2① 反向断言：默认不再是 tmux（flip 真生效，不是两处赋值共存）
  [PASS] B1② 门面函数 term_require 恰 1 处定义
  [PASS] B1② 门面函数 term_snapshot 恰 1 处定义
  [PASS] B1② 门面函数 term_liveness 恰 1 处定义
  [PASS] B1② 门面函数 term_argv 恰 1 处定义
  [PASS] B1② 门面函数 term_deliverable 恰 1 处定义
  [PASS] B1② 门面函数 term_spawn 恰 1 处定义
  [PASS] B1② 门面函数 term_deliver 恰 1 处定义
  [PASS] B1② 门面函数 term_session_start 恰 1 处定义
  [PASS] B1② 门面函数 term_reclaim 恰 1 处定义
  [PASS] B1② 门面函数 term_cleanup 恰 1 处定义
  [PASS] B1② 真脚本：门面外 0 处裸后端调用（标记区 + 台账之外一律红）
  [PASS] B1② 台账可验：函数存在 · 仍含裸调用 · 去重 · 不超 baseline · 不收录渲染层/标记区内函数
  [PASS] B1②/B4 台账头写明 baseline（B2 减 2 / B3 减 3 / B4 减 3 ⇒ 0；只减不增）
  [PASS] B4 台账条目数 = 0（布局段进 tmux 标记区 + cmd_check 的裸调用进 term_session_name 门面）
  [PASS] B1② 负控A: cmd_status 内注入 tmux 调用 ⇒ 旧面 lint 必红（不是空转）
  [PASS] B1② 负控A: 命中并回显被注入的那一行（可定位）
  [PASS] B1② 负控B: cmd_status 内直接调 herdr ⇒ 必红
  [PASS] B1② 负控B: 命中标签点名「herdr-区外」
  [PASS] B1③ herdr 实现区 0 处 tmux 句柄/标题字段名（BR2/BR6 机械兜）
  [PASS] B1③ 负控: herdr 区注入 $TMUX_PANE ⇒ 禁字扫描必红
  [PASS] B1③ 负控: 回显被注入的句柄名
  [PASS] B1③ 负控: herdr 区注入 terminal_title（读标题）⇒ 禁字扫描必红
  [PASS] B1② 负控C1: 已迁移函数留在台账 ⇒ stale 必红（只减不增是断言，不是口头约定）
  [PASS] B1② 负控C2: 台账函数名 typo ⇒ 必红
  [PASS] B1②/B4 负控C3: 条目数超 baseline ⇒ 必红（B4: 0 条上限；自造第 1 条即红）
  [PASS] B1② 负控C4: 标记区内函数混进台账 ⇒ 必红
/tmp/infra566/tests/t4/cases/06-contract-guards.sh: 行 799: REAL_TMUX_B1: 参数为空或未设置
  [PASS] B1④ 真 tmux 可用（桩要转发）
  [PASS] B1④ herdr 模式 check rc=0（herdr 桩 protocol 22）
  [PASS] B1④ herdr 模式 check **加一行**生效后端（BR1 六条之一）
  [PASS] B1④ herdr 模式 check 零 tmux 调用（桩 0 命中）
  [PASS] B1④ 旧后端变量 check ⇒ rc=2（用法守卫，命令未执行 —— D2）
  [PASS] B1④ stderr 点名「已移除」+ herdr 指路（D2 文案）
  [PASS] B1④ 提示恰为单行（不刷屏）
  [PASS] B1④ 守卫先于一切后端调用（桩 0 命中，零副作用）
  [PASS] P2④ herdr 摘要首行 = roles/files 计数（layout= 字段随 tmux 布局删除 —— D3）
  [PASS] P2④ herdr 摘要恒 3 行（摘要 + codegraph 态 + 生效后端）
  [PASS] P2-1 夹具自证：临时仓已有 1 条 stash（判据非空转；真仓全程未造 stash）
  [PASS] P2-1 夹具自证：该 stash 的 %ct 在 7 小时前以上（#130 D1 年龄阈值下仍会 warn）
  [PASS] P2-1① 注入「有 stash 的临时仓」：摘要行仍在（正锚）
  [PASS] P2-1① 该形态首行 ≠ golden（QA 实测的假红面 —— 现由注入规避，而非剥行）
  [PASS] P2-1② 相对基线（同形态无 stash 注入的那一轮）恰 +1 条 warn（闸门真在跑）
  [PASS] P2-1② warn 真出现时**断言仍能抓**：`-v` 恰 1 条 stash warn（未被本用例剥掉 ⇒ 非空转）
  [PASS] P2-1② 该 warn 含 BR5 依据（与 cases/35 同文案契约）
  [PASS] P2-1③ 注入非仓根：首行 == golden（不受仓 stash 影响）
  [PASS] P2-1③ 注入非仓根：无 warn= 字段（不新增噪音）
  [PASS] P2-1 夹具自证：pop 后临时仓无 stash
  [PASS] P2-1④ pop 掉 ⇒ warn 消失（双向，判据非恒真）
  [PASS] P2① 未设 NAO_TERMINAL（默认）check rc=0
  [PASS] P2① 未设 ⇒ herdr（默认已翻；B1 的「仅 herdr 模式加行」靠本行反向验）
  [PASS] P2① 未设(herdr) check = 3 行（摘要 + codegraph 态 + 生效后端行）
  [PASS] P2① 反向断言：未设(herdr) 与 显式 =tmux 的 check 输出必 **不同**（防 flip 未生效仍全绿）
  [PASS] B2④ herdr 模式 ensure 全败 ⇒ rc=1（T563/AC5；仍是 SPAWN_FAIL 而非 crash）
  [PASS] B2④ herdr 模式 ensure 不再点名「未实现」
  [PASS] B2④ herdr 模式 ensure 失败计入摘要（逐目标 fail loud，不冒充成功）
  [PASS] B2④ herdr 模式 ensure 走 herdr 分支（桩有调用）
  [PASS] B2④ herdr 模式 ensure 零 tmux 调用（后端隔离）
  [PASS] B2④ herdr 模式 ensure 确有 herdr 调用（非空转）
  [PASS] B3④ herdr 模式 close 不再是 exit 4（回收面已接；空 label ⇒ 未运行 rc=0）
  [PASS] B3④ herdr 模式 close 不再点名「未实现」
  [PASS] B3④ close 空现场：幂等成功行（不谎报在线/失败）
  [PASS] B3④ herdr 模式 close 确有 herdr 调用（非空转）
  [PASS] B3④ herdr 模式 close 零 tmux 调用（后端隔离）
  [PASS] B3④ herdr 模式 cleanup --session 不再是 exit 4（幂等：effect=0）
  [PASS] B3④ cleanup 空现场：明确报 effect=0（判 effect 不看 rc）
  [PASS] B3④ herdr 模式 cleanup 不再点名「未实现」
  [PASS] B3④ herdr 模式 cleanup 零 tmux 调用（后端隔离）
  [PASS] B3④ herdr cleanup 缺 --session ⇒ rc=2（显式目标必给）
  [PASS] B3④ 缺参给可执行指路
  [PASS] B3④ 缺参守卫先于一切后端调用（桩 0 命中）
  [PASS] B3④ herdr cleanup --session default 无 --force ⇒ rc=2（放行但零动作）
  [PASS] B3④ default 打印影响面
  [PASS] B3④ 旧「≠default」拒绝文案已退场
  [PASS] B3④ default 零拆场动作
  [PASS] B2④ herdr 模式 session-start --session default ⇒ rc=2（BR9：绝不碰用户会话）
  [PASS] B2④ session-start 拒绝 default 并点名原因
  [PASS] B2④ herdr 模式 session-start 缺 --session ⇒ 非 0（用法守卫）
  [PASS] B2④ session-start 缺参给可执行指路
  [PASS] B2④ herdr 模式 session-start 可用（桩 api snapshot 可应答 ⇒ 已就绪）
  [PASS] B2④ session-start 回显目标会话名
  [PASS] B2④ session-start 的每次 herdr 调用都带 --session nao-b2-start（唯一入口，禁串到 default）
  [PASS] B3④ herdr cleanup 给 -S ⇒ rc=2（-S 只属 tmux 实验场；按后端分派）
  [PASS] B3④ -S 误用：指路 --session
  [PASS] B3④ -S 误用零后端调用（守卫在一切副作用之前）
  [PASS] B1④ NAO_TERMINAL=bogus ⇒ rc=2（fail loud，不静默回落）
  [PASS] B1④ 非法后端回显取值与期望值域
  [PASS] P2① NAO_TERMINAL=（空串）= 未设 ⇒ 按 **herdr** 默认跑（rc=0）
  [PASS] P2① 空串 ⇒ herdr（:- 语义；不是 tmux、也不是非法）
  [PASS] B1④ NAO_TERMINAL=TMUX（大小写不符）⇒ rc=2（空串放过、拼错不放）
  [PASS] P2② app 区间**外**（旧面）token 位 exit 3 = 7（T555 原句不变量；app 侧单列）
  [PASS] P2② app 区间内 exit 3 闸门存在（三件套/窗口/socket/文档前置）
  [PASS] P2② token 位站点总数 = 旧面(7) + app(7)（无区间外游离站点）
  [PASS] P2② 两轴相等（独占行与 token 位当前同值；若有人写成「cmd || exit 3」本断言会把差异摆出来）
  [PASS] P2② 每条 exit 3 文案都给后续动作（重试 / pin 回旧版；T555：tmux 回退指路已随后端删除）
  [PASS] P2② 含后续动作的 exit 3 = 全数（herdr 7 + app 7）
  [PASS] P2② 负控A：摘掉一条 herdr 文案的回退指路 ⇒ 全扫恰 1 条必红（断言不是空转）
  [PASS] P2② 负控B：改成「cmd || exit 3」后独占行数 -1（旧判据会漏掉它）
  [PASS] P2② 负控B：token 级计数不变 ⇒ 新写法被计入（≠ 旧判据）
  [PASS] P2② 负控B：该形态同样受报文指路判据约束（hint 仍在 ⇒ 0 命中）
  [PASS] P2② 负控B2：该形态缺指路时 hint 扫描必红（覆盖到位，不是只计数）
  [PASS] P2② 负控C：app 区间内改「cmd || exit 3」⇒ 独占行总数 −1
  [PASS] P2② 负控C：app 区间 token 位计数不变（app 轴不是空转）
  [PASS] P2③ 测试基座：run.sh 按 BE_BACKEND 显式导出 NAO_TERMINAL（CI 固定后端）
  [PASS] P2③ 测试基座：be_fleet_handles 显式给 NAO_TERMINAL=herdr（T555：单后端，不靠默认值）
  [PASS] P2③ 全部用例：默认值探针块外 0 处 unset / env -u / 空串 NAO_TERMINAL ⇒ 无任何用例在 unset 下跑生产路径
  [PASS] P2③ 扫描面 = 全部用例文件（= run.sh CASE_IDS 登记数；用例增删须两侧同步）
  [PASS] P2③ 最大用例编号 = run.sh CASE_IDS 末位（退役编号不复用）
  [PASS] P2③ 默认值探针块白名单 = 显式文件清单（06 默认值段 · 28 B1① 反向断言 · 44 AC1「默认=herdr」反向断言 · 45 #175 AC4「app 终端内未设 NAO_TERMINAL」；新增须显式改本断言，不靠计数漂移）
  [PASS] P2③ 负控：探针块外 unset ⇒ 扫描必红并点名（判据非空转）
  [PASS] P2③ 负控：探针块外 env -u ⇒ 扫描必红
  [PASS] P2③ 正控：标记块内的 unset/空串被放过（白名单生效；否则真用例无法验默认值）
  [PASS] E1: CARD_MAX_LINES 保持 200（不设硬限；阈值仍由脚本单点给）
  [PASS] E1: 真仓 check -v rc=0（基线不改 rc）
  [PASS] E1: check -v 输出卡预算基线行（可观测）
  [PASS] E1: 基线最大卡与实测最大卡同名（product-manager.md）
  [PASS] E1: 基线行数与实测一致（136 行）
  [PASS] E1: 基线阈值取自脚本常量（200 行）
  [PASS] E1: 基线最大占比与实测一致（68.0%）
  [PASS] E1 夹具：最大卡已超阈值（product-manager.md 201 行）
  [PASS] E1 超阈值：check rc 仍 0（warn-only，不设硬限）
  [PASS] E1 超阈值：逐卡行报 !（点名 product-manager.md）
  [PASS] E1 超阈值：报出实际行数 201
  [PASS] E1 超阈值：基线给最大占比 100.5%（>100% 可见）
  [PASS] E1 变异：移除基线实现 ⇒ 同一判据取值为 0（断言非空转）
  [PASS] P3-1 正控：宿主 NAO_SKILLS=<真仓> ⇒ 夹具仍读**夹具**的 .agents（`-u NAO_SKILLS` 承重）
  [PASS] P3-1 负控镜像：不清 NAO_SKILLS ⇒ 读到真仓（同一夹具相反结果 ⇒ 正控有判别力）
  [PASS] P3-1 正负控输出必不同（否则「清了但没用」也会绿）
  [PASS] P3-1 静态审计：本用例全部 check 调用点都已清/给 NAO_SKILLS（新增未清点必红）
  [PASS] P3-1 审计负控：无菌样本的那处调用必被点名（行号 2；判据非空转）
  [PASS] P3-1 审计正控：同块内出现 NAO_SKILLS ⇒ 放过（白名单生效，否则真用例全红）
  [PASS] D2① 单源定义处恰 1 处（tests/t4/lib.sh）
  [PASS] D2② 单源集合 == 收敛前各点清理变量的**并集**（8 个，只增不减）
  [PASS] D2③ 调用点零手写（tests/ 下 「env -u <HERDR 变量>」 直写 = 0 行）
  [PASS] D2④ lib-backend 夹具经单源清（引用 + 缺失时 fail loud 的守卫）
  [PASS] D2④ cases/06 「B3_CLEAN_ENV」 改为引用单源
  [PASS] D2④ cases/28 `B2_ENV` 改为引用单源（T555：原 TMUX_FIELD_ENV 随 tmux 夹具退役）
  [PASS] D2④ cases/28 四处直连（herdr 场负控 ×2 + B3 桩场 ×2）改为引用单源
  [PASS] D2⑤ 派生参数数 = 2×8（「env -u <名>」 成对；形态可运行）
  [PASS] D2⑥ 变异锚点：副本单源只剩 7 个（「HERDR_SOCKET_FILE」 已删）
  [PASS] D2⑥ 变异自证：删一个变量 ⇒ D2② 必红（枚举收紧蒙混不过）
  [PASS] D2⑦ 变异锚点：副本单源已含新增的 9 个变量
  [PASS] D2⑦ 新增一个 HERDR_* 只改单源一行 ⇒ 派生参数自动 18（调用点零改动）
  [PASS] D2⑦ 新增后 tests/ 仍零手写（引用形态不变 ⇒ 不靠改调用点）
  [PASS] D2⑧ 夹具清理参数默认 = 单源全集（8 对 = 16 行）
  [PASS] D2⑧ 显式豁免一个变量 ⇒ 清理参数只剩 7 对（14 行）
  [PASS] D2⑧ 被豁免的 HERDR_PANE_ID 不再出现在清理参数里（故意注入能活到子进程）
  [PASS] D2⑧ 豁免逻辑单点派生（定义 1 + be_run_fleet 调用 1；不复制到各用例）
  [PASS] D2⑧b 逗号分隔也生效（8−2=6 对 = 12 行）
  [PASS] D2⑧b 逗号分隔时两个变量都真被豁免（不是只认首个）
  [PASS] D2⑨ 探针自证：直接跑桩时能看见 HERDR_ENV（判据非空转）
  [PASS] D2⑨ 夹具自证：被测桩确实执行（rc=0，非空转）
  [PASS] D2⑨ 行为反渗漏：父进程注入 8 个 HERDR_* ⇒ 被测子进程 env 里 0 条（验进程真实 env，不是 argv 文本）
  [PASS] D2⑩ 夹具自证：被测桩确实执行（rc=0，非空转）
  [PASS] D2⑩③ 上下文真初始化：输出里无『BE_BACKEND: 未绑定的变量』（否则 ① 会因「根本无句柄」空转）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_ENV=HOSTLEAK-env 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_SESSION=HOSTLEAK-sess 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_SOCKET_PATH=/HOSTLEAK/prod.sock 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_SOCKET_FILE=/HOSTLEAK/f 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_PANE_ID=HOSTLEAK-pane 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_WORKSPACE_ID=HOSTLEAK-ws 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_TAB_ID=HOSTLEAK-tab 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩① 清理生效：宿主值 HERDR_BIN_PATH=/HOSTLEAK/bin 不在子进程 env（逐条钉值，不数条数）
  [PASS] D2⑩② 注入在清理之后：实验句柄 HERDR_ENV=1 在场
  [PASS] D2⑩② 注入在清理之后：HERDR_SESSION = 本实验场会话名
  [PASS] D2⑩② 注入在清理之后：HERDR_SOCKET_PATH = 实验根下该会话目录（/tmp/nao-t4.YXQOo0/d2h-cfg-3818007）
  [PASS] D2⑩② 注入在清理之后：NAO_TERMINAL=herdr 在场（父给定为 tmux ⇒ 只能来自注入，两种后端下都承重）
  [PASS] D2⑩② 注入真覆盖了父值（NAO_TERMINAL 不再是父给定的 tmux）
  [PASS] E2-2 夹具自证：临时仓有 1 条 stash（判据非空转；真仓未造 stash）
  [PASS] E2-2② 旁证（直连脚本 -v）：注入根 + 阈值 0 ⇒ 恰 1 条 stash warn（闸门活着、根注入本来生效）
  [PASS] E2-2② 旁证点名滞留内容（判据锚在闸门文案上，不是泛化的 warn 汇总数）
  [PASS] E2-2① t4_run_shim 基线（非仓根）：正锚在场（空输出不会空转通过）
  [PASS] E2-2① t4_run_shim：注入根与外层基线 **warn 数相同**（宿主注入根已被清掉；无关 warn 不参与）
  [PASS] E2-2① be_run_fleet 基线（非仓根）：正锚在场（非空转）
  [PASS] E2-2① be_run_fleet：注入根与外层基线 **warn 数相同**（宿主注入根已被清掉）
  [PASS] E2-2 解耦夹具自证：该夹具确有**非 stash** 的 warn（product-manager.md 超卡预算）
  [PASS] E2-2 解耦夹具经 helper：基线确有非 stash warn（N=1）
  [PASS] E2-2③ 解耦（P3-2）：无关 warn 在场时注入根仍不改变 warn 数（本组不会被卡预算 warn 带红）
  [PASS] E2-2④ 变异锚点：副本 lib.sh 的 `-u NAO_STASH_ROOT` 已删
  [PASS] E2-2④ 单点锚点：门面的动态兜底调用恰 1 处
  [PASS] E2-2④ 变异锚点：副本已中和动态兜底（NAO_STASH_ROOT 不再被清）
  [PASS] E2-2④ 变异副本 lib.sh 语法仍合法（红点只能来自判据）
  [PASS] E2-2④ 变异副本 lib-backend.sh 语法仍合法
  [PASS] E2-2④ 反空转（t4_run_shim）：删掉 `-u` ⇒ 注入根复活 ⇒ warn 恰 +1（基线 0 ⇒ 1）
  [PASS] E2-2④ 反空转（be_run_fleet）：删掉 `-u` ⇒ 注入根复活 ⇒ warn 恰 +1（基线 0 ⇒ 1）
  [PASS] E2-2⑤ 单点①：t4_run_shim 带 `env -u NAO_STASH_ROOT` 恰 1 处
  [PASS] E2-2⑤ 单点②：净化入口定义恰 1 处（「be_clean_env」，Q7）
  [PASS] E2-2⑤ 单点②：净化入口的调用点恰 1 处（be_run_fleet；调用点不再手写 「-u」）
  [PASS] E2-2⑤ 行为面：宿主导出 NAO_STASH_ROOT ⇒ 门面净化参数含它（清空面非空转）
RESULT: PASS

==================== T4 汇总 ====================
  06  PASS         契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态替代
  ---
  SKIP=0 · DEGRADE=0 · NOTE=2
  （SKIP 含用例内 [SKIP]/SKIP: 行；DEGRADE=能力降级，默认豁免、full 计分；NOTE 按白名单分轴）
  NOTE 白名单命中（2 条）：06:static-contract · 06:static-contract
缓存目录: /tmp/nao-t4.YXQOo0（已清理）
RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）
```

### case 36

`bash tests/t4/run.sh --case 36`

```text

===== 用例 36: PRD 结构探针（Q8 · warn-only）：缺 AC 组 / 超行数 / 老日期不追溯 / 空文件拒判合格 / SINCE 非法回落 / warn= 不污染 / 本仓输出与探针关闭逐字一致 + 三条变异负控 =====
  [PASS] 前置：被测脚本存在
  [PASS] ① 缺组：check rc=0（warn-only 不改 rc）
  [PASS] ① 缺组：恰 1 条提示行
  [PASS] ① 点名缺项（AC 分组 4 < 5）
  [PASS] ① 点名具体文件
  [PASS] ② 夹具自证：文件 >150 行（166 行）
  [PASS] ② 超行数：check rc=0
  [PASS] ② 默认模式仍**恰 1 条**聚合提示（不按文件刷屏）
  [PASS] ② 聚合提示给出违规份数（2 份）
  [PASS] ② -v 展开到超行数那份文件
  [PASS] ② -v 点名超行数
  [PASS] ③ 老日期（2026-10-01）即使缺组也不提示（只剩 ① 那 1 条）
  [PASS] ③ 老文件不出现在提示里（不追溯）
  [PASS] ④ 0 字节：计入违规份数（不得静默当合格）
  [PASS] ④ -v 点名空文件
  [PASS] ④ -v 点名「不可读或空文件（拒绝判为合格）」
  [PASS] ⑤ 非法取值：-v 点名「非法（应为 YYYY-MM-DD）」
  [PASS] ⑤ 非法取值：说明回落默认阈值
  [PASS] ⑤ 非法取值：仍按默认阈值报同一 1 条（行为不漂）
  [PASS] ⑥ 摘要里不出现 warn=（PRD 提示不计入 warn 计数）
  [PASS] ⑥ 摘要行仍在（rc=0 正常路径）
  [PASS] ⑦ 负控锚点：副本已删掉探针调用（自证变异生效）
  [PASS] ⑦ 本仓：探针零输出（无 ≥2026-11-18 的 PRD）
  [PASS] ⑦ 本仓：check 输出与「探针关闭」逐字一致（md5 相等 ⇒ 既有 golden 不受本探针影响）
  [PASS] N1 删掉探针调用 ⇒ 同一夹具 0 条提示（① 的判据非空转；还原即复绿）
  [PASS] N2 负控锚点：原脚本排除名单含 PRD 提示前缀
  [PASS] N2 负控锚点：副本已去掉排除（变异生效）
  [PASS] N2 去掉排除名单 ⇒ 摘要出现 warn=（⑥ 必红 ⇒ 排除名单是承重的）
  [PASS] N3 负控锚点：原脚本含「老日期跳过」一行
  [PASS] N3 负控锚点：副本过滤已中和（变异生效）
  [PASS] N3 中和追溯过滤 ⇒ 老文件被报（③ 必红 ⇒ 过滤是承重的）
RESULT: PASS

==================== T4 汇总 ====================
  36  PASS         PRD 结构探针（Q8 · warn-only）：缺 AC 组 / 超行数 / 老日期不追溯 / 空文件拒判合格 / SINCE 非法回落 / warn= 不污染 / 本仓输出与探针关闭逐字一致 + 三条变异负控
  ---
  SKIP=0 · DEGRADE=0 · NOTE=0
  （SKIP 含用例内 [SKIP]/SKIP: 行；DEGRADE=能力降级，默认豁免、full 计分；NOTE 按白名单分轴）
  NOTE 白名单命中（0 条）：无
缓存目录: /tmp/nao-t4.CYxMP0（已清理）
RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=0 · NOTE白名单=0）
```

## 附录二：push 后在线复核（2026-11-24 · rebase 后二轮）

回执 `head=e4e76fc` 的 `pushed:true` 不是自述 —— 下列输出均为 push 后实跑（`origin` = GitHub 真实远端）：

```text
$ git ls-remote --heads origin | grep feat/566-queue-receipt
e4e6bc8dbbd140a52e403260337d112cffa87524	refs/heads/feat/566-queue-receipt

$ node bin/nao-queue validate --queue docs/queue.jsonl --receipts docs/queue
OK: queue=docs/queue.jsonl（1 行）· receipts=1 份 · push 复核=on(origin)

$ node bin/nao-queue receipt-line --id T566 --queue docs/queue.jsonl --receipts docs/queue
receipt: T566 rd-infra head=e4e76fcced0360cc9a2fc76f5536faddb1e15a86 gates=ok,ok acs=4/4
```

- 回执 `head` = 代码交付提交 `e4e76fc`（回执自身在下一提交落盘，故 head 恒为生成时 tip —— 与实际远端 tip `e4e6bc8` 构成祖先关系，`verifyPushed` 判据即「在远端任一 head 上或为其祖先」）。
- `--no-push-check` 未使用：本条 `validate` 走的就是默认远端复核。

