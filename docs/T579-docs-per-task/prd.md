# PRD · docs 按任务分割（水平切分 + 一级索引）

- 任务：**T579** · 分支 `nao/T579-docs-per-task` · 类型：机制约定 + 文档面（含 `check` 探针扩展）
- 状态：草稿（待开工确认 + arch 落点回执）
- 本文件自身即新规范的第一个样板：放在 `docs/T579-docs-per-task/`，不再进 `docs/prds/`

## TL;DR

`docs/` 从「按类别分割」（6 目录 / 319 文件 / 1229 处指针）改为「**一任务一目录** `docs/<任务号>-<slug>/` + `docs/README.md` 唯一索引」，**历史冻结不迁移**。ADR 进任务目录、发版说明进任务目录并在索引版本段登记权威路径（版本只此一处）。判红载体 = `tests/t4/cases/53`（`check` 只 warn-only）。本任务自身是首个样板。

## 一、问题证据

- **一个任务的产物要跨 2–6 个目录才找得齐**。`docs/` 现有 6 个类别目录：`reports` 167 文件 / 2.2M · `releases` 71 · `prds` 49 · `adr` 26 · `designs` 4 · `research` 2，合计约 **319 个文件**。以最近两批为例：T576 的 3 份审计/勾表/复核全在 `reports/`，其内容改写又在 `apps/document/content/`；T573+T574 的 4 份报告混用复合编号（`573-574-qa-verify.md`、`573-574-rd-infra-fix.md`），靠文件名认领任务。
- **命名四种写法并存**：`118-mechanism-review.md`（纯编号）· `T538-gate-number-provenance-rd.md`（T 前缀 + 角色后缀）· `143-profile.md`（Issue 号）· `M20261014-pi-ext-update-followups.md`（维护型编号）。同一目录里同类产物无法按形态区分。
- **索引是两个分散 README**：`docs/prds/README.md` + `docs/adr/README.md`（`reports` 无索引）。新增一份 PRD 要记得改前者，新增一篇 ADR 要改后者，`docs/` 一级没有任何入口。
- **归档与检索代价**：回看一批时要先 `grep` 台账拿到若干路径再逐个打开；`find docs -name '*576*'` 只能命中命名里带编号的那部分。
- **反证（不是问题）**：全仓指向这六个目录的 markdown 指针共 **1229 处**（台账 245 / 归档 52 / `github-flow.md` 14 等），且既有 Issue、PR 评论里的链接不可改写 ⇒ 历史路径必须冻结，否则会成片失效。

## 优先级（RICE + 战略筛子）

- **RICE**：Reach 20（未来 3 个月受影响的批次数）· Impact 2（每批都省一次跨目录拼装）· Confidence 0.8 · Effort 2 人天 ⇒ **Score ≈ 16**。
- **战略筛子**：① 是否阻塞当前交付 —— 否；② 是否降低长期熵 —— 是（与 2026-11-09「队列只放需要动作的项」同族：减少堆积与找回成本）；③ 是否用户可见 —— 是（发版说明的落盘路径变了）。
- **MoSCoW**：Must = 目录规范 + 一级索引 + PRD 探针覆盖新路径（否则新路径无防护）；Should = 版本权威份唯一断言、模板骨架；Could = 索引的机读强化（TBD-2）；Won't = 历史迁移。
- **结论**：用户直接提出 ⇒ 排本批，不排队。

## 二、目标指标

- **找齐率**：新批次任务的 PRD、架构评审、ADR、实现报告、QA 报告、发版说明，**100% 落在同一个任务目录内**（验收方式：任取 T580 之后的一个任务，`ls docs/<该任务号>-*/` 一屏可见全部产物）。
- **入口唯一**：新批次任务在 `docs/README.md` 恰好 1 行登记；`docs/` 一级不再有第二份索引文件（现状 2 份 ⇒ 目标 1 份）。
- **零迁移成本**：历史 319 个文件的路径改动 **0 个**、`docs/{prds,reports,adr,designs,research,releases}` 下文件数基线不变；全仓旧路径指针数 **1229 → 1229**（只增新批次的新路径，不改旧路径）。
- **防护不退化**：PRD 结构探针（AC 分组、行数阈值、`warn` 不污染摘要）对新路径同样生效，且**负控必红**。

## 三、范围 / 非范围

**范围内**

