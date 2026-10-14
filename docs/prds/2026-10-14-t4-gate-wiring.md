# PRD：tests/t4 接入 `npm test` 门禁（补 1874 行 `nao-fleet.sh` 的机械护栏）

- 状态：**待派发（开工已确认 2026-10-14）** · Owner：PM · 更新：2026-10-14
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **全纳入**（接线 + 默认严格 + full 入口 + 门禁可信度缺陷 A/B 修复）· D2 严格默认 = **翻转 `run.sh`/`lib.sh` 默认**（宽松改显式 `T4_ALLOW_MISSING=1`）· D3 立项 = **降级批次 `nao/t4-gate`**（无 Issue）· D4 版本 = **v0.18.0（MINOR）** · D5 闸门 = **采纳**（开工确认后、派发前送 arch-designer 结构评审）
- 开工确认卡·二轮（2026-10-14 · arch 评审后 ask-me 拍板 5 项）：D1 网络面 = **修极性**（case 02/07 外部不可达/未成功启动 → SKIP/NOTE；仅「拿到真实输出但内容不符」判 FAIL）· D2 范围微扩 = **全批准**（三类参数错误 + 06 第 3 条断言 + N4/N5 负控 + `--preflight` 标签修正）· D3 ADR = **授权 arch 落盘**（`docs/adr/2026-10-14-npm-test-gate-scope.md` + 评审报告）· D4 npm = **默认不重发**（发布节点再终拍）· D5 网络中断 = **继续推进本地实现**（`github.com:443` 超时中，push/PR 待恢复）
- **arch 结构评审** = 2026-10-14 arch-designer `done(full)`：结构**有条件可行** —— 采纳「`test` 全量串联 / `prepack`=`test:agents` / 默认严格 / v0.18.0 / npm 不重发 / 需补 ADR」；**6 处修订 P1–P6 已落本稿** + 新识别**第三类假绿**（用例不以 `t4_exit|t4_skip|exec` 收尾仍可 rc=0）
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
  1. `package.json` scripts 重排：`test:agents`（现 `check && check:agents` 原文）· `test:t4`（= `bash tests/t4/run.sh`，默认严格）· **`test:t4:full` = 显式双轴 `T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1 bash tests/t4/run.sh`**（P1）· `test` = `test:agents && test:t4` · `prepack` = `test:agents`（**剥离 t4**）。
  2. `tests/t4/run.sh` + `tests/t4/lib.sh`：**默认严格**（`T4_ALLOW_MISSING` 默认翻为 `0`，宽松仅剩显式 `1`）· 新增 `T4_REQUIRE_FULL=1`（SKIP 也判 FAIL，**与 `T4_ALLOW_MISSING` 正交**，只管 SKIP 轴；判据为**汇总层 SKIP 计数 = 0**，含从用例输出解析的 `[SKIP]`/`SKIP:` 行 ⇒ 覆盖 11/12 子项；NOTE 允许并计数）· **汇总改白名单**（`PASS|SKIP` 通过 / `BLOCKED`→rc 2 / 其余含 `MISSING`·`NOT_RUN`·未知值→rc 1，一次覆盖缺陷 A + 死代码 + 未知态）· **三类参数错误非 0 退出**（`--case` 缺值 / `--case` 无匹配 / 裸位置参数；`--list`·`--preflight` 行为不变）· `--preflight` 标签修正为 `T4_ALLOW_MISSING=%s（0=严格默认）`。
  3. `tests/t4/cases/06-contract-guards.sh`：**新增 ≥3 条静态契约断言**（`scripts.test` 走 `test:t4` 且 `test:t4:full` 含两个严格轴；`scripts.prepack` 不含 t4；**用例脚本均以 `t4_exit|t4_skip|exec` 收尾**）——断言实体由 QA 维护，防「接线被后人摘掉无人报警」+ 封第三类假绿。
  4. `tests/README.md`：运行章节更新（新脚本 + 严格默认 + 宽松仅显式 `1` + full 口径 + SKIP/NOTE 计数 + 安装包内不适用）+ 清理两条陈旧跑批行。
  5. 文档同步：`docs/releases/v0.18.0.md`（语义变更写「⚠️ 请留意」；**正文禁写用例数/通过率**，数字下沉「技术细节」+ 消费者侧不适用）· `docs/tasks-state.md` 待裁量项 ⑫ 收口 · **发布前锚点落 `.agents/skills/github-flow.md` 阶段 7：前置 `npm run test:t4:full` rc=0**（P4；`release-notes.md` §四是「发版说明写作」核对表，不是发布运行清单）· ADR + 评审报告（arch 落盘，见 §九）。
  6. **case 02 / case 07 网络面极性修正**（D1 拍板 · 每例 1–2 行）：外部不可达 / 未成功启动 → SKIP/NOTE；仅「拿到真实输出但内容不符」判 FAIL。
