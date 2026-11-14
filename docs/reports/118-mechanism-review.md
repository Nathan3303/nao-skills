# 机制整体 Review（Issue #118 · arch 主审）

- 状态：待 PM 验收（qa 交叉复核待回填末节）· 更新：2026-11-14 · Owner：arch-designer
- 指针：PRD `docs/prds/2026-11-14-mechanism-review.md` · Issue #118 · 追溯深度 = 只看当前口径（PRD §十一）
- ADR：**本批不需要 ADR** —— 全部发现都是「现行文件之间口径不一致」，修法是收敛到既有单源，无新增结构决策；唯一候选（卡行数预算）属 PM 拍板项，见 §六 D1。

## 一、结论（可行性：有条件可行）

- 机制**可继续用**：门禁、清单计数、§ 锚点这些「机械面」本轮实测全对得上（§五）。
- 三条 P1 都是**口径失真**，不是实现缺陷：后端口径整层停留在 tmux、ADR 状态八成未回填、遗留「转办」出口无载体。
- 最大风险不是某条规则错，而是**同一规则的多处副本各自漂移**（三段阶梯 9 份、ADR 状态 2 份），改一处必漏其余。
- 因此建议先做**零逻辑的文本对齐批**（批次 A/B），把「卡是否还该长」这类结构问题留到 §六 拍板后再动。

## 二、① 自洽（4 条）

- **S1 [P2]** `skills/commit.md:38` 白名单标题写「不经 PR 流程」，第 1 条 `:42` 却是「走 `hotfix/<id>` 分支 + PR 快速合并」⇒ 读者判不出 hotfix 到底走不走 PR。归属：批次 A。
- **S2 [P2]** ADR 是**无条件**红线（`prompts/architecture-designer.md:96`、`checklists/architecture-designer.md:33`），而用户 2026-11-14 定「仅结构性决策才写、否则明写不需要」⇒ 本批按用户口径交付会被自家清单判未过。三份清单有「不适用：<理由>」写法，arch 清单 `grep -c 不适用` = 0。归属：批次 A。
- **S3 [P2]** 三段阶梯原文 14 处 / 9 文件（`grep -rln '原生入口 \`codegraph_explore\`' .agents` 命中 5 张卡 + 3 份清单 + `pm-operations`），而 `prompts/backend-developer.md:52` 这类条目又写「详情见 `@.agents/skills/codegraph.md`」⇒ 单源声明与全文复写并存，改口径需手改 9 处，正是本批要防的双源。归属：批次 C（需 D2）。
- **S4 [P3]** 三件套（静默工作区 / HEAD / 命令+输出）定义在 `common/output-format.md:33` 声明单源，`checklists/qa.md:23`、`checklists/rd-infra.md:19` 仍内联复写定义句。归属：批次 C。

## 三、② 膨胀（3 条，给可测量代理）

- **E1 [P1]** 卡预算阈值失真：`scripts/nao-fleet.sh:169` `CARD_MAX_LINES=200`，而最大卡 `prompts/product-manager.md` = 145 行（阈值 72.5%）、7 卡合计 661 行；超阈值只打印 `!`（`:2899`）不改 rc，`intercom-protocol.md:60` 的「记 TODO」无载体，`grep -rn CARD_MAX_LINES tests/` = 0 条断言 ⇒ 卡还能再长 27% 而无任何信号。归属：批次 C（D1）。
- **E2 [P2]** 闸门密度（代理已证实 / 因果未证）：PM 卡 16 处「闸门」、`.agents` 全文 75 处；单批 feat 勾选面 = 44 清单 + 34 红线 = 78 条，再加 check / npm test / dual / QA / PR 五道机械门禁 ⇒ 单批判定点 ≥83。「读不完就跳过」属推定，不作结论（需实测项见 §五-3）。归属：批次 C。
- **E3 [P3]** 通道级差：feat 78 条 vs fix 8 条，而「文档随 PR」「计数自证」在 `checklists/pm.md:105`、`:114`、`:138` 两节重复要求 ⇒ 同一风险两套勾选面。归属：批次 C。