- 目录规范：`docs/<任务号>-<slug>/`，任务号 = `T579` / `M20261014-<slug>` 形态，slug 全小写连字符。
- 目录内文件（扁放，唯一允许的子目录是 `assets/`）：**8 类主产物固定名** —— `prd.md` · `arch-review.md` · `adr-<topic>.md` · `design.md` · `impl-<role>.md` · `qa-verify.md` · `followups.md` · `release-notes-v<X.Y.Z>.md`；**其余用自由后缀**（`user-acceptance.md` · `retro.md` · `review.md` · `repro.md` · `<topic>-调研.md` 之类），主产物必须用上面的固定名。
- 反例（arch 实测）：本仓实存 8 类装不下的产物 —— 缺陷单 · 用户验收 · 复盘 · 交叉评审 · 复现脚本 · 调研 · 图片（`assets/`）⇒ 固定名只锁主产物，不锁全集。
- `docs/README.md`：唯一一级索引，三段 —— **任务批次**（`任务号` · `目录` · `一句话` · `Issue/PR`，恰 4 列）· **版本**（`版本` · `权威路径` · `发布日期`）· **决策时间线**（`日期` · `决策` · `任务号` · `状态`，决策格带 `adr-*.md` 相对链接）。**逐字表头 + 严格单元格文法**，解析前先剥 ``` 围栏；三处双向断言：目录 ↔ 行 · 版本 ↔ 文件 · ADR ↔ 时间线。
- 机制文本落点：`github-flow.md`（BR1 全量清单与发布节）· `common/release-notes.md`（落盘路径与同源判据）· `checklists/{pm,qa,rd-infra}.md` · `intercom-protocol.md` §发布说明 · `skills/arch-patterns.md`（ADR 索引登记）· `checklists/deliverable-docs.md`（骨架与路径）· `pm-to-spec.md` 指针。
- 模板骨架：`.agents/templates/task-docs/`（PRD / 报告 / notes 三份骨架，供 `deliverable-docs` 引用）。
- `check` 扩展：PRD 结构探针扫描面从 `docs/prds/*.md` 扩到「`docs/prds/*.md` + `docs/T*/prd.md`」；新增「索引一致性」断言（每个任务目录在 `docs/README.md` 有且仅一行、每行指向存在的目录、同一版本号只出现一次）。
- 本任务自身作为首个实例（`docs/T579-docs-per-task/`）。

**范围外**

- 历史 319 个文件不迁移、不改名、不建软链、不改写任何旧路径指针（含 Issue/PR 正文）。
- 站点 `apps/document/content/**` 的结构与内容（另有任务）。
- 台账 `docs/tasks-state.md` / `tasks-archive.md` 位置不变（活文件，不属于任何任务）。
- `docs/INSTALL.md` / `ARCHITECTURE.md` 位置不变。
- 不改版本号策略、不改发版节奏。

## 四、用户场景

- **PM 立项**：开 Issue 后建 `docs/T<号>-<slug>/`，把 PRD 写进 `prd.md`，在 `docs/README.md` 加 1 行 ⇒ 此后所有派单只给这一个路径。
- **RD 交付**：实现报告写 `impl-<role>.md`，不发散到 `docs/reports/`。
- **QA 复核**：`qa-verify.md` 同目录，红旗与放行结论与实现报告并排可比。
- **发版**：`release-notes-v<X.Y.Z>.md` 进「本次发布点名的那个任务目录」，`docs/README.md` 版本段登记 `vX.Y.Z → 该路径`（**权威份唯一**，其余任务目录不复制）。
- **三个月后回看**：打开 `docs/README.md`，按任务号或版本号一步进目录；要看决策沿革走「决策时间线」段。
- **新会话接手**：只读 `docs/README.md` + `docs/tasks-state.md` 快照区即可定位历史，不必先 grep。

## 五、业务规则

- **冻结线**：以本任务合并提交为界，之前的文件保持现有路径（历史只读）。判定以目录是否存在为准，不按文件名猜。
- **权威份唯一**：同一版本号的发版说明全仓只有 1 份；索引里该版本只出现 1 行。
- **索引即契约**：新任务目录出现但索引无行 ⇒ 判异常；索引行指向不存在的目录 ⇒ 判异常。
- **单源**：路径约定的正文只写一处（`deliverable-docs.md`），其余机制文本只给指针（防双源，沿用本仓既有纪律）。
- **活文件例外清单**（仅这 4 个，任何新增需改本节）：`tasks-state.md` · `tasks-archive.md` · `INSTALL.md` · `ARCHITECTURE.md`，以及索引 `README.md` 本身。
- **发版说明归属**：由 PM 在发布时点名「归属任务」；一个版本只归一个任务。若该版本无对应任务（纯发版），归「本次最后一个合并任务」。**版本号只登记在索引版本段**（任务段不含版本列），同一事实不写两处。
- **命名空间**：`T<编号>` 与 `M<YYYYMMDD>-<slug>` **共用同一命名空间**（同一个 `docs/<任务号>-<slug>/` 规则，不靠前缀区分）。
- **ADR 归属**：`adr-<topic>.md` 进任务目录；同时必须在 `docs/README.md` 决策时间线段登记一行（日期 + 决策 ≤20 字 + 任务号 + 状态），替代原 `docs/adr/README.md` 的角色（旧索引文件冻结保留，不再追加）。

## 六、NFRs（业务视角，技术指标待 arch 转译）

- **可检索性**：任一任务号、版本号、决策关键词，能在 `docs/README.md` 一步命中；`find docs -maxdepth 2` 可枚举全部任务目录。
- **可回滚**：本任务改动须能 `git revert <sha>` 单条回退，回退后旧路径与新批次目录的判定回到「未启用」，不产生半启用状态。
- **零静默降级**：新批次目录的登记缺失必须以可观测方式暴露（`check` 摘要可见），不得只写进文档靠人自觉。
- **判红载体**：`check` 只做 warn-only（不改 rc、不计 `warn=`），**「删一行必须红」由 `tests/t4/cases/53` 承载**（先例 `cases/36`）；本仓只断言「零输出 + md5」，防立项中途假红。
- **性能**：`check` 新增断言不得让体检明显变慢（目标增量 ≤0.3s，`-v` 同样）。
- **兼容**：升级到本版本的用户，其仓里只有 `docs/prds/` 老结构时 `check` 必须照旧零输出（不因新规矩报错）。

## 七、AC

### 主路径

**AC1 · 新目录可建可登记（主路径）**
Given 一个新任务号 T999 且 `docs/` 无该目录，When 按规范建 `docs/T999-<slug>/prd.md` 并在 `docs/README.md` 任务批次段加一行，Then `check` rc=0，且 `check -v` 的索引小节显示该行已登记、无 warn。

### 负向闭环

**AC2 · 未登记必报（负向闭环）**
Given 存在 `docs/T998-<slug>/` 但 `docs/README.md` 无对应行，When 跑 `check`，Then 摘要/明细点名该目录「未登记」（先红后绿验证：删掉那一行 ⇒ 必提示；加回 ⇒ 归零）。

**AC4 · PRD 结构探针覆盖新路径（防护不退化）**
Given 在 `docs/T996-<slug>/prd.md` 造一份缺 AC 分组的 PRD，When 跑 `check`，Then 探针点名该文件缺组（**与 `docs/prds/` 老路径同样的判据与文案**）；把 `docs/prds/` 老路径的同型夹具一起跑，两者都必须红 —— 证明新路径不是「探针看不见所以永远绿」。

### 异常

**AC3 · 幽灵行必报（异常）**
Given `docs/README.md` 有一行指向不存在的 `docs/T997-<slug>/`，When 跑 `check`，Then 点名该行「目录不存在」。

**AC7 · 老仓不受影响（兼容）**
Given 一个只含 `docs/prds/*.md`、无任何 `docs/T*/` 目录的仓，When 跑 `check`，Then 索引与目录相关断言零输出、rc=0（不因新规矩报错）。

### 边界

**AC5 · 版本权威份唯一（边界）**
Given 索引版本段同时出现 `v0.99.0` 两行（指向两个不同目录），When 跑 `check`，Then 点名重复版本（同一版本只允许一行、且该行指向的 notes 文件存在）。

**AC6 · 历史冻结（不回归）**
Given 本任务合并前后，When ① 对比 `git ls-files docs/{prds,reports,adr,designs,research,releases}`（文件集与行数完全一致）② 对这 6 个冻结目录**只**统计指针数（`grep -rho 'docs/\(prds\|reports\|adr\|designs\|research\|releases\)/' --include='*.md' . | wc -l`），Then ① diff 为空 ② 值仍为 **1229**，差值 0。**判据说明**：不统计「全仓 md 指针总数」——写规范本身就在新增 `docs/T*/` 指针（arch 实测本分支 1229 → 1251），把该数字当判据等于禁止记录规则。

### 设计一致性

**AC8 · 单源与模板（设计一致性）**
Given 机制文本，When `grep -c` 路径约定正文（`docs/<任务号>-<slug>/`），Then 正文定义只在 `deliverable-docs.md` 一处，其余文件只出现指针（每处须能在同段找到指向 `deliverable-docs.md` 的引用）；`.agents/templates/task-docs/` 三份骨架存在且被 `deliverable-docs.md` 引用。

**AC9 · 本任务自身即样板（自证）**
Given 本任务合并后，When 执行 `ls docs/T579-docs-per-task/`，Then 至少含 `prd.md` 与实现/QA 报告，且 `docs/README.md` 有一行登记 T579 —— 即规矩的第一个实例由发布者自己遵守。

**AC10 · 发版说明可发（上线闭环）**
Given 本任务随版本发布，When PM 用 `gh release create --notes-file docs/T579-docs-per-task/release-notes-v<X.Y.Z>.md`，Then 索引版本段有该版本一行指向该文件，且 `common/release-notes.md` 的「落盘路径」条款已改为新路径（不留旧路径的双源说法）。

## 八、上线闭环

- **发布节奏**：MINOR（机制约定变更 + `check` 新增断言，属行为面变化但不破坏既有命令；0.x 下按 MINOR 走）。
- **回滚**：`git revert <合并 sha>` 单条；之后 `check` 关于索引/目录的断言消失，新批次目录即便存在也不被判异常（不残留半启用）。
- **台账**：`docs/tasks-state.md` 本批行 + `docs/README.md` T579 行。
- **迁移说明**：`docs/INSTALL.md` 增一段「文档目录怎么摆」指针到 `deliverable-docs.md`（只指针，不复制正文）。

## 九、变更治理

- **谁定**：该约定的正文归 PM（`deliverable-docs.md`）；`check` 断言归 `rd-infra`；ADR（是否新建「文档布局」决策）由 `arch-designer` 判定 —— **是否需要 ADR 由 arch 出回执时明说**（若判「结构性决策」则写 `adr-docs-per-task.md` 进本目录）。
- **怎么改**：新增目录内文件名 / 新增例外清单条目，须同时改 `deliverable-docs.md`（正文）+ `check` 断言 + 本 PRD 的 §五，三者缺一视为未完成。
- **arch 已裁定（2026-11-27，PRD 定稿）** —— 原文 TBD-1..4 均已定，判据与反例见 `docs/T579-docs-per-task/arch-review.md`：
  - **TBD-1 判定边界**：用**结构自描述谓词**（`docs/README.md` 三段标题逐字齐 + 目录形态），**不加** `NAO_DOCS_LAYOUT_SINCE`，**不与** `NAO_PRD_STRUCT_SINCE` 统一（后者回答「旧 PRD 追溯面」，本条回答「本仓是否已在新布局」；变量化会让同仓/CI 判定不同、revert 后残留语义）。半启用态用单条提示防「删索引免责」。
  - **TBD-2 断言载体**：双层 —— `check` 只 warn-only（不计 `warn=`、摘要常驻回显）；**「删一行必须红」由 `tests/t4/cases/53` 承载**（`check` 的 `!` 行永不改 rc，先例 `cases/36`）。
  - **TBD-3 索引最小机读结构**：见 §三（4 列 + 逐字表头 + 严格单元格文法 + 三处双向断言 + 先剥 ``` 围栏）。
  - **TBD-4 并存期话术**：**改判据不列路径** —— 权威份 = 归属任务目录的 `release-notes-v<X.Y.Z>.md`（正文只在 `deliverable-docs.md`），`docs/releases/` 冻结只读；并存唯一判据 = **同一版本全仓仅一文件**。实测该文件只有 **3 处**写死路径（L15/L22/L57），非 5 处。
- **PM 拍板（2026-11-27，对应 arch 待拍 3 项）**：① PRD §七 补 5 个 `###` 组（**不放宽探针**；五覆盖是既有硬规则）② 任务段**去掉版本列**（版本只登记在版本段，防双源）③ `M<YYYYMMDD>-<slug>` **与 `T<编号>` 共用命名空间**（允许）。
- **ADR**：`arch-designer` 判「需要」（路径契约 + 门禁归位 + 索引机读 API 三项结构性决策）⇒ `docs/T579-docs-per-task/adr-docs-per-task.md`，状态自「提议」转「已接受（待落地）」。
