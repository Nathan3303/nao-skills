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
- 待办（建议单开）：status 分组标题 v1 示例（`nao-fleet.sh:3561/3563`）。

- 修订：2026-11-23 初稿
