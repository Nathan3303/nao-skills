# T566 编排器阶段 1（队列 / 回执 / 渲染 / 状态机）—— QA 只读复核

- 状态：**一轮 CONDITIONAL（P1×1 · P2×1 · P3×3）→ 二轮复核后状态见 §六**（终版结论 `PASS with followups`）· 2026-11-24 · Owner：qa
- 复核对象：PR #179 · 分支 `feat/566-queue-receipt` @ **25fcdd1**（`7a30fff` 实现 · `25fcdd1` 回执）
- 指针：PRD `docs/prds/2026-11-24-orchestrator.md`（AC1–AC4 为阶段 1）· RD 报告 `docs/reports/566-impl-rd-infra.md` · 实现 `bin/nao-queue` · 用例 `tests/t4/cases/46-queue-receipt.sh`
- 边界：**只读复核**（仅新增本报告），未跑全量（按派单，合并门禁由 PM 跑）；变异/造数全在 `/tmp/qa566/**`，仓内 `git status --porcelain` 复核后仅 `?? .pi/`（会话元数据，与本批无关）。

## TL;DR

- **派单五点全部取证通过（P1/P2 见 §三，均非五点所述判据失效）**：
  1. 承重性：自造变异「移走 `bin/nao-queue`」⇒ **57 FAIL**（rc=1）；「允许集判定短路恒放行」⇒ **9 FAIL**（红点全在 ③）。未复用 RD 日志。
  2. `pushed:true` 确认真调 `git ls-remote`：PATH 包一层 `git` 记录子进程 ⇒ 捕获 `ls-remote --heads <remote>`；假 sha ⇒ rc=1；远端不可达 ⇒ rc=1；`pushed:false` ⇒ **零** git 调用（对照组）。
  3. 渲染幂等：连跑两次 `diff` 空；手改渲染区 ⇒ `--check` rc=1 且逐行点名；再 render ⇒ 手改残留 0，**与首渲染逐字节相同**。
  4. `docs/prds/…orchestrator.md` 结构重排是真因：两个用例文件 **本 PR 零改动**（merge-base 后 0 行），HEAD 上 06 = **331 PASS**、36 = **31 PASS**；把 PRD 换回重排前版本（`bc98f81`）⇒ 两例各 **2 FAIL**。
  5. 状态机：跳级 / 终态出边 / 同态自转各 1 次 ⇒ 全 **rc=1 fail loud**；前两者回显允许集，**同态自转不回显**（P3-1）。
- **P1-1（合并前必须处理）**：分支基点 = `1567991`（#172），**落后 `origin/main` 3 提交**（PM 派单写「base=origin/main+PRD 两提交」不成立）。`tests/t4/run.sh` 双方改同一数组 ⇒ `git merge-tree` 实测 **3 处冲突**；按并集合并后登记例数 = **43**（main 的 45 + 本批 46），而本 PR 的 AGENTS / tests/README / 回执 / 报告都写 **42**。
- **P2-1**：`receipt-line` 对 `pushed:true` **静默跳过** ls-remote 校验（无 NOTICE、无逃生阀提示），可给假 sha 出机读首行且 rc=0 —— 与文件头自述「跳过必打 NOTICE（不静默假绿）」自相矛盾（`validate` 路径正确）。
- 本报告不代替合并门禁：回执自述 `gates.full = 42 例 / 2708 断言 / 0 FAIL` 未由我复跑。

## 一、环境与命令

- 环境：`node v24.22.3` · `git 2.56.0` · 本仓 `feat/566-queue-receipt @ 25fcdd1` · `NAO_SKILLS=/home/nathan/Projects/nao-skills`。
- 分支拓扑（只读）：
  - `git merge-base HEAD origin/main` → `1567991`；`HEAD=25fcdd1`，`origin/main=49ce447`。
  - `git rev-list --count HEAD..origin/main` → **3**（`eca6921` / `002c835` / `49ce447`）；`origin/main..HEAD` → 4。
  - `git ls-remote --heads origin` → `25fcdd1… refs/heads/feat/566-queue-receipt` · `49ce447… refs/heads/main`。
- 基线用例（仓内只读跑）：`bash tests/t4/run.sh --case 46` → `RESULT: PASS`，**80 PASS / 0 FAIL**，`SKIP=0 DEGRADE=0 NOTE=0`，9.2s。
- 真件只读：`node bin/nao-queue render --check` → `OK`，rc=0；`node bin/nao-queue validate`（默认 `--remote origin`，含真 ls-remote）→ `OK: queue=docs/queue.jsonl（1 行）· receipts=1 份 · push 复核=on(origin)`，rc=0。
- 变异底座：`git archive HEAD` 解到 `/tmp/qa566/{base,mutA,mutB}`，用例脚本与仓内同一 blob，未改断言。

