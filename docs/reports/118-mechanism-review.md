# 机制整体 Review（Issue #118 · arch 主审）

- 状态：待 PM 终验（qa 复核已回填 §九；本稿已按 CONDITIONAL 订正，§十 留痕）· 更新：2026-11-14 · Owner：arch-designer
- 指针：PRD `docs/prds/2026-11-14-mechanism-review.md` · Issue #118 · 追溯深度 = 只看当前口径（PRD §十一）
- ADR：**本批不需要 ADR** —— 全部发现都是「现行文件之间口径不一致」，修法是收敛到既有单源，无新增结构决策；唯一候选（卡行数预算）属 PM 拍板项，见 §八 D1。

## 一、结论（可行性：有条件可行）

- 机制**可继续用**：门禁、清单计数、§ 锚点这些「机械面」本轮实测全对得上（§五）。
- 三条 P1 都是**口径失真**，不是实现缺陷：后端口径整层停留在 tmux、ADR 状态未回填（正文 **6/16 篇 = 38%** · 索引 **9/16 行 = 56%**，其中 3 行与正文矛盾；口径 `grep -rn 待落地 docs/adr` = 15 行 / 7 文件）、遗留「转办」出口无载体。
- 最大风险不是某条规则错，而是**同一规则的多处副本各自漂移**（三段阶梯 10 个文件、ADR 状态正文与索引两处），改一处必漏其余。
- 因此建议先做**零逻辑的文本对齐批**（批次 A/B），把「卡是否还该长」这类结构问题留到 §八 裁定后再动。

## 二、① 自洽（4 条）

- **S1 [P2]** `skills/commit.md:38` 白名单标题写「不经 PR 流程」，第 1 条 `:42` 却是「走 `hotfix/<id>` 分支 + PR 快速合并」⇒ 读者判不出 hotfix 到底走不走 PR。归属：批次 A。
- **S2 [P2]** ADR 是**无条件**红线（`prompts/architecture-designer.md:96`、`checklists/architecture-designer.md:33`），而用户 2026-11-14 定「仅结构性决策才写、否则明写不需要」⇒ 本批按用户口径交付会被自家清单判未过。三份清单有「不适用：<理由>」写法，arch 清单 `grep -c 不适用` = 0。归属：批次 A。
- **S3 [P2]** 三段阶梯原文 12 处 / 10 文件（`grep -rn '原生入口 \`codegraph_explore\`' .agents --include=*.md` = 6 卡 + 3 清单 + `pm-operations`；`原生入口` 全集 22 行 / 11 文件含单源 `skills/codegraph.md`），而 `prompts/backend-developer.md:52` 这类条目又写「详情见 `@.agents/skills/codegraph.md`」⇒ 单源声明与全文复写并存，改口径需手改 10 个文件，正是本批要防的双源。归属：批次 C（需 D2）。
- **S4 [P3]** 三件套（静默工作区 / HEAD / 命令+输出）定义在 `common/output-format.md:33` 声明单源，`checklists/qa.md:23`、`checklists/rd-infra.md:19` 仍内联复写定义句。归属：批次 C。

## 三、② 膨胀（3 条，给可测量代理）