## 四、③ 脱节（5 条）

- **T1 [P1]** 后端口径整层脱节：实现 `scripts/nao-fleet.sh:141` 默认 herdr、`README.md:30` / `docs/INSTALL.md:14` 已同步；但 `common/intercom-protocol.md:36` 仍写「唯一路径 = tmux 会话内」、`AGENTS.md:18` / `:33` 仍写「只支持 pi + tmux」、`.agents/**` 全域 **0** 次提到 herdr（`grep -rn herdr .agents --include=*.md` 空）⇒ 按卡执行（tmux 内 `ensure`）在默认后端下直接 exit 3。归属：批次 A。
- **T2 [P1]** ADR 状态未回填：8 篇写「待落地 vX.Y.Z」而该版本早已发布（`ls docs/releases` 有 v0.17.2 / 0.18.0 / 0.18.3 / 0.18.5 / 0.20.0 / 0.21.0）；索引与正文自相矛盾 3 例 —— strict-tmux-pi 正文「已落地 v0.19.1」vs `docs/adr/README.md`「待落地」、fleet-status 正文 v0.20.2 vs 索引待落地、herdr-scope 正文 v0.23.1 vs 索引待落地。归属：批次 A。
- **T3 [P2]** 被现行文件引用的废止口径未标废：herdr 转默认（v0.23.0）后 `adr/2026-10-27-strict-tmux-pi.md` 状态仍「已接受（已落地 v0.19.1）」且被 `intercom-protocol.md:36` 当现行前提引用，无取代注记 ⇒ 命中 PRD §十一 的「废止口径仍被引用 = 脱节」。归属：批次 A。
- **T4 [P2]** 台账当前事实数字陈旧：`tasks-state.md:349` ⑫ 称「实测 1874 行 / 72 函数 / `cmd_check` 228 行」，实测 4234 行 / 133 函数 / 275 行（命令见 §五）。归属：批次 B。
- **T5 [P2]** 自检摘要行数不符：`prompts/product-manager.md:66` 称 check「默认 2 行摘要」，实测 3 行（摘要 + codegraph + `生效后端 NAO_TERMINAL=herdr`，#96 后新增）。归属：批次 A。
- **T6 [P3]** `reports/121-impl.md:50` 仍留「R1–R6 **6/6 安全**」，订正只在 `:72` 末尾 ⇒ 只读正文者得到已被证伪的结论；订正留痕合规，但正文未同步。归属：批次 B。

## 五、覆盖证据（含判定「无问题」的项）

1. 清单条数（声明 vs 实测全等，`grep -c '^- \[ \]'` 分段计）：pm 34/44 · rd-fe 19/14 · rd-be 9/14 · rd-infra 8/14 · qa 14/18 · arch 12/13 —— **无漂移**。
2. 交叉引用锚点：抽取 `@.agents/*.md §<中文序号>` 逐条回查目标标题，**0 处悬空**；但 `check_cross_refs`（`nao-fleet.sh:1436-1460`）只校验**文件存在**（且白名单漏 `extensions/`），不校验 § 锚点 —— 声明「文件齐备」成立，「引用可达」无闸。
3. 已闭合线索（PM 清单里的）：`reports/96p3-layout-p1.md` 的 `HERDR_SESSION` 回退**已在 `:28` 加「已作废」注记**（PRD 记的 `:22` 是表格行本身）⇒ 该条不列为缺陷。`tests/t4/cases/32` 旧断言已随 T545 退场。
4. 门禁与规模：`check` rc=0 · `roles=7` · `files=54`；`wc -l` = prompts 661 / skills 1160 / checklists 628 / common 282 / `nao-fleet.sh` 4234。
5. 需实测（不得当结论）：herdr 默认后端下「tmux 内 `ensure` ⇒ exit 3」仅据脚本头 `:10` 与 `INSTALL.md:32` 文档，**未实跑**；判据 = tmux 会话内 `ensure` 得 rc=3 + 文案含 `NAO_TERMINAL=tmux` 回退指路，执行者 rd-infra（批次 A 验收项）。

