# PRD：tests/t4 接入 `npm test` 门禁（补 1874 行 `nao-fleet.sh` 的机械护栏）

- 状态：**待派发（开工已确认 2026-10-14）** · Owner：PM · 更新：2026-10-14
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **全纳入**（接线 + 默认严格 + full 入口 + 门禁可信度缺陷 A/B 修复）· D2 严格默认 = **翻转 `run.sh`/`lib.sh` 默认**（宽松改显式 `T4_ALLOW_MISSING=1`）· D3 立项 = **降级批次 `nao/t4-gate`**（无 Issue）· D4 版本 = **v0.18.0（MINOR）** · D5 闸门 = **采纳**（开工确认后、派发前送 arch-designer 结构评审）
- 指针：上游 = 用户 2026-10-14 选定批（由 T521 QA 备注 N2 引出：「`npm test` = `check + tsc`，未跑 `tests/t4/run.sh`」）+ 同轮 ask-me 回执「按此推进」· 成熟度判定 = 命中 §一.4「用户明示可直接成稿」· **QA 接缝复核** = 2026-10-14 `done(full)`（采纳 C1 接缝 + C2 形态；改定 4 处 = `prepack` 剥离 t4 · 默认严格 · 补 full 入口 · 门禁可信度缺陷 A/B 必须前置修复）
- 优先级：**中高**（本批产出即「唯一机械门禁」的可信度）· 战略筛子：命中「机制护栏 / 低成本高杠杆」→ 做 · MoSCoW：**Must** · Kano：基本型（无护栏 = 缺陷）· RICE ≈10.8（附录）

## TL;DR（≤5 行）

- **做什么**：把 `tests/t4`（12 例 / 263 断言 / ≈2min）串入 `npm test`，默认严格；补发布前 full 入口；封堵两个「静默假绿」；`prepack` 与 t4 解耦。
- **给谁**：本仓维护者 / 交付批次的 RD 与 QA / 下游三仓维护者（照抄门禁口径）。
- **成功标准**：向 `.agents/scripts/nao-fleet.sh` 注入 1 处缺陷 ⇒ `npm test` rc≠0；删除用例文件或空选择器 ⇒ rc≠0；`npm test` rc=0 且 t4 12/12 · 断言 ≥263。
- **不做什么**：不拆 `nao-fleet.sh`（1874 行 / 72 函数，另批待 arch 评审）；不加 CI workflow；不改 `nao-fleet.sh` 功能代码；不扩 t4 用例面（仅 06 增 2 条契约断言）。

## 一、问题证据

- **实测（PM 本轮）**：`npm test` = `bash .agents/scripts/nao-fleet.sh check && npm run check:agents`（`package.json:42`）→ rc=0 · **2.2s**（QA 独立实测 3s）；**不含** `tests/t4/run.sh`。
- **实测（PM + QA 双跑）**：`T4_ALLOW_MISSING=0 bash tests/t4/run.sh` → **12/12 PASS · 263 PASS 断言 / 0 FAIL / 3 NOTE / rc=0**（≈1m43s–2min）；跑后工作区干净、无 tmux/进程残留。护栏本体是绿的，只是**没接线**。
- **口径漂移证据**：历批 PRD 的 AC 都**双写**「`npm test` rc=0」**和**「`tests/t4` 全绿」（`docs/prds/2026-10-08-fleet-alias-close-fix.md:80` · `docs/prds/2026-10-13-t517-derived-pane-window.md:74` · `docs/prds/2026-10-14-tasks-state-slim.md:82`）⇒ 存在**人工约定**，但**无机械执行**。
- **本仓无 CI**（`.github/` 仅 `pull_request_template.md`）⇒ `npm test` 是唯一机械门禁；`prepack: npm test` 使其同时充当打包/发布前置。
- **5 Whys**：`nao-fleet.sh`（1874 行 / 72 函数 / `cmd_check` 单函数 228 行）无机械护栏 ← 回归靠每批人工记得跑 `tests/t4` ← t4 未被 `npm test` 调用 ← 当年 t4 按「独立验证套件」立项（PRD #18），`npm test` 只需覆盖 static check ← 无人承担「把独立套件升格为门禁」这一步。
- **静默假绿（QA 只读副本实证，本批必堵）**：缺陷 A —— `tests/t4/run.sh:80` 把用例文件缺失记为 `MISSING`，而汇总（`:100-103`）只认 `FAIL*`/`BLOCKED` ⇒ **删掉任一用例文件 = rc 0 假绿**（`cases/` 全空 → 12×`MISSING` · rc=0）；缺陷 B —— `run.sh --case 99`（无匹配）→ **一个用例未跑 · rc=0**。
- 次要：`tests/README.md` 两条并存且互相矛盾的「最近一次跑批」行（`8/8` 与 `7/7`），与现 12 用例均不符。