## 二、派单五点逐条判定

### 1. cases/46 断言承重（自造变异，不复用 RD 日志）= 过

| 变异（只在 `/tmp` 副本） | 结果 | 红点分布 |
|---|---|---|
| 移走 `bin/nao-queue`（`mv bin/nao-queue …`） | rc=1 · **57 FAIL / 23 PASS** | ①–⑤ 全线（如 `④ AC4 渲染 rc=0` 报 `node:…MODULE_NOT_FOUND`、`④ 渲染产物带 generated 头` 未包含） |
| `cmdTransition` 允许集判定短路：`if (!allowed.includes(to))` → `if (false)` | rc=1 · **9 FAIL / 71 PASS** | **全在 ③**：4 组跳级×2 断言（rc + 点名）+ `③ 失败信息给出从 queued 的允许集` |

- 与 `tests/README.md` 自述数字（57 / 9）**逐一吻合**，且 80 = 57+23 = 9+71（断言总数不变 ⇒ 不是脚本崩掉骗红）。
- 附带实证：同态自转 `queued → queued` 在短路变异下**仍绿** —— 因为它走 `from===to` 分支，与允许集判定是两条独立防线（设计合理）。

### 2. `pushed:true` 必须真调 `git ls-remote`（不是 worker 自述）= 过

夹具：本地 bare 仓 `/tmp/qa566/remote.git` + 已推送提交 `afd1414`；回执取本仓 `docs/queue/T566.receipt.json` 改 `head/pushed`；队列取 `docs/queue.jsonl`。

| 场景 | 命令（要点） | 结果 |
|---|---|---|
| 正控：head = 已推送 sha，`pushed:true` | `nao-queue validate --remote <bare>` | rc=0 `push 复核=on(<bare>)` |
| 假 sha：`head=deadbeef…(40)`，`pushed:true` | 同上 | **rc=1**：`pushed:true 与 git ls-remote 不一致 —— head=deadbeef… 不在 … 的任何 head 里（队列行分支 feat/566-queue-receipt）` |
| 远端不可达（模拟断网）：`--remote https://127.0.0.1:9/x.git` | 同上 | **rc=1**：`git ls-remote --heads … 失败（Failed to connect …）` |
| 调用取证：`PATH=<shim>:$PATH`，shim 记录 argv 后 `exec /usr/bin/git` | 正控场景 | 日志逐字：`ls-remote --heads /tmp/qa566/remote.git` |
| 反证：`pushed:false`，远端不可达 | 同上 | rc=0 且 shim 日志**为空**（不调用远端） |

- ⇒ 判据来自**远端实测**，`pushed:true` 无法靠自述过关；`pushed:false` 不产生网络/子进程调用。
- 真件回执自洽：`head=7a30fff…` 是远端分支 tip `25fcdd1` 的祖先（`git merge-base --is-ancestor` 成立），故真件 `validate`（含 push 复核）rc=0，**`pushed:true` 属实**。

### 3. 渲染幂等 / 手改必被覆盖 = 过

夹具：`/tmp/qa566/render/{q.jsonl,state.md}`（真件副本）。

- 连跑两次：`diff state.1 state.md` → **空**（第 2 次输出 `OK: 无变化（幂等）`）。
- 手改渲染区（把 T566 标题改成「【手改】伪造标题」+ 插入 `- **T999** · 手写行`）：
  - `render --check` → **rc=1**，`不一致（手改会被覆盖；判据见 AC4）`，逐行给出 `行 652 当前/期望`（当前=伪造标题，期望=jsonl 原文）。
  - `render`（无 `--check`）→ rc=0；手改残留计数：伪造标题 **0**、T999 **0**；源标题 **1**；与首渲染 `cmp` **逐字节相同**。
- 真件 `render --check` rc=0 ⇒ 仓内 `docs/tasks-state.md` 当前与 `docs/queue.jsonl` 渲染一致（无未提交手改）。

### 4. PRD 结构重排后 06/36 转绿（零改用例期望）= 过（附一处口径订正）