- **E1 [P1]** 卡预算阈值失真：`scripts/nao-fleet.sh:169` `CARD_MAX_LINES=200`，而最大卡 `prompts/product-manager.md` = 145 行（阈值 72.5%）、7 卡合计 661 行；超阈值只打印 `!`（`:2899`）不改 rc，`intercom-protocol.md:60` 的「记 TODO」无载体，`grep -rn CARD_MAX_LINES tests/` = 6 行（**全在 `tests/t4/fixtures/` 快照**，`| grep -v fixtures` = 0）⇒ 无任何断言 ⇒ 卡还能再长 27% 而无信号。归属：批次 C（D1）。
- **E2 [P2]** 闸门密度（代理已证实 / 因果未证）：PM 卡 16 处「闸门」（`grep -o 闸门 .agents/prompts/product-manager.md | wc -l` = 16，分布 `:27` / `:29` / `:34` / `:43` / `:65` / `:67` / `:68`×2 / `:69` / `:70` / `:71` / `:72` / `:73` / `:75` / `:105` / `:137`）、`.agents` 全文 75 处（`grep -o 闸门 | wc -l`）；单批 feat 勾选面 = `checklists/pm.md:72`–`:115` 44 条 + `:28`–`:65` 34 红线 = 78 条，再加 check / npm test / dual / QA / PR 五道机械门禁 ⇒ 单批判定点 ≥83。「读不完就跳过」属推定，不作结论（需实测项见 §五-5）。归属：批次 C。
- **E3 [P3]** 通道级差：feat 78 条 vs fix 8 条，而「文档随 PR」「计数自证」在 `checklists/pm.md:105`、`:114`、`:138` 两节重复要求 ⇒ 同一风险两套勾选面。归属：批次 C。

## 四、③ 脱节（6 条）

- **T1 [P1]** 后端口径整层脱节：`common/intercom-protocol.md:36` 写「唯一路径 = tmux 会话内」、`AGENTS.md:18` / `:33` 写「只支持 pi + tmux」，而实现 `scripts/nao-fleet.sh:141` 默认 herdr、`README.md:30` / `docs/INSTALL.md:14` 已同步；`AGENTS.md` 不在 `.agents/` 下，`.agents/**/*.md`（卡/清单/协议/技能）**0** 次提到 herdr（`grep -rn herdr .agents --include=*.md` 空；`nao-fleet.sh` 内 340 处）。**静态可证的是反向**：`require_tmux` 只在 `:284` 的 `tmux)` 分支调用，默认 herdr 走 `:440`–`:474`（`:447` 是 `HERDR_ENV=1` 缺失闸门）⇒ herdr pane 内（无 `$TMUX`）命令实际可用，卡面却让角色误以为不能跑。归属：批次 A。
- **T2 [P1]** ADR 状态未回填：正文 **6 篇**写「待落地 vX.Y.Z」而版本均已发布（v0.17.2 / 0.18.0 / 0.18.3 / 0.18.5 / 0.20.0 / 0.21.0，`ls docs/releases` 均有；`grep -rn 待落地 docs/adr` = 15 行 / 7 文件）；索引 `docs/adr/README.md:17`–`:25` 共 **9 行**写待落地，其中 **3 行与正文直接矛盾**（`:21` ↔ strict-tmux-pi `:3`「已落地 v0.19.1」· `:23` ↔ fleet-status `:3`「v0.20.2」· `:25` ↔ herdr-scope `:3`「v0.23.1」）。归属：批次 A。
- **T3 [P2]** 被现行文件引用的废止口径未标废：herdr 转默认（v0.23.0）后 `adr/2026-10-27-strict-tmux-pi.md` 状态仍「已接受（已落地 v0.19.1）」且被 `intercom-protocol.md:36` 当现行前提引用，无取代注记 ⇒ 命中 PRD §十一 的「废止口径仍被引用 = 脱节」。归属：批次 A。
- **T4 [P2]** 台账当前事实数字陈旧：活约束 ⑫（`docs/tasks-state.md` @ `4c46c9c`；`grep '实测 1874 行'` 1 命中）称「1874 行 / 72 函数 / `cmd_check` 228 行」，实测 4234 行 / 133 函数 / 275 行（`wc -l` + `grep -c '^[a-zA-Z_][a-zA-Z0-9_]*() *{'` + `awk` 量函数体）。归属：批次 B。
- **T5 [P2]** 自检摘要行数不符：`prompts/product-manager.md:66` 称 check「默认 2 行摘要」，实测 3 行（摘要 + codegraph + `生效后端 NAO_TERMINAL=herdr`，#96 后新增）。归属：批次 A。
- **T6 [P3]** `reports/121-impl.md:50` 仍留「R1–R6 **6/6 安全**」，订正只在 `:72` 末尾 ⇒ 只读正文者得到已被证伪的结论；订正留痕合规，但正文未同步。归属：批次 B。

