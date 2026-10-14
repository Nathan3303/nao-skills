# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 历史见 `docs/tasks-archive.md`；权威来源 = `docs/prds/` 与 `docs/releases/`；本文件只记**运行时**状态，保持精简。
> 归档动作 = 从「进行中」**删除** + 归档墙**新增**（同一 id 同时出现在两处会因 `arch` 优先被判 **`closed`**，`close` 闸门保护静默消失）。

## PM 接续快照（会话重开后**先读本区**）

> 本区是 PM 的**悬空状态**（任务状态见下方五栏）；重开后逐行回读确认（当前阶段 · 未决决策 · 口头约束）。

- ✅ **PM 交接收尾（2026-10-14 · 用户拍板重开 · T520 批次终态）**：T520 **全链路闭环**（PRD → arch 结构定稿 → rd-infra 落地 → QA 独立验证 → squash `160cc60` → tag `v0.17.2` + Release（`9833344`）→ 台账归档），**无在飞任务、无未决决策**。新 PM `01a137a8`（pane %26）**已按交接回读确认 3 行**（ask-me · 用户「确认无误，进入待命」），旧 pm `01a13661`（%15）已自收窗，**舰队无派生会话残留**（实测 `list` 仅本会话）。**唯一待办** = 下游三仓（nao-todo / nao-todo-server / nue-ui）PM 会话唤醒后补发广播 `card pm v25`（T518/T521 批累计，原 v24 被 T521 取代）/ `card qa v14`（T518 批遗留）+ `card arch-designer v12`（T520 批）——**触发条件 = 目标会话在线且 `idle`，发前 `list` 核验并留痕**（本仓侧均已发）。
- ✅ **T521 交付闭环（2026-10-14 · v0.17.3）**：GitHub Release 标题口径 = 裸 `vX.Y.Z` —— 权威单处 `common/release-notes.md` §一.5 硬约束 + §四清单 + §五红线 · 两处引用收敛（`github-flow.md:56` / PM 卡 :121）并指回单处 · PM 卡 **v24→v25** · 模板注释 1 行（6 分段标题未动）· 一次性只读探针 `PASS=28 FAIL=0` + 负控 2/2 · QA 独立复跑 **GO** · squash `eff44ec` · tag + Release 已发（发布提交 `4d97f00` · **AC9 自证：标题严格 = `v0.17.3`**）· **npm 重发 0.17.3（用户执行 · 待核）**。
- ✅ **T520 交付闭环（2026-10-14 · v0.17.2）**：ADR 文档契约 —— 必写 5 节 + 可选 3 节（参考来源恒末）· 头部恰 4 字段 · 状态值域 4 值 · 禁写/下沉清单 · 新增 `templates/adr.md.example` + `adr-index.md.example` · `arch-designer` 卡 v11→v12 · QA 探针 `PASS=53 FAIL=0` + 负控 2/2 · squash `160cc60` · tag + Release 已发（`9833344`）· **npm 不重发**。

- 当前阶段：**T521 实施中**（发布标题口径 → 裸 `vX.Y.Z` · 降级批次 `nao/release-title-bare`）：**T521-接缝已确认**（QA `done(full)` 2026-10-14）→ rd-infra 落地中；上批 T520（v0.17.2）已闭环发布
- 当前 PRD：`docs/prds/2026-10-14-release-title-bare-version.md`（状态：**待开工确认**）
- 未决决策点：无（D1 **已拍板** = 重发 npm 0.17.3；AC7 **已裁定 (a)** 不动范围）；PR Reviewer = qa（已落开工卡）
- 待用户回答：无
- 当前阶段：**全部批次闭环**（T521 → v0.17.3 已交付并发布 · PR #39 `eff44ec`；T520 → v0.17.2；更早批次已下沉 `docs/tasks-archive.md`）
- 当前 PRD：`docs/prds/2026-10-14-release-title-bare-version.md`（状态：**已归档**）
- 未决决策点：无（D1 = 重发 npm 0.17.3 已拍板；AC7 已裁定 **(a)**）· PR Reviewer = qa（无法 `gh --reviewer` 指派 → 结论走 intercom）
- 待用户回答：无。**唯一待用户执行动作** = `npm publish` 0.17.3（成功判据 = registry 实测，非 `PUT 202`）
- 未派发队列：见下方「待派发队列」（共 0 项）
- 下次唤醒条件：**下批需求授意 / 用户要求重开 PM**；先读本快照 + `docs/prds/README.md` 索引；舰队现状 = 仅本 PM 会话（T521 派生会话已回收）；下批需求先 `ensure pm arch-designer rd-fe rd-be qa rd-infra`
- 口头约束已落盘：项目 `AGENTS.md` 项目约束（ask-me 提问）· PRD §5 BR6 格式禁令 + §9 R5/R6（T519）· ADR 字段口径 = `deliverable-docs.md` §四（T520 · 状态值域 4 值 / 头部 4 字段 / 60 行上限）
- 需求分支 / PR：见下方「需求分支 / PR / 发布」（降级分支 `nao/release-title-bare`——已 squash 合并并删净）
- 会话体检：当前 PM 会话 = `01a137a8`（pane %26），T521 全程 ctx ≈ 7%→（交接时 20.2k/1000k · 无压缩）· 旧 pm 已自收窗 · 舰队无派生会话残留（T521 派生已回收）· 本快照为接续唯一事实源（main = v0.17.3 发布提交 `4d97f00`）