- **两个用例文件本 PR 零改动**：
  - `git diff origin/main...HEAD -- tests/t4/cases/06-contract-guards.sh | wc -l` → **0**；`…/36-prd-structure-probe.sh` → **0**。
  - HEAD 与 merge-base 的 blob 相等（`git hash-object` = `HEAD:path`）。**口径订正**：`git diff origin/main HEAD` 显示 06 有 2 行差异，那是 main 侧 #175 给 06 白名单新增 `45-app-placement.sh`（本 PR 未碰），不是本批改用例期望。
- HEAD 实跑：`--case 06` → **331 PASS / 0 FAIL**，rc=0（`NOTE=2` 均白名单 `06:static-contract`）；`--case 36` → **31 PASS / 0 FAIL**，rc=0。
- **先红后绿独立复现**（把 HEAD 树的 PRD 换回重排前版本 `git show bc98f81:docs/prds/…`，用例字节不动，副本 `git init` 后跑）：
  - `--case 36` → **2 FAIL**：`⑦ 本仓：探针零输出（无 ≥2026-11-18 的 PRD）（期望=0 实际=1）` + `⑦ check 输出与「探针关闭」md5 不一致`。
  - `--case 06` → **2 FAIL**：`P2① 未设(herdr) check = 3 行（期望=3 实际=4）` + `P2④ herdr 摘要恒 3 行（期望=3 实际=4）` —— 多出的第 4 行就是 `! PRD 结构（warn-only…）`。
  - ⇒ 06 的敏感是**间接的**（`check` 输出恰 3 行的既有断言咬住了 PRD 提示行），不是读了 PRD 内容；结论仍成立：**是 PRD 真对齐结构，不是改用例期望**。

### 5. 状态机非法转换 = 过（同态自转的回显有缺口 → P3-1）

| 输入 | rc | stderr |
|---|---|---|
| 跳级 `queued → merged` | 1 | `非法状态转换 queued → merged（从 queued 允许：dispatched）` |
| 终态出边 `released → queued` | 1 | `非法状态转换 released → queued（从 released 允许：无（终态））` |
| 同态自转 `working → working` | 1 | `非法状态转换 working → working（同一状态不是转换；转换必须改变 state）` ← **未回显允许集** |
| 合法对照 `queued → dispatched` | 0 | `OK: queued → dispatched` |
| 未知状态 `bogus` | 2 | `--from 取值非法：bogus（合法值 queued/…/blocked）` |

## 三、缺陷 / 未过项

- **P1-1（合并阻塞 · 分支落后 main + 登记数会错）**：分支基点 `1567991`，落后 `origin/main` 3 提交；`tests/t4/run.sh` 双方都改 `CASE_IDS/CASE_TITLES/FAST_SKIP_*` ⇒ legacy `git merge-tree` 实测 **3 处冲突**（`<<<<<<< .our`）。并集后登记 = **43 例**（main 的 45 + 本批 46），与本 PR 写死的 **42** 不符；且 rebase 后 `25fcdd1` 的 sha 变化 ⇒ 回执 `head=7a30fff` / `pushed:true` / `gates.full.cases=42` 全部要重生成。**注意 main 侧本身也有既存计数漂移**：`origin/main:AGENTS.md:19` 仍写「39 例」而 `CASE_IDS` 已 42（case 45 由 `eca6921` 加入，未同步计数）⇒ rebase 时不要照抄 39。修法（RD，合并前）：rebase onto main → run.sh 取并集（45/46 同时登记）→ AGENTS.md/tests/README/回执改 **43 例**并重跑门禁 → 更新回执 head 与计数 → 重验 `pushed:true`。
- **P2-1（`receipt-line` 静默绕过 AC2）**：`cmdReceiptLine` 固定 `checkReceipt(..., noPushCheck: true)`，且不打印 NOTICE、无 CLI 逃生阀提示。实测：假 sha + `pushed:true` 的回执 → `receipt: T566 rd-infra head=deadbeef… gates=ok,ok acs=4/4`，**rc=0**（同一回执 `validate` 是 rc=1）。与文件头「只有 `pushed:true` 会显式调用 `git ls-remote`…跳过必打 NOTICE（不静默假绿）」自相矛盾。修法二选一：默认开启复核（`--no-push-check` 跳过时打 NOTICE），或至少打 NOTICE 明示「AC2 未验」。
- **P3-1（同态自转不回显允许集）**：PM 派单要求「跳级 / 终态出边 / 同态自转…必须 fail loud 且回显允许集」；前二者满足，同态自转只说明原因。建议补 `（从 working 允许：qa/blocked）`，并在 cases/46 ③ 补一条断言（当前只断言「非法状态转换」）。
- **P3-2（PRD 内部不一致 · 阶段 2 前对齐）**：§六「回执伪造（自述 pass 无日志）⇒ `gates.full.log` 指向不存在/无 `RESULT: PASS` ⇒ 判红」与 §四 schema（`gates.full` 只有 `rc,cases,pass,fail,note`，**无 log**）冲突；阶段 1 未实现伪造判据，且 AC1 实测接受「自洽但空数」的回执（`cases=0 pass=0 fail=0 rc=0` → rc=0）。若按 §八「只增不删」补 `gates.full.log` 可后置，但**判据文字与 schema 须先对齐**，否则阶段 2 会照一段无法执行的条款实现。
- **P3-3（`receipt-line` 缺省文件名硬编码）**：`positional[0] || path.join(opts.receipts, 'T566.receipt.json')` —— 通用 CLI 的缺省值是某个具体任务号；别的任务忘传参时会静默校验 T566 的回执。建议缺省改为「唯一/必填」，否则报错点名。

