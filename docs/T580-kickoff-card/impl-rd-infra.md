# 实现报告 · T580 开工卡表格化 + 台账按批次分割（rd-infra）

- 任务：**T580** · 角色：rd-infra · Issue [#238](https://github.com/Nathan3303/nao-fleet/issues/238) · 更新：2026-11-27
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
- **未过**：无。**偏离（明示，不留沉默省略）**：

1. **工作区纪律的 warn-only 软闸未实现**（`.git/worktrees` 非空 / `git status --porcelain` 非空 ⇒ 一条提示）。**理由**：正常干活时两者恒为真（本仓 `.pi/` 长期未跟踪）⇒ 常驻噪声，最终所有人都学会无视该行；AC11 本身明示「不承诺机判」。**去向**：PM 已裁定接受不做，登记 T583 观察（到期回看是否有「真被切分支卷走」的复发）。
2. **角色卡未加指针**（`.agents/prompts/*.md` 内 `git worktree add` 计数 0）。**理由**：正文已单源在 `skills/github-flow.md`（每个任务必读的流程文件）；改卡要 bump + 全员广播，无人值守期广播只能写留档、等于半成品。**去向**：PM 已裁定本批接受不补，随 T583 A 批与其它卡改动一起做。

## 缺陷与风险

- 批次索引 102 行是迁移现实（历史约百批次），仍 ≤300；后续每批增量 1 行。
- 归档段里的历史表格行以「原文行」形式保留（不重复表头），`grep` 与事实核对不受影响。
- 探针只认逐字表头；markdown 变体判「结构非法」，不给容错（与 §十 同口径）。

## 建议

放行前请 QA 复核 `cases/54` 与台账迁移保真（建议 `grep -c` 血统字段对照本报告数字）。