## 二、目标指标

- **北极星**：`nao-fleet.sh` 的行为缺陷**能被默认门禁机械拦截**，不依赖任何人的记忆。
- **预期**：`npm test` 链路确实执行 t4（可负控证明）· 注入 1 处守卫缺陷 ⇒ rc≠0 · 用例文件缺失 / 空选择器 ⇒ rc≠0 · t4 断言数只增不减（基线 **263 PASS / 3 NOTE / 0 FAIL**）。
- **观测**：`npm test` rc + t4 用例/断言/红数 + N1/N2/N3 负控结论 + `git status` 空。

## 三、范围 / 非范围

- **范围**
  1. `package.json` scripts 重排：`test:agents`（现 `check && check:agents` 原文）· `test:t4`（= `bash tests/t4/run.sh`，默认严格）· `test` = `test:agents && test:t4` · `prepack` = `test:agents`（**剥离 t4**）。
  2. `tests/t4/run.sh` + `tests/t4/lib.sh`：**默认严格**（`T4_ALLOW_MISSING` 默认翻为 `0`，宽松改为显式 `1`）· 新增 `T4_REQUIRE_FULL=1`（SKIP 也判 FAIL）+ `npm run test:t4:full` · 修缺陷 A（`MISSING` 并入失败）+ 缺陷 B（空选择器非 0 退出）。
  3. `tests/t4/cases/06-contract-guards.sh`：**新增 2 条静态契约断言**（`scripts.test` 走 `test:t4` 且严格性成立；`scripts.prepack` 不含 t4）——断言实体由 QA 维护，防「接线被后人摘掉无人报警」。
  4. `tests/README.md`：运行章节更新（新脚本 + 严格默认 + full 入口 + SKIP/NOTE 口径）+ 清理两条陈旧跑批行。
  5. 文档同步：`docs/releases/v0.18.0.md`「本次更新」写明 `npm test` 语义变更 · `docs/tasks-state.md` 待裁量项 ⑫ 收口 · 发布清单增一条前置 `npm run test:t4:full`。
- **非范围**（各带理由）
  - **不拆 `nao-fleet.sh`**：理由 未立项，属 ⑫ 的另一半，待 arch 评审后另批（用户已选「先小批 t4」）。
  - **不加 CI（`.github/workflows/`）**：理由 本批只补本地门禁；CI 面涉及 runner/密钥/环境能力降级，另批立项。
  - **不改 `nao-fleet.sh` 功能代码**：理由 本批只做「接线 + 可信度」，注入缺陷仅作一次性负控演练并还原。
  - **不扩 t4 用例面 / 不动既有断言实体**：理由 避免与本批目标（接线）混淆；除 06 新增 2 条外零改动。
  - **不改 `package.json files`（tests/ 不入包）**：理由 发布面不变；已知副作用 = 安装后包内无 `tests/t4`，`npm test` 在**消费者机器**上不适用（本批记录，不修）。
  - **不改宽松默认的前置兼容**：理由 t4 为本仓内部套件，无外部调用方；翻转默认是「默认值才是唯一持久约束」的取舍（QA 建议）。

## 四、用户场景

- 画像 A（本仓维护者）：改 `nao-fleet.sh` 后只跑 `npm test` 就跑到了 12 例回归；改坏了 D7 守卫会被当场拦下。
- 画像 B（交付批次 RD / QA）：单命令即可自证全范围门禁；回执只需报 `npm test` rc + t4 精确数字。
- 画像 C（下游三仓维护者）：照抄 `package.json` 三行即可把自家套件升格为门禁（口径可复制）。
- 画像 D（发布者）：发布前置显式跑 `npm run test:t4:full`（SKIP=0 才发）；`npm publish` 本身不被 t4 阻塞。
- 状态清单（门禁语义）：**成功** = rc 0 + 12/12 + SKIP/NOTE 明细；**环境缺能力** = rc 0 但显式 SKIP 计数（不得称「全量通过」）；**真实缺陷** = rc≠0 且指名用例号 + 断言；**接线被摘** = 06 断言 FAIL 或 N1 负控 rc≠0；**T2 产物缺失** = FAIL（严格）。

