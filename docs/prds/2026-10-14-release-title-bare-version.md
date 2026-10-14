# PRD：GitHub Release 标题口径（裸版本号，去描述性文本）

- 状态：**已交付并发布（v0.17.3）** · Owner：PM · 更新：2026-10-14
- 指针：上游 = 用户 2026-10-14 指示（「修改 Github 发布模板，标题不要带有描述性文本，仅 vxx.xx.xx」）+ 同轮 ask-me 拍板（范围 = 只改约定不回改历史 · 方式 = 降级批次走 GitHub Flow · D1 = 重发 npm 0.17.3）· 成熟度判定 = 命中 §一.4「用户明示可直接成稿」· **QA 接缝复核** = 2026-10-14 `done(full)`（改定 1 + 补 3 断言 + AC7 裁定 (a)）
- 优先级：中（发布口径固化 · 低成本高杠杆）· 战略筛子：命中「机制一致性」→ 做 · MoSCoW：Should · Kano：期望型质量属性 · RICE ≈13.5（附录）

## TL;DR（≤5 行）

- **做什么**：把「GitHub Release 标题」口径固化为**裸版本号 `vX.Y.Z`**，权威单处 = `.agents/common/release-notes.md`；收敛 2 处引用 + 1 个模板注释，PM 卡 bump v25。
- **给谁**：PM（发版执行）、下游三仓（同口径发版）、最终用户（列表页只看版本号，描述进正文）。
- **成功标准**：机制内「用户可读标题」类指引命中数 = **0**；权威单处含标题条款；`check` rc=0；探针全绿。
- **不做什么**：不回改 13 个既有 Release 标题；不改 release notes 正文规范；不动 tag；不加脚本强校验。

## 一、问题证据

- 实测 `gh release list`（本轮）：15 个 Release 中 **13 个标题含描述性文本**（如 `v0.17.2 — 文档模板与格式约定：ADR 结构契约 + 骨架单源 + 索引模板`），仅 `v0.14.0` / `v0.11.0` 为裸版本号 ⇒ **口径漂移、无权威定义**。
- 5 Whys：标题冗长不统一 ← 无任何文件定义标题写法 ← `release-notes.md` 只规范**正文** ← 发版步骤里 `--title "<用户可读标题>"` 成了唯一指引 ← 该占位语是「正文面向用户可读」规则的**类推外溢**，越权充当标题规则。
- 可观察代价：Release 列表 / `gh release list` 宽度溢出；同一仓分隔符都不统一（`v0.17.1 · …` vs `v0.17.2 — …`），版本号与标题难机械比对。
- 证据留痕：`gh release list` 输出（本轮）；`.agents/prompts/product-manager.md:121`；`.agents/skills/github-flow.md:56`。

## 二、目标指标

- 北极星：**发版标题零自由度** —— 机械可核验（匹配 `^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$`）。
- 预期：新发 Release 标题 100% 匹配该正则；机制内旧占位语出现次数 = 0。
- 观测：探针 `PASS/FAIL` 计数 + `grep -rn` 命中数 = 0 + `check` rc。

## 三、范围 / 非范围

- **范围**
  1. `.agents/common/release-notes.md`（**权威单处**）：§一 增硬约束「Release 标题 = 裸 `vX.Y.Z`（仅版本号；一句话概括进正文首段）」；§四 核对清单 + §五 红线 各增对应一条。
  2. `.agents/skills/github-flow.md:56`（发布步骤）：`--title "<用户可读标题>"` → `--title "vX.Y.Z"`，并指回权威单处。
  3. `.agents/prompts/product-manager.md`（§十三 发布 bullet）：同改；**bump `version` 24→25 + `updated`**（角色卡纪律），广播 `card pm v25`。
  4. `.agents/templates/release-notes.md.example`（头部注释）：加一行「Release 标题 = 裸 `vX.Y.Z`，描述进正文」。
