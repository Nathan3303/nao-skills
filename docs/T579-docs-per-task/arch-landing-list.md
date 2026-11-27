# T579 实施落点清单（评审附件 · 非报告正文）

> 用途：把 `arch-review.md` 的裁定翻成可执行改动（文件 + 行段 + 改什么）。本文件由 rd-infra 执行；arch 只读、不改机制文件。
> 行号均为 as-of `ce70c62`（本任务 PRD 提交）实测；改动前按 `git show <sha>:<file>` 复核。
> **Owner 归口**（清单项持有者）：§一/§二/§四/§七 + 用户文档 = **PM**（机制正文与卡维护人）· §五 = **rd-infra**（`check` 与用例）· §六 = **PM**（PRD/索引/台账）· 5 张角色卡 = **PM 改 + 各角色本人收广播**（`card <role> v<N+1>`）。

## 一、路径契约正文（单源，AC8 的落点）

1. `.agents/checklists/deliverable-docs.md` —— **新增 §十「任务目录与索引（路径约定正文唯一）」**：目录形态 `docs/<任务号>-<slug>/`、8 类固定主产物 + `<类别>-<后缀>.md` 自由后缀 + `assets/` 唯一子目录、索引三段四列表头逐字、版本归属与并存判据、ADR 登记与出具日口径。**这是全仓唯一正文**，其余文件只许指针。
2. 同文件需同步的既有条款：§二 L39「列数 ≤4」（索引表在 §七 例外中登记后仍受 ≤4 列约束）· §三 L52（调研明细落点 `docs/research/` → 任务目录 `research.md`）· §四 L65（`docs/reports/<编号>-arch-review.md` → `arch-review.md`）· §四「出具日 = 文件名日期前缀」补一句「任务目录内 ADR 无前缀 ⇒ 出具日 = 索引时间线日期」· §五 L75（`cases.md`）· §七 L92 例外清单加「③ 索引表（机读契约，行数不限、列数 ≤4）」· §九 L150（`docs/designs/<编号>-<slug>.md` → `design.md`；`docs/designs/README.md` 标为历史冻结）。
3. `.agents/templates/task-docs/prd.md.example` · `report.md.example` · `release-notes.md.example`（新建；AC8 要求被 §十 引用）。

## 二、归档约定与回执口径

4. `.agents/common/intercom-protocol.md` L145–149（五条归档约定）→ 收敛成两条：① 「新任务产物一律进 `docs/<任务号>-<slug>/`，路径与文件名约定见 @.agents/checklists/deliverable-docs.md §十」；② 「`docs/{prds,reports,adr,designs,research,releases}/` 为 2026-11-27 前历史，冻结只读」。
5. `.agents/common/output-format.md` L17（示例 `docs/prds/<file>.md#<section>`）、L38（`docs/reports/<编号>.md`）。
6. `.agents/checklists/comm-templates.md` L33（回执 `详情：docs/reports/<编号>.md`）。
7. `.agents/checklists/pm.md` L63（notes 落盘）· L94（PRD 归档 + 索引）· L102（调研落盘）· L106（Issue 指针路径）· L110（发布 notes 落盘）· L133/L134/L136（三处降级载体 `docs/reports/<编号>-review.md`、`-repro.*`）。
8. `.agents/checklists/qa.md` L61（`user-acceptance.md`）· `.agents/checklists/architecture-designer.md` L49（`docs/research/`）。
9. `.agents/skills/arch-patterns.md` L8 / L47（ADR 索引改 `docs/README.md` 决策时间线）· `research.md` L42 / L61 · `task-completion.md` L31 / L33 / L46 / L47（followups / retro）· `test-design.md` L47 / L53 / L63（user-acceptance / defects / cases）· `pm-to-spec.md` L14 / L35 / L50 / L51 / L74 / L75（含 §六「落 docs/prds/ 且索引更新」）· `pm-operations.md` L62 / L100–102 · `uiux-design.md` L23 / L24（`assets/` 例外）· `design-loop.md` L64 / L77。

## 三、发版说明（TBD-4）

10. `.agents/common/release-notes.md` L15（顶部口径）· L22（口径与落盘一致 + 并存期判据）· L57（核对清单）—— 实测 **3 处**，非 5 处。
11. `.agents/templates/release-notes.md.example` L2（复制目标路径）· L43（文档链接）。
12. `.agents/skills/github-flow.md` L107（`gh release create --notes-file` 命令样例）· L110（notes 落盘 + 骨架指针）· L124（离线降级表）· L45（阶段 7 产出「notes 落 `docs/releases/`」）。

## 四、BR1 全量清单与文档载体（必改，现列的是即将作废的路径）

