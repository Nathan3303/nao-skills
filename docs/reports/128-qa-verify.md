# QA 非作者复核（#128 · 卡与规则收敛）

- 状态：复核完成 · 结论 **通过（无 P1/P2；P3 ×4）** · 分支 `nao/M20261115-converge` @ `d3a322e` · 2026-11-15 · Owner：qa
- 指针：PRD `docs/prds/2026-11-15-converge.md`（AC1–AC8）· 实现报告 `docs/reports/128-converge.md` · Issue #128 · 不发版

## 范围 / 不测

- 测：AC1–AC8 逐条判据 + PM 圈定的 7 个重点面（单源是否削判据、`=1 文件` 是否靠删凑、G5 双判据负控、E1 断言是否在闸门上、6 卡 bump、零夹带、门禁数字）。
- 不测：`bin/` 与安装器行为（本批未改）、真实下游仓安装、UI 呈现（无机读面）。
- 边界遵守：真仓只读（未 checkout/switch、未造 stash）；负控与变异全部在 `/tmp/qa128` 整仓副本中做。

## 环境与命令（HEAD `d3a322e`，门禁时工作区静默 `git status --porcelain` 空）

- `bash .agents/scripts/nao-fleet.sh check` ×2 ⇒ rc=0/0，`diff` 空，`check: OK · roles=7 · files=54`。
- `npm test`（herdr 默认）⇒ rc=0，`SKIP=0 · DEGRADE=0 · NOTE=10（全白名单）· PENDING=0`，RESULT: PASS。
- `NAO_TEST_TERMINAL=tmux npm test` ⇒ rc=0，`SKIP=0 · DEGRADE=0 · NOTE=9（全白名单）`，RESULT: PASS。
- `--case 06` / `--case 18` 双后端 ⇒ 均 PASS（06：`NOTE=2` 白名单；18：`NOTE=0`）。

## 结果

- 用例/断言：本批新增面 06 E1 组 13 条、18 G5 组 2 条（绝对形态）+ 负控 1 条；全量 34 用例双后端 PASS。
- 缺陷：**未过项：无（P1/P2）**；P3 见下（均不阻塞合并）。

## 逐面复核（PM 圈定 7 项）

1. **单源收敛未删判据（最要紧）—— 成立**：`skills/codegraph.md` 本体完整（①原生入口含「插件+CLI+索引」前提与「声明≠生效」告警；②12 条 CLI 真命令含 `codegraph node --file … --offset/--limit`；③`grep -rn` + 行段与「禁 cat 全文」永久条款；另有 token 纪律/索引维护）。`common/output-format.md` 本次**零改动**（`git diff main...HEAD -- .agents/common/output-format.md` 空），三件套定义 + 反例 + 「缺一即打回」原样。`checklists/{qa,rd-infra}.md` 只换指针，均保留「缺任一项该数字不得作验收依据」，qa/rd-fe 保留「回退须注明原因」「禁 cat 全文」。逐条 before/after 对应：被删文字全部能在单源命中同义可执行内容（命令/前提/反例/禁令），无独占判据随删除消失。
2. **`=1 文件` 不是靠删凑的 —— 成立，但指针形态不均**：实测 `原生入口` 22 行/11 文件（main）→ 5 行/1 文件（`git grep -n '原生入口' main -- '.agents/*.md'` = 22/11）；`静默工作区` 7/6 → 2/1，两行 = 定义 + 反例。删掉的是复写，判据落在单源。指针够不够用：rd-fe / qa / pm 的指针自带触发与禁令（「未走三段阶梯…？」「禁 cat 全文」「回退注明」）⇒ 不构成退化；arch 指针点名场景（影响面评审）＋清单门禁，够用；**rd-be / infra 仅「按需技能」列表内的主题名**，无触发时机，见 P3-1。
3. **G5 双判据自做负控（副本 `/tmp/qa128/repo`，真仓零触碰）**：
   - 删 `frontend-developer.md` 指针（连带 0 处 codegraph 字样）⇒ 条件式 G5 **PASS（绿）**、绝对形态 **FAIL 并点名 `frontend-developer.md`** —— 正是 RD 补这条要封的逃逸，证明有效（另有 `CARDS_WITH_CG=6` 计数绊线同时红，但不点名）。
   - 只删 `product-manager.md` 指针（保留 1 处 codegraph 提及）⇒ 条件式与绝对形态**双红**，条件式判据未被削弱。
