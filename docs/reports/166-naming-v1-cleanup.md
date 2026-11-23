# #166 v1 命名口径清理（用法头 · 放置键 = 仓基键）

- 状态：待验收 · 更新：2026-11-23 · Owner：rd-infra
- 指针：Issue [#166](https://github.com/Nathan3303/nao-skills/issues/166) · 任务 T561 · 分支 `fix/166-naming-v1-cleanup`（基线 `607aa6e`，文档面归 PM）
- 上游：ADR `2026-11-20-workspace-as-binding-unit`（取代 `2026-11-17-fleet-identity-source`）

## TL;DR

- 用法头是 `--help` 的**唯一来源**（`usage()` 用 awk 抽首段注释），改它 = 改用户看到的第一印象。本批把它从 v1 舰队口径拉齐到 **v2**：名字 `<role>[<N>](<task>)`、**不含位置**；放置键 = **仓基键**（同机同基名让号 `base2`..`base9`）。
- `--fleet` / `--scope` / `.agents/fleet-scope` / `fleet.yaml:` `slug:` 统一写成**弃用块**（非空 ⇒ 恰一行 warn 后忽略；给参但空 ⇒ 用法错），删掉「等价 `--fleet`」「与 `--fleet` 同给即歧义」这类**已失效**表述。
- 废弃 ADR 引用在 `.agents/**` **清零**（脚本 2 处：用法头 + CLI 解析注释）；`docs/adr/README.md` 的「已废弃/取代」行按规矩保留。
- 机械判据全 0；`--help` 逐行重扫**无**「新会话带 `@`」（`@` 仅剩 `@<repo>` 选择符与旧形只读说明）。

## 一、事实复核（自己跑，不采信转述）

- `--fleet` / `--scope` 非空 ⇒ warn 后**忽略**：`_fleet_deprecated_warn`（`grep -n '^_fleet_deprecated_warn()' ⇒ 2011`）；两者**同给不再拒绝**（`grep -n '"--scope")' ⇒ 2015` 无冲突分支，用例 33 AC5 亦断言双 warn + rc=0）。
- 放置键 = 仓基键：`place_key_label`（`grep -n '^place_key_label()' ⇒ 2040`）；同基名让号 = `${base:0:15}$n`，`n=2..9`，段满 rc=1（`grep -n '^_ensure_place_label()' ⇒ 4091`）。
- 名字构造唯一点：`fleet_core_build`（`grep -n '^fleet_core_build()' ⇒ 2069`）⇒ `<role><num>(<task>)`，`num` 空 = 槽位 1。
- `--as` 三形态 + 禁括号：`grep -n '"--as 不可用' ⇒ 4278`。
- **无 `--name` 标志**：`grep -nE '^\s+--name\)'` ⇒ 空。旧用法头的「`--name <别名>-<编号>@<fleet>`」是在描述**结果名**，容易被读成一个参数 ⇒ 已改为「名字 = …」。

## 二、改动位置（7 处 · 行号为改后实测）

- `:13-16` 布局 A：`label=fleet，可用 --fleet/fleet-scope 覆盖` → `label = 仓基键` + 让号语义 + ADR `2026-11-20`。
- `:31-34` `ensure` / `--task`：`--name <别名>-<编号>@<fleet>` → 名字 `<别名>(<编号>)`；同 workspace 该 role 已有会话 ⇒ 槽位 `<别名><N>(<编号>)`；补「`@<repo>` = 目标仓选择符（不入会话名）」。
- `:36-40` `--card --as`：补 `<role><N>` 形态与「含 `(` 即拒 —— 派生 task 只走 `--task`」。
- `:41-44` 会话名契约：`<role>[-<task>]@<fleet> / 恒带 @` → v2 契约 + 「旧形只读：status/close 能认、ensure 永不生成」。
- `:45-48` `--fleet` / `--scope` / `fleet-scope·slug`：弃用块（同口径，不再互斥）。
- `:56-60` `close`：`派生名如 rd-be-T1；全名如 rd-be-T1@todo` → `rd-be(T1)` / `rd-be2(T1)`，legacy 全名标「旧形只读」。
- `:4442`（CLI 注释，非用法头）：`--fleet > --scope > fleet-scope > slug` 优先级 → 「弃用，仅保留空值守卫」。

## 三、v1 残留自查（改 / 不改）

- **改**：§二 7 处。
- **不改**：`:44` 旧形 `<core>[-<task>][@<scope>]` —— 保留但标「只读」，`close`/`status` 实际接受（`grep -n '旧形如 rd-be-T1' ⇒ 3828` 同口径）。
- **不改**：`:48` `fleet.yaml` 文件名 —— 弃用的是其中 `slug:` 字段，非文件本身（`grep -n '^    slug)' ⇒ 2017`）。
- **范围外登记（本批不改）**：`:3562` / `:3564` status 分组标题示例仍是 `rd-be-T1 / rd-be-T1@todo`（用户可见输出）—— 超出「用法头」范围，建议下一批；`:3828` die 文案列旧形「仍可回收」**正确**，保留。

## 四、判据（机械 · 均可 grep）

```text
用法头 1-60 行：@<fleet>=0 · 恒带=0 · <-task>@=0 · label=fleet=0 · 等价 `--fleet`=0
2026-11-17-fleet-identity-source：脚本=0 · .agents/=0（仅 docs/adr/README.md「已废弃」行保留）
--help rc=0；逐行重扫无「新会话带 @」
```

## 五、门禁（数字取自落盘日志）

- `check` rc=0 → `check: OK · roles=7 · files=53`（`/tmp/rd-t561-check.log`）。
- `npm test` rc=0 → **40 例 · 2513 PASS / 0 FAIL**（`/tmp/rd-t561-test.log`；取数 `grep -c '\[PASS\]'` / `grep -c '\[FAIL\]'`）。
- `bash -n` 语法零错；`--help` rc=0。
- 零角色卡改动 ⇒ 无 bump、无广播；单源未破（规则正文仍是 ADR，用法头是契约本文，不复制规则解释）。

## 六、风险与待办

- 用例 33/40 已覆盖弃用 warn 与放置键；本批**行为零变化**（只改注释/文案），全量绿即证。
- 原「待办：status 分组标题 v1 示例」经 PM 裁定**纳入本批**（见 §七），已无遗留待办。

## 七、追加 2 处（PM 裁定纳入本批 · 同 Issue #166）

**① `status` 分节标题示例（`nao-fleet.sh:3562/3564`）**

- 修前：`如 rd-be-T1 / rd-be-T1@todo`（`any_scoped` 分支）· `如 rd-be-T1 / rd-infra-T1`（else 分支）
- 修后：`如 rd-be(T1) / rd-be2(T1)；含旧式 @ 名` · `如 rd-fe(T1) / rd-infra(T1)`
- 分工：`any_scoped` 分支仍只表示「在场有旧式 `@` 名会话」（判据变量、分支条件**未动**），示例换成 v2 形态；else 分支示例换 v2 且**不再出现** 旧派生名。
- **`status` 分节标题示例文案变更（非行为变更，无 golden 依赖）**：`grep -rn '任务派生会话' tests/` 仅命中 `tests/t4/fixtures/nao-fleet-baseline-{2b4ade3,2692b42}.sh`（冻结快照，按纪律**不改**），`tests/t4/cases/**` 对这两个标题字面断言 = 0；`cases/28` 断言的 `rd-be-T1@todo` 是 **legacy 解析语义**（`parse` ⇒ `LEGACY OK derived`），与标题文案无关，不受影响。

**② `.agents/skills/pm-operations.md:28`（任务派生会话段）**

- 修前：`` `ensure <role>@<repo> --task <编号>` → `--name <角色>-<编号>`（如 `rd-be-T1`） ``
- 修后：`` `ensure --task <编号> <角色>[@<仓>]` → 名字 `<角色>(<编号>)`（如 `rd-be(T1)`；同 workspace 该角色已在 ⇒ 槽位 `<角色><N>(<编号>)`） ``
- 只改「命令 → 名字」这一截；同段「回收命令 + 双闸门」与「回执 role 写派生名」**逐字未动**。
- 与用法头（`ensure --task` 行）同源措辞，仍不复制规则解释（单源纪律未破）。

**判据补充（实测）**

- `grep -rn 'rd-be-T1\|rd-infra-T1' .agents/scripts/nao-fleet.sh` = **0**
- `pm-operations.md` 内 `-<编号>` 派生名形态 = **0**

**③ 连带项：用例 28 `P2① herdr golden` 同步（必改，否则全量红）**

- 现象：全量首跑 `rc=1`，唯一真失败 = `P2① herdr golden == 记录的 golden（期望=123bf85b… 实际=8b504752…）`（其余 2512 条与用例 43 全 PASS）。
- **订正派单前提**：PM 核「`tests/t4/cases/**` 对这两个标题字面断言 = 0」**成立**（我复算同结论），但该 case 的 **herdr golden 是对整段 `status` 渲染取 md5** ⇒ 标题文案改了，哈希必变，**等价于断言**。所以「纯文案改动」在 golden 面上仍是**渲染契约变更**，必须同步记录值。
- 同步纪律（该 case 注释自带）：`**有意改 herdr 渲染（文案/节标题/列）时须同步更新本行**`。
- **变更最小性证明**（两树对照，不靠推理）：`git worktree add /tmp/wt-t561 ccaf373`（无我本轮改动的旧树）⇒ `--case 28` **PASS @ 123bf85b**；在该旧树上**只打这 2 行标题补丁** ⇒ **FAIL @ 实际 8b504752**（与主树完全同值，且仅 1 条断言翻红）⇒ 证明哈希位移**精确等于**这 2 行，无夹带漂移。
- 处置：`28-naming-contract.sh` 的 `GOLD_HERDR_MD5_RECORDED` `123bf85b…` → `8b504752…`，并在该行上方注明 T561 原因与证据；`--case 28` 复跑 **PASS（0 FAIL）**。

**判据复算时多抓到 1 处（本批一并修）**：`:3828` `close` 的 `die` 未知目标文案仍带 `旧形如 rd-be-T1 / qa@todo 仍可回收` ⇒ 改为抽象形态 **`旧形（<角色>-<任务号> / <角色>@<scope>）仍可回收`**。信息量不减（仍告诉用户旧名可回收），且不再把具体旧派生名写死。`grep -rn '旧形' tests/t4/cases/` 对照：用例断言的是**行为**（`28` 的 `parse` 契约、`37/39` 的旧形回收），**无一处断言该文案字面**，故安全。

- 修订：2026-11-23 初稿