## 五、覆盖证据（含判定「无问题」的项）

1. 清单条数（声明 vs 实测全等，`grep -c '^- \[ \]'` 分段计）：pm 34/44 · rd-fe 19/14 · rd-be 9/14 · rd-infra 8/14 · qa 14/18 · arch 12/13 —— **无漂移**。
2. 交叉引用锚点：抽取 `@.agents/*.md §<中文序号>` 逐条回查目标标题，**0 处悬空**；但 `check_cross_refs`（`nao-fleet.sh:1436-1460`）只校验**文件存在**（且白名单漏 `extensions/`），不校验 § 锚点 —— 声明「文件齐备」成立，「引用可达」无闸。
3. 已闭合线索（PM 清单里的）：`reports/96p3-layout-p1.md` 的 `HERDR_SESSION` 回退**已在 `:28` 加「已作废」注记**（PRD 记的 `:22` 是表格行本身）⇒ 该条不列为缺陷。`tests/t4/cases/32` 旧断言已随 T545 退场。
4. 门禁与规模：`check` rc=0 · `roles=7` · `files=54`；`wc -l` = prompts 661 / skills 1160 / checklists 628 / common 282 / `nao-fleet.sh` 4234。
5. 需实测（不得当结论）：herdr 默认后端下「tmux 内 `ensure` ⇒ exit 3」未实跑（依据仅脚本头 `:10` 与 `INSTALL.md:32`），且 `HERDR_ENV` 若被继承进 tmux pane 则未必 exit 3；判据 = tmux 会话内 `ensure` 得 rc=3 + 文案含 `NAO_TERMINAL=tmux` 回退指路，执行者 rd-infra（批次 A 验收项）。

## 六、④ 遗留三档（12 行 / 真遗留 11 · 逐条处置 + 前提订正）

- **前提订正（P1）**：PRD §一 写「三档共 13 条」，实测 **12** 行（`awk` 计数见下），且日期三档已变（表内 2026-11-27 / 11-28 / 12-14 / 12-28 / 12-31×5 / 2027-05-09×2）。计数命令：`awk '/^## 观察/,/^## 进行中/' docs/tasks-state.md | grep -c '^| [A-Za-z]'` ⇒ 12（台账 @ `4c46c9c`）。
- **L1 [P1]「转办」出口无载体**：`T545` 验收行（`docs/tasks-state.md` @ `4c46c9c`；`grep '| **T545** |'` 1 命中，内含「同 slug 两仓接受」）与 `T543` 验收行（台账 @ `4c46c9c`；`grep '| **T543** |'` 1 命中，内含「O2 转办 2026-12-31」）标「转办」，但 `待派发队列` 仅剩 #121/#118 ⇒ 转办项实际丢失；同类只在批次行、未入三档表：96 期 `O1`（台账 @ `4c46c9c`；`grep '卡会话跨仓同 core'` 2 命中）、96 期「未验三项」（台账 @ `4c46c9c`；`grep '2027-06-30'` 1 命中）、T545 同 slug 两仓（台账 @ `4c46c9c`；`grep '同 slug 两仓共用'` 1 命中）。日期扫描 `grep -c '2027-01-31\|2027-06-30' docs/tasks-state.md` @ `4c46c9c` = **4 命中**，均在批次行、不在三档表段。归属：批次 B。
- 逐条处置（12 行，与台账顺序一致）：`T529-D1` 关闭（用户已改口径，nao-skills 不再代做）· `M20261028-F2` 合并 → codegraph 版本耦合条 · `M20261028-F5` 合并 → codegraph 版本耦合条（与 `M20261028-F2` 同条） · `M20261014-F1` 保留（2026-12-14 核上游）· `T537-O3` 保留 · `T537-O4` 保留（首次真实使用后定级）· `M20261102-F1` 保留 · `M20261102-F2` 合并 → 「t4 flake 归口」条 · `T534-O2` 合并 → 「t4 flake 归口」条（与 `M20261102-F2` 同条，复现率 ≈15% 归该条）· `M20261109-install-scripts` 保留（2027-05-09）· `M20261109-herdr-base` 移出（类别列「已改判 → 立项 #96」、到期列空 ⇒ 决策轨迹）· `M20261109-pi-threshold-docs` 合并 → 批次 A 的「文档字面量收敛」项。
- **L2 [P2] 处置原则建议**：三档表只收「接受含到期 / 定时重评」，观察项与转办项一律指向单一载体（转办 → 队列，观察 → 批次行指针），否则「到期只回看」必然失忆。