4. **E1 断言真在闸门上 —— 成立**：副本删掉 `卡预算基线` 实现行后跑 `--case 06` ⇒ **6 FAIL**（基线行/最大卡/行数/阈值/占比/超阈值占比），而 `check -v` 仍 rc=0（失败来自断言，不是命令报错）；恢复后 13 PASS。断言把行内字段解析出来与**实测最大值/实测占比**比对，不是「命令没报错」。默认摘要未污染：tmux 全输出 md5 golden（P2④）与 herdr 3 行契约均 PASS，`check` 默认输出无基线行。`CARD_MAX_LINES` 仍 200。
5. **6 卡 bump —— 成立**：arch 14 / rd-be 13 / rd-fe 14 / infra 5 / pm 38 / qa 17（对 main 各 +1），`updated` 全 `2026-11-15`；uiux 未动（2）；`roles.yaml` 零改动（numstat 无该文件）。广播文本 6 条逐条对照 diff：每条声明都有对应改动，无「说了没改」。
6. **零夹带 —— 成立**：`git diff --numstat main...HEAD` 无 `bin/`、`package.json`、`site/`；`docs/` 仅新增 PRD/报告 + `tasks-state.md`（PM 面）。#126 交付物 `skills/github-flow.md`、`cases/34`、`cases/35`、`tests/README.md` 均未出现在 diff；同批触及的 `checklists/pm.md` / `nao-fleet.sh` / `cases/06,18` 分别只含本批 S4 指针行、E1 新区块、E1/G5 新断言。
7. **门禁抽核 —— 通过**：见上「环境与命令」；`check` 两次逐字一致且 `files=54` 未变（未增删 `.agents/` 文件）。

## 缺陷（P3，均不阻塞）

- **P3-1 判据回声缺失（rd-be / infra）**：`prompts/backend-developer.md:14`、`prompts/infra-engineer.md:12` 的指针不再含「禁 cat 全文」（main 各 1 → 现 0），且这两角色别处无承载（`grep -c codegraph .agents/checklists/rd-be.md` = 0）。判据本体在单源完整（case18 G2 钉住），故非 AC3 退化；但「按需技能」无触发时机，存在「定位代码时不读技能」的漏读面。复现：`grep -c '禁 cat 全文' .agents/prompts/{backend-developer,infra-engineer}.md` ⇒ 0/0。建议零行成本补在同一行（「…；定位/变更代码时用，禁 cat 全文」）。
- **P3-2 点用处指针退化（arch）**：`prompts/architecture-designer.md:101` 由「定位口径见 @.agents/skills/codegraph.md 三段阶梯」改为「见本卡按需技能」，PR Reviewer 场景不再直接给路径。复现：`grep -n '本卡按需技能' .agents/prompts/architecture-designer.md`。建议改回显式路径。
- **P3-3 依据指针落点不准（arch 清单）**：新增「不适用：<一行理由>」出口的依据写作 `deliverable-docs.md §三`，而 §三 = 「PRD（9 模块）」；通用约定在 §一/§二。要求本身无误，仅落点不精确。复现：`grep -n '^## ' .agents/checklists/deliverable-docs.md | head -4`。
- **P3-4 报告措辞（E1 可见面）**：「卡预算基线仅 `-v` 可见」只对 rc=0 成立 —— `check` 失败时默认即整份报告，基线行随之出现（+1 行）。无功能影响。复现：副本改坏一卡 frontmatter ⇒ `check` rc=1，输出 67 行含基线行。建议报告限定为「成功摘要」。

## 未覆盖与风险

- 未覆盖：真实下游项目安装/注入面（本批未改 `bin/`，AC8 已证）；`uiux` 豁免与 `CARDS_WITH_CG=6` 为文件名/数量硬编码 —— 新增角色卡需同步改 `cases/18`（增量约束，非缺陷）。
- 风险低：S3/S4 之后同一规则只在单源生效，后续改口径须改对文件；已由 `check`+case18 指针判据兜底。

## 发布建议

- **可验收、可合并**（不发版）。P3-1 建议在本 PR 内顺手补（零行成本，同时不破 NFR「卡不增行」）；P3-2/P3-3/P3-4 可并入同批或转 `docs/reports/128-followups.md` 三出口，不阻塞。
