# 实现报告 · T579 docs 按任务分割（rd-infra 侧）

- 任务：**T579** · 角色：rd-infra · Issue [#237](https://github.com/Nathan3303/nao-skills/issues/237) · 更新：2026-11-27
- 指针：PRD `docs/T579-docs-per-task/prd.md` · 评审 `arch-review.md` · 落点 `arch-landing-list.md` · ADR `adr-docs-per-task.md`

## 范围 / 不测

- **改动面**（14 改 + 4 新增）：`fleet/lib/check.sh`（PRD 探针扩面 + 新 `check_docs_index`）· `nao-fleet.sh`（摘要排除 + 常驻回显）· `fleet/functions.txt`（+1 函数锚）· `checklists/{deliverable-docs,pm,qa,rd-infra}.md` · `common/{intercom-protocol,release-notes}.md` · `skills/{github-flow,arch-patterns}.md` · `docs/README.md`（删「停更说明」非版本行）· `tests/t4/{run.sh,cases/06,cases/53}` · 新增 `.agents/templates/task-docs/`（3 份骨架）。
- **不测**：全量 `npm test`（归 QA）。本报告只给 rd-infra 侧单条命令自查。
- **不动**：6 个冻结目录 319 文件（`git status --porcelain docs/{prds,reports,adr,designs,research,releases}` 为空）· 站点 · `docs/tasks-state.md` · 本任务 PRD/评审/ADR 正文。

## 环境与命令

```bash
bash .agents/scripts/nao-fleet.sh check            # 体检（rc=0）
bash tests/t4/run.sh --case 53                     # 索引探针持久用例（PASS）
bash tests/t4/run.sh --case 36                     # PRD 探针回归（PASS）
bash tests/t4/run.sh --case 06                     # 函数锚/用例编号/摘要 golden（PASS）
```

## 结果

- **先红后绿**：先落 `cases/53` 未实现 ⇒ `RESULT: FAIL（14 项断言未过）`；实现后 `RESULT: PASS`。
- **守卫三段证据**：正常 `check` rc=0 · 变异（删调用 / 去排除名单 / 取反幽灵判据）各必红 · 还原复绿（详见 `cases/53` N1–N3）。
- **性能**：`check -v` 探针开 1182–1202ms / 关 1171–1186ms（各 5 次）⇒ 增量约 **+11ms**（NFR ≤300ms）。
- **敏感值**：改动文件按 token / 私钥头 / 绝对家目录三类模式 grep ⇒ 命中 0（命令与模式见回执）。
- **未过**：无。

## 缺陷与风险

- **AC6 ② 的字面判据不可达**（发现即报，未自行放宽）：基线文件集的 `docs/{6 目录}/` 指针数 origin/main 1233 → 本分支 1181（**−52**，全部来自本任务按 §三/§十 有意改写的机制文本旧路径；改写文件集 = **14 个**，无第 15 个）；冻结目录文件集与行数 diff 为空；**未改写面 Δ = 0**（口径：排除本任务全部改动文件后统计该 6 目录指针数，origin/main 与本分支相等；绝对值随排除口径浮动，故只主张差值）。判据已由 PM 定稿为「冻结目录 diff 空 + 可枚举的 14 文件 + 只允许路径/指针变更」。
- 索引是单点：PM 忘加行 ⇒ `check` 摘要常驻回显（已实现），「删一行必须红」由 `cases/53` 承载。
- 约 8 个落点文件（`output-format.md` / `comm-templates.md` / `skills/{test-design,task-completion,pm-to-spec,pm-operations,research,design-loop}.md`）仍写旧路径 —— 按派单 Owner 归 PM（落点清单 §二/§八/§九），本 PR 未改。

## 建议

放行前请 PM 裁 AC6 ② 判据（建议改为「未改写文件内指针数不变 + 冻结目录 diff 为空」）。其余 AC 按回执逐条附命令与输出。
