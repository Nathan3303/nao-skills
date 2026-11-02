# T538 门禁数字可复现口径 —— 交付报告（rd-infra）

- 状态：待 QA 复核改判 · 更新：2026-11-02 · Owner：rd-infra
- 指针：`docs/prds/2026-11-02-gate-number-provenance.md`（AC1–AC5 + D1–D4）· QA 点检 `docs/reports/T538-gate-number-provenance-qa.md`

## TL;DR

- 做了什么：回执「测试」字段三件套（静默工作区 / HEAD sha / 命令 + 输出）+ 不合格反例；四条取数命令正文集中 `tests/README.md`；**两份可复制的回执模板与协议硬性条同步三件套**；PM/QA/RD 三侧只留指针；清单条数零漂移。
- 结论：AC2–AC5 过；AC1 的生效路径在 QA 点检（CONDITIONAL）后已补全 —— 照模板填不再产出不合格回执。
- 边界：只改文本，脚本与门禁实现零改动；本批**只合并不发版**（合并后 main 机制文本领先 npm 0.21.2）。
- 待办：QA 确认改判 AC1 → PM 验收 → squash 合并 → 随下次发布进 release notes。

## 变更清单（7 个机制文件 + 本报告 = 8）

- `.agents/common/output-format.md`「回执硬性」第 3 条：三件套三条（静默工作区 = `git status --porcelain` 空 + 同 worktree 无并行会话跑门禁；HEAD sha；命令 + 输出，禁「我数了 N」）+ 一条**不合格回执反例**写明「据此打回」。
- `tests/README.md`：新增「取数命令四条（全仓单源）」——用例数 / 断言数 / `files=` / 变更行数与文件数，各带「何时用 + 易错点」，并写明正文只在本处、三侧只留指针、不符即打回。
- `.agents/checklists/pm.md`:110 改指针（删内嵌命令串）；`qa.md`:23、`rd-infra.md`:19 在**既有条目内**补同源指针（不新增条目）。
- `.agents/checklists/comm-templates.md`：`lite`/`full` 两份模板 `测试：` 段补 `HEAD=`（跑门禁时短 sha）· `工作区=<静默|非静默(原因)>` · 每个计数数字后跟「命令 → 输出」；`commit=` 标注「交付提交（**≠ 门禁 HEAD**）」+ 一条指向 `output-format.md`「回执硬性」第 3 条的指针（不复写三件套）。
- `.agents/common/intercom-protocol.md` 终态回执硬性条：同步三件套 + 同源指针（该处原为旧口径）。

> 口径订正（PM 2026-11-02）：原标题「8 文件」未声明是否含本报告；实测机制文件 **7**（output-format / tests-README / pm / qa / rd-infra / comm-templates / intercom-protocol）+ 本报告 **1** = 8。QA 的「tests/README.md 重复计入」判断不成立（清单内该文件仅出现 1 次）。

## QA CONDITIONAL 补丁（`0f24293` · P1-a / P3-a / P3-c）

- **P1-a**：模板与协议条（上两条）—— 此前「照模板填即产不合格回执」，AC1 生效路径被自身模板截断；补后模板字段即三件套形态。
- **P3-a**：`tests/README.md` 取数命令节补「**复核范围 = `.agents/**` + 本文件**；`docs/**` 历史文档引用不计『正文唯一』违规」。
- **P3-c**：`files=` 易错点补「`NAO_SKILLS` 未设置时该 `find` 向 stderr 报错、而**管道 rc 仍为 0**」⇒ 属「计数静默得 0、报错不静默」。
- 约束遵守：零新增 `- [ ]` 条目（`94/32/22` 不变）· 无表格 · 无新章节骨架 · 全 LF · 四条命令串仍各 1 次。

## 门禁（HEAD `0f24293` · `git status --porcelain` 为空 · 本会话独占 worktree）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=6 · files=50 · layout=main-row2` · rc=0
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · rc=0 · 断言 **694**
- 用例数 = `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **20**（不以最大编号 21 推断）
- `files=` 交叉 = `find "$NAO_SKILLS/.agents" -type f | wc -l` → **50**（= `check`）
- `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · rc=0 ⇒ **非白名单 NOTE=0**
- 变更（首轮）= `git show --shortstat --oneline 2df07f9` → `5 files changed, 15 insertions(+), 5 deletions(-)`
- `git diff 4346bb4..HEAD -- .agents/roles.yaml` → 0 行；`nao-fleet.sh` / `tests/t4/**` 未触碰

## AC 自证

- **AC1**：三件套 + 反例在 `output-format.md`；**模板侧**（`comm-templates.md` ×2）与**协议侧**（`intercom-protocol.md`）已同步 ⇒ 复制模板即合格。
- **AC2**：四条命令串在 `.agents/**` + `tests/README.md` 字面命中各 **1** 次（补丁后复跑仍 1/1/1/1）；三份清单内命中 **0**。改前→改后：用例数 `3→1`、断言数 `1→1`（迁位）、`files=` `1→1`（迁位）、行数 `0→1`。
- **AC3**：`qa.md:23` / `rd-infra.md:19` 各一条指向单源的条目（既有红线内，风格贴合）。
- **AC4**：`grep -c '^- \[ \]\|^| '` = `pm 94` · `qa 32` · `rd-infra 22`，补丁前后均不变。
- **AC5**：见上「门禁」。

## 风险与已知边界

- 两轮门禁（`2df07f9` 机制文本 / `0f24293` 补充后）同数字：`check` rc=0 files=50 · `npm test` rc=0 例数 20 断言 694 · `test:t4:full` rc=0。审查实效只能靠观察：下 2 批回执若仍缺 HEAD / 命令 / 输出，即视为本批未生效（PRD §八 监控项）。

- 修订：2026-11-02 补 QA P1-a/P3-a/P3-c 后门禁复跑同数字。
