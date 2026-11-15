# 卡与规则收敛（#128 · M20261115-converge）实现报告

- 状态：待 PM 验收（RD 自验完成；`qa` 非作者复核待）· 更新：2026-11-15 · Owner：rd-infra
- 指针：Issue [#128](https://github.com/Nathan3303/nao-skills/issues/128) · PRD `docs/prds/2026-11-15-converge.md` · 分支 `nao/M20261115-converge` · **不发版**

## 结论（TL;DR）

- 范围 5 项（S1–S4 + E1）全部落地；单源收敛只删复写，未删可执行判据。
- S1 hotfix 口径取「**走 PR 快速合并**」：main 只收 squash，审计链保留；白名单免的是「等完整评审」，不是 PR 本身。
- S3 三段阶梯写全处由 **11 文件 / 22 行** 收敛到 **1 文件 / 5 行**（只剩 `skills/codegraph.md`）；卡内全部改为单源指针。
- S4 三件套写全处由 **6 文件 / 7 行** 收敛到 **1 文件 / 2 行**（只剩 `common/output-format.md`，含定义与反例）。
- E1 `check -v` 新增卡预算基线（最大卡 / 行数 / 阈值 / 占比），**不进 rc、不设硬限**；超阈值仍有逐卡 `!`。`CARD_MAX_LINES` 保持 **200**。
- 门禁：`check` rc=0 ×2 输出逐字一致（`roles=7` / `files=54` 不变）；`npm test` **双后端** rc=0；`cases/06` golden 未破（双后端均 PASS）。
- 卡体量：7 张卡合计 **661 → 655 行**（净减 6 行，本批无卡增行）；被改 6 张卡均 bump `version` + `updated=2026-11-15`。

## 改动

- `skills/commit.md`（S1）：白名单标题段改为「目标分支 ≠ main；合入 main 仍走 PR」，hotfix 明确走 PR 快速合并；消除「不经 PR 流程」与正文互斥。
- `prompts/architecture-designer.md` + `checklists/architecture-designer.md`（S2）：ADR 改为「仅结构性决策才写；无决策 ⇒ 报告内明写『本批不需要 ADR』」；清单补「不适用：<理由>」出口，并把 ADR 红线条件化。arch 卡 `version 13 → 15`（S2/单源 + P3 回声补强）。
- `common/intercom-protocol.md`（S2 连带）：arch 回执的「ADR 路径」补「无结构性决策时写『本批不需要 ADR』」，避免与 S2 新口径互斥。
- S3 单源：`skills/codegraph.md` 保持唯一写全处；`prompts/{architecture-designer,backend-developer,infra-engineer,test-engineer,frontend-developer,product-manager}.md`、`checklists/{architecture-designer,rd-fe,qa}.md`、`skills/pm-operations.md` 全部改为指针（arch 的 PR Reviewer 场景保留显式路径）。6 张卡最终 bump：arch 15 / rd-be 14 / rd-fe 14 / infra 6 / pm 38 / qa 17。
- S4 单源：`common/output-format.md` 保持唯一写全处；`checklists/{qa,rd-infra}.md` 改指针；`checklists/{comm-templates,pm}.md` 与 `common/intercom-protocol.md` 去掉重复列名（只留「三件套」+ 单源指针）。
- `scripts/nao-fleet.sh`（E1）：`cmd_check` 的卡循环统计最大行数，新增 `  · 卡预算基线：最大 <卡> <N> 行 / 阈值 200 行（<pct>%）`；**成功摘要**（默认 2–3 行）不含该行，`-v` 与失败展开的完整报告可见。超阈值原有逐卡 `!` 保留，rc 不变。
- 测试：`cases/06` 新增 E1 组（13 条断言，含超阈值负控 + 移除实现变异自证）；`cases/18` 的 G5 判据由「每张卡必须含 `codegraph_explore`」改为「每张提及 codegraph 的卡必须指向单源 `@.agents/skills/codegraph.md`」，并补一条**绝对形态**断言（除 uiux 外每卡至少 1 处单源指针，不以「先提及 codegraph」为前件）+ 删指针负控——**判据保留、只换指向且不留条件式后门**（见下「关键决策」）。
- 报告：本文件。未动 `docs/tasks-state.md` / `docs/prds/*`（PM 面）。

## 关键决策

- **S1 取「hotfix 走 PR 快速合并」**：项目红线是 main 只收 squash、禁直推 main；hotfix 若绕过 PR，事后补 Release/变更单会失去可审计的合并点。白名单真正放宽的是「等完整评审」的时效，而不是 PR 形式。因此标题与正文统一为「可直接推目标分支（非 main），合入 main 仍走 PR」。
- **S3 未删 `cases/18` G5 判据，且不留条件式后门**：该断言原本用「卡内必须出现 `codegraph_explore`」来防止「提及 codegraph 却不给入口」。S3 要求卡只留指针，故把断言改为「提及 codegraph 的卡必须含 `@.agents/skills/codegraph.md`」；但新判据以前件存在为条件（卡把 codegraph 字样全删即可规避）。PM 2026-11-15 复核指出后，本批补**绝对形态**：`cg_abs_missing` 对「除 uiux 外每张角色卡」断言至少 1 处单源指针，并加「删掉指针 ⇒ 必点名」负控。条件式判据保留（管「提及即须给去处」），绝对判据补「不许删到不管」；G1 仍钉技能含 `codegraph_explore`。这不是削弱，而是把重复的工具名换成单源指针并封住删除逃逸。
- **E1 基线放在完整报告（成功摘要不含）**：成功摘要被 `cases/06` 的 2 行 golden 钉住（`check: OK …` + codegraph 状态行），加行会破既有契约。基线属于诊断信息，`-v` 与失败展开的完整报告均可见；`check` 失败（rc≠0）时默认输出整份报告，基线行随之出现（P3-4 已按此订正措辞）。
- **S2 连带改 `intercom-protocol` 一行**：不改则 arch 回执仍强制「ADR 路径」，与「本批不需要 ADR」冲突。该行只补条件，不改回执结构。

## AC 逐条（before → after）

- **AC1（S1）**：`grep -n '不经 PR 流程' .agents/skills/commit.md`：1 行（`:40`）→ **0 行**；`grep -c 'hotfix/'`：1 → **1**（正文保持 PR 快速合并）。标题段与正文同口径，文中无互斥表述。
- **AC2（S2）**：arch 清单 `grep -c '不适用'`：**0 → 1**；`grep -c '结构性决策'`：清单 **0 → 3**、卡 **0 → 7**。arch 卡 `version 13 → 15`、`updated 2026-10-28 → 2026-11-15`。
- **AC3（S3）**：`grep -rn '原生入口' .agents --include=*.md | wc -l`：**22 → 5**；`grep -rl … | wc -l`：**11 → 1**（唯一文件 = `.agents/skills/codegraph.md`）。卡内该主题均 ≤1 行指针（逐卡 `grep -c 'codegraph\|三段阶梯'`：arch / rd-be / rd-fe / qa（test-engineer）/ infra 各 1；pm 的第 2 处是 `check` 的 codegraph 状态行，不是三段阶梯）。`cases/18` 另有绝对形态断言：除 uiux 外每卡至少 1 处单源指针（删掉即红）。
- **AC4（S4）**：`grep -rn '静默工作区' .agents --include=*.md | wc -l`：**7 → 2**；`grep -rl … | wc -l`：**6 → 1**（唯一文件 = `.agents/common/output-format.md`，两行为定义 + 反例）。`qa` / `rd-infra` 清单已改指针。
- **AC5（E1）**：`grep -rn 'CARD_MAX_LINES' tests/ | grep -v fixtures | wc -l`：**0 → 3**；`CARD_MAX_LINES`：**200 → 200**。`check -v` 基线实测：`最大 product-manager.md 144 行 / 阈值 200 行（72.0%）`（改动前最大卡 145 行 / 72.5%；本批卡缩 1 行后为 144）。
  - **先红**：`NAO_TEST_TERMINAL=tmux bash tests/t4/run.sh --case 06` ⇒ `RESULT: FAIL`，E1 组 **6 FAIL**（基线行/最大值/阈值/占比/超阈值基线均缺失）。
  - **后绿**：同一命令 ⇒ `RESULT: PASS`，E1 组 **13 PASS**；超阈值负控（副本卡垫到 201 行）⇒ rc 仍 0、逐卡 `!` + 基线 `100.5%`；删掉副本基线实现 ⇒ 同一判据取值为 0（变异自证）。
- **AC6（纪律）**：被改 6 张卡 `version` 全部 +1（P3 再 bump 的 arch/rd-be/infra 以最终值为准）、`updated` 全部 2026-11-15；广播文本见下节。
- **AC7（门禁）**：`check` rc=0 ×2，`diff` 为空：`check: OK · roles=7 · files=54 · layout=main-row2`（`files=` 未变 = 未增删 `.agents/` 文件）。`npm test`：herdr 默认后端 rc=0（SKIP=0 · DEGRADE=0 · NOTE=10 全白名单 · PENDING=0）· `NAO_TEST_TERMINAL=tmux` rc=0（SKIP=0 · DEGRADE=0 · NOTE=9 全白名单）。`cases/06` 双后端 PASS（golden 未破）。
- **AC8（零夹带）**：改动仅 `.agents/**` + `tests/t4/cases/{06,18}` + 本报告；不含 `bin/`、`package.json`、`site/`；未碰 `docs/tasks-state.md` / `docs/prds/*` / 批次 A/B 交付物。合并前用 `git diff --numstat main...HEAD` 复核。

## 门禁命令（可复跑）

```bash
bash .agents/scripts/nao-fleet.sh check                 # rc=0 ×2，输出 diff 空
bash .agents/scripts/nao-fleet.sh check -v              # 看「卡预算基线」行
NAO_TEST_TERMINAL=herdr npm test                        # 默认后端全量
NAO_TEST_TERMINAL=tmux  npm test                        # 回退后端全量
NAO_TEST_TERMINAL=tmux bash tests/t4/run.sh --case 06    # E1 / golden
grep -rn '原生入口' .agents --include=*.md | wc -l       # 5
grep -rl '原生入口' .agents --include=*.md | wc -l       # 1
grep -rn '静默工作区' .agents --include=*.md | wc -l     # 2
grep -rl '静默工作区' .agents --include=*.md | wc -l     # 1
grep -rn 'CARD_MAX_LINES' tests/ | grep -v fixtures | wc -l   # 3
```

## 广播文本（6 张卡）

- `card arch-designer v15`：ADR 条件化（仅结构性决策才写；无决策 ⇒ 报告明写「本批不需要 ADR」）+ 三段阶梯改单源指针；清单补「不适用：<理由>」出口；P3 回声：PR Reviewer 场景恢复显式路径 `@.agents/skills/codegraph.md`。
- `card backend-developer v14`：三段阶梯改单源指针；P3 回声补回「读码前 / 禁 cat 全文 / 只用行段」（无行为变化）。
- `card frontend-developer v14`：三段阶梯改单源指针（保留硬红线一句 + 单源去处）。
- `card infra-engineer v6`：三段阶梯改单源指针；P3 回声补回「读码前 / 禁 cat 全文 / 只用行段」（无行为变化）。
- `card product-manager v38`：验收读码三段阶梯改单源指针；卡内不再复写阶梯全文。
- `card qa v17`：三段阶梯硬红线与交付清单均改单源指针（两处判据保留、不再复写阶梯）。

## 遗留

- 无机制侧遗留。观察项：卡预算基线在**成功摘要**中仅 `-v` 可见（默认 2–3 行受 golden 约束）；失败时默认整份报告也会出现。若后续要成功摘要默认可见，需同时更新 `cases/06` 的 2 行契约，另立任务。

## QA P3 收口（本批内修）

- **P3-1 rd-be / infra 回声缺失**：两卡按需技能指针改为「**读码前**：阶梯 + CLI/回退；**禁 cat 全文 / 只用行段**」；替换原行，零增行。rd-be `version 13 → 14`、infra `5 → 6`。
- **P3-2 arch 指针退化**：PR Reviewer 行恢复显式路径 `@.agents/skills/codegraph.md`；arch `14 → 15`。
- **P3-3 arch 清单依据落点**：依据改为 `deliverable-docs.md §三「9 模块」`（并注明通用约定见 §一/§二），不再把 §三 当作通用节。
- **P3-4 报告措辞**：E1 可见面统一为「成功摘要中仅 `-v` 可见；失败时默认整份报告出现」，移除「仅 `-v` 可见」的绝对表述。
- 三卡净增：0 行（全部替换）；卡合计仍 **655 行**。