## 七、拆解（批次 A 可直接开工）

- **范围**：① `.agents/common/intercom-protocol.md:36` 后端口径改为「默认 herdr / 回退 tmux」并给 `README.md`「前置环境」+ `INSTALL.md`「herdr 后端」指针（不复制）② `AGENTS.md:18` / `:33` 同口径订正（PM 治理范围）③ ADR 状态回填正文 6 篇 + `docs/adr/README.md:17`–`:25` 共 9 行（含 3 处矛盾）+ `strict-tmux-pi` 加「被 herdr 默认取代」注记 ④ `prompts/product-manager.md:66` 改「3 行摘要」。
- **AC 草稿**：AC1 `.agents/**/*.md` 内 `grep -rn herdr` ≥3 处且负向 `grep -c '唯一路径.*tmux'` = 0；AC2 **16 篇** ADR「正文状态 == 索引状态」（逐篇对照表落报告）；AC3 `check` rc=0 `files=54` 不变；AC4 纯 md 改动（`git diff --numstat` 无 `.sh`/`.mjs`）。
- **主责**：PM（`AGENTS.md` + ADR 索引）+ arch（ADR 正文与取代注记）+ rd-infra（`intercom-protocol` 口径与 §五-5 实测）；批次边界 = 1 PR、不发布（纯文本，随下次 PATCH）。
- 批次 B（台账载体，PM 单人可开工）：L1/L2 落地 + T4/T6 数字订正；批次 C（卡与规则收敛）**待 §八 拍板后再立项**。

## 八、决策点（PM 已裁 · 2026-11-14）

- **D1 卡行数上限（已裁：暂不设硬上限）**：先立可观测基线（7 卡合计 661 行 = pm 145 / arch 118 / qa 90 / rd-fe 87 / rd-be 82 / uiux 72 / rd-infra 67），有基线后再议 150/200 —— 无信号设限会逼出「为凑数删证据」。
- **D2 三段阶梯收成 1 处指针（已裁：做，但单独立项）**：会改 10 个文件 + 卡 bump + 广播，不与口径订正混批。
- **D3 遗留单一载体（已裁：采纳）**：所有「接受含到期 / 观察」必进三档表，批次行只给指针（L1 即此洞）。
- **D4 一致性闸门（已裁：不加新闸门）**：改为现有 `check` 内**单点 warn**（比对协议 / `AGENTS.md` 的端前提 vs `nao-fleet.sh` 默认后端），实施归批次 A、不在本批。
- **本次教训（归批次 B）**：引用易变载体（`docs/tasks-state.md`）**不得裸用行号**，须「条目 ID + as-of sha + 可 grep 定位串」—— 同一命中行的行号在 `fa87517` → `ce94b5b` → `929b51d` 三次台账编辑中连续漂移（+3 → +1），本轮被咬 3 次。

## 九、交叉复核（qa 回填）