- **非范围**（各带理由）
  - **不拆 `nao-fleet.sh`**：理由 未立项，属 ⑫ 的另一半，待 arch 评审后另批（用户已选「先小批 t4」）。
  - **不加 CI（`.github/workflows/`）**：理由 本批只补本地门禁；CI 面涉及 runner/密钥/环境能力降级，另批立项。
  - **不改 `nao-fleet.sh` 功能代码**：理由 本批只做「接线 + 可信度」，注入缺陷仅作一次性负控演练并还原。
  - **不扩 t4 用例面**：理由 避免与本批目标（接线）混淆；仅 06 新增 ≥3 条断言 + case 02/07 极性 1–2 行（D1 批准），其余既有断言实体零改动。
  - **不改 `package.json files`（tests/ 不入包）**：理由 发布面不变；已知副作用 = 安装后包内无 `tests/t4`，`npm test` 在**消费者机器**上不适用（本批记录，不修）。
  - **不改宽松默认的前置兼容**：理由 t4 为本仓内部套件，无外部调用方；翻转默认是「默认值才是唯一持久约束」的取舍（QA 建议）。**不加** `test:t4:loose` 具名脚本（避免把宽松提升为可见表面）。

## 四、用户场景

- 画像 A（本仓维护者）：改 `nao-fleet.sh` 后只跑 `npm test` 就跑到了 12 例回归；改坏了 D7 守卫会被当场拦下。
- 画像 B（交付批次 RD / QA）：单命令即可自证全范围门禁；回执只需报 `npm test` rc + t4 精确数字。
- 画像 C（下游三仓维护者）：照抄 `package.json` 三行即可把自家套件升格为门禁（口径可复制）。
- 画像 D（发布者）：发布前置显式跑 `npm run test:t4:full`（SKIP=0 才发）；`npm publish` 本身不被 t4 阻塞。
- 状态清单（门禁语义）：**成功** = rc 0 + 12/12 + SKIP/NOTE 明细；**环境缺能力** = rc 0 但显式 SKIP 计数（不得称「全量通过」）；**真实缺陷** = rc≠0 且指名用例号 + 断言；**接线被摘** = 06 断言 FAIL 或 N1 负控 rc≠0；**T2 产物缺失** = FAIL（严格）。

## 五、业务规则

- **BR1 接缝唯一**：门禁接缝 = `npm test` rc=0（复用既有唯一机械门禁，**不新增接缝**）。
- **BR2 分段命名**：`test:agents`（轻量：`check` + `tsc`）· `test:t4`（重：12 例回归，默认严格）· `test`（串联，轻在前 fail-fast）· `test:t4:full`（显式双轴：严格 + SKIP 即 FAIL）。
- **BR3 严格默认**：缺失 T2 产物 ⇒ FAIL；缺 `node`/`npm`/`git` ⇒ FAIL（现行为）。环境能力缺失（无 `pi` CLI / 无 tmux / 无 bwrap / registry 或凭据不可达）⇒ **SKIP，算门禁通过**（须满足 BR10 极性要求）。
- **BR4 SKIP 诚实性**：SKIP/NOTE 必须显式计数（汇总层 + 用例内子项）并进回执；「绿 + N SKIP」不得表述为「全量通过」；发布判据用 `test:t4:full`（**SKIP 计数为 0** 才算过）。
- **BR5 prepack 解耦**：`prepack` 只跑 `test:agents` —— 发布流程不得被 LLM 调用（case 02 真发 1 次 pi 请求）/ registry（case 07 `npm view` + `pi install`，离线白等 2×40s）/ tmux 阻塞。
- **BR6 无递归**：t4 内部打包一律 `npm pack --ignore-scripts`（`tests/t4/lib.sh:96`）；`prepack` 与 t4 不得互调（QA 已实证）。
- **BR7 假绿封堵**：三类均 rc≠0 —— ①用例文件缺失（`MISSING`）②**参数错误**（`--case` 缺值 / `--case` 无匹配 / 裸位置参数）③**汇总未识别状态**（含 `NOT_RUN` 与未知值）。任何「未跑」不得等同「通过」。
- **BR8 断言只增不减**：t4 用例数 12、PASS 断言 **≥265**（基线 263 + 06 新增）；允许 NOTE（环境降级，须报明细），不允许 FAIL/SKIP 静默。
- **BR9 语义变更可见**：`npm test` 语义从「check + tsc」扩为「含 t4 回归」必须在 release notes 明写（「⚠️ 请留意」）+ `tests/README.md` 同步（既有文档曾把 `npm test` 定义为 `check + tsc`）。
- **BR10 极性（外部依赖不得假红）**：case 02/07 等真接口用例 —— 外部不可达 / 未成功启动 / 无凭据 ⇒ SKIP/NOTE；只有「确已拿到真实输出且内容不符」才 FAIL ⇒ 默认门禁**不得因网络/凭据抖动变红**（本批硬约束，见 §六）。