## 六、④ 遗留三档（12 条逐条处置 + 前提订正）

- **前提订正（P1）**：PRD §一 写「三档共 13 条」，实测 **12** 行（`awk` 计数见下），且日期三档已变（表内 2026-11-27 / 11-28 / 12-14 / 12-28 / 12-31×5 / 2027-05-09×2）。计数命令：`awk '/^## 观察 \\/ 定时 \\/ 已接受/,/^## 进行中/' docs/tasks-state.md | grep -c '^| [A-Za-z]'` ⇒ 12。
- **L1 [P1]「转办」出口无载体**：`T545 /tmp/nao-t4.*`（2026-12-31）、`T543-O2`（`HERDR_*` 清单收敛，2026-12-31）在批次行标「转办」，但 `待派发队列` 仅剩 #121/#118 ⇒ 转办项实际丢失；同类：96 期 `O1`（2027-01-31）、96 期「未验三项」（2027-06-30）、T545「同 slug 两仓共用 workspace」（2027-01-31）只存在于批次行，未入三档表（`grep -n '2027-01-31\\|2027-06-30' docs/tasks-state.md` 仅命中 :1、:87）。归属：批次 B。
- 逐条处置（12 行，与台账顺序一致）：`T529-D1` 关闭（用户已改口径，nao-skills 不再代做）· `M20261028-F2` 合并 → codegraph 版本耦合条 · `M20261028-F5` 合并同上 · `M20261014-F1` 保留（2026-12-14 核上游）· `T537-O3` 保留 · `T537-O4` 保留（首次真实使用后定级）· `M20261102-F1` 保留 · `M20261102-F2` 合并 → 「t4 flake 归口」条（与 `T534-O2` 同族，复现率 ≈15%）· `T534-O2` 合并同上 · `M20261109-install-scripts` 保留（2027-05-09）· `M20261109-herdr-base` 移出（决策轨迹，非遗留 → `tasks-archive`）· `M20261109-pi-threshold-docs` 合并 → 批次 A 的「文档字面量收敛」项。
- **L2 [P2] 处置原则建议**：三档表只收「接受含到期 / 定时重评」，观察项与转办项一律指向单一载体（转办 → 队列，观察 → 批次行指针），否则「到期只回看」必然失忆。

## 七、拆解（批次 A 可直接开工）

- **范围**：① `.agents/common/intercom-protocol.md:36` 后端口径改为「默认 herdr / 回退 tmux」并给 `README.md`「前置环境」+ `INSTALL.md`「herdr 后端」指针（不复制）② `AGENTS.md:18` / `:33` 同口径订正（PM 治理范围）③ ADR 状态回填 8 篇 + `docs/adr/README.md` 3 处 + `strict-tmux-pi` 加「被 herdr 默认取代」注记 ④ `prompts/product-manager.md:66` 改「3 行摘要」。
- **AC 草稿**：AC1 `.agents/**` 内 `grep -rn herdr` ≥3 处且无「只接受 tmux」表述（负向 `grep -c '唯一路径.*tmux'` = 0）；AC2 12 篇 ADR「正文状态 == 索引状态」（逐篇对照表落报告）；AC3 `check` rc=0 `files=54` 不变；AC4 纯 md 改动（`git diff --numstat` 无 `.sh`/`.mjs`）。
- **主责**：PM（`AGENTS.md` + ADR 索引）+ arch（ADR 正文与取代注记）+ rd-infra（`intercom-protocol` 口径与 §五-5 实测）；批次边界 = 1 PR、不发布（纯文本，随下次 PATCH）。
- 批次 B（台账载体，PM 单人可开工）：L1/L2 落地 + T4/T6 数字订正；批次 C（卡与规则收敛）**待 §八 拍板后再立项**。