## 五、业务规则

- **BR1 接缝唯一**：门禁接缝 = `npm test` rc=0（复用既有唯一机械门禁，**不新增接缝**）。
- **BR2 分段命名**：`test:agents`（轻量：`check` + `tsc`）· `test:t4`（重：12 例回归）· `test`（串联，轻在前 fail-fast）· `test:t4:full`（发布前收紧）。
- **BR3 严格默认**：缺失 T2 产物 ⇒ FAIL；缺 `node`/`npm`/`git` ⇒ FAIL（现行为）。环境能力缺失（无 `pi` CLI / 无 tmux / 无 bwrap / registry 不可达）⇒ **SKIP，算门禁通过**。
- **BR4 SKIP 诚实性**：SKIP/NOTE 必须显式计数并进回执；「绿 + N SKIP」不得表述为「全量通过」；发布判据用 `test:t4:full`（SKIP 即 FAIL）。
- **BR5 prepack 解耦**：`prepack` 只跑 `test:agents` —— 发布流程不得被 LLM 调用（case 02 真发 1 次 pi 请求）/ registry（case 07 `npm view` + `pi install`，离线白等 2×40s）/ tmux 阻塞。
- **BR6 无递归**：t4 内部打包一律 `npm pack --ignore-scripts`（`tests/t4/lib.sh:96`）；`prepack` 与 t4 不得互调（QA 已实证）。
- **BR7 假绿封堵**：用例文件缺失、空选择器、汇总未识别状态一律 rc≠0；任何「未跑」不得等同「通过」。
- **BR8 断言只增不减**：t4 用例数 12、PASS 断言 ≥263；允许 NOTE（环境降级，须报明细），不允许 FAIL/SKIP 静默。
- **BR9 语义变更可见**：`npm test` 语义从「check + tsc」扩为「含 t4 回归」必须在 release notes 明写 + `tests/README.md` 同步（既有文档曾把 `npm test` 定义为 `check + tsc`）。

## 六、NFRs

