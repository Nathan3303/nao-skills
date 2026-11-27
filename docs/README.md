# docs 索引

> 这里是**唯一入口**。找某次任务的全部产物（PRD / 架构评审 / 决策 / 实现报告 / QA 复核 / 发版说明），按任务号进目录即可，不再去六个类别目录里拼。

## 一、任务批次

> 规则：2026-11-27（T579）起，每个任务一个目录 `docs/<任务号>-<slug>/`，产物扁放其中。
> 新任务在此表**加一行**；目录与表行必须一一对应（缺一行或多一行都算异常）。

| 任务号 | 目录 | 一句话 | Issue/PR |
| :--- | :--- | :--- | :--- |
| T579 | `docs/T579-docs-per-task/` | docs 按任务分割 + 一级索引（本规矩的样板） | [#237](https://github.com/Nathan3303/nao-fleet/issues/237) |
| T580 | `docs/T580-kickoff-card/` | 开工确认卡表格化 + 台账按批次分割（模板 + `check` 最小断言） | [#238](https://github.com/Nathan3303/nao-fleet/issues/238) |
| T587 | `docs/T587-home-banner/` | 首页 Hero 下纯装饰动画（动画 WebP + 静态降级） | [#249](https://github.com/Nathan3303/nao-fleet/issues/249) |
| T588 | `docs/T588-favicon/` | 站点图标 404 修复 + 图标守卫（本版发版说明在此） | [#250](https://github.com/Nathan3303/nao-fleet/issues/250) |
| T590 | `docs/T590-favicon/` | favicon 重设计（3 方向 + A 案落地：`>_` 图标 + apple-touch + dev 注入修复） | [#256](https://github.com/Nathan3303/nao-fleet/issues/256) |
| T594 | `docs/T594-rename/` | 仓库改名 nao-fleet（包名去 scope + env/bin 别名 + CI base，本版发版说明在此） | [#262](https://github.com/Nathan3303/nao-fleet/issues/262) |

## 二、版本

> 规则：发版说明由 **PM 在发布时点名归属任务**，落该任务目录的 `release-notes-v<X.Y.Z>.md`；同一版本全仓只有**一份权威**，这里只登记路径。

| 版本 | 权威路径 | 发布日期 |
| :--- | :--- | :--- |
| v0.37.0 | `docs/T594-rename/release-notes-v0.37.0.md` | 2026-11-27 |
| v0.36.0 | `docs/T588-favicon/release-notes-v0.36.0.md` | 2026-11-27 |

## 三、决策时间线

> 规则：新 ADR 进任务目录（`adr-<topic>.md`），并在此段登记一行；`docs/adr/README.md` 保留为历史索引，不再追加。

| 日期 | 决策 | 任务号 | 状态 |
| :--- | :--- | :--- | :--- |
| 2026-11-27 | [docs 按任务分割 + 一级索引](T579-docs-per-task/adr-docs-per-task.md) | T579 | 已接受（待落地） |

## 四、历史（冻结）

- **PRD**：`docs/prds/`（49 篇 · 索引 `docs/prds/README.md`，不再追加）
- **实现/评审/QA 报告**：`docs/reports/`（167 篇，无索引，按任务号 grep）
- **ADR**：`docs/adr/`（26 篇 · 索引 `docs/adr/README.md`，不再追加）
- **发版说明**：`docs/releases/`（71 篇，`v<版本>.md`）
- **设计稿**：`docs/designs/`（4 篇）· **调研**：`docs/research/`（2 篇）
- **活文件（不属于任何任务，位置不变）**：`docs/tasks-state.md` · `docs/tasks-archive.md` · `docs/INSTALL.md` · `docs/ARCHITECTURE.md`

> 冻结含义：历史文件不改名、不迁移、不建软链；既有 Issue / PR 里的老链接继续有效。