## 六、NFRs

- **时长基线**：`npm test` 由 ≈3s 升至 **≈2min**（+t4）；`npm run test:agents` 与 `prepack` **保持 ≈3s 不变**（发布路径不劣化）。
- **可移植性 / 降级**：默认门禁**不得**因缺 `pi`/`tmux`/`bwrap`/网络而 FAIL（BR3）；缺基础工具链则 FAIL（正确）。
- **网络 / 非确定性（本批硬约束）**：默认门禁**不得因网络或凭据抖动变红** —— case 02（真发 1 次 pi 调用）与 case 07（`npm view` + `pi install`）必须按 BR10 极性归 SKIP/NOTE（**实测风险**：`reg_tsv` 空即 FAIL 只覆盖 `No API key`；`pi install rc≠0` 即 FAIL 不区分「不可达」与「真失败」）；registry 半通（`npm view` 通但 tarball 拉取失败）亦归 SKIP/NOTE。想强制真跑用 `test:t4:full`（SKIP 即 FAIL）。
- **可诊断**：失败输出必须含用例编号 + 断言原文 + 汇总（不得只有一行 rc）。
- **安全**：门禁不得执行 `git push` / `npm publish`；负控演练只在临时副本或注入后立即 `git checkout --` 还原（工作区必须回到干净）。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：`npm test` rc=0（复用项目全范围门禁，接缝数不增；QA 复核改定 = 形态用具名脚本 + `prepack` 剥离）。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核接缝候选 3 个，Then 确认或改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`：采纳 C1 接缝 + C2 形态，改定 4 处）。
- **AC2（主路径 · 真接线，防装饰）**：Given 改后仓库，When（a）读 `package.json.scripts.test` 且（b）06 静态契约断言通过且（c）**N1 负控**临时移走 `tests/t4/run.sh` 后 `npm test` rc≠0（还原后工作区干净），Then 三条同时成立。
- **AC3（业务规则 · 严格语义 + 极性）**：Given 严格默认，When T2 产物缺失 / 缺 `node`·`npm`·`git`，Then FAIL；When 缺 `pi`/`tmux`/`bwrap`/凭据或 registry 不可达，Then SKIP 且**计数可见**、rc=0（BR3/BR4/BR10）；**负向**：When 真接口返回真实输出但内容不符，Then FAIL（极性不得被滥用为「一律 SKIP」）。
- **AC4（负向闭环 · prepack 解耦）**：Given 改后 `prepack`，When **N3 负控**跑 `npm run prepack`，Then rc=0 **且输出无 t4 汇总行、无 pi/tmux 调用**；且 06 断言钉住 `scripts.prepack` 不含 t4（BR5）。
- **AC5（异常 · 失败传播，本批核心价值）**：Given 改后仓库，When 向 `.agents/scripts/nao-fleet.sh` 注入 1 处守卫缺陷（如破坏 `NAO_SHIM_ENTERED` 或 `DEGRADED:` 输出），Then `npm test` rc≠0 且至少用例 03 FAIL；还原后 `git status --porcelain` 空且复跑全绿（**N2 负控**）。
- **AC6（边界 · 假绿封堵 + full 入口）**：Given 缺陷 A/B 与第三类假绿已封，When（a）`cases/` 临时清空（临时副本）（b）`--case 99`（c）`--case`（缺值）（d）裸位置参数 `run.sh 99`（e）临时用例 `exit 77`，Then（a）–（d）rc≠0 且（e）默认 rc=0 / `T4_REQUIRE_FULL=1` 下 rc≠0（**N4/N5 负控**）；且 `test:t4:full` 判据 = 汇总层 SKIP 计数（含用例内 `[SKIP]` 行）= 0（BR7）。
- **AC7（设计一致性 · 只增不减 + 文档同步）**：Given 改后 t4，When 严格跑，Then 用例 12 · PASS **≥265**（基线 263 + 06 新增）· 0 FAIL，NOTE/SKIP 明细入回执；且 `tests/README.md` 运行章节含新脚本/严格默认/full 口径/安装包内不适用、两条陈旧跑批行已清；且 `docs/releases/v0.18.0.md` 明写语义变更（数字下沉技术细节）；且 `.agents/skills/github-flow.md` 阶段 7 含发布前置 `npm run test:t4:full`；且 `docs/tasks-state.md` 待裁量项 ⑫ 收口（BR8/BR9/P4/P5）。
- **AC8（一致性闸门）**：Given PRD 接缝/AC 范围与 QA 用例范围，When 比对，Then 一致；不一致则 PM 验收**打回**。
- **AC9（负向闭环 · 无残留 + 无递归）**：Given 门禁与负控跑完，When 检查 `git status --porcelain` / `tmux list-sessions` / 残留进程，Then 全空或仅有预期项；且 t4 内部打包走 `--ignore-scripts`（BR6）。

## 八、上线闭环

- **版本**：**v0.18.0（MINOR）** —— 新增「t4 升格门禁 + full 入口」能力（feat 语义）；`prepack` 行为不变。
- **灰度**：不适用（本仓内部门禁，无运行面灰度）。
- **回滚**：改回 `package.json` 三行 + `run.sh`/`lib.sh` 默认值并发下一 PATCH；已 push tag 不删。
- **npm 重发**：**默认不重发**（D4 拍板；发布节点再终拍）—— `package.json` 在 tarball 内改动可见，但 `tests/` 不入包 ⇒ 消费者侧 `npm test` 本就不可用，重发无收益；**记版本漂移**（repo `0.18.0` / registry `0.17.3`）并在 release notes「技术细节」明写「安装包内 `npm test` 不适用（rc≠0 属预期）」（P6）。
- **监控**：不适用（本地门禁）；唯一指标 = `npm test` rc + t4 用例/断言/SKIP/NOTE 数字。

## 九、变更治理

- **流程**：降级批次分支 `nao/t4-gate`（无 Issue · D3 拍板）→ PR → QA 独立只读复跑 + N1–N5 负控 → PM 验收 → RD `--squash` 合并（显式 `--subject`）→ PM 发 tag/Release → PRD 归档。**网络降级**：`github.com:443` 当前超时（`api.github.com` 通），实现与本地门禁不受影响，push/PR/合并/发布恢复后补（github-flow 离线降级条款，保持 main = 1 条/需求）。
- **实现分工与顺序（同分支顺序写，禁并发）**：① **rd-infra** 起分支 + 落地 `package.json`/`run.sh`/`lib.sh`/`tests/README.md`/文档同步 → 回执；② **arch-designer** 落盘 ADR（`docs/adr/2026-10-14-npm-test-gate-scope.md`，状态 `已接受（待落地 v0.18.0）`；必写 5 节 + 对照模式 + 参考来源）+ 评审报告（`docs/reports/2026-10-14-T522-arch-review.md`，实施办法类内容下沉于此）→ 回执；③ **qa** 加 06 断言（≥3 条）+ 独立负控 N1–N5 + 复跑复核 → `done(full)` 回执。
- **架构评审闸门**：开工确认后、派发前送 `arch-designer` 评审 —— **已完成 2026-10-14**（`done(full)`：结构有条件可行 + 6 处修订 + 新识别第三类假绿）；**ADR 落盘已获用户授权（D3）**，随本批分支交付。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-t4-gate-wiring.md`（本文件；归档时登记 `docs/prds/README.md` 索引）；运行时状态记 `docs/tasks-state.md`。
- **待裁量项 ⑫ 收口**：本批完成后 `nao-fleet.sh` 体量/职责混装一项**保留**（脚本拆分仍未立项），仅把「tests/t4 未接入 npm test」这半条关闭。

## 附：RICE 与依据

- Reach 2（本仓维护者 + 交付批次 RD/QA，间接下游三仓）· Impact 3（护栏防回归，防的是 1874 行脚本的静默破坏）· Confidence 0.9（已双跑实测绿 + 负控设计明确）· Effort 0.6（5 文件 + ≥3 断言 + 极性修正 + 文档同步 + ADR）⇒ **RICE ≈9.0**。
- 战略筛子：命中「机制护栏 + 单一机械门禁可信度」→ 本批做；「脚本拆分」被筛除（未立项，待 arch 评审后另批）。