- **时长基线**：`npm test` 由 ≈3s 升至 **≈2min**（+t4）；`npm run test:agents` 与 `prepack` **保持 ≈3s 不变**（发布路径不劣化）。
- **可移植性 / 降级**：默认门禁**不得**因缺 `pi`/`tmux`/`bwrap`/网络而 FAIL（BR3）；缺基础工具链则 FAIL（正确）。
- **网络**：默认门禁**无硬网络依赖**（case 07 不可达 → SKIP）；registry 抖动只体现为 SKIP/NOTE 计数，不产生 flaky FAIL。
- **可诊断**：失败输出必须含用例编号 + 断言原文 + 汇总（不得只有一行 rc）。
- **安全**：门禁不得执行 `git push` / `npm publish`；负控演练只在临时副本或注入后立即 `git checkout --` 还原（工作区必须回到干净）。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：`npm test` rc=0（复用项目全范围门禁，接缝数不增；QA 复核改定 = 形态用具名脚本 + `prepack` 剥离）。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核接缝候选 3 个，Then 确认或改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`：采纳 C1 接缝 + C2 形态，改定 4 处）。
- **AC2（主路径 · 真接线，防装饰）**：Given 改后仓库，When（a）读 `package.json.scripts.test` 且（b）06 静态契约断言通过且（c）**N1 负控**临时移走 `tests/t4/run.sh` 后 `npm test` rc≠0（还原后工作区干净），Then 三条同时成立。
- **AC3（业务规则 · 严格语义）**：Given 严格默认，When T2 产物缺失 / 缺 `node`·`npm`·`git`，Then FAIL；When 缺 `pi`/`tmux`/`bwrap` 或 registry 不可达，Then SKIP 且**计数可见**、rc=0（BR3/BR4）。
- **AC4（负向闭环 · prepack 解耦）**：Given 改后 `prepack`，When **N3 负控**跑 `npm run prepack`，Then rc=0 **且输出无 t4 汇总行、无 pi/tmux 调用**；且 06 断言钉住 `scripts.prepack` 不含 t4（BR5）。
- **AC5（异常 · 失败传播，本批核心价值）**：Given 改后仓库，When 向 `.agents/scripts/nao-fleet.sh` 注入 1 处守卫缺陷（如破坏 `NAO_SHIM_ENTERED` 或 `DEGRADED:` 输出），Then `npm test` rc≠0 且至少用例 03 FAIL；还原后 `git status --porcelain` 空且复跑全绿（**N2 负控**）。
- **AC6（边界 · 假绿封堵 + full 入口）**：Given 缺陷 A/B 已修，When `cases/` 临时清空（临时副本）或 `--case 99`，Then rc≠0（不得 `MISSING`/空跑判 0）；When `T4_REQUIRE_FULL=1` 且存在 SKIP，Then rc≠0（BR7）。
- **AC7（设计一致性 · 只增不减 + 文档同步）**：Given 改后 t4，When 严格跑，Then 用例 12 · PASS ≥263 · 0 FAIL，NOTE/SKIP 明细入回执；且 `tests/README.md` 运行章节含新脚本与严格默认、两条陈旧跑批行已清；且 `docs/releases/v0.18.0.md` 写明 `npm test` 语义变更；且 `docs/tasks-state.md` 待裁量项 ⑫ 收口（BR8/BR9）。
- **AC8（一致性闸门）**：Given PRD 接缝/AC 范围与 QA 用例范围，When 比对，Then 一致；不一致则 PM 验收**打回**。
- **AC9（负向闭环 · 无残留 + 无递归）**：Given 门禁与负控跑完，When 检查 `git status --porcelain` / `tmux list-sessions` / 残留进程，Then 全空或仅有预期项；且 t4 内部打包走 `--ignore-scripts`（BR6）。

## 八、上线闭环

- **版本**：**v0.18.0（MINOR）** —— 新增「t4 升格门禁 + full 入口」能力（feat 语义）；`prepack` 行为不变。
- **灰度**：不适用（本仓内部门禁，无运行面灰度）。
- **回滚**：改回 `package.json` 三行 + `run.sh`/`lib.sh` 默认值并发下一 PATCH；已 push tag 不删。
- **npm 重发**：`package.json` 在 `files` 内（`scripts` 字段随包分发），但 `tests/` **不入包** ⇒ 消费者侧 `npm test` 不适用（已知副作用，记入 release notes）；**是否需要重发 npm 在发布节点由用户拍板**（先例：T521 重发 / T520 不重发）。
- **监控**：不适用（本地门禁）；唯一指标 = `npm test` rc 与 t4 数字。

## 九、变更治理

- **流程**：降级批次分支 `nao/t4-gate`（无 Issue；如用户选择建 Issue 则 `feat/<id>-t4-gate`）→ PR → QA 独立只读复跑 + N1–N3 负控 → PM 验收 → RD `--squash` 合并（显式 `--subject`）→ PM 发 tag/Release → PRD 归档。
- **实现分工**：`package.json` / `run.sh` / `lib.sh` / `tests/README.md` / 文档同步 → **rd-infra**（工程基座）；06 静态契约断言 + 独立负控 → **qa**（断言实体维护者）；同分支**顺序写**（rd-infra 先落 wiring，QA 再加断言与复核），禁并发写同文件。
- **架构评审闸门**：开工确认后、派发前送 `arch-designer` 评审（本批触及构建配置 + 门禁语义 + NFR 时长/可移植性；纯 CRUD 例外不适用）—— **D5 已拍板采纳**，PRD 终稿以 arch 回执为准。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-t4-gate-wiring.md`（本文件；归档时登记 `docs/prds/README.md` 索引）；运行时状态记 `docs/tasks-state.md`。
- **待裁量项 ⑫ 收口**：本批完成后 `nao-fleet.sh` 体量/职责混装一项**保留**（脚本拆分仍未立项），仅把「tests/t4 未接入 npm test」这半条关闭。

## 附：RICE 与依据

- Reach 2（本仓维护者 + 交付批次 RD/QA，间接下游三仓）· Impact 3（护栏防回归，防的是 1874 行脚本的静默破坏）· Confidence 0.9（已双跑实测绿 + 负控设计明确）· Effort 0.5（4 文件 + 2 断言 + 文档同步）⇒ **RICE ≈10.8**。
- 战略筛子：命中「机制护栏 + 单一机械门禁可信度」→ 本批做；「脚本拆分」被筛除（未立项，待 arch 评审后另批）。