## 八、需 PM 拍板的决策点

- **D1** 卡行数上限：维持 200（现状无信号）／降到 150（pm 145 已贴线）／按「卡 ≤120 + 溢出拆 skills」重设？超限 TODO 落哪个载体？
- **D2** 三段阶梯是否收成 1 处指针（改 9 文件）—— 与「system prompt 稳定 = 前缀缓存」权衡：一次改到位 vs 分批漂移。
- **D3** 遗留单一载体：是否强制「接受项必须进三档表，批次行只留指针」（本次 L1 的根因）。
- **D4** 是否新增「文档-实现一致性」闸门（如 ADR 状态 / herdr 口径 lint）—— 新增闸门本身与 E2 膨胀相反，需你定取舍。

## 九、交叉复核（qa 回填）

- **边界**：只读复核（HEAD `1f2cc9f`）。`.agents/`、`tests/` 自本报告提交 `f67062a` 起零 diff（`git diff --stat f67062a 1f2cc9f -- .agents tests` 空）⇒ 下述计数与报告写作时同源，差异不是快照问题。未实跑 `ensure`（需双后端环境）、未跑 `npm test`（AC8 免跑）；`check` 复跑 rc=0 · `files=54`。**判定 = CONDITIONAL**：结论与拆解可用（AC1 71 行 ≤80 ✓ · AC4 ✓ · AC7 ✓ · AC8 ✓），须订正 3 处计数 + 2 处口径 + 1 处行段，均为文本订正。**另注**：含本节全文 **80 行**（AC1 ≤80 恰好达线）—— 后续任何追加即超限，请 PM 明示 AC1 是「含复核节」还是「仅主审正文」。
- **AC4 行段抽查 13 条（逐条自读，均可达且支持结论）**：T1 = `intercom-protocol.md:36`（逐字「只接受 tmux 会话内 … 不满足 ⇒ `exit 3`」）+ `AGENTS.md:18` / `:33`，旁证 `nao-fleet.sh:141` / `README.md:30` / `INSTALL.md:14` ✓；T2 三例 = `docs/adr/README.md:21` ↔ `2026-10-27-strict-tmux-pi.md:3`「已落地 v0.19.1」· `:23` ↔ `2026-10-31-fleet-status-repo-attribution.md:3`「v0.20.2」· `:25` ↔ `2026-11-13-herdr-workspace-scope-key.md:3`「v0.23.1」（三版本在 `docs/releases/` 均在）✓；L1 见下第 2 项；S1 `commit.md:38` + `:42` ✓；S2 `prompts/architecture-designer.md:96` + `checklists/architecture-designer.md:33`（`grep -c 不适用` = 0）✓；E1 `nao-fleet.sh:169` + `:2899` + `intercom-protocol.md:60` ✓；E3 `checklists/pm.md:105/:114/:138` ✓；S4 `output-format.md:33`（三件套定义在 `:34–:36`）+ `checklists/qa.md:23` + `checklists/rd-infra.md:19` ✓；T3 `2026-10-27-strict-tmux-pi.md` 全文 0 次 herdr、且只「取代」更早 ADR ✓；T4 `tasks-state.md:349` ⑫ 原文 ✓（实测 4234 行 / 133 函数 / `cmd_check` 275 行 ✓）；T5 `prompts/product-manager.md:66` ✓（实测 check 3 行 ✓）；T6 `reports/121-impl.md:50` + 订正 `:72` ✓。
- **计数裁决 ① T2「8 篇待落地」[P2 · 不实]**：`grep -rl 待落地 docs/adr` = **7 文件** · `grep -rn | wc -l` = **15 行** · ADR 正文 = **6 篇**（各 1 行状态）· 索引 = **9 行（`README.md:17–25`）** · 涉及 ADR = **9 篇**；无任何口径得 8。**PM 的「正文 6 篇」对，但「索引 5 行 + 另 4 行属其它条目」亦不实** —— 9 行全是 ADR 索引行，其中 6 行与正文一致、3 行即 T2 的三处矛盾。建议写法 =「正文 6 篇 / 索引 9 行（含 3 处与正文矛盾的陈旧行）」。
- **计数裁决 ② AC6 [P3 · 口径]**：应记「**12 行 / 真遗留 11**」。`awk` 计数 12 ✓；第 11 行 `M20261109-herdr-base` 类别列 =「已改判 → 立项 #96」、到期列空 ⇒ 决策轨迹（报告 §六 已移出）。§六 标题「12 条逐条处置」会被读成「12 条遗留」，建议同步改「12 行（真遗留 11）」。
- **计数裁决 ③ 另 3 处不实 [P3]**：① E1 引用「`grep -rn CARD_MAX_LINES tests/` = 0」实跑 **6 行**（全在 `tests/t4/fixtures/nao-fleet-baseline-*.sh` 快照，非断言）—— 「无断言」结论成立（`… | grep -v fixtures` = 0），引用须换命令；② L1 引用「`grep -n '2027-01-31\|2027-06-30'` 仅 :1、:87」实跑 **4 行（:1 · :2 · :87 · :429）**，均不在三档表段 ⇒ 结论成立、行号订正；③ S3「14 处 / 9 文件」实测 **12 处 / 10 文件**（6 卡 + 3 清单 + `pm-operations`；`原生入口` 全集 22 行 / 11 文件含单源 `skills/codegraph.md`）⇒ 结论成立、须手改的是 10 文件；④ §七 AC 草稿「AC2 12 篇 ADR」应为 **16 篇**（`ls docs/adr/*.md` = 17 含 README）。
- **声明 vs 判据落差 3 条**：
  - **D1 [P2]** T1 把「tmux 内 `ensure` ⇒ `exit 3`」写成事实（§四），§五-5 又把**同一句**标「未实跑 · 需实测（rd-infra）」⇒ 违反 PRD §五「需实测项不得写成结论」。读码：`nao-fleet.sh:284` 只有 `tmux)` 分支调 `require_tmux`（`:250–253`），默认 herdr 走 `:440–474`，`:447` 是 `HERDR_ENV=1` 缺失 ⇒ `exit 3` ⇒ 成因是 **herdr 闸门**而非「tmux 被拒」，且 `HERDR_ENV` 若被继承进 tmux pane 则未必 exit 3（这正是要实跑的理由）。**更该进 P1 且可静态证的是反向**：herdr pane 内（唯一可用环境、无 `$TMUX`）`require_tmux` 不被调用、命令可用，而卡面「只接受 tmux 会话内」会让角色误以为不能跑。
  - **D2 [P2]**「`.agents/**` 全域 **0** 次提到 herdr」强于判据：引用命令带 `--include=*.md`，只证 md 层 0 次；`nao-fleet.sh` 内 herdr **292 行 / 340 处**，而 `AGENTS.md` 不在 `.agents/` 下 ⇒ 应写「`.agents/**/*.md`（卡 / 清单 / 协议 / 技能）0 次」。
  - **D3 [P3]** AC2 零容忍下 E2 **无行段**（16 处 / 75 处 / 78 条 / ≥83 判定点全无 `文件:行段`；我复核其计数成立：`grep -o` = 16 / 75，44 清单 + 34 红线 = 78）⇒ 补行段或降级「观察」。同类：T2 引 `docs/adr/README.md` 未给行号（应 `:21/:23/:25`）、L1「批次行标转办」未给行号。L2 与 §八 属建议/决策，不计。
- **处置建议**：进 PR 前订正上述 ①②③ 与 D1/D2 口径 + E2 行段；不动结论、不扩批次，主审一轮可收。D1 的 `exit 3` 实跑仍归批次 A 的 rd-infra 验收项，不因本次读码而免。

## 十、修订

- 2026-11-14 初稿（arch 主审 · HEAD 见回执）。
