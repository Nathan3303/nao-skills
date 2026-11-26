# T576 文档站逐页终勾（user-guide-writing · 质量门禁）

- 状态：已定稿（复勾 **GO**） · 更新：2026-11-26 · Owner：qa
- 指针：Issue [#217](https://github.com/Nathan3303/nao-skills/issues/217) · 规范 `.agents/skills/user-guide-writing/SKILL.md` §一/§二/§五 · 勾表 `docs/reports/576-doc-skill-gate.md` · 清单 `docs/reports/576-doc-skill-audit.md` · 被测 `ff32b6f`

## TL;DR

- **GO**（上轮 CONDITIONAL → 复勾后 GO）：两条阻断已在 `44bf324`（PR #241）闭合，其余 20 页沿用本轮结论，无新红。
- 判定点 **287** = 286 格（22 页 × 13 条）+ 1 专项（`quickstart/fleet` golden）：**过 201 · N-A 84 · 红 2（原阻断，已闭合）**；**20 页零红**。
- 建议 34 条 / 17 页（长句、少数首现未解释词、措辞），按 §五「建议项不是 KPI」只列不改、不阻断。
- 范围比审计清单多一页：`quickstart/logs.md`（批 2 后新增）⇒ 22 页 / 1241 行；按 B 档判。

## 复勾（只判两条 · `44bf324`）→ GO

- `npm --prefix apps/document run build` → rc=0（4.06s，22 页 + 404）。
- `dist/how/task-journey.html`：`使用者` 命中 **0**；新句「给用你这个产品的人看的那份」命中 1；全站 `grep -rn '用户\|操作者\|使用者' content/` → **0 命中**。
- `dist/quickstart/fleet.html`：`files=67` 命中 1 / `files=69` 命中 **0**；:27「随版本变…`roles=7` 才是判据」仍在。
- 同源复核（脚本）：index 6 问 / faq 命中 5 / **逐字一致 5**（第 6 问「要花钱吗」属首页子集，上轮已记录）。

## 命令与数字（逐字）

```bash
bash .agents/scripts/nao-fleet.sh check                        # rc=0 · check: OK · roles=7 · files=67
find .agents -type f ! -path '*/.nao-obsolete/*' | wc -l       # 67（与 check 的 files= 同口径，非最大编号推断）
npm --prefix apps/document run build                           # rc=0 · build complete in 4.10s · dist 23 html（22 页 + 404）
```

- 渲染抽查（规范 §四「看渲染，不看源」）：`dist/quickstart/fleet.html` 的三行 golden 与 `←` 注记逐行渲染、无并段；`dist/roles/*.html` 的 ` ```card ` 渲染成卡片区（**不是代码块**）⇒ `§二.5` 不因组件载体判红；`dist/faq.html` 的 `<details>` 折叠正常、`index.html` 的 `command:`/`terminal:` 模拟与 `faq ↔ index` 5 条问答逐字一致（脚本比对：5/5 SAME）。
- 逐页 13 条按勾表 §一；`N-A` 口径 = 该页**没有这个元素**（无表格 / 无加粗 / 无代码 / 无提示块 / 无折叠 / `index` 无 Markdown 标题与列表），规则无可违反，不记过。

## 红旗（2 处 · 原阻断，均已闭合）

- 〔已闭〕`how/task-journey.md:17` · `§一.1` · 实际「发版说明（给使用者看的那份）」 · 期望「给用你这个产品的人看的那份」（`git log -S'使用者'`：由「面向用户」改来 ⇒ 同义词替换绕规则，与「用户」同罪）。
- 〔已闭〕`quickstart/fleet.md:22` · 勾表 `§二.5` / 规范 `§二.10` · 实际 `files=69`（0.34.0 的数） · 期望 `files=67`；或删掉具体数字只留 `roles=7`（:27 那句「随版本变，对不上不算装坏」保留）。

## 逐页（过 / N-A / 红；建议只记不改）

A 档 13 页

- `faq.md`：10 / 3 / 0 — 建议 2（:12、:33 长句 117·157 字；「接续快照」「台账」首现未解释）。`<details>` 12 个 = FAQ 按需展开，勾表 §一.13 明确允许。
- `glossary.md`：9 / 4 / 0 — 建议 2（「元数据」「系统提示」「workspace」定义句内未解释；:24、:25 长句）。专项判据全过：`scope` 保留「已弃用 + 一句现状」、术语名不再整名加粗（加粗 0 处）、`rd-be-T1` 类示例已去。
- `roles/arch-designer.md`：10 / 3 / 0 — 建议 1（:25「纯 CRUD」未解释）；3 处加粗 = 并列「典型误用」标签，判例允许。
- `roles/pm.md`：10 / 3 / 0 — 建议 1（:25「轻通道」未解释）。
- `roles/qa.md`：10 / 3 / 0 — 建议 1（:23「负向闭环」未解释）。
- `roles/rd-be.md` · `roles/rd-fe.md` · `roles/rd-infra.md`：各 10 / 3 / 0 — 零建议（接口 / 契约 / 不变量首现即解释；`exit 0` 已改「命令没报错」）。
- `roles/uiux-designer.md`：10 / 3 / 0 — 建议 2（「设计变量」与 `index.md:211`「视觉令牌」同一事物两名；「断点」未解释）。
- `how/acceptance.md`：9 / 4 / 0 — 建议 2（:18 长句 90 字；「归口」未解释）；专项过：回执代码块保留、:19 已标「换成你项目的检查命令与条数」。
- `how/task-journey.md`：7 / 5 / **1** — 建议 3（第 7 站一条塞三动作；「台账」「开工确认卡」首现未解释；:25 长句）。
- `collab/dispatch.md`：9 / 4 / 0 — 建议 2（:35 长句 115 字；:7「七个人格」未解释）；`--scope` / `fleet-scope` 弃用口径与 `ensure <角色>@<仓>` 经脚本核对一致。
- `collab/conflict.md`：8 / 5 / 0 — 零建议（「破坏性契约改动」已改「会破坏对外承诺的改动」，有序列表用法正确）。

B 档 8 页 + 新增 1 页

- `quickstart/prereq.md`：9 / 4 / 0 — 建议 2（「pane」首现未解释；:26 长句）；`herdr integration install pi` 经 `herdr integration status` 核对（pi: current）。
- `quickstart/install.md`：9 / 4 / 0 — 建议 2（示例 pin 用 `@0.24.0`，落后 11 个版本易被照抄；:14、:40 长句）；`.pi/npm` 物化 + gitignore 与 `docs/INSTALL.md:287` 一致。
- `quickstart/fleet.md`：9 / 4 / **1（专项）** — 建议 1（:52 长句 116 字）；别名 `arch`/`infra`、`close --task T1 rd-be` 参数序、`status --json` 均经脚本核对一致。
- `quickstart/troubleshoot.md`：10 / 3 / 0 — 建议 2（:23「同上——」断成残句；:21 长句）；3 列 × 5 行表格合规，返回码 0/1/2/3 与 `exit 3` 前提闸门一致。
- `advanced/custom-cards.md`：9 / 4 / 0 — 建议 3（:36「fork 或 overlay」未解释；`<file>` 占位符易被照抄；:34/:40「一、/二、」是伪小标题）；专项过：模板内 `## 一、职责` 与 frontmatter 按**位置判定**（围栏 :11–:23）属照抄件，不算违规；256 KiB / `--as` 前缀 / 必须在 `<repo>/.agents/prompts/` 均与 `resolve_card` 一致。
- `advanced/multi-project.md`：9 / 4 / 0 — 建议 3（4 处长句；:8「供不了团队」措辞；:15 的 `<角色>[<槽位号>]` 是机制元记号、合规，但就地补 `rd-be`/`rd-be2` 例子更省事）；`@main` = manifest 所在仓、scope 家族弃用 均经 `fleet_repo_resolve` / `--fleet` 守卫核对一致。
- `plugins.md`：8 / 5 / 0 — 建议 2（:21「自动——你没有直接操作它的时候」绕；:56 长句 99 字）；5 个插件名与包名逐个对上 `bin/nao-skill.js:97-101`。
- `index.md`：6 / 7 / 0 — 建议 3（`ADR`/`视觉令牌`/`CI` 首现未解释；「会话窗口」与「会话」混用；「派活 / 派发」两名）；专项过：首屏 `command:`/`terminal:` 保留、`check` 后只写 7 角色、`ensure` 后写 3 个会话（数字归属正确，无「体检后 7 个窗口」反例）。
- `quickstart/logs.md`（**新页，超出 21 页基线**）：10 / 3 / 0 — 零建议（「会留多久」两列两行表：勾表 §三 把「两列短内容用表格」列为硬项，但条件→时长属多行多列对应关系、单元格不短 ⇒ **不红**，已由 PM 2026-11-26 裁定接受，判例随 T580 补进勾表附录）。事实核对全过：目录形状 `--<编码仓路径>--`、24h/7 天、`.retention.log` 点名、`--raw/--list/--task/--repo/--purge --days`、`ctrl+n`/`ctrl+d`（`pi/docs/keybindings.md:143/145`）、「删除 N 条」。

## 建议汇总（页级 34 条 / 44 处 / 17 页，不阻断）

- **首现未解释词（18 处）**：`faq` 接续快照/台账 · `glossary` 元数据/系统提示/workspace · `roles/arch-designer` CRUD · `roles/pm` 轻通道 · `roles/qa` 负向闭环 · `roles/uiux-designer` 断点 · `how/acceptance` 归口 · `how/task-journey` 台账/开工确认卡 · `collab/dispatch` 人格 · `quickstart/prereq` pane · `advanced/custom-cards` fork/overlay · `index` ADR/视觉令牌/CI。
- **长句（>70 字，15 处 / 10 页）**：`faq:12,33` · `how/acceptance:18` · `how/task-journey:25` · `collab/dispatch:35` · `quickstart/prereq:26` · `install:14,40` · `fleet:52` · `troubleshoot:21` · `plugins:56` · `multi-project:4,8,12,17`。规则是 [建议]（§五），且多数是带行内代码的清单项，字数被代码拉高，拆句收益有限。
- **措辞 / 形态（11 处）**：`index` 会话窗口·派活/派发 · `uiux-designer` 设计变量 vs 视觉令牌 · `task-journey` 第 7 站三动作 · `install` 示例 `@0.24.0` · `troubleshoot:23` 同上—— · `custom-cards` `<file>` 与「一、/二、」 · `multi-project:8` 供不了团队 / :15 补例子 · `plugins:21` 自动—— · `faq` 无（`index` 的「要花钱吗」不在 faq，属首页子集，不是同源复制）。

## 判定与口径

- 顺序按勾表：先 `[阻断]`（会让读者做错 / 看不懂）→ 再 `[建议]` → 最后才看总量。故 2 红优先于 34 建议；183 处加粗那类总量问题已在批 2 消掉（现存加粗 25 处，最多 1 处/行，全部为关键动作或并列项标签）。
- 判定前先核过「看起来像错」的两处：`<角色>[<槽位号>]` = 机制元记号（见上）；`troubleshoot.md` 3 列表格 = 多行多列对应关系（合规），`logs.md` 2 列表格 = 条件→时长对应、**PM 裁定接受**（判例随 T580 补进勾表附录）。
- `CONDITIONAL` 的依据：阻断项均为**单点机械修正且不涉及示例/模板**；`GO` 需要这两条改完复勾。`NO-GO` 不成立（没有被改坏的模板、没有删掉的命令、没有读不通的步骤）。
- 未覆盖：`check` 的 `files=` 只在本机（机制包根）实测；如果发布包文件集与本仓 `.agents/` 不同，`67` 需按发布包复核一次（这条是数字口径风险，不是页面问题）。

- 修订：2026-11-26 首版（22 页逐页终勾 + 两处阻断）· 2026-11-26 按 PM 裁定：`logs.md` 两列表格判不红（不记建议），待复勾范围收为两条阻断 · 2026-11-26 复勾 `44bf324`：两条闭，**GO**。
