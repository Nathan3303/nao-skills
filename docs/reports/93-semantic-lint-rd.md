# #93 测试护栏补覆盖：真实缺陷类（全 server 计数 + 顺序挑尾）—— 交付报告（rd-infra）

- 状态：第二轮复核整改完成 · 待 QA 复核 / PM 验收 · 更新：2026-11-09 · Owner：rd-infra
- 指针：Issue [#93](https://github.com/Nathan3303/nao-skills/issues/93) · PR [#94](https://github.com/Nathan3303/nao-skills/pull/94) · 分支 `fix/93-semantic-lint` · 来源 QA #84 P3-2（台账待派发 Q2）
- 门禁 HEAD：`6cd8167`（本轮整改提交，tests 内容即交付面）；本报告为其后的 docs-only 提交，工作区静默 = `git status --porcelain` 0 行

## TL;DR

- 做了什么：新增语义化 lint `t4_scan_all_server_tail1`（`list-panes -a` 所在**第一条**管道直接接 `tail -1` 即命中）；缺陷形态与非纳管类固化为 `tests/t4/fixtures/` 固定 fixture；`cases/06` 断言「新 lint 必红 + **pre-#93 旧 lint 快照**仍绿」。
- 第二轮整改（QA CONDITIONAL：0 P1 / 1 P2 / 3 P3）四项全改：P2-1 注释与判据对齐并逐类列不纳管 · P3-1 收紧跨语句（`;`/`&&`）假阳 · P3-2 trim 缩进注释 · P3-3 旧 lint 对照改快照解耦；另补 C5 两行变量负控。
- 结论：AC1–AC6 全由 `cases/06` 机械断言；门禁全绿（`check` rc=0 连跑 2 次同输出 · `npm test` rc=0 · **1011 断言 / 25 例**，上一轮 1004/25，**+7 断言、例数不变**）。
- 回退：整分支 squash 后单条 `git revert`；改动面只在 `tests/` + 本报告。

## 一、缺陷与判据

- 旧护栏 `t4_scan_host_pane_refs` 只判「命令行位裸 `tmux` 必须显式 `-S`」；修前 `cases/20` 的 `pane_count(){ TX list-panes -a … }` / `pane_total(){ tmux -S … list-panes -a … }` + `| tail -1` **全部带 `-S`** ⇒ 行级 lint 零覆盖。
- 新判据（行级、静态）：同一行内 `list-panes` 带全 server 旗标 `-a`，且 `list-panes` 所在**第一条**管道直接接只取末行的 `tail`（`-1` / `-n 1` / `-n1` / `--lines=1`）。不判 socket 形态；**不解析引号 / 续行 / 数据流**。
- 承诺边界写在 `tests/t4/lib.sh`（P2-1 订正后）：
  - 纳管：该组合（含包装函数 `TX list-panes -a … | tail -1`、显式 `tmux -S …`、同行 `env tmux` / `bash -c "tmux …"` 前缀、`tail -n 1` / `-n1` / `--lines=1`）。
  - 不纳管（已知漏判，理由 = 行级静态不解析引号/续行/数据流）：① 中间隔别的管道（`| grep … | tail -1`，只认第一条管道）② `list-panes` 紧跟 `(` / `"` / `$(`（`arr=(list-panes -a …)` / `args="list-panes -a …"` / `x=$(list-panes -a … | tail -1)`）③ 跨行 ④ 两行变量拼装（`cmds="list-panes -a …"` 再 `$cmds | tail -1`）⑤ `| wc -l` / `| head -1` ⑥ 会话定向 `list-panes -t … | tail -1`。
  - 已知假阳（不承诺判对，理由 = 不解析引号）：字符串字面量 `echo "run list-panes -a | tail -1"`、引号内 `-a`（`list-panes -F '#{@x} -a ' | tail -1`）。

## 二、第二轮整改（QA CONDITIONAL 四项）

- **P2-1（注释比判据强）**：`lib.sh` 旧措辞「同一条管道把结果喂给 tail」「同行即命中 / 变量间接纳管」已改为「**第一条**管道直接接 `tail`」，并把 ①–④ 四类不纳管（中间管道 / `(` `"` `$(` / 跨行 / 两行变量）逐条写明 + 理由（行级静态不解析引号/续行/数据流）；实测这四类输出如下（均 0 命中）：
  ```
  y() { tmux -S "$S" list-panes -a -F x | grep -v x | tail -1; }   → 0
  x=$(list-panes -a -F x | tail -1)                                → 0
  arr=(list-panes -a -F x); tmux -S s "${arr[@]}" | tail -1        → 0
  args="list-panes -a -F x"; tmux -S s $args | tail -1             → 0
  ```
- **P3-1（跨语句假阳）**：管道 gap 由 `[^|]*` 收紧为 `([^|;&]|&[^&])*`（等价收紧 `;` / `&&`，但容忍 `2>&1` 这类单个 `&`，不制造新漏判）。实测：
  ```
  x() { … list-panes -a …; echo done | tail -1; }        → 0（改前命中）
  list-panes -a -F x && echo done | tail -1              → 0（改前命中）
  pane_total() { … list-panes -a … 2>&1 | tail -1; }     → 命中（未因收紧而漏判）
  ```
  字符串字面量与引号内 `-a` **不修**（不解析引号），按 PM 口径写进「已知假阳」边界，实测仍命中、明确不承诺判对。
- **P3-2（缩进注释）**：新 lint 先 trim 前导空白再判 `#`；`  # list-panes -a … | tail -1` 实测 0 命中。旧 `t4_scan_host_pane_refs` 不动（本批不碰既有判据）。
- **P3-3（反向变异耦合）**：`tests/t4/fixtures/pre93-host-pane-refs.sh` 固化 pre-#93 旧 lint（逐字复制自 `main@2497d87` · v0.22.6 · 日期 2026-11-09），AC1 的「旧 lint 仍绿」改读**快照**；live 旧 lint 只保留 AC3 对错断言。反向变异实测：在临时 worktree 把 live 旧 lint 增强到能命中该缺陷类（对 fixture 输出 `defect.sh:15:…`）⇒ `cases/06` **rc=0 / RESULT: PASS**（不再假红）。
- **⑤ 补负控**：`controls.sh` 增 C5 两行变量拼装（`pane_two_lines`），与注释 ④ 对齐；另加 C6 `;` / C7 `&&` / C8 缩进注释三条，分别锁 P3-1 与 P3-2。

## 三、AC1/AC2：同一份输入 —— 新 lint 红、旧 lint（快照）绿

- **先红**（commit `93c5f13`，未实现 lint，独立 worktree 跑 `--case 06`）：`rc=1`，`PASS=67 / FAIL=4`，红点全在 #93 正断言：
  ```
  [FAIL] AC1 #93: 同一份缺陷输入 ⇒ 新语义 lint 必红（不应等于 ）
  [FAIL] AC2 #93: 恰 2 条命中（包装函数调用 + 显式 -S 直调）（期望=2 实际=0）
  [FAIL] AC2 #93: 点名包装函数调用形态（未包含: pane_count）
  [FAIL] AC2 #93: 点名显式 -S 直调形态（未包含: pane_total）
  ```
- **后绿**（本轮 `6cd8167`，`--case 06`）：`rc=0`，`PASS=78 / FAIL=0`。
- 同一 fixture（`fixtures/93-all-server-tail1/defect.sh`，头注 Issue #93 + 2026-11-09）：新 lint 恰 2 条（`pane_count` 包装 / `pane_total` 显式 `-S`）；**pre-#93 快照**对同一份字节副本输出为空（历史事实：旧 lint 对真实缺陷类零覆盖）。
- 常态护栏：新 lint 扫 `tests/t4/cases` 恒 0 命中。

## 四、AC3：真阳性不退化

`cases/06` 现有三条护栏断言保持全绿（未改判据与夹具）：裸 `tmux` 命中并点名、合规 `tmux -S` 不计入、人造违规负控恰 2 条。

## 五、AC4/AC5：负控与变异自证

- 负控（`controls.sh`，逐条断言不命中）：C1 会话定向+挑尾 · C2 `| wc -l` · C3 `| head -1` · C4 跨行 · C5 两行变量 · C6 `;` 跨语句 · C7 `&&` 跨语句 · C8 缩进注释。
- 恒假变异（子进程替换 lint，复刻断言）：`hits n=0`，`rc=1` ⇒ `[FAIL] AC2: 缺陷 fixture 必红（不应等于 ）` + `恰 2 条命中（期望=2 实际=0）`。
- 丢 `-a` 变异：`hits n=4`，`rc=1` ⇒ `[FAIL] AC2: 恰 2 条命中（期望=2 实际=4）` + `[FAIL] AC4: 会话定向采样不纳管`。
- **gap 改回 `[^|]*` 变异**（临时 worktree 只改该行）：`cases/06` `rc=1`，**3 红** ⇒ `AC2: 恰 2 条命中（期望=2 实际=4）` + `P3-1 负控: 分号后接无关 tail -1 不得命中（不应包含: pane_then_echo）` + `P3-1 负控: 逻辑与后接无关 tail -1 不得命中（不应包含: pane_and_echo）`。⇒ 跨语句收紧有机械护栏，不是只靠注释。

## 六、AC6：门禁（HEAD `6cd8167` · 工作区静默）

- `bash .agents/scripts/nao-fleet.sh check` 连跑 2 次：`rc1=0 / rc2=0`，两次输出 `diff` 0 行；`check: OK · roles=7 · files=54 · layout=main-row2`
- `npm test` → `rc=0` · 用例 **25**（`run.sh --list | tail -n +2 | wc -l`）· 断言 **1011**（`grep -c '\[PASS\]'`）· `FAIL=0` · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）
- 断言数对账：上一轮 **1004** → 本轮 **1011**（**+7**），逐条 = 快照 fixture 存在 +1 · 快照来源 sha +1 · 快照日期 +1 · C5/C6/C7/C8 负控 +4；基线 v0.22.6 **986** → 本轮 **1011**（**+25**，全部为 #93 及相关复核断言）。

## 七、变更面与回退

- 本轮 `6cd8167`：5 文件 · `tests/README.md +1 −1` · `cases/06 +18 −4` · `controls.sh +9` · `pre93-host-pane-refs.sh +29`（新）· `lib.sh +31 −18`
- 全分支（含报告）：7 文件 **+276 −3**（`tests/` + 报告；`nao-fleet.sh` / `bin/` / `.agents/` 零改动）
- 回退：单条 squash `git revert` 可干净回退。
- 已知边界：行级静态不拼续行、不追数据流、不解析引号（P2-1 已逐类声明）；字符串字面量/引号内 `-a` 是已知假阳，不承诺判对。
