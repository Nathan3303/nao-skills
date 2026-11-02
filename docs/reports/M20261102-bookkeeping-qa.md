# QA 报告：台账卫生小批复核（M20261102 · v0.21.2）

- 状态：复核完成 · **GO**（无阻塞缺陷）· 更新：2026-11-02 · Owner：qa
- 指针：分支 `nao/bookkeeping-20261102` · head `e25b891` · Draft PR [#64](https://github.com/Nathan3303/nao-skills/pull/64) · 范围 = 8 文件 `+83 −17`、零机制代码
- 复核方式：轻量复核（六项 + 自跑全范围门禁 + 自建只读探针与负控）；**未修改任何实现文件**

## TL;DR

- **六项全过**，唯一问题集中在文档口径闭环（4 条 P3）与 RD 报告一处数字笔误（1 条 P3），**均不阻塞合并**。
- **独立复核数字（自跑，未采信回执）**：用例数 **20** · `8 文件 +83 −17` · `roles.yaml` diff **0** · `check` rc=0/roles=6/files=50 · `npm test` rc=0（SKIP=0 · DEGRADE=0 · NOTE=2 白名单）· `test:t4:full` rc=0（非白名单 NOTE=0）。
- **状态行「已核验」经独立证真**：v0.21.0 / v0.21.1 的回填值与直连 registry + `npm pack` 实测**逐字节相同**（integrity 全文一致、tarball 155,621 B / 155,669 B 一致）⇒ 不是假陈述。
- **探针有效**：13 条断言全 PASS；负控在临时副本删掉 A 句后点名 `FAIL A1` 且 rc=1；还原后仓库三文件 md5 全同。

## 一、范围 / 不测

- 复核范围：`git diff main...HEAD` 全 8 文件（`.agents/common/release-notes.md` · `.agents/skills/github-flow.md` · `tests/README.md` · `docs/reports/M20261102-bookkeeping-rd.md`（新）· `docs/reports/2026-11-01-T537-ac1-title-probe.md`（新）· `docs/tasks-state.md` · `docs/releases/v0.21.0.md` · `docs/releases/v0.21.1.md`）。
- 不测 / 不可测：
  - **T537 AC1② 真 `pi` 终端标题**未独立复跑（需真 pi 会话 + 隔离 tmux + 卡夹具；属 PM 发布日自证项）。我采信报告内容，并与台账既有记载（`π - review-helper - t537-ac1`）**一致**。
  - **`gh release create --target <短 sha>` 的失败信息**无法无害复现（会产生真实 Release）⇒ 以侧证替代：远端 tag `v0.21.0`/`v0.21.1` 均存在（`d50dc03`/`42f71ec`，且为 **annotated** ⇒ 确走 `git tag -a`），两个 Release 的 `targetCommitish` 均为 `main`（非短 sha）⇒ 与「push tag 后 `--verify-tag`」路径一致，与文档描述不矛盾。

## 二、六项逐项结论

**① 内容正确性 —— PASS（含 3 条 P3）**

- A（`release-notes.md`）：§一 新增第 6 条硬约束，包含完整三段式「先『待核验』→ 按**唯一判据**核验（`dist-tags.latest` = 该版本 + `dist.integrity` 与本地 `npm pack` tarball **逐字节一致**）→ 回填实测值（`latest` + integrity 全文 + tarball 字节数）」+ v0.20.4 假陈述理由；§二 结构侧新增「状态行（骨架：标题下第一行）」并显式 `口径见 §一.6`。
- 指向关系：**§二 → §一.6 已在**；§一.6 未回指 §二（单向，不影响判定，见遗留 O2/O3）。
- B（`github-flow.md`）：降级路径 `git tag -a` → `git push origin <tag>` → `gh release create … --verify-tag` 与两次实测事实（tag 已 push 且为 annotated、Release 已存在且标题为裸版本号）**一致**；并明确禁用 `--target` 指向未 push 短 sha。
- 回填真伪（我独立证真）：`0.21.0` integrity `sha512-ymY6bicO…VSQ==` / `155,621 B`、`0.21.1` integrity `sha512-7DaUdR6t…RnsQ==` / `155,669 B`，与 registry `dist.integrity` 及 `npm pack` 产物**完全相同**。

**② 文档规范 —— PASS**

- 新增行**无表格**（`git diff` 中命中 `|` 的行全部是 `tasks-state.md` 既有队列表的行替换/新增，未引入新表）；`release-notes.md` 全文表格行数 0。
- 全 LF：8 文件 `grep -c $'\r'` 均 0。
- **未新增章节骨架**：`git diff` 新增标题行只出现在 2 个**新报告文件**内（新交付物自带骨架，属预期），既有 `.agents/**` / `docs/**` 文件零新增标题。

**③ 交叉引用 —— PASS**

- 自跑 `bash .agents/scripts/nao-fleet.sh check`：**rc=0** · `roles=6` · `files=50` · `layout=main-row2`（`@.agents/...` 引用扫描含在此命令内，零断裂）。
- 手工抽核：`@.agents/templates/release-notes.md.example`、`@.agents/checklists/deliverable-docs.md` 均存在。

**④ 数字复核 —— PASS（全部自跑）**

- 用例数：`bash tests/t4/run.sh --list | tail -n +2 | wc -l` = **20**（编号 `01–10`、`12–21`，`11` 已退役）。
- 文件数：`git diff --shortstat main...HEAD` = **8 files changed, 83 insertions(+), 17 deletions(-)**（numstat 复算 `+83 −17`）。
- `git diff --stat main...HEAD -- .agents/roles.yaml` = **空（0）**。
- `check` = **rc=0 roles=6 files=50**（同上）。

**⑤ 台账一致性 —— PASS（含 1 条 P3）**

- 队列表实计 **14 行**：7 待派发（`T536-O2`/`T536-O4`/`T536-O3`/`T536-O1`/`T535-O2`/`T534-O2`/`T529-D3`）+ 3 已登记接受项（`T537-O3`/`T537-O4`/`M20261102-F1`）+ 4 定时（`T529-D1`/`M20261028-F2`/`M20261028-F5`/`M20261014-F1`）⇒ 与快照段描述一致。
- `T533-O5`/`T533-O4`：**队列表内 0 命中**（仅存于立项行与历史教训散文，属正常留痕）。
- `M20261014-F1` 行**完整未截断**：4 列齐全（编号 / 目标会话 / 概要 / 排队原因），与改前文本等价。
- 快照段「当前阶段」与仓库事实一致：main `3e155d6` ✓ · tag `v0.21.1` ✓（本地 + 远端 ref 均在）· `npm dist-tags.latest = 0.21.1` ✓。

**⑥ 只读探针 + 反例 —— PASS**

- 探针 `/tmp/M20261102-probe/probe.sh`（grep 级，13 条断言）：A1–A5（A 硬约束 6 关键句、三段式、「口径见 §一.6」）· B1–B5（`--target` 不可用、两类报错文案、`git tag -a` 路径、`--verify-tag`、禁 `--target` 未 push 短 sha）· C1–C3（README 例数口径命令、禁最大编号、三侧同口径）⇒ **PASS=13 FAIL=0**。
- 负控：**临时副本**（`cp -a` 到 `/tmp`）把 A1 句改为「状态行写法。」⇒ 探针 **FAIL A1（缺句…）**、`PASS=12 FAIL=1`、rc=1（点名机制有效）。副本还原后复跑 PASS=13。
- 还原核对：仓库三文件 `md5sum -c` 全「成功」（`release-notes.md` / `github-flow.md` / `tests/README.md` 未被我改动）；`git status --porcelain` 空（本报告除外）。

## 三、门禁（精确数字，自跑）

- `bash .agents/scripts/nao-fleet.sh check`：**rc=0** · `roles=6` · `files=50`
- `npm test`：**rc=0** · 20 用例全 **PASS** · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）· 汇总 `RESULT: PASS`
- `npm run test:t4:full`：**rc=0** · 20 用例全 PASS · `SKIP=0 · DEGRADE=0 · NOTE=2` ⇒ **非白名单 NOTE=0**
- `roles.yaml` diff：**0** 行 · 工作区：干净（本报告提交前）
- 未推送：**0**（PR #64 `headRefOid` = `e25b8914…` = 本地 `HEAD`，逐字相同；见遗留 O6 关于本地远端 ref 滞后）

## 四、遗留（全 P3 · 三出口）

- **O1（本批可清 · 转 PM）**：`T536-O4` 仍在队列表内（「防线待落文本」），而本批 E **已把该文本落盘**（`release-notes.md` §一.6）⇒ 该行已属可关闭项。建议验收时同步清行或改写为「已落文本 · 待发布验证」，否则「7 项待派发」里含 1 条已交付项，下批会重复派发。
- **O2（建议下批补 · 转 rd-infra 或 PM 定）**：新品文 §一.6 未镜像到 §四「发布前核对」与 §五「红线」（两节现存 0 条「状态」条目）。T521 立标题口径时是先例（§一 + §四 + §五 三处同落）；本次只有 §一 + §二 ⇒ PM 逐条打勾 §四 时不会碰到这条，防线只对「读 §一」的人生效。
- **O3（建议下批补）**：`@.agents/templates/release-notes.md.example` 骨架内**无状态行**（0 命中），而 §二 说状态行是「标题下第一行」。复制模板写新发布说明 ⇒ 不会自动带出状态行，与 §一.6 的强制要求错位。
- **O4（口径澄清 · 转 PM）**：状态行现在强制携带 integrity 全文 + tarball 字节数（内部信息、且置顶），与 §一.2「内部信息一律下沉技术细节」在字面上张力。建议 §一.6 或 §二 加半句「状态行为元数据行，不受 §一.2 正文禁令约束」，避免后续读者/后续 QA 按 §一.2 判违规。
- **O5（文档笔误 · 转 rd-infra 订正）**：`docs/reports/M20261102-bookkeeping-rd.md` §二标题写「3 文件 · **+7 −1**」，实际 numstat（`release-notes.md` +3、`github-flow.md` +1、`tests/README.md` +1 −1）= **+5 −1**。不影响结论，建议随验收订正（与 `e25b891` 已订正的「两文件→三文件」同型，属第二次数字笔误）。
- **O6（流程提示 · 转 PM，不需改文件）**：本地 `refs/remotes/origin/nao/bookkeeping-20261102` 仍停在 `8832e8b`（落后 HEAD 2 个提交），PR 侧 head 已是 `e25b891`。若合并闸门直接跑 `git rev-list --count origin/<branch>..HEAD` 会**误报 2** ⇒ 跑 T533-O4 那条闸门前**先 `git fetch`**（本次 github.com:443 一度不可达，属网络瞬断，非仓库问题）。

## 五、结论

**GO** —— 六项复核全过，门禁全绿（`check` rc=0 · `npm test` rc=0 · `test:t4:full` rc=0 且非白名单 NOTE=0），状态行「已核验」为**可证真的真陈述**，探针与负控双向有效，零机制代码改动、`roles.yaml` 零 diff。4 条文档口径闭环项 + 1 条报告数字笔误 + 1 条流程提示均为 P3，可随验收或下批收口，**不构成合并阻塞**。
