# #126 台账载体 B2 非作者复核（QA）

- 状态：**CONDITIONAL**（1×P1 须修 · 2×P2 待裁 · 2×P3）· 2026-11-15 · 独立复核，不采信 RD/PM 自述
- 对象：分支 `nao/M20261114-ledger` as-of **`dd8d8e1`** · PR [#127](https://github.com/Nathan3303/nao-skills/pull/127) · Issue [#126](https://github.com/Nathan3303/nao-skills/issues/126)
- 纪律：全程只读；先红演练在**仓副本**（`cp -a` 到 `/tmp`）里做，真实仓 5 个被复核文件 md5 前后一致；未 checkout/switch、未在真实仓造 stash。

## 一、逐项结论（对 PM 的 7 条）

1. **stash warn 双向自做 = 成立**。临时 `git init` 仓 + `NAO_STASH_ROOT` 注入：1 条 stash ⇒ `  ! git stash 非空（1 条 …BR5…pop…归口…最新一条=…）`、`warn=1`、rc=0；`stash pop` ⇒ 零输出、摘要无 `warn=`；不注入（根非仓）/注入非仓目录/**注入仓内子目录**（根上无 `.git`）⇒ 均零输出（「不向上 walk」实测成立）。真实仓 `git stash list | grep -c .` = **0**（开工前/全部门禁后）、`git worktree list | wc -l` = **1**。
2. **先红成立且红点同形**：副本内换回 `main` 版脚本 ⇒ `--case 35` = `FAIL (12 项)`，红点恰为 B2 / B2b / B3 / B4 / B5 / B6 / B8 / D2 / D3 / G1 / G2 / G3（A 组无 stash 仍绿 ⇒ 非空转）。还原后 36 PASS，连跑 3 次同形。
3. **BR7 只写一处 = 成立**：`grep -c 'as-of' .agents/skills/github-flow.md` = **3**；全 `.agents/` 仅 2 文件命中（`github-flow.md` 3 · `checklists/pm.md` 1，且后者只是勾选项内指针）。`pm.md` diff = 1 行、`grep -c '\[ \]'` 95 = main 95、头部「34/44」文案未动；`prompts/` 零 diff ⇒ PM 卡仍 **v37**。
4. **台账口径 = 部分过（P1/P2 见 §二）**：三档表 **12 → 18 行**成立；但两条「转办 ⇒ 队列」在队列里**无行**，且 6 条新行**均无判定命令**。⑫ 数字：@`705fd69` 实测 `wc -l` = **4298**、函数 = **135** ✓；`cmd_check` 277 可复现（不含闭括号）。
5. **T6 撤回 = 成立**（独立判）：`reports/121-impl.md:39` 已写「二轮修后 **5/6** · 三轮修后 **6/6**」，且 `:50` 位于「## 三轮修」节内 ⇒ 6/6 属实，主审原判不成立。撤回理由成立；但落点不完整（P3-1）。
6. **引用规范自伤已修**：`grep -cE '^\| \*\*T543\*\* \|' docs/tasks-state.md` = **1**（非锚定 = 2，`O2 转办 2026-12-31` = 5 —— 与 BR7 文本一致）。RD 报的「PM 判据三处实测偏差」全部复现（漂移 `430/433/434`）。
7. **门禁抽核 + 全量**：见 §三。

## 二、缺陷

### P1-1 「转办 ⇒ 队列」仍是空指针 —— L1 原始缺陷未修
`docs/tasks-state.md` 三档表两行（`as-of dd8d8e1`，locator `^| T543-O2 |` / `^| T545-cache-residue |`，第 399/400 行）都写「**队列行见「待派发队列」**」，但该表**没有**对应行：数据行仅「批次 A / 批次 B / 批次 C」3 行（A、B 已划销）。
```
sed -n '/^## 待派发队列/,/^## 观察/p' docs/tasks-state.md | grep -cE '^\| [^-: ]'   # 4（含表头）⇒ 3 数据行
grep -nE '^\| (T543-O2|T545-cache-residue) \|' docs/tasks-state.md               # 仅 399 / 400（三档表）
grep -n 'T543-O2\|T545-cache-residue' docs/tasks-state.md                        # 其余命中 420/422，均为批次行正文
```
影响：#118 的 L1 判据是「转办必须落到队列」，本批把它**写成了规则**却仍没落载体，且新增「指向空处」的指针 —— 与 T6 同型（正文承诺 vs 事实不符）。修法：队列补两行（或删掉「转办 → 队列」标签改回「接受含到期」+ 理由）。

### P2-1 工作台有 stash 时 `cases/06` 假红（假红面 = 本批新增）
`check` 现在对**真实仓**（cwd/`SKILLS_DIR` 有 `.git`）也生效，而 `cases/06` P2④ 在 `$T4_ROOT` 里跑 check 并钉「首行逐字 + 全输出 md5」。安全复现（仓副本，真实仓不动）：
```
cp -a . /tmp/x/repo && cd /tmp/x/repo && echo a >> docs/tasks-state.md
git stash push -qm probe -- docs/tasks-state.md && bash tests/t4/run.sh --case 06
⇒ FAIL ×2：首行 `… layout=main-row2 · warn=1（-v 看详情）`（期望无 warn=）
     md5 3934a6cd…（期望 31b5978e…）；RESULT: FAIL (2 项断言未过)
```
影响面：只有「真实仓有 stash 且 codegraph 齐备」时触发；被测功能正常 ⇒ 属**假红**，且恰好发生在 BR5 正式鼓励的动作（`git stash` 保住批间事实）之后。建议（择一）：cases/06 该 4 处 check 调用统一给 `NAO_STASH_ROOT="$T4_CACHE_DIR/no-repo"`；或 md5 前剥掉 `warn=` 与 `^  ! ` 行（+ 另立一条显式断言）。本项不影响本次门禁（现仓 0 stash）。

### P2-2 6 条漏登项「判定命令」缺失 ⇒ 准入原则不可执行
三档表新增准入原则要求「到期时只需读该行 + **一个命令**即可决定关闭/续期，不需要回溯批次行」；实读 6 行：`T545-O1` / `T545-same-slug` / `96-未验三项` / `T545-cache-residue` / `T543-O2` **均无命令**（`96-未验三项` 只给 `herdr.txt` 指针），`M20261114-stash-exit` 只描述「`check` 对 `git stash list` 非空 ⇒ warn」。到期时仍须回溯 #96 / T543 / T545 报告 ⇒ 与本批要治的「只在批次行可判」同族。另 `M20261114-stash-exit` 写「本批 **A 项** 落地后」——本批分 B1/B2，无「A 项」，指代错位。修法：每行补一行判定命令，或把原则改成「可判定（命令或明确判据）+ 来源指针」并允许回溯。

### P3-1 T6 撤回未与发现行互指
`docs/reports/118-mechanism-review.md:34` 仍是完整生效的 `**T6 [P3]**` 条目（无「已撤回」标记），撤回只在 `:82`（§十一）；`docs/tasks-state.md` 已归档行仍记「**15 条发现**（T1–T6 …）」。读者只读 §四 会得到与 PM 结论相反的事实 —— 这正是 T6 原判指控的形态。修法：`:34` 行末加「**（误报 · 已于 §十一 撤回）**」。

### P3-2 ⑫ 第三个数字缺命令 + 口径歧义
台账只给两条自证命令（`wc -l` / 函数数），`cmd_check` 277 无命令；常用写法 `awk '/^cmd_check\(\) *\{/,/^\}/'` = **278**（含闭括号），277 = 不含闭括号。建议把第三条命令连同「不含闭括号」口径写进行内（HEAD 实测 281）。

## 三、门禁回执（精确数字）

- `bash .agents/scripts/nao-fleet.sh check` ×2 ⇒ rc=0、输出**逐字一致**：`check: OK · roles=7 · files=54 · layout=main-row2`（+2 行；零 stash ⇒ 无 `warn=`）。
- `npm test`（默认 herdr，全 34 例）⇒ **rc=0**：34 例全 PASS/TMUX-ONLY，`SKIP=0 · DEGRADE=0 · NOTE=10`（全白名单）；索引对账 `共享 22 / 专有 10 / tmux 专有 2 / PENDING 0 = 34`，`--list` = **34**。
- 抽核：`cases/06` PASS（NOTE=2，无 stash 时 golden 未破）· `cases/28` PASS · `cases/35` 36 PASS ×3。
- 零副作用：真实仓 `git stash list` 0 / `git worktree list` 1（全程）；`git status --porcelain` 空；`.agents/scripts/nao-fleet.sh` md5 `6b4a74c7…` 前后一致（github-flow / pm.md / tasks-state / cases/35 同法已核）。
- 禁夹带：diff 仅 11 文件（3 机制 + 6 文档 + 2 用例/注册），`prompts/`、`roles.yaml` 零改动。

## 四、未做 / 边界

- 未做 tmux 后端 dual 全量（PM 只要求抽核；herdr 全量已 rc=0）。
- P2-1 的假红复现只在仓副本进行（真实仓零 stash 为本项前置），副本已删；P1-1 属文档事实错误，不涉实现。

## 追加 · 点检轮（as-of `399c660` · QA 独立复算）

**结论：NO-GO（单点 P2，1 行可修；其余全过）。** P2-1 修复本身通过验证。

1. **P2-1 双向 + 反空转 = 通过**。仓副本造 1 条 stash ⇒ `cases/06` **234 PASS**（含 P2④ 首行 golden + md5 `31b5978e…`）；同条件换 `399c660^` 的用例 ⇒ **222 PASS + 2 FAIL（= 224）**，md5 `3934a6cd…` —— 与你报的 224→234 与红点一致。**反空转 A**：`check_stash_residue` 首行插 `return 0` ⇒ **FAIL 4**（P2-1①首行≠golden · ②+1 · ②`-v` 恰 1 条 · ②含 BR5）；**反空转 B**：warn 前缀改 `! STASH 滞留` ⇒ **FAIL 1**（②`-v` 恰 1 条 ⇒ 措辞漂移会被抓）。注入面：7 处 check 调用里 5 处真实仓全部带 `NAO_STASH_ROOT`（`c6_check` 参数化 · `lab_check` 跑在 mktemp 夹具根 ⇒ 非仓天然免疫）；`cases/28` 全文 0 处 check ⇒ 结构性免疫。真实仓 stash 0 / worktree 1 / `npm test` rc=0（34 例，SKIP=0/DEGRADE=0/NOTE=10 白名单）。
2. **`-u NAO_STASH_ROOT` 确有必要（RD 说法成立）**：副本删该行 + 宿主 `export NAO_STASH_ROOT=<有 stash 的仓>` ⇒ `cases/35` **FAIL 1（E2）**；还原该行同条件 ⇒ **PASS**。
3. **B1 4 处修复**：队列行 ✓ 真在「待派发队列」内（`sed -n '/^## 待派发队列/,/^## 观察/p' … | grep -c T543-O2` = 1，且与三档表那行不同行）· `T545-cache-residue` 关闭决策成立（#121 交付物在：`T4_STALE_CACHE_HOURS` 6 处 / `cases/14` 4 处）· `118:34` 已标「⚠️ 已撤回」且已归档「有效 14 条」自洽 · ⑫ 三命令实测复现 **4326 / 136 / 281**。

**缺陷（本轮新增）**
- **P2-1（新）BR7 的范例数字已被同批打掉**：`grep -c 'O2 转办 2026-12-31' docs/tasks-state.md` **= 4**，BR7 写 **= 5** —— `7da08a6` 从 `T543-O2` 来源列删掉该短语所致（B1 修 P1 时顺手改了 B2 的证据）。修法：改「正文多处引述（非唯一）」不写数字，或加 as-of sha。其余两例仍准（非锚定 `T543` = 2 · 锚定 = 1）。
- **P3-1** `T545-O1` 判定命令 `grep -c "\$\{core\}-\$\{task\}"` **rc=2**（`\{\}` 被当区间表达式）⇒ 复制即报错，非「复制即跑」。
- **P3-2** `96-未验三项` 判定 `grep -c '未验' tests/t4/backends/herdr.txt` = **0 恒**（该文件无此字面）⇒ 无判别力。
- **P3-3** `T545-cache-residue` 行「存量亦已清零 /（常态 0）」不实：失败跑**按设计保留**缓存（T524），实测残留 11（7 个是我本轮 FAIL 演练、已删；4 个早于本轮）。建议改「成功跑后 0；失败跑保留（T524）」。
- **P3-4** 宿主导出 `NAO_STASH_ROOT` 时只有 35 被硬化 ⇒ 实测 `cases/34` 红 3、`cases/18` 红 2（假红）。属你登记的低概率观察面；建议同法在 34/18（及 04/15）零成本加 `-u`。

**回滚自证**：真实仓 3 文件 md5 与 RD 提交一致（`6b4a74c7…` / `0de29cec…` / `919e7c0a…`）、`git status` 空、stash 0、worktree 1；全部破坏性演练在 `/tmp` 副本内完成、副本 3 文件 md5 还原后复核并已删除。
