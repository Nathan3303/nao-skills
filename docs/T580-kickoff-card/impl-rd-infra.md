# 实现报告 · T580 开工卡表格化 + 台账按批次分割（rd-infra）

- 任务：**T580** · 角色：rd-infra · Issue [#238](https://github.com/Nathan3303/nao-skills/issues/238) · 更新：2026-11-27
- 指针：PRD `docs/T580-kickoff-card/prd.md` · 卡 `kickoff.md` · 结构正文 `checklists/deliverable-docs.md` §十一

## 范围 / 不测

- **改动面**：`fleet/lib/check.sh`（新增 `check_ledger_structure` + PRD 探针加「新布局正文禁表格」）· `nao-fleet.sh`（`! 台账` 不计 warn + 摘要常驻）· `fleet/functions.txt`（+1，234）· `checklists/{deliverable-docs,pm}.md` · `skills/github-flow.md`（工作区纪律正文）· `templates/task-docs/kickoff.md.example`（新增）· `docs/tasks-state.md`（**重写为批次结构**）· `docs/tasks-archive.md`（追加 102 段 + 保真附录）· `docs/README.md`（T580 行）· `tests/t4/{run.sh,cases/06,cases/54}` · `tests/README.md`。
- **不测**：全量 `npm test`（归 QA）。
- **台账迁移口径**：历史原文**零删改**（逐行 containment 校验：迁移前 664 行非空行 → 迁移后缺失 **0**）；旧段标题随内容下沉、事实字段（sha / Issue / PR / 数字）一字未改；未新增解释性文字到历史段。

## 环境与命令

```bash
bash .agents/scripts/nao-fleet.sh check        # rc=0 · roles=7 · files=71
bash tests/t4/run.sh --case 54                 # 新增用例（先红 10 项 → 绿）
bash tests/t4/run.sh --case 06                 # 函数锚 234 三向守恒 / files golden / 用例编号末位 54
bash tests/t4/run.sh --case 53 --case 36       # T579 索引探针 + PRD 探针回归
```

## 结果

- **先红后绿**：`cases/54` 首跑 `RESULT: FAIL (10 项断言未过)` → 实现后台账/文档到位 ⇒ `RESULT: PASS`（28 条断言）。
- **台账**：**804 → 195 行**（≤300 目标达成）；`##` 活批次 1（T580）· 批次索引 102 行 · 归档锚点 102 个（探针双向核）。
- **搬迁保真**：迁移前非空行 664 → 缺失 0；`已合并`/`PR [`/`Issue [#` 三类血统计数在「状态+归档」合并面上不减少。
- **性能**：`check` 增量（台账探针 + PRD 表格扫描）实测 < 30ms（同一夹具 5 次取中位）。
- **敏感值**：改动文件按 token / 私钥头 / 绝对家目录三类模式 grep ⇒ 命中 0。
- **未过**：无。**偏离**：① 工作区纪律的「warn-only 软闸」（`.git/worktrees` 非空 ⇒ 一条提示）本批**未实现** —— 常驻提示在多数工作区恒触发（porcelain 非空是常态），噪声 > 收益；AC11 本身不要求机判。② 角色卡未加指针（避免 5 张卡 bump + 广播的批外成本），正文已单源在 `github-flow.md`；如需指针请指派。

## 缺陷与风险

- 批次索引 102 行是迁移现实（历史约百批次），仍 ≤300；后续每批增量 1 行。
- 归档段里的历史表格行以「原文行」形式保留（不重复表头），`grep` 与事实核对不受影响。
- 探针只认逐字表头；markdown 变体判「结构非法」，不给容错（与 §十 同口径）。

## 建议

放行前请 QA 复核 `cases/54` 与台账迁移保真（建议 `grep -c` 血统字段对照本报告数字）。
