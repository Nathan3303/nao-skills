# T566 实现报告：编排器阶段 1（队列与回执契约）

- 状态：待验收 · 更新：2026-11-24 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-11-24-orchestrator.md`（§四 契约 / §七 AC1–AC4）· Issue #177 · 分支 `feat/566-queue-receipt`（基线 = `origin/main` + PRD 两提交 `4bf4f77`/`bc98f81`）

## TL;DR

- **交付**：`bin/nao-queue`（render / validate / transition / transitions / receipt-line）· 单源 `docs/queue.jsonl`（1 行）·
  回执 schema 实例 `docs/queue/T566.receipt.json` · `docs/tasks-state.md` 两区渲染标记 · 用例 `tests/t4/cases/46-queue-receipt.sh`（80 断言）。
- **AC**：① 回执缺字段/空证据/自述矛盾/脱离队列 ⇒ 红；② `pushed:true` 用 `git ls-remote` 复核（未推送 ⇒ 红）；③ 跳级/终态出边/自转 ⇒ 红；
  ④ jsonl → md 单向渲染 · 幂等 · 手改后 `--check` ⇒ 红 · 标记缺失 ⇒ rc=2 且不改盘。
- **门禁**：`check` rc=0 ×2 逐字一致（roles=7 · files=53）· 目标用例 `06` / `36` / `42` / `46` 全 **RESULT: PASS**（`46` = 80 PASS / 0 FAIL）。
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

## 门禁与证据（先红后绿，日志在 `/tmp/566-evidence/`）

- `bash tests/t4/run.sh --case 46`：**80 PASS / 0 FAIL**；`--case 06` PASS（NOTE=2 白名单）· `--case 36` PASS · `--case 42` PASS。
- 先红：移走 `bin/nao-queue` ⇒ rc=1 / **57 FAIL**（`red-missing-impl.log`）；恢复 ⇒ rc=0 / 80 PASS（`green.log`）。
- 变异负控：把 `transition` 的允许集判定短路（`if (false && …)`）⇒ rc=1 / **9 FAIL**，红点全在 ③（`red-mutation.log`）；
  按 md5 还原（`07203717…`）⇒ rc=0 / 80 PASS（`green-again.log`）。
- `check` rc=0 ×2 逐字一致（`cmp` IDENTICAL）· `render --check` rc=0 · `validate --no-push-check` rc=0（queue=1 行 · receipts=1 份）。

## 边界遵守

- 未实现 tick / 定时器 / systemd（阶段 2）· 未改 `nao-fleet.sh` 调度行为 · 未动 `.agents/prompts/**` / 发布说明 / `package.json`。
- `tasks-state.md` 结构不变：只加两对标记 + 各一行说明；**既有手写台账一行未删**（迁移到 jsonl 属 PM 台账动作，本批不做）。
- 未把 `bin/nao-queue` 注册进 `package.json`（派单禁改）；当前调用 = `node bin/nao-queue <cmd>`，`bin` 已随包发布。

## 修订

- 2026-11-24 首版（阶段 1 交付）。
