# 台账载体 B2（引用规范 + stash 闸门）实现报告（#126 · M20261114-ledger）

- 状态：待 PM 验收（RD 自验完成，待 QA 非作者复核）· 更新：2026-11-14 · Owner：rd-infra
- 指针：Issue [#126](https://github.com/Nathan3303/nao-skills/issues/126) · 上游依据 `docs/reports/118-mechanism-review.md` §四（BR5 批间收尾）+ §批次 B · 分支 `nao/M20261114-ledger`（HEAD 见回执）· 新增用例 `tests/t4/cases/35-stash-residue-warn.sh` · 本批不发版
- 范围：**只做 B2**（B2-1 机制文本 / B2-2 脚本闸门）。B1（台账 L1/L2/T4 + #118 报告 T6 撤回）由 PM 在分支首提交 `d56a6ba` 交付，本批**未碰** `docs/tasks-state.md` 与 `docs/reports/118-*.md`。

## 结论（TL;DR）

- 目标：① 给「引用易变载体」定纪律（禁裸行号，须「条目 ID + as-of sha + 唯一 locator」）；② 给 `check` 加一条 **stash 滞留**机械闸（`git stash list` 非空 ⇒ 一条 warn，**不改 rc**；空 / 不适用 ⇒ 零输出）。
- 做法：`github-flow.md` 新增 **BR7 引用纪律** 3 行 + BR5 一句指针（闸门存在性）；`checklists/pm.md` **只加指针**（复用既有勾选项，不加条目 ⇒ 条数 34/44 与 PM 卡版本均不变，无双源、无计数漂移）；`nao-fleet.sh` 新增 `check_stash_residue`（与 `check_backend_premise` 同形态：单点实现 + 单点调用 `|| true`、进摘要 `warn=N`、`-v` 面一条 `  ! `）。
- 根可注入（PM 硬要求）：`NAO_STASH_ROOT` ⇒ 默认 `$SKILLS_DIR`；**根上无 `.git` ⇒ 零输出且不向上 walk** ⇒ 用例只在 `mktemp -d` 的临时仓造/弹 stash，**真实仓库 stash 全程 0**。
- 结果：AC 全过（B2-1 三判据 + B2-2 五判据）；**先红后绿**（实现前 `cases/35` 12 条断言红 → 实现后 36 PASS，连跑 3 次同形）；`check` rc=0 ×2 输出逐字一致（`files=54` 不变）；`cases/06` / `cases/28` PASS；`npm test` 与双后端 gate 全绿（tmux 1783 / herdr 1925 PASS，SKIP=0/DEGRADE=0/非白名单 NOTE=0）。
- 影响：一处 warn（只读，零自动处置）+ 文本纪律；未改任何契约/版本/发布面。
- 回退：`git revert <合并 sha>` 一条命令。

## 改动

- `.agents/skills/github-flow.md`（§文档与台账载体，新增 3 行 + 1 句指针）：
  - **BR7 引用纪律**：易变载体（`docs/tasks-state.md` 这类高频编辑文件）引用须「**条目 ID + as-of `<sha>` + locator**」，禁裸行号；附**实测漂移**（`T543` 行在 `fa87517`→`ce94b5b`→`929b51d` 由 `:430` → `:433` → `:434`）。
  - **locator 必须唯一且可自证**（`grep -c` = 1）：用行首锚定形 `^| \*\*T543\*\* |`；非锚定 / 正文短语不可用（实测 `O2 转办 2026-12-31` = **5** 命中；`| **T543** |` 在 HEAD = **2**）。
  - **稳定载体（角色卡 / 清单 / 脚本 / ADR）仍可用行号**；易变与稳定混引时整段按易变处理。
  - **读侧校验（as-of）**：以 `git show <sha>:<path>` 为准；as-of 过期 ⇒ 用条目 ID + locator 重新定位，不跟随行号。
  - BR5（批间收尾）句末加一句**指针**：`check` 见 stash 非空 ⇒ 一条 warn、不改 rc（细则仍只在 BR7 同节，不复制）。
- `.agents/checklists/pm.md`（**只加指针，不加勾选项**）：既有「为文档 / 台账单开 PR」条追加「引用易变载体禁裸行号 ⇒ 条目 ID + as-of sha + 唯一 locator，细则只写一处 = `github-flow.md` §BR7」。条数保持 34/44（未动标题与 PM 卡 `34 项/44 项` 文案）。
- `.agents/scripts/nao-fleet.sh`：新增 `check_stash_residue`（根 = `${NAO_STASH_ROOT:-$SKILLS_DIR}`；`[[ -e "$root/.git" ]]` 不满足即 `return 0`；`git -C "$root" stash list` 计数 + `-1 --format='%s'` 取最新一条消息；非空 ⇒ 一条 `  ! `，含条数、根（相对 `$SKILLS_DIR` 显示，等于根时显示 `.`）、`BR5`、`pop 或归口`、最新消息）+ `cmd_check` 内单点调用 `check_stash_residue || true`（放在「PR 模板（GitHub Flow）」节后，Git 卫生语境）。
- 测试：新增 `cases/35`（36 断言、7 组）；`run.sh` 注册 `35`；`backends/herdr.txt` 登记 `35 shared —`；`tests/README.md` 计数同步（**共享 21→22 · 33→34 例**）+ 用例表增行；`cases/06` 扫描面硬编码 `33 → 34`（并点名 `#126 增 cases/35`）。

## 先红后绿（B2-2 AC③）

- 先写用例（未实现）：`bash tests/t4/run.sh --case 35` ⇒ `RESULT: FAIL (12 项断言未过)` —— 红点 = `B2`（恰 1 条 warn）/`B2b`（条数文案）/`B3`（BR5）/`B4`（pop）/`B5`（归口）/`B6`（点名最新消息）/`B8`（摘要 `warn=1`）/`D2`（多条仍一条）/`D3`（条数=2）/`G1`（单点定义+调用）/`G2`（`|| true`）/`G3`（`NAO_STASH_ROOT` 可注入）。
- 实现后：`RESULT: PASS`（**36 PASS**），连跑 3 次同形。
- 双向（AC④）：造 stash ⇒ 出现（B 组）；`git stash pop` ⇒ 消失（C 组）；两条 stash ⇒ **仍一条** warn 且条数=2（D 组）。
- 不适用面：不注入根（默认 `$SKILLS_DIR` = 夹具包根，非仓）与显式注入非仓目录 ⇒ **零输出**（E 组，钉住「不向上 walk」）。

## 门禁（本地实测，命令 + 数字）

- `bash .agents/scripts/nao-fleet.sh check` ×2 ⇒ rc=0 两次**逐字一致**：`check: OK · roles=7 · files=54 · layout=main-row2`。
  - `files=54` **无变化**：新增文件只落在 `tests/`（不进 `files=` 口径）；`.agents/` 内本批只改既有 3 个文件（`skills/github-flow.md`、`checklists/pm.md`、`scripts/nao-fleet.sh`）。
  - 无 stash ⇒ `check` 输出与改动前**逐字相同**（手检 = 上面三行，与 `d56a6ba` 同形）。
- `bash tests/t4/run.sh --case 06` ⇒ PASS（`NOTE=2` 均白名单；`P2④` 的 tmux check 旧 golden md5 `31b5978e…` 仍命中 ⇒ 零输出口径成立）。
- `bash tests/t4/run.sh --case 28` ⇒ PASS（C1/C2/C3 + 双拼写 md5）。
- `npm test`（默认 herdr，含 `test:agents` = `check` + `tsc`）⇒ **rc=0**，34 例全 PASS/TMUX-ONLY，`SKIP=0 · DEGRADE=0 · NOTE=10`（全白名单）。
- `npm run test:t4:full:dual`（`T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1`，两后端各一组）⇒ **rc=0**：组 1 tmux `PASS` 1783 / `SKIP=0 · DEGRADE=0 · NOTE=9`；组 2 herdr `PASS` 1925 / `SKIP=0 · DEGRADE=0 · NOTE=10`；结论行「组1 断言 tmux ✓ / 组2 断言 herdr ✓」。
- 后端登记集对账：`共享 22 / 本后端专有 10 / tmux 专有 2 / PENDING 0 = 34`，与 `--list` 计数 34 一致。
- 零副作用自证（AC⑤）：`git stash list` 在真实仓 **前=0 / 后=0**（用例 F1/F2 断言 + 全部门禁串行跑完后手检仍 0）；`git worktree list` = 1（未新建 worktree）。

## PM 判据实测偏差三处（按「先实测再报」口径）

1. **漂移行号**：pm 记 `:429`→`:432`→`:433`；实测（`git show <sha>:docs/tasks-state.md | grep -n '^| \*\*T543\*\*'`）= **`:430` → `:433` → `:434`**（三处整体 +1，判断的是同一行）。报告与文本按实测值写。
2. **正例 `grep '| **T543** |'` = 1**：在 `929b51d` 成立，但**在 HEAD = 2** —— 因为 PM 自己的 B1 新增台账条目（`docs/tasks-state.md:417`「引用规范」）把 `| **T543** |` 写进了正文 ⇒ locator 被引述后自伤。已改用行首锚定形 `^| \*\*T543\*\* |`（HEAD 实测 = 1），并把「用前先 `grep -c` 自证」写进 BR7。
3. **反例 `grep 'O2 转办 2026-12-31'` = 3**：HEAD 实测 = **5** 命中。仍是非唯一反例（结论不变），但数字按实测写。
4. 附：`tests/README.md` 的 `共享 N / M 例` 汇总行在 `#124 增 case34` 那次只加了句子、没更新数字 ⇒ 改动前该行仍写 `共享 21 / 33 例`（当时事实 = 22/34）。本批已按 `--list` 与登记集实测同步为 **22 / 34**（现两者互证一致）。

## 判据映射（AC）

- B2-1：`grep -c 'as-of' .agents/skills/github-flow.md` = **3**（≥1）；新增块 = 3 行（≤4）；全仓仅 BR7 写全（`checklists/pm.md` 只指针、BR5 只一句指针）。
- B2-2 ①：`cases/35` B1/B2/B8（恰 1 条 + `warn=1` + rc=0）；②：A2/A3（空 ⇒ `^  ! ` 0、摘要无 `warn=`）；③：见「先红后绿」；④：C2（pop ⇒ 消失）；⑤：F1/F2。
- 测试纪律：`cases/35` 全部 stash 动作只发生在 `$T4_CACHE_DIR/c35/gitroot`（`git init` 自建）；被测脚本以 `NAO_STASH_ROOT` 注入该根 ⇒ **机制脚本本身只读**（静态断言 G4：无 `push|pop|apply|drop|save|clear`）。

## 遗留 / 后续（不阻断）

- `checklists/pm.md` 未新增勾选项（保持 34/44 与 PM 卡计数不变）；若 PM 认为需要独立勾选项，另立：需同时 bump 两处计数文案与 `product-manager.md` 卡版本 + 广播。
- `check_stash_residue` 根默认取 `$SKILLS_DIR` 且**要求根上即 `.git`**：npm 全局安装且直接以包目录为 `SKILLS_DIR` 时该闸不生效（下游 shim 形态 `SKILLS_DIR` = 项目根，正常生效）。如需覆盖该形态，另议「根候选列表」。