13. `github-flow.md` **L56 BR1**：`docs/prds/README.md` → `docs/README.md`；`docs/releases/<v>.md` → `docs/<任务>/release-notes-v<v>.md`；`docs/reports/*-followups.md` → `docs/<任务>/followups.md`；并补 `docs/<任务>/prd.md`、`arch-review.md`、`adr-*.md`。
14. `github-flow.md` L39（阶段 1 PRD 落点）· L43（阶段 5 报告与用户验收清单）· L63（验证接缝探针路径）· L90 / L91（规格与 Issue 指针路径）· L119（降级表「立项」）· L138（降级载体 `-review.md`）。
15. 模板：`.agents/templates/prd.md.example` L2 / L26 · `tasks-state.md.example` L4 / L11 / L24 / L49 / L61 · `adr-index.md.example` L1 / L5（索引职责移交 `docs/README.md`，本骨架标历史冻结）· `adr.md.example` L1 · `github/pull_request_template.md.example` L5。
16. 角色卡 5 张（**每张须 bump `version` + 更新 `updated` + intercom 广播 `card <role> v<N+1>`**，`AGENTS.md` 硬纪律）：`product-manager.md` L66 / L135 / L148 / L155 / L158 · `architecture-designer.md` L54 / L86 / L89 / L90 / L103 · `test-engineer.md` L67 · `uiux-designer.md` L21 / L30 / L32 / L34 / L54 · `infra-engineer.md` L47。
17. 用户可见文档：`README.md` L98 / L133 · `docs/INSTALL.md` L159 + **新增一段「文档目录怎么摆」**（只给指针，PRD §八）· `docs/ARCHITECTURE.md` L91（该处为历史 ADR 具体指针，**不改**，仅确认无需动）。

## 五、`check` 与回归用例（rd-infra）

18. `.agents/scripts/fleet/lib/check.sh`：
    - L172–183 注释口径扩写（新路径分支、锚点谓词、「不计 warn=」同口径）；
    - L184–240 `check_prd_structure`：扫描面加 `docs/<任务号>-*/prd.md`。**注意**：新路径无 `YYYY-MM-DD-` 前缀，现 L201–207 的无前缀跳过逻辑会把它们全部跳过 ⇒ 需先按目录形态分流，再决定是否套 `[[ "$d" < "$since" ]]`；`-v` 明细 L232 写死 `docs/prds/$base`，须改相对路径；
    - 新增 `check_docs_index()`（三段标题锚点 + 剥 ``` 围栏后解析 + 双向断言 + 半启用提示），单条聚合 `  ! 索引…`，`-v` 展开；
    - L510 之后（与 `check_prd_structure` 同位）加调用 `check_docs_index || true`。
19. `.agents/scripts/nao-fleet.sh` L296（`WARNS` 排除名单加 `-e '^  ! 索引'`）· L309–310（摘要常驻回显：再 `grep -m1 '^  ! 索引'`）。
20. `tests/t4/cases/53-docs-index.sh`（新建，形态照 `cases/36`；**编号须 >52** —— 46–50 已随编排器 T578 退役，`cases/06` 有「退役编号不复用」元断言）：主路径（目录+行齐 ⇒ 零输出）· AC2 未登记 · AC3 幽灵行 · AC5 版本重复 · 文法非法行 · 老仓无索引 ⇒ 零输出 + rc=0（AC7）· 本仓零输出 + md5 与「探针关闭」逐字一致 · 变异负控 3 条（删调用 / 去排除名单 / 取反幽灵判据）。
21. `tests/t4/run.sh` L37 `CASE_IDS` · L38 `CASE_TITLES` · L93 `FAST_CASES`（未登记 → 硬错）——另注意 `cases/06` 的两条元断言会因此变红：「最大用例编号 = `CASE_IDS` 末位」（新编号 53 须同时成为末位）与「`CASE_IDS` 数 = 用例文件数」。`tests/README.md` 若有用例清单同步。

## 六、本任务自身（样板，AC9）

22. `prd.md`：补 `## TL;DR`（≤5 行）+ §七 改 5 个 `###` 组（主路径 / 异常 / 边界 / 负向闭环 / 设计一致性）；§三 文件名集合改「8 主产物 + 自由后缀 + assets」；§三/§二 去掉任务段「版本」字段；AC6 判据按 `arch-review.md` ①.2 改写；AC4 明确「新路径不套 `NAO_PRD_STRUCT_SINCE`」。
23. `docs/README.md`：任务段去「版本」列（4 列）· 版本段**删「停更说明」行**（§四 已含同一信息，留着会被文法判红）· 段首补一行机读契约说明（表头逐字、单元格禁 `|`、禁止在本文件放示例表）。
24. 台账：`docs/tasks-state.md` 增 T579 行（实测当前**无**该行，`grep -c 'T579'` = 0）。

## 七、明确「不改」的（防误伤历史）

- 历史具体文件的引用：`pm.md` L84 / L109 / L114 / L134 中的 `docs/reports/2026-…`·`docs/reports/<编号>-repro` 历史引述仅改「载体约定」处，历史文件名不动；`design-loop.md` L84（`docs/adr/2026-11-24-…`）· `check.sh` L332 · `status.sh` L382 · `term-herdr.sh` L915 / L923 · `docs/ARCHITECTURE.md` L91。
- `docs/{prds,reports,adr,designs,research,releases}/` 下 319 个文件：零改名、零移动、零软链。
