# #93 测试护栏补覆盖：真实缺陷类（全 server 计数 + 顺序挑尾）—— 交付报告（rd-infra）

- 状态：待 QA 复核 · 更新：2026-11-09 · Owner：rd-infra
- 指针：Issue [#93](https://github.com/Nathan3303/nao-skills/issues/93) · 分支 `fix/93-semantic-lint` · 来源 QA #84 P3-2（台账待派发 Q2）
- 门禁 HEAD：`a415fe9`（本报告随其后的 docs-only 提交进入 PR；工作区静默 = `git status --porcelain` 0 行）

## TL;DR

- 做了什么：新增语义化 lint `t4_scan_all_server_tail1`，判据 = 同一行出现 `list-panes` + 全 server 旗标 `-a` + 管道喂给只取末行的 `tail`（`-1` / `-n 1` / `-n1` / `--lines=1`）；缺陷形态固化为 `tests/t4/fixtures/93-all-server-tail1/` 的固定 fixture，`cases/06` 对它断言「新 lint 必红 + 旧行级 lint 仍绿」。
- 结论：AC1–AC5 全由 `cases/06` 机械断言；AC6 门禁全绿（`check` rc=0 · `npm test` rc=0 · **1004 断言 / 25 例**，基线 986/25，**+18 断言、例数不变**）。
- 边界：只承诺「`list-panes -a` + `| tail -1`」这一组合；#84 的假阳 3 例 / 漏判 4 例逐类写在 `lib.sh` 注释（纳管 / 不纳管 + 理由）。不判 socket 形态、不拼接续行。
- 回退：两条 `wip(93)` 提交可整分支 `git revert` 或 squash 后单条 revert；改动面只在 `tests/` + 本报告。

## 一、缺陷与修法

- 旧护栏 `t4_scan_host_pane_refs` 只判「命令行位裸 `tmux` 必须显式 `-S`」；真实缺陷类（修前 `cases/20` 的 `pane_count(){ TX list-panes -a … }` / `pane_total(){ tmux -S … list-panes -a … }` + `| tail -1`）**全部带 `-S`** ⇒ 行级 lint 零覆盖，缺陷原样回归仍绿。
- 新 lint 不看「调用方是谁」也不看 socket：只要同行含「`list-panes` 带 `-a`」且管道进「只取末行的 `tail`」即命中（包装函数 `TX`、变量/数组间接、`env` / `bash -c` 前缀同样按行识别）。
- 承诺边界写进 `tests/t4/lib.sh` 的 lint 注释（AC4）：纳管 = 该组合（含 `tail -n 1` / `-n1` / `--lines=1`）；不纳管 = ① `| wc -l` / `| head -1` ② 会话定向 `list-panes -t … | tail -1` ③ 跨行（行级不拼续行，已知漏判）④ 先存变量/拼接再喂 tail（同类漏判）；#84 假阳 3 例（`-S"$SOCK"` 紧贴 / 跨行 `tmux \` / `tmux -L`）因本 lint 不判 socket ⇒ 均不纳管、不构成新假阳面；#84 漏判 4 例中同行出现的 `env tmux …` / `bash -c "tmux …"` / 数组或变量间接均纳管，跨行/拼变量的沿用 ③④ 漏判声明。

## 二、AC1/AC2：同一份输入 —— 新 lint 红、旧 lint 绿（先红 → 后绿）

- **先红**（commit `93c5f13`，未实现 lint，`NAO_SKILLS=<该提交工作树> bash tests/t4/run.sh --case 06`）：
  `rc=1`，`case06 PASS=67 / FAIL=4`，红点**全部落在 #93 的正断言**（旧 lint 断言仍绿）：
  ```
  [FAIL] AC1 #93: 同一份缺陷输入 ⇒ 新语义 lint 必红（补上旧 lint 的零覆盖）（不应等于 ）
  [FAIL] AC2 #93: 恰 2 条命中（包装函数调用 + 显式 -S 直调）（期望=2 实际=0）
  [FAIL] AC2 #93: 点名包装函数调用形态（未包含: pane_count）
  [FAIL] AC2 #93: 点名显式 -S 直调形态（未包含: pane_total）
  RESULT: FAIL (4 项断言未过)
  ```
- **后绿**（commit `a415fe9`，`bash tests/t4/run.sh --case 06`）：`rc=0`，`case06 PASS=71 / FAIL=0`。
- **同一份 fixture 的双向对照**（`tests/t4/fixtures/93-all-server-tail1/defect.sh`，来源 Issue #93 / QA 84 与日期 2026-11-09 写在 fixture 头）：
  - 新 lint 命中恰 2 条（`pane_count` 包装函数 + `pane_total` 显式 `-S`）；
  - 旧 lint 对**同一目录**输出为空 ⇒ 证明此前是**零覆盖**，不是 lint 坏了。
- 常态护栏：新 lint 扫 `tests/t4/cases` 恒为 0 命中（将来谁把该缺陷类写回用例当场红）。

## 三、AC3：真阳性不退化

`cases/06` 现有三条护栏断言保持全绿（未改动其判据与夹具）：裸 `tmux` 命中并点名、合规 `tmux -S` 不计入、人造违规负控恰 2 条。

## 四、AC4：不纳管类负控（`tests/t4/fixtures/93-all-server-tail1/controls.sh`）

四个负控逐个断言「不得命中」：会话定向采样 + 挑尾（`pane_of_session`）· 全 server 计数但不挑尾（`pane_total_wc`）· 全 server 计数取首行（`pane_first`）· 跨行写法（`pane_multiline`，已知漏判、显式声明不纳管）。

## 五、AC5：变异自证

在子进程里只替换 lint（`cases/06` 复刻同一组断言并对子进程 rc 与 FAIL 文案断言），两处变异都当场红：

- **恒假**（`t4_scan_all_server_tail1() { :; }`）⇒ `hits n=0`，`rc=1`：
  ```
  [FAIL] AC2: 缺陷 fixture 必红（新 lint 命中）（不应等于 ）
  [FAIL] AC2: 恰 2 条命中（包装函数 + 显式 -S）（期望=2 实际=0）
  RESULT: FAIL (2 项断言未过)
  ```
- **只匹配 `tail` 不管 `-a`** ⇒ `hits n=4`（多命中 `pane_of_session` 与跨行负控），`rc=1`：
  ```
  [FAIL] AC2: 恰 2 条命中（包装函数 + 显式 -S）（期望=2 实际=4）
  [FAIL] AC4: 会话定向采样不纳管（不应包含: pane_of_session）
  RESULT: FAIL (2 项断言未过)
  ```

## 六、AC6：门禁（HEAD `a415fe9` · 工作区静默）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=7 · files=54 · layout=main-row2`，`rc=0`
- `npm test` → `rc=0` · 用例 **25**（`bash tests/t4/run.sh --list | tail -n +2 | wc -l`）· 断言 **1004**（`grep -c '\[PASS\]'`）· `FAIL=0` · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）
- 基线对照：v0.22.6 **986 断言 / 25 例** → 本分支 **1004 / 25**，**+18 断言**、例数不变；增量全部来自 `cases/06` 新增的 #93 断言（fixture 存在/来源日期 4 · 新 lint 正断言 4 · 不纳管负控 4 · 旧 lint 仍绿 1 · 用例集常态 1 · 变异自证 4）。

## 七、变更面与回退

- 提交 1 `93c5f13`：3 文件 `+97 −0`（fixture 2 + `cases/06`）。
- 提交 2 `a415fe9`：2 文件 `+40 −3`（`lib.sh` 新增 lint 与边界注释 + `tests/README.md` 口径）。
- 本报告：1 文件（docs-only）。
- 回退：单条 squash `git revert` 可干净回退（纯 `tests/` + 报告，无运行时代码/`nao-fleet.sh`/`bin/`/`.agents/` 改动）。
- 已知边界：行级静态判据不拼接续行、不追数据流（`p = $(list-panes -a …)` 再 `| tail -1` 漏判），已逐条声明，不构成隐含承诺。