## 需求分支 / PR / 发布（PM 维护）

- Issue：**无（降级批次 T521）** —— 摘要见 `docs/prds/2026-10-14-release-title-bare-version.md`
- 需求分支：`nao/release-title-bare`（base `main` = `832459d`；**已 squash 合并 `eff44ec` 并删净**）
- PR owner / Reviewer：rd-infra / qa（GitHub 侧无 `qa` 账号 ⇒ `--reviewer` 指派失败，QA 结论走 intercom `GO` 2026-10-14）（独立只读探针 · 开工确认卡落定）
- PR：[#39](https://github.com/Nathan3303/nao-skills/pull/39)（**已 MERGED** · squash `eff44ec`）· 预览环境：无
- 合并：**已 squash 合并**（main 恰 1 条 · 无 `wip()` · 分支已删）
- 版本 / Tag：**v0.17.3（PATCH）** —— tag + Release **已发**（发布提交 `4d97f00`）· **AC9 已自证**（`gh release view` name == `v0.17.3`）· **npm 重发 0.17.3（用户执行 · 待核）**（`package.json`/README pin 已升 0.17.3）
- 降级标注：无 Issue · 无预览环境
- 特例提交（白名单）：合并须显式 `--subject "<用户可读主题>" --match-head-commit <完整 40 位 sha>`（T511 教训沿用）

## 上一批（T520 · 已闭环 · 已归档）

- Issue：**无（降级批次）** —— 摘要见 `docs/prds/2026-10-14-doc-templates-convention.md`
- 需求分支：`nao/doc-templates`（base `main` = `5d9d609`；**已 squash 合并并删净**）
- PR owner / Reviewer：rd-infra-T520 / arch-designer-T520（结构契约评审 `done(full)` · 待拍板 D1–D3 **全采纳**）
- PR：[#38](https://github.com/Nathan3303/nao-skills/pull/38)（**已 MERGED** · squash `160cc60`）· 预览环境：无
- 合并：**已 squash 合并**（main `160cc60`；main 上本需求**恰 1 条** · 无 `wip()`）· 分支已删：**是**
- 版本 / Tag：**v0.17.2（PATCH）** —— tag + Release **已发**（发布提交 `9833344`）· **`package.json` / README pin 保持 0.17.0**（npm **不重发**，包运行面与 0.17.x 无差异）
- 降级标注：无 Issue · 无预览环境
- 特例提交（白名单）：合并由 rd-infra 执行 —— `gh pr merge 38 --squash --delete-branch --subject "文档模板与格式约定：ADR 结构契约 + 骨架单源 + 索引模板" --match-head-commit 160cc60…`（**完整 40 位**；T511 教训沿用）

## 活约束与遗留跟踪（长期有效 · 不下沉）

- 待用户裁量的后续项（均不阻塞、**未开单**）：① **O1** nao-todo `AGENTS.md:131` 仍把 `.nao-migrated` 列为「0.12.0 起入库面」→ 收敛 ② **B8** `close` 同名跨仓不可定向（工具侧可叠加名册 cwd / `pane_current_path` 约束；使用纪律 = 仓级唯一任务号）③ **D6** `failWarn` 文案措辞（PRD §8.1）④ **B1** legacy 目录名判定过宽（`--dry-run` / 内容白名单）⑤ 三仓 `.agents/.nao-version` 仍 `0.12.0`（0.13.0 无读取方，版本权威 = pin）⑥ **T512-①** `status`/`close` 排除/识别 `subagent-*`（父子 pane 串扰隐患，与 T511-B8 同类；脚本类需回归）⑦ **T512-②** nao 版 `intercomBridge.instructionFile` + 协议补「会话内子代理」条款（自动桥在当前装机**整条死**，仅显式路径可用）⑧ **T512-③** 角色→pi-subagents agent 薄壳（缓，有 `--append-system-prompt` 替代）⑨ **T512 附录** pi-subagents 引入目标流程 A/B（**已登记 · 未立项 · 未落地**；报告附录 105 行）⑩ **宿主检测 ⇒ 已交付（T513 / 0.14.0，见上）**；原问题：`detect_host` 不识别 foot / Hyprland；用户 2026-10-12 拍 **D1–D5**（D1 默认开可见窗口 · D2 非 tmux 宿主 close 支持 / status turn 判定明确降级 · D3 tmux 内仍优先 · D4 无图形会话必须显式 `--background` 否则 exit 2 · **D5 tmux 可用但当前不在 tmux 时可用 tmux，但必须前台可见、禁静默后台会话**）。**D5 使阶梯③保留完整 tmux 句柄 ⇒ 回归面大幅缩小**。P3/P4 已实测（127 裸中断 / rc0 假成功）。PRD：`docs/prds/2026-10-12-non-tmux-host-spawn.md`。⑪ ✅ **npm 发布已执行（2026-10-13）**：只发 `0.16.0`（`latest → 0.16.0`，不补发 0.12.1–0.15.0）· 用户执行 · 已验 tarball sha512 与 dist.integrity 一致。
- 既定口径（长期有效）：**README 视角 = 纯舰队机制，不写具体上下游应用信息（应用仓名/迁移操作细节不入 README；用户 2026-10-13 拍板，已删除「下游仓库迁移」节并中和泛化措辞）**；迁移命令从**仓外**执行；`.pi/settings.json` pin 入库；`.agents/.nao-obsolete/` 加 gitignore；迁移判据 = 机制类归零 + 自有资产保留；历史归档文档不改；不碰源码/测试/构建配置
- **PM 交互约定（用户 2026-10-14 拍板，长期有效）**：**需要用户确认 / 拍板的问题一律用 `ask-me` 提问**（不用自由文本提问）；本约定写入项目 `AGENTS.md` 项目约束（T518 范围内）。
- ⚠️ **合并纪律（T511 教训，已落 `.agents/skills/github-flow.md`）**：PR 只有 1 条提交时 `gh pr merge --squash` 取**该提交 subject**（非 PR 标题）⇒ **必须显式 `--subject "<用户可读主题>"`**，否则 `wip()` 进主干
- ⚠️ **同仓协作纪律**：nao-skills 本仓工作（如 T509/T510）——RD 持有分支期间 PM 不做本仓 git 写操作；台账提交只在「派发前」「合并后」两个时点
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析已修（0.12.1）· `ensure` 会真拉 pane，未信任目录会停在 pi Trust 提示（D7）· `close` 以 intercom 名册为权威在线判定 · `status` 残留识别要求表格内**裸批次号**单元格
- ⚠️ **本仓 remote（2026-10-13 起）**：origin 已改 **HTTPS**（`https://github.com/Nathan3303/nao-skills.git`）——SSH :22 banner 超时持续，HTTPS push 已验证可用（凭据走全局 `credential.https://github.com.helper` = `gh auth git-credential`）。若后续 SSH 恢复可由用户改回
- ⚠️ **npm 发布教训（v0.16.1 首次 + v0.16.2 首次均中招，同型）**：`npm publish` 若 `~/.npmrc` 的 `_authToken` 无发布权限 ⇒ `PUT 401` → CLI 转浏览器 web auth → **`PUT 202` + `exit 0` + "being processed" = 假成功**，registry 永远无该版本。**成功判据 = 输出出现 `+ @nathan33/nao-skill@<ver>`**（或几秒后 `npm view ... dist-tags` 已是新版）；修复 = `npm login` 重授权 **或** 换含 Publish 权限的 Granular Access Token（必要时勾 bypass 2FA）。
- 📌 **台账写法约定（T519 订正）**：`status` 残留识别按**单元格全等**匹配 ⇒ 进行中行须有**裸批次号**单元格（如 `T508`）；带后缀单元格（`T508-QA`/`T508-RD`）实测判 **`absent`**（非「仅散文提及」）。
- **通用既定口径（T506 · 留档见 `docs/tasks-archive.md` §9）**：`.pi/*` + `!.pi/settings.json`；迁移判据 = 机制类归零 + 自有资产保留；旧脚本调用改 `$NAO_SKILLS/…`。

### 上游遗留单（**已收敛** · 2026-10-14 刷新）

- **#19 / #21 已闭环**：分别由 **T509（v0.12.1）/ T510（v0.13.0）** 交付，原「待用户确认开工」状态作废（原文见 `docs/tasks-archive.md` §1）。
- 原候选「`close` 跨仓派生会话回收宿主定位假阴性（报「未运行」但 pane 存活）」→ 与「待用户裁量的后续项」**② B8** 重复，已合并登记、不再单列。
- 结论：**当前无待开工的上游遗留单**。

## 待派发队列

| 任务编号 | 目标会话 | 概要 | 排队原因 |
| :--- | :--- | :--- | :--- |

## 进行中

| 任务编号 | 目标会话 | 概要 | 派发时间 | 对应 AC | WIP 提交 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T521 | rd-infra-T521 | 4 文件落地（权威单处标题条款 + 两处引用改 `--title "vX.Y.Z"` + PM 卡 v24→v25 + 模板注释）+ 探针脚本 | 2026-10-14 | AC2–AC7 | — |

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |

## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |

## 已验收 / 已归档

| 任务编号 | 结论 | 详情路径 | 备注 |
| :--- | :--- | :--- | :--- |
| **T521** | **验收通过 · 已合并归档**（v0.17.3）：Release 标题口径 = 裸 `vX.Y.Z` —— 权威单处 `release-notes.md` §一.5 + §四清单 + §五红线 · 两处引用收敛（`github-flow.md:56` / PM 卡 :121）并指回单处 · PM 卡 **v24→v25** · 模板注释 1 行（6 分段标题未动）· 一次性只读探针 `PASS=28 FAIL=0` + 负控 2/2 · `check` rc0 roles=6 files=46 + `npm test` rc0 · QA 独立复跑 **GO** · PR [#39](https://github.com/Nathan3303/nao-skills/pull/39) squash `eff44ec`（main 恰 1 条 · 无 `wip()` · 分支删净）· **tag `v0.17.3` + Release 已发**（发布提交 `4d97f00` · **AC9 自证：标题严格 = `v0.17.3`**）· **npm 重发 0.17.3（用户执行 · 待核）** | PR [#39](https://github.com/Nathan3303/nao-skills/pull/39) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-release-title-bare-version.md` · 探针 `docs/reports/2026-10-14-T521-release-title-probe.sh` | 裁定：AC6 偏差**采纳**（探针自身除外 + raw 回显）· AC7 **(a)** 不动范围 · N1 探针一次性（含行号/`files` 计数 ⇒ 勿作长期门禁）· N2 `npm test` 未含 `tests/t4/`（另批）· Reviewer 无法指派（无 `qa` 账号）结论走 intercom · `card pm v25` 广播：本仓已发 · 下游三仓待唤醒补发 |
| **T521-接缝** | **接缝确认（2026-10-14 · QA `done(full)`）**：候选够用、接缝数不增；**改定 1 处**（补 `npm test` = 项目全范围门禁）+ **补 3 条断言**（AC3 反删除 / AC4 补 `updated` / AC5 补分段标题）· AC7 二选一 → **PM 裁定 (a)**（不动范围，观测点改 `github-flow.md:71` 防回归） | `docs/prds/2026-10-14-release-title-bare-version.md` §七 | 只读复核，未改文件 · QA 二次验证按改定接缝执行 |
| **T520** | **验收通过 · 已合并归档**（v0.17.2）：ADR 文档契约（骨架单源 + 职责下沉 + 索引模板）—— 必写 5 节 + 可选 3 节（参考来源恒末）· 头部恰 4 字段 · 状态值域 4 值 · 禁写/下沉清单 → `docs/reports/<编号>-arch-review.md` · 60 行上限保留（仅新增件断言）· 9 文件（2 新增模板 + 3 机制文件 + 索引 + 首实例 ADR + 评审报告 + 探针）· **QA 独立只读探针 `PASS=53 FAIL=0`**（`--fast` 46/0/4）· 负控 2/2（禁词注入 / 节序打乱均 FAIL）· `check` rc0 roles=6 **files 44→46** · `npm test` rc0 · t4 12/12 · squash `160cc60`（main 恰 1 条 · 无 `wip()` · 分支删净）· **tag `v0.17.2` + Release 已发**（发布提交 `9833344` · npm 不重发） | PR [#38](https://github.com/Nathan3303/nao-skills/pull/38) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-doc-templates-convention.md` · 首实例 ADR `docs/adr/2026-10-14-adr-structure-contract.md` · 探针 `docs/reports/2026-10-14-T520-doc-contract-probe.sh` | 角色卡 `arch-designer` **v11→v12**（广播已发本仓；下游三仓待补发）· 历史 7 篇 ADR 零改动（不追溯）· 边界：`check` 的 `files` 只统计 `.agents/**`；探针一次性不入 `tests/` |
> 更早批次（T519 及以前）见 `docs/tasks-archive.md`。