- **非范围**（各带理由）
  - 不回改既有 13 个 Release 标题：理由 用户本轮拍板「只改约定，未来生效」+ 不追溯改写历史。
  - 不加脚本强校验（探针仅本批一次性验证，不入 `tests/`）：理由 纯文本约定无运行面，加校验需动工具面并带回归，另批（同 T520 边界）。
  - 不改 release notes **正文**规范：理由 本轮只动标题；正文口径稳定，不扩大改动面。
  - 不动已 push 的 tag / Release 正文 / `docs/releases/*.md` 历史落盘：理由 已 push tag 不删 + 历史归档文档不改。

## 四、用户场景

- 画像 A（PM 发版）：`gh release create v0.17.3 --title "v0.17.3" --notes-file docs/releases/v0.17.3.md` —— 标题无需构思，描述由正文承载。
- 画像 B（下游三仓 PM）：三仓发版照同一形态，跨仓 Release 列表可直接比对版本。
- 画像 C（最终用户）：Release 列表 / 通知只见版本号，点进去首段即「本次更新」一句话。

## 五、业务规则

- **BR1 标题形态**：`v<MAJOR>.<MINOR>.<PATCH>`，可带预发布后缀（如 `-beta.1`）；除版本号外无任何字符。
- **BR2 标题不含**：描述性短语、`—` / `·` / `：` 分隔的副题、任务编号、issue 号、日期。
- **BR3 描述归属**：描述性内容一律进正文**最前**「本次更新」段（正文规范不变）。
- **BR4 降级（无 `gh`）**：`git tag -a vX.Y.Z` —— tag 名本就裸版本号，口径天然一致；notes 落 `docs/releases/`。
- **BR5 权威单处**：标题规则只写 `common/release-notes.md`；`github-flow.md` / 角色卡 / 模板只给指针或示例，不复制正文。
- **BR6 适用面**：本仓 + 下游三仓（规则写在通用文件，非仓库专属）。
- **BR7 冲突消解**：被改文件的行内表述若与权威单处冲突，以权威单处为准（worker 须对齐后交付）。

## 六、NFRs

- 不适用：纯文档口径变更，无性能 / 容量 / 兼容性业务基线。
- 沿用既有文档 NFR：中文写作 + 正文不用表格（`deliverable-docs.md` §三 default-no-table）。

## 七、AC

- 验证接缝（**QA 已确认 2026-10-14**）：`bash .agents/scripts/nao-fleet.sh check` rc=0 **+ `npm test` rc=0**（项目全范围门禁）**+** 一次性只读探针 `docs/reports/2026-10-14-T521-release-title-probe.sh`。
  - QA 复核结论：接缝数不增（仍 1 个新建探针接缝 + 复用项目门禁）；**改定 1 处** = 候选漏了 `npm test`（4 个被改文件全在 `.agents/` 机制面，按项目红线必须全范围门禁）。