- **边界与判定**：只读复核 HEAD `1f2cc9f`；`.agents` / `tests` 自 `f67062a` 零 diff（`git diff --stat f67062a 1f2cc9f -- .agents tests` 空）；未实跑 `ensure`（需双后端环境）、未跑 `npm test`（AC8 免跑）；`check` 复跑 rc=0 · `files=54`。判定 **CONDITIONAL**：AC1 / AC4 / AC7 / AC8 ✓，待订正 3 处计数 + 2 处口径 + 1 处行段。
- **AC4 行段抽查 13 条全部可达**（逐条自读、均支持结论）：T1 = `intercom-protocol.md:36` + `AGENTS.md:18` / `:33`（旁证 `nao-fleet.sh:141` · `README.md:30` · `INSTALL.md:14`）· T2 三例 = `docs/adr/README.md:21` / `:23` / `:25` ↔ 各 ADR `:3` 状态行（三版本在 `docs/releases/` 均在）· S1 `commit.md:38` + `:42` · S2 `prompts/architecture-designer.md:96` + `checklists/architecture-designer.md:33` · E1 `nao-fleet.sh:169` + `:2899` + `intercom-protocol.md:60` · E3 `checklists/pm.md:105` / `:114` / `:138` · S4 `output-format.md:33` + `qa.md:23` + `rd-infra.md:19` · T3 该 ADR 全文 0 次 herdr · T4 台账活约束 ⑫（`docs/tasks-state.md` @ `4c46c9c`；`grep '实测 1874 行'` 1 命中；实测 4234 行 / 133 函数 / 275 行 ✓）· T5 `product-manager.md:66`（check 实 3 行 ✓）· T6 `reports/121-impl.md:50` + `:72` · L1 = 台账非三档表段（`docs/tasks-state.md` @ `4c46c9c`；`grep '2027-06-30'` 1 命中 · `grep '卡会话跨仓同 core'` 2 命中）。
- **计数裁决 ①（T2）**：`grep -rl 待落地 docs/adr` = 7 文件 · `-rn` = 15 行 · 正文 **6 篇** · 索引 **9 行（`README.md:17`–`:25`，6 行与正文一致 + **3 行矛盾**）⇒ 任何口径都得不出 8，已按此改写。
- **计数裁决 ②（AC6）**：**12 行 / 真遗留 11**（第 11 行 `M20261109-herdr-base` 类别列「已改判 → 立项 #96」、到期列空 ⇒ 决策轨迹），§六 标题已同步。
- **计数裁决 ③（另 3 处）**：E1 `grep -rn CARD_MAX_LINES tests/` = **6 行**（全在 fixtures 快照；`| grep -v fixtures` = 0）· L1 日期扫描 = **4 命中**（`grep -c '2027-01-31\|2027-06-30'` @ `4c46c9c`；均在批次行、不在三档表段）· S3 = **12 处 / 10 文件**（全集 22 行 / 11 文件含单源 `skills/codegraph.md`）· §七 AC2 应为 **16 篇**（`ls docs/adr/*.md` = 17 含 README）—— 均已在正文改写。
- **声明 vs 判据落差（已改）**：**D1** `exit 3` 已从事实降为需实测（§五-5）；可静态证的**反向证据**已进 T1 —— `require_tmux` 仅 `nao-fleet.sh:284` 的 `tmux)` 分支调用，默认 herdr 走 `:440`–`:474`、`:447` 是 `HERDR_ENV=1` 缺失，故 herdr pane 内（无 `$TMUX`）命令可用而卡面说不能跑。**D2** 改为「`.agents/**/*.md` 0 次」（`nao-fleet.sh` 内 340 处；`AGENTS.md` 不在 `.agents/` 下）。**D3** E2 已补 `product-manager.md:27` / `:65`–`:75` / `:105` / `:137`，T2 补 `README.md:21` / `:23` / `:25`，L1 改「条目 ID + as-of sha + grep 定位串」。D1 的 `exit 3` 实跑仍归批次 A rd-infra 验收项，不因读码而免。

## 十、修订

- 2026-11-14 初稿（arch 主审 · HEAD 见回执）。
- 2026-11-14 订正一轮（PM CONDITIONAL + qa 回填）：T2 6 篇 / 9 行 · AC6 12 行·真遗留 11 · E1 6 行 · S3 12 处 / 10 文件 · §七 AC2 16 篇；D1 的 `exit 3` 降为需实测并补反向证据。**订正二轮（`53995da`）：台账引用改「ID + as-of `4c46c9c` + grep 定位串」+ §一 比例判据 + E2 枚举 16 处**。结论与分级不变。
