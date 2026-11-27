# ADR · docs 按任务分割（一任务一目录 + 一级索引 + 分层门禁）

- 状态：提议
- 更新：2026-11-27
- Owner：arch-designer
- 指针：`docs/T579-docs-per-task/prd.md` · 评审 `docs/T579-docs-per-task/arch-review.md` · 实施清单 `docs/T579-docs-per-task/arch-landing-list.md`

## 背景

任务产物按**类别**分居 6 目录（319 文件），一次任务的 PRD / 评审 / ADR / 实现 / QA / 发版说明要跨 2–6 目录才找得齐；索引两份（`docs/prds/README.md` + `docs/adr/README.md`）且 `docs/` 一级无入口。全仓 1229 处旧路径指针（含 Issue / PR 正文）不可改写 ⇒ 历史只能冻结、只能换布局。

## 决策

1. 新批次产物一律进 `docs/<任务号>-<slug>/`（扁放；8 类固定主产物 + 自由后缀；`assets/` 唯一子目录），历史路径冻结不迁移、不建软链。
2. `docs/README.md` = 唯一一级索引，三段（任务批次 / 版本 / 决策时间线）均为**四列表**，表头即机读契约。
3. 启用判定 = **结构自描述谓词**（索引三段标题逐字齐 + 目录形态），**不引入 `NAO_DOCS_LAYOUT_SINCE`**，也不与 `NAO_PRD_STRUCT_SINCE` 合并。
4. 断言分两层：`check` 只做 warn-only 可观测（不计 `warn=`、摘要常驻回显）；「必须红」由 `tests/t4/cases/53` 承载（夹具 + 变异负控 + 本仓零输出 + md5）。
5. 发版说明权威份 = 归属任务目录的 `release-notes-v<X.Y.Z>.md`；`docs/releases/` 冻结；并存期判据 = **同一版本全仓仅一文件**（非路径白名单）。

## 理由

- **业务匹配**：痛点是「找回成本」，聚合粒度应与评审单位一致（一次任务 = 一次评审 = 一个 PR）。
- **技术成熟度**：全部 bash/awk + 既有 `check` 探针形态，无新依赖；性能增量可忽略（索引 38 行 + 每行一次 `test -d`）。
- **团队能力**：与既有 `check_prd_structure` / `cases/36` 同一套手法，RD/QA 无需学新机制。
- **成本**：历史 0 迁移；改动集中在机制文本 + 一条探针 + 一条用例。

## 对照过的备选模式

- **维持现状（6 类目录 + 2 份索引）** —— 适用：以「文档类型」为检索主轴。代价：每批跨目录拼装、索引双写。不采纳：痛点即此。
- **不动目录，只加一份汇总索引** —— 适用：不愿改约定。代价：索引一行要背 6 条路径，删行漏行同样无人守，「一屏可见」仍未解。不采纳。
- **纯日期分桶 `docs/2026-11/`** —— 适用：无任务编号体系。代价：同月多任务混居，编号仍是唯一键，未减拼装。不采纳。
- **`NAO_DOCS_LAYOUT_SINCE` 日期开关** —— 适用：有旧语料需按时间收窄（旧 PRD 场景）。代价：同仓不同会话 / CI 判定不同（不可复现），`revert` 后残留环境语义。不采纳：新布局零旧语料，形态即证据。
- **只落 `check`（单层门禁）** —— 适用：允许 warn 的内容类 lint。代价：`!` 行永不改 rc ⇒ 删行仍绿，与「删一行必红」需求直接冲突。不采纳。
- **索引改用带标签列表块（非表格）** —— 适用：列多、需长说明。代价：违背「一任务一行」目标指标，机读需 4 行/任务。不采纳。

## 后果与风险

- 索引成单点：PM 忘登记 ⇒ 全仓不可发现；缓解 = `check` 摘要常驻回显 + t4 本仓断言。
- 机制文本约 28 文件需同批改；5 张角色卡须 bump `version` + intercom 广播（否则卡与清单冲突）。
- 并存期两处 releases 路径靠「同版本仅一文件」机械判据维持，不靠文字禁令。

## 限制与已知边界

- 任务目录内 ADR 文件名无日期前缀 ⇒ 出具日改由索引时间线日期承担；与 `deliverable-docs` §四「出具日 = 文件名日期前缀」冲突，已在实施清单登记为需补条款。
- 历史 6 目录与两份旧索引永久只读，**不享受**新断言保护（旧路径失效不会被 `check` 发现）。
- 探针只认逐字表头与固定段序；markdown 变体（改标题、增列）一律判「结构非法」，不给容错。

## 相关指针

- 逐条落点（文件 + 行段 + 改什么）：`docs/T579-docs-per-task/arch-landing-list.md`
- 先例：`tests/t4/cases/36-prd-structure-probe.sh`（warn-only 探针的持久用例与变异负控）、`docs/adr/README.md`（4 列索引表 26 行在用）

## 参考来源

- Diátaxis（按读者需求类型分四类，本仓现状即「按类别切」的同类实践）· https://diataxis.fr/ · 访问 2026-11-27
- Architectural Decision Records / MADR（决策日志集中索引的业界惯例）· https://adr.github.io/ · https://adr.github.io/madr/ · 访问 2026-11-27
- Spotify Engineering《Solving documentation for monoliths and monorepos》（monorepo 文档聚合与 README 入口实践）· https://engineering.atspotify.com/2019/10/solving-documentation-for-monoliths-and-monorepos · 访问 2026-11-27
- 未检索到「按任务号目录 + 四列机读索引 + 分层门禁」的同型公开方案；上列来源只支持「按需求类型分类」与「决策日志集中索引」两项，分层门禁部分依据仓内先例（`cases/36`）。