- **AC1（主路径 · 接缝）**：Given 舰队就绪，When QA 复核接缝候选，Then 确认或改定更高接缝并记录日期 —— **已完成 2026-10-14**（QA `done(full)`：改定 1 处 + 补 3 断言 + AC7 二选一由 PM 裁定）。
- **AC2（主路径 · 权威单处）**：Given `common/release-notes.md`，When 读 §一，Then 硬约束含「标题 = 裸 `vX.Y.Z`」且明示描述归属正文首段。
- **AC3（设计一致性 · 引用收敛 + 反删除）**：Given 全 `.agents/` 目录，When `grep -rn '用户可读标题'`，Then 命中数 = 0；**且** `skills/github-flow.md`、`prompts/product-manager.md` 两文件**仍存在且各含 `--title "vX.Y.Z"`（各 1 处）** + 指回权威单处（防「删文件达成 0 命中」的假通过）。
- **AC4（角色卡纪律）**：Given `product-manager.md`，When 读 frontmatter，Then `version: 25` **且 `updated: 2026-10-14`**（两项均断）；且全范围门禁 rc=0（`check` roles=6）。
- **AC5（边界 · 模板）**：Given `release-notes.md.example` 头部注释，When 读，Then 含标题口径一行；**且**模板原分段标题（`# 本次更新` / `## ✨ 更好用了` / `## 🐛 修好了` / `## ⚠️ 请留意` / `## 技术细节`）仍在（才等于「分段结构未被破坏」）。
- **AC6（负向闭环 · 不误伤）**：Given 探针负控，When 注入旧占位语副本，Then 断言 FAIL；When 核正文规范关键词（「本次更新」/「技术细节」），Then 仍存在。**负控须在 `mktemp -d` 临时副本上跑（不得改工作区），探针收尾断言 `git status --short` 为空。**
- **AC7（异常 · 降级路径）**：**PM 裁定 (a)（不动范围）** —— Given 既有降级口径，When 核 `skills/github-flow.md:71` 降级表行，Then 该行**仍在**（回归保护）+ 全 `.agents/` 未新增对 `gh` 的硬依赖表述（探针加 1 条断言）；权威单处 `release-notes.md` 本批**不**新增 `git tag -a` 行。
- **AC8（一致性闸门）**：Given PRD 接缝与 QA 用例范围，When 比对，Then 一致；不一致则 PM 验收打回。
- **AC9（发布自证 · 首个实证）**：✅ **已自证（2026-10-14）** —— `gh release view v0.17.3` 的 `name` 严格等于 `v0.17.3`（`gh release list` 首行亦为 `v0.17.3`）。**不属预合入接缝**：发版后由 PM 人工读取核验，探针不覆盖（QA 照实说明）。

## 八、上线闭环

- **版本**：v0.17.3（PATCH · 机制文档口径）。
- **回滚**：约定类改动，回滚 = 文本改回并发下一 PATCH；已 push tag 不删。
- **npm 重发：已拍板（用户 2026-10-14）= 重发 `0.17.3`** —— 理由 `package.json files` 含 `.agents/`，**本批唯一产出即包内文本**（与 T519/T520 先例不同）；`npm publish` 由**用户执行**，成功判据 = **直连 registry 实测**（`dist-tags.latest` 已是 0.17.3 + `dist.integrity` 与本地 `npm pack` tarball 逐字节一致；`PUT 202` 不作判据）。
- **监控**：无（纯文本）。

## 九、变更治理

- **流程**：降级批次 `nao/release-title-bare`（无 Issue）→ PR → QA 只读验证 → PM 验收 → RD squash 合并 → PM 发 tag/Release → PRD 归档。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-release-title-bare-version.md`（✅ 已归档并登记索引）；运行时状态记 `docs/tasks-state.md`（T521 已入「已验收 / 已归档」，T519 已下沉 `docs/tasks-archive.md` §7）。
- **交付记录**：PR [#39](https://github.com/Nathan3303/nao-skills/pull/39) squash 合并 `eff44ec`（main 恰 1 条 · 无 `wip()` · 分支删净）· 发布提交 `4d97f00` · tag `v0.17.3` + Release 已发（**标题 = `v0.17.3`**）· `package.json`/README pin 已升 0.17.3 · **npm 0.17.3 重发待用户执行**（成功判据 = registry 实测）。
- **角色卡广播**：`card pm v25` 本仓已发（2026-10-14）+ 下游三仓唤醒后补发（原待补发的 v24 项顺延合并为 **v25**）。

## 附：RICE 与依据

- Reach 3（本仓 + 下游三仓发版面）· Impact 2（口径统一，用户侧可见）· Confidence 0.9（改动小、可机械核验）· Effort 0.4（4 文件文本 + 1 探针）⇒ **RICE ≈ 13.5**。
- 战略筛子：命中「机制单一事实 + 低成本高杠杆」→ 本批做；不进非范围（不受阻）。