## 四、未覆盖与风险

- **未跑全量**（按派单）；回执 `gates.full`（42 例 / 2708 断言 / 0 FAIL / NOTE=17）与 `gates.check` 日志均未独立复跑 —— 以 PM 合并门禁为准。
- 未做视觉/UI 验证（纯 CLI 契约，无 UI 面）。
- 未验证阶段 2/3 面（tick / flock / systemd / `status --json` / board），本批按 PRD 只交阶段 1。
- 风险：若 P1-1 未处理就 squash，run.sh 冲突需手工解，且「42 例」会以错误数字落入 main 与回执（历史回执改 schema/改数成本高，PRD §八 已提示）。
- 复核副作用：所有变异均在 `/tmp/qa566/**`；仓内未改任何实现/用例（`git status --porcelain` 仅 `?? .pi/`）。

## 五、发布建议

- **CONDITIONAL**：派单五点判据全部成立，代码与用例质量可接受；**合并前须收口 P1-1（rebase + 43 例登记 + 回执重生成）**，P2-1 建议本批修（一处小改 + 一条 NOTICE 断言即可），P3-1/P3-2/P3-3 由 PM 裁定「本批修 / 登记到期」。
- 合并门禁由 PM 跑；本报告只报未过项与证据，不代替 `npm test` / `test:t4:full`。
- 本批按 PRD 只交阶段 1（新增文件 + 用例），不影响既有 `tasks-state.md` 手写区（仅两对渲染标记）。

- 修订：2026-11-24 首版（五点取证 + P1/P2/P3 五条）。

## 六、二轮复核（终版）

- 复核对象：PR #179 squash **`b6bb4cb`**（已落 main）· 台账收口 **`f44dda9`**（origin/main tip）· 本报告落盘 PR 的 base = `f44dda9`。
- 方式：**独立实测**（不转述 RD 说法）；造数与变异全在 `/tmp/qa566/**`，仓内只改本文件（见 §六.4）。
- 一轮 §一–§五 **原样保留**（2026-11-24 首轮史证，未按二轮结果回改判定）。

### 6.1 五修逐条复核（每条 = 我的命令 + 实测结果）

