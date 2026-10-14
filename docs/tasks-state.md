# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 历史见 `docs/tasks-archive.md`；权威来源 = `docs/prds/` 与 `docs/releases/`；本文件只记**运行时**状态，保持精简。
> 归档动作 = 从「进行中」**删除** + 归档墙**新增**（同一 id 同时出现在两处会因 `arch` 优先被判 **`closed`**，`close` 闸门保护静默消失）。

## PM 接续快照（会话重开后**先读本区**）

> 本区是 PM 的**悬空状态**（任务状态见下方五栏）；重开后逐行回读确认（当前阶段 · 未决决策 · 口头约束）。

- ✅ **T524 交付闭环（2026-10-14 · 待发布 v0.18.2 · 含 npm 重发）**：⑯ `nao-fleet.sh:1676` **删净**与实现不符的「或用 `--force` 跳过闸门」子句（用例 13 加**双向断言**：负 = 输出不含 `--force`、正 = 仍含「人工核对」；变异 M1/M2 各恰 2 条 FAIL）；⑮ t4 夹具缓存**自洽生命周期**（`lib.sh` 单点 `t4_cache_cleanup` + `EXIT` trap：成功即清 / rc≠0 保留 + 打印路径 / 用户传入永不删 / `T4_KEEP_CACHE=1` 逃生口 / 只读命令不建目录 / `mktemp` 失败非 0；OWNED 不导出 + 前缀/软链/单层守卫），新增 `cases/14`（27 条断言，含 ⑲⑳ 单点与破坏面静态断言），存量 `/tmp/nao-t4.*` **129 → 0**。**验收 = 通过（AC1–AC8 全过）**：QA 独立复跑 **GO（终）**（`check` rc=0 roles=6 files=46 · `npm test` rc=0 · 14/14 PASS · **断言 282→313** · SKIP/DEGRADE=0 · 空载 `test:t4:full` rc=0）· ⑮ 25+ 条独立探针全过 · PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) squash **`e83ced2`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 报告 79 行 · **tag/Release 待发 + npm 重发待用户执行**。
- 🔄 **T524 批次开工（2026-10-14 · 台账待裁量项 ⑯+⑮ 合并小批）**：用户选定 **⑯**（`nao-fleet.sh:1676` warn 文案与实现不符 —— 该分支不消费 `--force`）+ **⑮**（`/tmp/nao-t4.*` 夹具累积 129 个 · 无 trap 收尾 · 只读命令也建目录 · `mktemp` 失败空值续跑）。已过三关：PRD `docs/prds/2026-10-14-cache-warn-cleanup.md`（待派发）· QA 接缝 `done(full)`（⑯ 采 C1 扩 `cases/13` 双向断言 + **删净** `--force` 子句 · ⑮ 采 S1 = `lib.sh` 单点 `t4_cache_cleanup` + `EXIT` trap + mode 感知 + **env-only** `T4_KEEP_CACHE=1` + 三态打印 · 新增 `cases/14`（≥12 条 hermetic 断言）· 存量 **X2** 一次性清理 · **两项均不需 arch**）· 开工卡 **D1–D5 全拍板**（按 QA 定稿 / **发布时重发 npm 0.18.2** / v0.18.2 / 降级 `nao/cache-warn-cleanup` / X2）。**在飞** = rd-infra-T524 落地中。
- ✅ **T523 交付闭环（2026-10-14 · v0.18.1 已发布）**：`close` 末段「无法确认在线状态」补回归护栏 —— 新增 `tests/t4/cases/13-close-guards.sh`（6 组 15 条**双侧断言**：不可验证 ⇒ 非静默失败·真离线 ⇒ 静默 rc=0·判据三子句正负·`--force` 现状锁定；③ 查 **stderr** 防恒假断言；夹具用派生名防命中调用者自身）+ `run.sh` 注册 `"13"` / usage `<01-13>` + `tests/README.md` 用例行 + `docs/releases/v0.18.1.md`。**验收 = 通过（AC1–AC8 全过）**：QA 独立复跑 **GO**（`check` rc=0 roles=6 files=46 · `npm test` rc=0 · 91.8s · **13/13 PASS** · SKIP=0/DEGRADE=0/NOTE=3 · **断言 267→282**）· 三变异 MUT-C/D/E 均被拦且还原 md5 一致 · BR2 注册负控（摘掉 `"13"` ⇒ 12 用例）· 机制脚本**一字未改** · PR [#41](https://github.com/Nathan3303/nao-skills/pull/41) squash **`ef391af`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 报告 66 行 · **tag + Release 已发**（发布提交 `292b3f4` · **AC9 自证：`gh release view` name = `v0.18.1`**）· npm **不重发** · 发布前置闸门 rc=0（空载 1m59s · SKIP=0/DEGRADE=0）。
- 🔄 **T523 批次开工（2026-10-14 · 台账待裁量项 ⑭）**：用户选定 ⑭（`close` 末段「无法确认在线状态」缺口补护栏 · 小批）。已过三关：PRD `docs/prds/2026-10-14-close-guard-coverage.md`（待派发）· QA 接缝 `done(full)`（采 C2 新增 `cases/13` + **补 `run.sh` 注册三行** + 6 条双侧断言（③ 查 stderr）· 夹具须派生名 `--task <唯一号>` · `--force` 预期按实测订正）· 开工卡 **D1–D5 全拍板**（按 QA 定稿 / ⑯ 另批 / v0.18.1 / 降级 `nao/close-guard` / 跳过 arch）。**QA 已实测三变异**：MUT-C（`if true` → ①②③ FAIL）· MUT-D（`if false` → ④ FAIL）· MUT-E（删 `NAO_TERMINAL` 子句 → ⑤ FAIL）。**在飞** = rd-infra-T523 落地中。
- ✅ **T522 交付闭环（2026-10-14 · v0.18.0 已发布）**：`tests/t4`（12 例）接入唯一机械门禁 —— `test:agents` + `test:t4` · 发布前置 `test:t4:full`（两轴：缺产物 + 能力）· 封三类静默假绿 + 第三类收尾契约 · case 02/07 网络面极性（BR10）· `prepack` 与重套件解耦。**验收 = 通过（AC1–AC9 全过）**：QA 独立复跑 **GO**（`check` rc=0 roles=6 files=46 · `npm test` rc=0 · 12 例 · **PASS 266 / FAIL 0 / SKIP 0 / DEGRADE 1 / NOTE 2** · full 本机 rc=1 期望语义 / 能力齐备 267+rc=0）· PR [#40](https://github.com/Nathan3303/nao-skills/pull/40) squash **`e8a495b`**（main 恰 1 条 · 无 `wip()` · 分支删净）· ADR 55 行 + arch 报告 56 行 + QA 报告 69 行 · **tag + Release 已发**（发布提交 `1600450` · **AC9 自证：`gh release view` name = `v0.18.0`**）· **发布前置 `test:t4:full` rc=0**（用户安装 `strace` 后 PM 实测 · PASS 267 / FAIL 0 / SKIP 0 / DEGRADE 0 / NOTE 2）· npm **不重发**（用户拍板 2026-10-14）。：三关已过（PRD → QA 接缝 → 开工卡）后，arch 结构评审 `done(full)`：**有条件可行**（采纳 `test` 全量串联 / `prepack`=`test:agents` / 默认严格 / v0.18.0 / npm 不重发 / 需补 ADR）+ **P1–P6 已落 PRD 定稿**（网络面极性 · full 判据 SKIP 计数 = 0 · 三类参数错误 · 发布锚点 → `github-flow.md` 阶段 7 · 断言基线 ≥265 · 版本漂移）。**用户二轮拍板 5 项（ask-me）**：D1 修极性 · D2 范围微扩全批准 · D3 授权 arch 落盘 ADR+报告 · D4 npm 默认不重发 · D5 网络中断下继续推进本地实现。**已实测环境**：`github.com:443` / `codeload.github.com:443` 超时（`api.github.com` 通 · registry 200）⇒ `git push` rc=124，台账提交 `554e4aa` 仅本地（origin 未推）；分支 push/PR/合并/发布恢复后补（github-flow 离线降级可用）。
- 🔄 **T522 批次开工（2026-10-14 · 晚于下条交接）**：新 PM `01a13817`（pane %31）已按重开纪律回读确认 3 行（ask-me · 用户「确认无误，进入待命」+「是，按此推进」）；旧 pm `01a137a8`（%26）已自收窗。**本批 = `tests/t4` 接入 `npm test` 门禁**（降级批次 `nao/t4-gate`）· 已过「PRD + QA 接缝确认 + 开工确认卡」三关：PRD `docs/prds/2026-10-14-t4-gate-wiring.md`（待派发）· QA `done(full)`（接缝 = `npm test` rc=0 不增 · 改定 4 处：prepack 剥离 / 默认严格 / full 入口 / 缺陷 A/B 前置）· 开工卡 **D1–D5 全拍板**（全纳入 · 翻转默认 · 降级 · v0.18.0 · 采纳 arch 评审）。**已实测基线**：t4 严格跑 12/12 PASS · 263 PASS / 0 FAIL / 3 NOTE / rc=0（PM+QA 各一次）· 现 `npm test` = check+tsc 2.2s 不含 t4。**在飞** = arch-designer-T522 结构评审中（闸门：评审回执后派 rd-infra）。
- 🔄 **PM 会话重开交接（2026-10-14 · 用户拍板重开 · T521 批次终态 · 含下批需求指针）**：T521 已**全链路闭环**（PRD → QA 接缝确认 → rd-infra 落地 → QA 独立复跑 GO → squash `eff44ec` → tag `v0.17.3` + Release（发布提交 `4d97f00` · 标题自证）→ **npm 0.17.3 重发已核验**（`latest: 0.17.3` + integrity 与本地 tarball 逐字节一致）→ 台账归档 + T519 轮换下沉），**无在飞任务、无未决决策**。**下批需求（用户 2026-10-14 选定 · 未立项）** = 把 `tests/t4` 接入 `npm test` 门禁（解「1874 行 `nao-fleet.sh` 无护栏」· 先小批、脚本拆分另议）。**新 PM 开工前规则**：先读本文件 + `docs/prds/README.md` 索引 → 向用户**回读确认 3 行**（当前阶段 · 未决决策 · 口头约束）→ 确认后方可调度；旧 pm 窗（%26）在本次交接消息发出后自行收窗。
- ✅ **PM 交接收尾（2026-10-14 · 用户拍板重开 · T520 批次终态）**：T520 **全链路闭环**（PRD → arch 结构定稿 → rd-infra 落地 → QA 独立验证 → squash `160cc60` → tag `v0.17.2` + Release（`9833344`）→ 台账归档），**无在飞任务、无未决决策**。新 PM `01a137a8`（pane %26）**已按交接回读确认 3 行**（ask-me · 用户「确认无误，进入待命」），旧 pm `01a13661`（%15）已自收窗，**舰队无派生会话残留**（实测 `list` 仅本会话）。**唯一待办** = 下游三仓（nao-todo / nao-todo-server / nue-ui）PM 会话唤醒后补发广播 `card pm v25`（T518/T521 批累计，原 v24 被 T521 取代）/ `card qa v14`（T518 批遗留）+ `card arch-designer v12`（T520 批）——**触发条件 = 目标会话在线且 `idle`，发前 `list` 核验并留痕**（本仓侧均已发）。
- ✅ **T521 交付闭环（2026-10-14 · v0.17.3）**：GitHub Release 标题口径 = 裸 `vX.Y.Z` —— 权威单处 `common/release-notes.md` §一.5 硬约束 + §四清单 + §五红线 · 两处引用收敛（`github-flow.md:56` / PM 卡 :121）并指回单处 · PM 卡 **v24→v25** · 模板注释 1 行（6 分段标题未动）· 一次性只读探针 `PASS=28 FAIL=0` + 负控 2/2 · QA 独立复跑 **GO** · squash `eff44ec` · tag + Release 已发（发布提交 `4d97f00` · **AC9 自证：标题严格 = `v0.17.3`**）· **npm 重发 0.17.3 已核验**（`latest` + integrity 逐字节）。
- ✅ **T520 交付闭环（2026-10-14 · v0.17.2）**：ADR 文档契约 —— 必写 5 节 + 可选 3 节（参考来源恒末）· 头部恰 4 字段 · 状态值域 4 值 · 禁写/下沉清单 · 新增 `templates/adr.md.example` + `adr-index.md.example` · `arch-designer` 卡 v11→v12 · QA 探针 `PASS=53 FAIL=0` + 负控 2/2 · squash `160cc60` · tag + Release 已发（`9833344`）· **npm 不重发**。

- 当前阶段：**T524 已验收合并（待发布 v0.18.2 + npm 重发）** · PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) squash `e83ced2` · 发布前置闸门已实测 rc=0（空载 · 1m27s）· 下一动作 = 发布（bump 0.18.2 + tag + Release → **用户执行 `npm publish`** → PM 直连 registry 核验）；上批 T523（v0.18.1）已闭环发布
- 当前 PRD：`docs/prds/2026-10-14-cache-warn-cleanup.md`（状态：**已交付并合并（待发布）**）
- 未决决策点：无（D1–D5 已拍板；npm 重发已拍 = 重发 0.18.2）
- 待用户回答：**1 项待你执行** = 发布节点 `npm publish`（token 须有 Publish 权限；成功判据 = 直连 registry 实测）
- 未派发队列：见下方「待派发队列」（共 0 项）
- 下次唤醒条件：**npm 重发核验 / 下批需求授意 / 用户要求重开 PM**；先读本快照 + `docs/prds/README.md` 索引；舰队现状 = PM + rd-infra-T524 + qa-T524（**发布闭环后 `close --task T524` 回收**）
- 口头约束已落盘：项目 `AGENTS.md` 项目约束（ask-me 提问）· PRD §5 BR6 格式禁令 + §9 R5/R6（T519）· ADR 字段口径 = `deliverable-docs.md` §四（T520 · 状态值域 4 值 / 头部 4 字段 / 60 行上限）
- 需求分支 / PR：见下方「需求分支 / PR / 发布」（本批降级分支 `nao/t4-gate`——**已 squash 合并 `e8a495b` 并删净**）
- 会话体检：当前 PM 会话 = `01a13817`（pane %31），T522 全批 ctx 5%→16%（闭批时约 160k/1000k · 无压缩）· 舰队 = 仅 PM（派生已回收） · 本快照为接续唯一事实源（main = `85606e9`）

## 需求分支 / PR / 发布（PM 维护）

### 本批 T524（⑯ 文案订正 + ⑮ 缓存生命周期 · 已合并 · 待发布）

- Issue：**无（降级批次 T524）** —— 摘要见 `docs/prds/2026-10-14-cache-warn-cleanup.md`
- 需求分支：`nao/cache-warn-cleanup`（base `main` = `2edb424`；**已 squash 合并 `e83ced2` 并删净**）
- PR owner / Reviewer：rd-infra / qa（`gh --reviewer` 无 `qa` 账号 ⇒ 结论走 intercom `GO`；无 arch 评审（D5 拍板跳过，理由记 PRD §九））
- PR：[#42](https://github.com/Nathan3303/nao-skills/pull/42)（**已 MERGED** · squash `e83ced2` · 验收评论 issuecomment-6170580515）· 预览环境：无
- 合并：**已 squash 合并**（main 恰 1 条 · 无 `wip()`）
- 版本 / Tag：**v0.18.2（PATCH · 待发）**；**npm 重发已拍板 = 发布时重发**（⑯ 在包内；用户执行 `npm publish`；registry 将由 `0.17.3` 跳 `0.18.2`）
- 降级标注：无 Issue · 无预览环境

### 上一批 T523（`close` 末段在线判定护栏 · 已闭环 · 已归档）

- Issue：**无（降级批次 T523）** —— 摘要见 `docs/prds/2026-10-14-close-guard-coverage.md`
- 需求分支：`nao/close-guard`（base `main` = `736d285`；**已 squash 合并 `ef391af` 并删净**）
- PR owner / Reviewer：rd-infra / qa（`gh --reviewer` 无 `qa` 账号 ⇒ 结论走 intercom `GO`；无 arch 评审（D5 拍板跳过，理由记 PRD §九））
- PR：[#41](https://github.com/Nathan3303/nao-skills/pull/41)（**已 MERGED** · squash `ef391af` · 验收评论 issuecomment-6169313064）· 预览环境：无
- 合并：**已 squash 合并**（main 恰 1 条 · 无 `wip()`）
- 版本 / Tag：**v0.18.1（PATCH）** —— tag + Release **已发**（发布提交 `292b3f4` · **AC9 自证：标题严格 = `v0.18.1`**）；npm **不重发**（`package.json` 运行面不变 · `tests/` 不入包）
- 降级标注：无 Issue · 无预览环境

### 上一批 T522（`tests/t4` 接入 `npm test` 门禁 · 已闭环 · 已归档）

- Issue：**无（降级批次 T522）** —— 摘要见 `docs/prds/2026-10-14-t4-gate-wiring.md`
- 需求分支：`nao/t4-gate`（base `main` = `0ae1355`；**已 squash 合并 `e8a495b` 并删净**）
- PR owner / Reviewer：rd-infra / qa（arch 结构评审闸门已过 · `gh --reviewer` 无 `qa` 账号 ⇒ 结论走 intercom `GO`）
- PR：[#40](https://github.com/Nathan3303/nao-skills/pull/40)（**已 MERGED** · squash `e8a495b` · 验收评论 issuecomment-6160248197）· 预览环境：无
- 合并：**已 squash 合并**（main 恰 1 条 · 无 `wip()` · 12 条批次提交压为 1 条）
- 版本 / Tag：**v0.18.0（MINOR）** —— tag + Release **已发**（发布提交 `1600450` · **AC9 自证：标题严格 = `v0.18.0`**）· npm **不重发**（用户拍板 2026-10-14 · release notes 已写明版本漂移 repo 0.18.0 / registry 0.17.3 · 消费者侧 `npm test` 不适用）· 发布前置 `test:t4:full` **rc=0**（装 `strace` 后 PM 实测：PASS 267 · SKIP 0 · DEGRADE 0 · NOTE 2）
- 降级标注：无 Issue · 无预览环境

### 上一批 T521（已闭环 · 已归档）

- Issue：**无（降级批次 T521）** —— 摘要见 `docs/prds/2026-10-14-release-title-bare-version.md`
- 需求分支：`nao/release-title-bare`（base `main` = `832459d`；**已 squash 合并 `eff44ec` 并删净**）
- PR owner / Reviewer：rd-infra / qa（GitHub 侧无 `qa` 账号 ⇒ `--reviewer` 指派失败，QA 结论走 intercom `GO` 2026-10-14）（独立只读探针 · 开工确认卡落定）
- PR：[#39](https://github.com/Nathan3303/nao-skills/pull/39)（**已 MERGED** · squash `eff44ec`）· 预览环境：无
- 合并：**已 squash 合并**（main 恰 1 条 · 无 `wip()` · 分支已删）
- 版本 / Tag：**v0.17.3（PATCH）** —— tag + Release **已发**（发布提交 `4d97f00`）· **AC9 已自证**（`gh release view` name == `v0.17.3`）· **npm 重发 0.17.3 已核验**（`latest: 0.17.3` · integrity 与本地 tarball 逐字节一致）（`package.json`/README pin 已升 0.17.3）
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

- 待用户裁量的后续项（均不阻塞、**未开单**）：① **O1** nao-todo `AGENTS.md:131` 仍把 `.nao-migrated` 列为「0.12.0 起入库面」→ 收敛 ② **B8** `close` 同名跨仓不可定向（工具侧可叠加名册 cwd / `pane_current_path` 约束；使用纪律 = 仓级唯一任务号）③ **D6** `failWarn` 文案措辞（PRD §8.1）④ **B1** legacy 目录名判定过宽（`--dry-run` / 内容白名单）⑤ 三仓 `.agents/.nao-version` 仍 `0.12.0`（0.13.0 无读取方，版本权威 = pin）⑥ **T512-①** `status`/`close` 排除/识别 `subagent-*`（父子 pane 串扰隐患，与 T511-B8 同类；脚本类需回归）⑦ **T512-②** nao 版 `intercomBridge.instructionFile` + 协议补「会话内子代理」条款（自动桥在当前装机**整条死**，仅显式路径可用）⑧ **T512-③** 角色→pi-subagents agent 薄壳（缓，有 `--append-system-prompt` 替代）⑨ **T512 附录** pi-subagents 引入目标流程 A/B（**已登记 · 未立项 · 未落地**；报告附录 105 行）⑩ **宿主检测 ⇒ 已交付（T513 / 0.14.0，见上）**；原问题：`detect_host` 不识别 foot / Hyprland；用户 2026-10-12 拍 **D1–D5**（D1 默认开可见窗口 · D2 非 tmux 宿主 close 支持 / status turn 判定明确降级 · D3 tmux 内仍优先 · D4 无图形会话必须显式 `--background` 否则 exit 2 · **D5 tmux 可用但当前不在 tmux 时可用 tmux，但必须前台可见、禁静默后台会话**）。**D5 使阶梯③保留完整 tmux 句柄 ⇒ 回归面大幅缩小**。P3/P4 已实测（127 裸中断 / rc0 假成功）。PRD：`docs/prds/2026-10-12-non-tmux-host-spawn.md`。⑪ ✅ **npm 发布已执行（2026-10-13）**：只发 `0.16.0`（`latest → 0.16.0`，不补发 0.12.1–0.15.0）· 用户执行 · 已验 tarball sha512 与 dist.integrity 一致。 ⑫ **`nao-fleet.sh` 体量与职责混装**（实测 1874 行 / 72 函数 / `cmd_check` 单函数 228 行 · 占机制文本 58.6%）—— **「`tests/t4` 未接入 `npm test`」半条已收口（T522 / v0.18.0）**：t4 已串入 `npm test` + 默认严格 + `test:t4:full` 发布前置（见 `docs/releases/v0.18.0.md`）；**脚本拆分/减重半条保留**（仍未立项，待 arch 评审后再议）。**新增待裁量项**：⑭ ✅ **已收口（T523 / v0.18.1）** —— `close` 末段「无法确认在线状态」静默语义已有回归护栏（新增用例 13 · 6 组 15 条双侧断言 · 三变异均被拦）；⑮ ✅ **已收口（T524 / v0.18.2）** —— `/tmp/nao-t4.*` 存量 129 → **0**，且新增自洽生命周期（成功即清 / 失败保留 / 用户目录永不删 / 只读命令不建目录 / `mktemp` 失败非 0）。· ⑯ ✅ **已收口（T524 / v0.18.2）** —— `nao-fleet.sh:1676` 已删净「或用 `--force` 跳过闸门」（用例 13 双向断言钉住）。**观察项 O-1（非缺陷）**：连续跑批可能出现**负载性 SKIP**（用例 02 真 `pi` 启动 rc=124 超时 · 用例 07 registry 不可达；该次 rc=0 · 用例 13 仍 PASS，空载单独复跑均 PASS）⇒ **发布判据须空载跑 `npm run test:t4:full``。 ⑬ ✅ **npm 0.17.3 重发已核验（2026-10-14 · 用户执行）**：`dist-tags.latest = 0.17.3` + `dist.integrity` 与本地 `npm pack` tarball 逐字节一致（`sha512-xKitNAZbPhphS+…`）。
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

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |

## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |

## 已验收 / 已归档

| 任务编号 | 结论 | 详情路径 | 备注 |
| :--- | :--- | :--- | :--- |
| **T524** | **验收通过（AC1–AC8 全过）· 已 squash 合并 `e83ced2` · 待发布 v0.18.2（含 npm 重发）**：⑯ 删净 `nao-fleet.sh:1676` 的 `--force` 误导子句 + 用例 13 双向断言（M1 回填 ⇒ 恰 2 条负向 FAIL；M2 删整条 warn ⇒ 恰 2 条正向 FAIL）；⑮ t4 夹具缓存自洽生命周期（`lib.sh` 单点 `t4_cache_cleanup` + `EXIT` trap：成功即清 / rc≠0 保留 + 三态打印 / 用户传入永不删 / `T4_KEEP_CACHE=1` / 只读命令不建目录 / `mktemp` 失败非 0；OWNED 不导出 + 前缀·软链·单层守卫）+ `cases/14`（27 条断言含 ⑲⑳ 单点与破坏面静态断言）+ `cases/09` 串行 cleanup + `tests/README.md` · **存量 `/tmp/nao-t4.*` 129 → 0**。**QA 独立复跑 GO（终）**：`check` rc=0（roles=6 · files=46）· `npm test` rc=0 · 106.7s · **14/14 PASS · 断言 282→313** · SKIP=0/DEGRADE=0/NOTE=3 · 空载 `test:t4:full` rc=0 · ⑮ 25+ 探针（OWNED 导出洞/前缀/软链/并发不互伤/rc 保真/早退净增 0/`mktemp` 失败/`rm` 失败只 warn）全过 · BR10 负控（去串联行恰泄漏 1 个）· AC3 注册负控。**交付**：PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) squash `e83ced2`（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 报告 `docs/reports/2026-10-14-T524-qa-verify.md`（79 行）· 无 ADR（D5 拍板跳过 arch）。**待办** = 发布（bump 0.18.2 + tag + Release · **用户执行 `npm publish`** · PM 直连 registry 核验）+ 派生会话回收。**残差**：R-4（`function` 前缀匹配只会误红，非阻塞）· O-1（发布判据须空载）· D-1（PRD 措辞按实现订正，已在合并后落 main）。 | PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-cache-warn-cleanup.md` · QA 报告见备注 | 发布前置 `npm run test:t4:full` ✅ rc=0（空载 1m27s · SKIP=0/DEGRADE=0）· **npm 重发**：用户 `npm publish` → 判据 = `dist-tags.latest` + `dist.integrity` 与本地 tarball 逐字节一致 · 派生会话 `close --task T524` 于发布闭环后执行 |
| **T523** | **验收通过（AC1–AC8 全过）· 已 squash 合并 `ef391af` · 已发布 v0.18.1**：新增 `tests/t4/cases/13-close-guards.sh`（**6 组共 15 条双侧断言**）—— `close` 末段「无法确认在线状态」不得静默谎报「未运行（无需回收）」；③ 查 **stderr**（BR4：warn 走 stderr，查 stdout 会得到恒假断言）；判据三子句各一条（`NAO_TERMINAL=tmux` 正 / `foot` 负 / `$TMUX` 正，另实测 `screen` 正 · `ghostty`/`ptyxis` 负）；`--force` 现状锁定；HERmetic 夹具用派生名（禁裸 `close qa` —— 会命中测试进程自身 pane）。`run.sh` 注册 `"13"` + usage `<01-13>`。**QA 独立复跑 GO**：`check` rc=0（roles=6 · files=46）· `npm test` rc=0 · 91.8s · **13/13 PASS** · SKIP=0/DEGRADE=0/NOTE=3 · **断言 267→282** · 三变异 MUT-C（`if true` ⇒ 恰用例 13 FAIL 8 条 · ④ 仍绿）/ MUT-D（`if false` ⇒ 用例 13 FAIL 6 条 + 用例 09 FAIL 10 条）/ MUT-E（删 `NAO_TERMINAL` 子句 ⇒ 恰 ⑤a FAIL 2 条）均即时还原 + md5 一致 · BR2 注册负控（摘掉 `"13"` ⇒ 12 用例 · 断言回 267）· 机制脚本**一字未改**。**交付**：PR [#41](https://github.com/Nathan3303/nao-skills/pull/41) squash `ef391af`（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 报告 `docs/reports/2026-10-14-T523-qa-verify.md`（66 行）· 无 ADR（D5 拍板跳过 arch）。**待办** = 发布 ✅（tag `v0.18.1` + Release 已发 · 发布提交 `292b3f4`）· 派生会话回收。**残差**：⑯ `:1676` 文案与实现不符（另批）· O-1 负载偶发 SKIP（发布判据须空载）。 | PR [#41](https://github.com/Nathan3303/nao-skills/pull/41) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-close-guard-coverage.md` · QA 报告见备注 | 发布前置 `npm run test:t4:full` ✅ rc=0（空载 · 1m59s · SKIP=0/DEGRADE=0）· 派生会话 `close --task T523` 于发布闭环后执行 |
| **T522** | **验收通过（AC1–AC9 全过）· 已 squash 合并 `e8a495b` · 已发布 v0.18.0**：`tests/t4`（12 例）接入唯一机械门禁 —— `test:agents` + `test:t4` · 发布前置 `test:t4:full`（两轴 = `T4_ALLOW_MISSING=0` 缺产物 + `T4_REQUIRE_FULL=1` 能力；判据 = **SKIP+DEGRADE=0**）· 封三类静默假绿（`MISSING`/`NOT_RUN`/未知态 + 三类参数错误）+ 第三类收尾契约（用例须 `t4_exit`/`t4_skip`/`exec` 收尾）· case 02/07 网络面极性（BR10：不可达⇒SKIP；真输出不符⇒FAIL）· `prepack` 与重套件解耦（保持 ≈3s）· 新增 `t4_degrade`（可计分、不终止）。**QA 独立复跑 GO**：`check` rc=0（roles=6 · files=46）· `npm test` rc=0 · 101s · 12 例 · **PASS 266 / FAIL 0 / SKIP 0 / DEGRADE 1 / NOTE 2**（本机缺 `strace`）· full 本机 rc=1（期望语义）/ 能力齐备桩 rc=0 · PASS 267 · 负控 N1（移走 `run.sh` ⇒ rc=127）/ N2-b（shim 注入 ⇒ 用例 03 FAIL）/ N2-c（机制脚本注入 ⇒ 用例 11 FAIL）/ N3（prepack 无 t4 行 · pi 0 次）/ N4 / N5 / C1–C5 / X1–X4 全过 · 断言口径 = 删 1 条空心（`cases/07`）+ 新增 4 条（`cases/06`）。**交付**：PR [#40](https://github.com/Nathan3303/nao-skills/pull/40) squash `e8a495b`（main 恰 1 条 · 无 `wip()` · 分支删净）· 验收评论 issuecomment-6160248197 · ADR `docs/adr/2026-10-14-npm-test-gate-scope.md`（55 行）+ ADR 索引 +1 行 · arch 报告 `docs/reports/2026-10-14-T522-arch-review.md`（56 行）· QA 报告 `docs/reports/2026-10-14-T522-qa-verify.md`（69 行）。**发布** = ✅ tag `v0.18.0` + Release 已发（发布提交 `1600450` · 标题自证）· 待办 = 派生会话回收。**残差**：R1（AC5 措辞订正，已落 PRD）· R2（⑭）· R4（⑮）· R3 自证-修复闭环。 | PR [#40](https://github.com/Nathan3303/nao-skills/pull/40) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-t4-gate-wiring.md` · ADR + arch/QA 报告见备注 | **发布门禁**：`npm run test:t4:full` ✅ rc=0（用户装 `strace` 后实测 · PASS 267 / SKIP 0 / DEGRADE 0）· 派生会话 `close --task T522` 于发布闭环后执行 |
| **T521** | **验收通过 · 已合并归档**（v0.17.3）：Release 标题口径 = 裸 `vX.Y.Z` —— 权威单处 `release-notes.md` §一.5 + §四清单 + §五红线 · 两处引用收敛（`github-flow.md:56` / PM 卡 :121）并指回单处 · PM 卡 **v24→v25** · 模板注释 1 行（6 分段标题未动）· 一次性只读探针 `PASS=28 FAIL=0` + 负控 2/2 · `check` rc0 roles=6 files=46 + `npm test` rc0 · QA 独立复跑 **GO** · PR [#39](https://github.com/Nathan3303/nao-skills/pull/39) squash `eff44ec`（main 恰 1 条 · 无 `wip()` · 分支删净）· **tag `v0.17.3` + Release 已发**（发布提交 `4d97f00` · **AC9 自证：标题严格 = `v0.17.3`**）· **npm 重发 0.17.3 已核验**（`latest` + integrity 逐字节）| PR [#39](https://github.com/Nathan3303/nao-skills/pull/39) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-release-title-bare-version.md` · 探针 `docs/reports/2026-10-14-T521-release-title-probe.sh` | 裁定：AC6 偏差**采纳**（探针自身除外 + raw 回显）· AC7 **(a)** 不动范围 · N1 探针一次性（含行号/`files` 计数 ⇒ 勿作长期门禁）· N2 `npm test` 未含 `tests/t4/`（另批）· Reviewer 无法指派（无 `qa` 账号）结论走 intercom · `card pm v25` 广播：本仓已发 · 下游三仓待唤醒补发 |
| **T521-接缝** | **接缝确认（2026-10-14 · QA `done(full)`）**：候选够用、接缝数不增；**改定 1 处**（补 `npm test` = 项目全范围门禁）+ **补 3 条断言**（AC3 反删除 / AC4 补 `updated` / AC5 补分段标题）· AC7 二选一 → **PM 裁定 (a)**（不动范围，观测点改 `github-flow.md:71` 防回归） | `docs/prds/2026-10-14-release-title-bare-version.md` §七 | 只读复核，未改文件 · QA 二次验证按改定接缝执行 |
| **T520** | **验收通过 · 已合并归档**（v0.17.2）：ADR 文档契约（骨架单源 + 职责下沉 + 索引模板）—— 必写 5 节 + 可选 3 节（参考来源恒末）· 头部恰 4 字段 · 状态值域 4 值 · 禁写/下沉清单 → `docs/reports/<编号>-arch-review.md` · 60 行上限保留（仅新增件断言）· 9 文件（2 新增模板 + 3 机制文件 + 索引 + 首实例 ADR + 评审报告 + 探针）· **QA 独立只读探针 `PASS=53 FAIL=0`**（`--fast` 46/0/4）· 负控 2/2（禁词注入 / 节序打乱均 FAIL）· `check` rc0 roles=6 **files 44→46** · `npm test` rc0 · t4 12/12 · squash `160cc60`（main 恰 1 条 · 无 `wip()` · 分支删净）· **tag `v0.17.2` + Release 已发**（发布提交 `9833344` · npm 不重发） | PR [#38](https://github.com/Nathan3303/nao-skills/pull/38) · 降级批次（无 Issue）· PRD `docs/prds/2026-10-14-doc-templates-convention.md` · 首实例 ADR `docs/adr/2026-10-14-adr-structure-contract.md` · 探针 `docs/reports/2026-10-14-T520-doc-contract-probe.sh` | 角色卡 `arch-designer` **v11→v12**（广播已发本仓；下游三仓待补发）· 历史 7 篇 ADR 零改动（不追溯）· 边界：`check` 的 `files` 只统计 `.agents/**`；探针一次性不入 `tests/` |
> 更早批次（T519 及以前）见 `docs/tasks-archive.md`。
