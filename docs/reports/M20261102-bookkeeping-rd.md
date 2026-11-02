# RD 报告：台账卫生小批 · 机制文本两处（M20261102 · v0.21.2）

- 状态：待 QA 独立复核 · 更新：2026-11-02 · Owner：rd-infra
- 指针：立项 `docs/tasks-state.md`（M20261102 首行）· 分支 `nao/bookkeeping-20261102` · 基线 `42dce3f`

## TL;DR

- **做了什么**：把两条已在用但没有落文本的口径写进机制文本 —— A `T536-O4`（发布说明状态行**禁提前写「已核验」**）落 `.agents/common/release-notes.md`；B `gh release create --target <短 sha>` 实测不可用、改走 `git tag -a` + `--verify-tag` 降级落 `.agents/skills/github-flow.md`。
- **结论**：三处均为**就近插入、零重排**；无新增章节骨架、无表格、无角色卡改动（不需 bump）。
- **影响面**：纯文档口径，零机制代码改动 —— `nao-fleet.sh` / `tests/t4/**` / `roles.yaml` 全未触碰（diff = 0）。
- **待办**：QA 轻量复核 → PM 验收 → squash → v0.21.2 发布。

## 一、范围 / 不测

- 范围：`.agents/common/release-notes.md`（硬约束 + 结构 + 核对 + 红线）· `.agents/skills/github-flow.md`（发布节一句）· `.agents/templates/release-notes.md.example`（骨架状态行）· `tests/README.md`（计数口径补一句，PM 订正追加）。
- 不测 / 不碰：`docs/**` 其余部分（PM 已完成）· 角色卡 `.agents/prompts/**`（无 bump）· `nao-fleet.sh` · `tests/t4/**`。

## 二、改动（A/B/C = 3 文件 · +5 −1；O2–O4 追加 = 1 文件 · +5 −0；合计 4 文件 · +10 −1）

- `.agents/common/release-notes.md` §一 新增第 6 条硬约束：状态行 **npm 核验前只能写「待核验」**；顺序固定 = 待核验 → 按唯一判据核验（`dist-tags.latest` = 该版本 + `dist.integrity` 与本地 `npm pack` tarball 逐字节一致）→ 回填实测值（latest + integrity 全文 + tarball 字节数）；附 v0.20.4 假陈述理由（QA P1）。
- `.agents/common/release-notes.md` §二 新增一条：状态行写法与「未核验前一律写待核验」口径，指向 §一.6。
- `.agents/skills/github-flow.md` 发布节新增一条：`gh release create <tag> --target <短 sha>` 会报 `tag_name is not a valid tag` / `target_commitish is invalid`（v0.21.0 / v0.21.1 两次实测）⇒ 正确路径 `git tag -a` → `git push origin <tag>` → `gh release create <tag> --title <裸版本号> --notes-file <file> --verify-tag`。
- `tests/README.md`「计数可见」条末尾补一句：**门禁回执的用例数一律用 `run.sh --list | tail -n +2 | wc -l`，不得用最大编号**（`11` 已退役；PM / QA / RD 三侧同一口径）—— 本批 RD 回执曾把最大编号 `21` 误当例数（同型第 3 次），以此句落防线。
- **O2/O4 追加** `.agents/common/release-notes.md`（+3）：§四「发布前核对」新增一条（状态行须是「待核验」，口径见 §一.6）· §五「红线」新增一条（npm 核验前写「已核验」即违规）· §一.6 补半句消解字面张力（**状态行属元数据行，不受 §一.2 下沉禁令约束**，integrity 全文 + tarball 字节数置顶可见）。
- **O3 追加** `.agents/templates/release-notes.md.example`（+2）：骨架标题下补状态行 `- 状态：待核验 · 更新：YYYY-MM-DD · Owner：PM`（与 §二「标题下第一行」对齐）。

## 三、门禁（精确数字）

- `bash .agents/scripts/nao-fleet.sh check`：**rc=0** · `roles=6` · `files=50` · `layout=main-row2` · codegraph 齐备。
- `npm test`：**rc=0** · **PASS=20**（用例数口径同下）· `SKIP=0 · DEGRADE=0 · NOTE=2`（NOTE 白名单 2 条 = `06:static-contract` ×2）。
- `tests/t4` 全量 20 例：**PASS=20** · SKIP=0 · DEGRADE=0 · NOTE=2（白名单）。
  - 用例数口径 = `bash tests/t4/run.sh --list | tail -n +2 | wc -l`（首行是表头；最大编号 ≠ 例数，编号 `11` 已退役）。
- `npm run test:t4:full`：**rc=0** · `RESULT: PASS` · 非白名单 NOTE=0。
  - 稳定性观察（后补）：共跑 5 次，**2 次 FAIL** 均为用例 02 的真 `pi` 动态注册检查 `rc=124`（`timeout 120` 超时、`stdout` 已出 82,900 B）⇒ `SKIP=1` 触发发布闸门；紧接着连跑 **2 次 PASS**。与本次改动无关（只改 markdown），属**网络慢导致的环境抖动**。
- `roles.yaml` diff：**0** 行 · 未提交改动（除本报告）0 · 未推送 0。
- 文本自检：三文件 CRLF=0（全 LF）· 未新增表格 · 未新增绝对家目录 / token 类字面。
- **行数口径**：改动行数一律以 `git diff --numstat` 为准（本批复算：`release-notes.md` +3/−0 · `github-flow.md` +1/−0 · `tests/README.md` +1/−1 ⇒ **+5 −1**）；不得按「新增了几句话」估数（与「两文件→三文件」同型，已第 2 次笔误）。

## 四、风险 / 遗留

- 无阻塞。`M20261102-F1`（`check` 对 legacy 同名机制卡跳过冲突检查）仍为观察项（到期 2026-12-31，PM 已登记），本批不处理。
- 观察（新增 · 非本批引入）：`test:t4:full` 的用例 02 跑真 `pi`，网络慢时以 `timeout 120` 超时 ⇒ `SKIP=1` ⇒ 发布闸门误红。三出口 = **转台账观察（建议编号 `M20261102-F2`）· 到期 2026-12-31 · owner rd-infra**；处置候选：超时上调或把「真 pi 慢」与「无凭据」分开计数（需独立任务，勿在本批夹带）。