1. **P1-1（rebase + 43 例登记）— 部分关闭**（残留 F1）
   - `node -e '…CASE_IDS…' tests/t4/run.sh` → **43**（末三项 `"44" "45" "46"`）；`bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **43**。
   - `bash tests/t4/run.sh --case 46` → rc=0 · **96 PASS / 0 FAIL** · `SKIP=0 DEGRADE=0 NOTE=0`（一轮为 80 断言；本批 +16）。
   - `tests/README.md` 两处 = 43 · 回执 `gates.full.cases=43` · RD 报告 `--list=43`。
   - 但 `git show origin/main:AGENTS.md | grep -oE '[0-9]+ 例' | sed -n 2p` → **`42 例`**（首个 `14 例` 是快档白名单；本行应为 43）⇒ **F1**。
2. **P2-1（`receipt-line` fail loud 且零机读行）— 关闭**
   - 缺 `pushed`：`node bin/nao-queue receipt-line <rec> --queue <q>` → **rc=1**、stdout **0 字节**（`stdout_bytes=0`）、stderr 点名「缺少必需字段 pushed」+ `receipt-line 要求 pushed:true（实际 undefined）—— 未推送的回执拒绝出机读首行`。
   - 假 sha + `pushed:true`（默认即走 ls-remote，本地 bare 仓当远端）：rc=1、stdout **0 字节**、点名 `pushed:true 与 git ls-remote 不一致 —— head=deadbeef… 不在 … 的任何 head 里`。
   - 正控（head 真已推送）：rc=0 → `receipt: T566 rd-infra head=<sha> gates=ok,ok acs=4/4`；`--id T566 --receipts <dir>` 形态逐字同。
   - 逃生阀：`--no-push-check` → stderr `NOTICE --no-push-check ⇒ 已跳过 pushed:true 的 git ls-remote 复核（机读首行基于回执自述）` + rc=0（出首行但已显式留痕，不再静默）。
3. **P3-1（同态自转回显允许集）— 关闭**
   - `node bin/nao-queue transition --from working --to working` → rc=1：`非法状态转换 working → working（同一状态不是转换；从 working 允许：qa/blocked）`。
   - `--from queued --to queued` → `…（同一状态不是转换；从 queued 允许：dispatched）`；case 46 ③ 已含这两条断言（96 断言内）。
4. **P3-2（PRD §六 逐字）— 部分关闭**（残留 F2）
   - `sed -n '/## 六、/,/## 七、/p' docs/prds/2026-11-24-orchestrator.md` → `gates.check.log 指向不存在文件，或 gates.full 缺 rc/cases/pass/fail/note 任一 ⇒ 判红`（与 §四 schema 字段已对齐）。
   - 缺 `gates.full.note`：`validate` → **rc=1** 点名「gates.full 缺少字段 note」✅。
   - **`gates.check.log="docs/reports/__no_such_log__.md"`：`validate` → rc=0**（实现只验「非空字符串」，不验文件存在）⇒ 条文前半句仍超出实现（**F2**）。
5. **P3-3（去硬编码 T566 默认回执）— 关闭**
   - `node bin/nao-queue receipt-line --queue <q>`（不给路径也不给 `--id`）→ **rc=2**：`receipt-line 需要回执文件路径或 --id <任务号>（不再内置默认回执）`。
   - `--id T566 --receipts <dir>` → rc=0 且首行正确；`grep -n 'T566.receipt.json' bin/nao-queue` → **0 命中**（代码面无硬编码）。

### 6.2 门禁口径

- **我（QA）实测的只读子集**：`--case 46` rc=0 · 96 PASS / 0 FAIL；`node bin/nao-queue render --check` → `OK` rc=0（真件 `docs/tasks-state.md` 与 `docs/queue.jsonl` 一致）。
- **PM 全量实测（由 PM 执行，非我执行）**：`EXIT=0 · 43/43 PASS · SKIP=0 DEGRADE=0 NOTE=18 全白名单`，日志 `/tmp/pm-t566-full.log`；回执 `gates.full` 记 `cases=43 · pass=43 · fail=0`。
- 我**未独立重跑** `npm test` 全量 —— 该数字按 PM 日志引用并明确归属。

### 6.3 残留（PASS with followups）

- **F1（P3 · 文档计数漂移）**：`AGENTS.md:19` 仍写 `npm test`（**42 例**），与 `run.sh`/`tests/README.md` 的 **43** 不一致。修法：改 43（一行文本）。归口建议：`T566-O1`，随下一任务 PR 首提交（本 PR 边界只允许本报告一个文件，故我未改）。
- **F2（P3 · PRD §六 与实现仍有一处不一致）**：条文「`gates.check.log` 指向不存在文件 ⇒ 判红」未实现（实测 rc=0；只校验非空）。修法二选一：① 实现文件存在性校验（须先定路径锚点：相对 cwd 还是仓库根）；② 条文回退为「为空/缺失 ⇒ 判红」。归口建议：`T566-O2`（阶段 2 前；不影响阶段 1 的 AC1 判据）。
- 无 P0/P1/P2 残留；两项均为文档/口径 P3，**不阻塞阶段 1 交付**。

### 6.4 结论

**PASS with followups**（F1/F2 两条 P3，建议随下一任务 PR 或台账到期收口）。

- **无源码改动声明**：本报告 PR 只新增 `docs/reports/566-qa-verify.md` 一个文件；`bin/`、`tests/`、`docs/prds/`、`docs/queue/`、`docs/tasks-state.md` 均未改。
- 变异/造数证据：`/tmp/qa566/r2/**`（本地 bare 仓、假 sha、缺 `pushed` 回执、不存在的 check.log）。
