# ADR：herdr workspace 放置键与 scope 分离（label = 仓 slug）

- 状态：提议
- 更新：2026-11-13
- Owner：arch-designer
- 指针：Issue [#112](https://github.com/Nathan3303/nao-skills/issues/112) · 评审 `docs/reports/T545-scope-isolation-arch.md` · 上游 `docs/prds/2026-11-10-herdr-base.md`（AC3.1）· 既有放置口径 `docs/reports/96p3-layout-p1.md:22`

## 背景

- 布局 A 定「1 workspace/仓（label=scope），无 scope ⇒ `HERDR_SESSION`」，`_term_herdr_spawn` 照此实现（`nao-fleet.sh:1083-1088`）。
- scope 是**可选身份字段**（缺失 = 空，BR1「空 scope 时名字逐字不变」的前提），而放置键要求**恒有值**：两个需求直接冲突，代码用会话名兜底掩盖。
- 实测（评审 §二）：目标仓无 scope 时，跨仓 `ensure` 把 pane 落进 label 恰等于会话名的调用方 workspace，或凭空新建以会话名命名的 workspace；现场 `rd-infra-T724`（cwd = nao-todo，落在 w1 = nao-skills）即此。
- 会话名、workspace label、仓名是三个命名空间；同名是巧合，不构成归属证据。
- herdr 原生模型：workspace = 顶层项目/工作上下文，label 默认取根 pane 的目录名 ⇒「1 workspace/仓、label = 仓名」才是原生形态。

## 决策

放置键改为**目标仓 slug**（`fleet_scope_slug`：git common-dir 父目录名 ⇒ worktree 同键；恒非空；≤16 字符），删除 `HERDR_SESSION` 回退；scope 只承担**会话名身份**（`<core>[@<scope>]`）与同名隔离。相对 `96p3-layout-p1.md:22` 的偏差：`label = scope（空 ⇒ HERDR_SESSION）` → `label = scope（已声明）否则仓 slug`。

## 理由

1. 键必须**全域**：scope 可空、slug 不可空 —— 把可选字段当必需键是缺陷源头，不是实现瑕疵。
2. 「1 workspace/仓」的本意是**按仓分组**；slug 即仓身份，解耦后两个键各自单源，不再互相借用。
3. 与 herdr 原生行为一致（label 默认取根 pane 目录名）⇒ 用户手工按仓名命名的工作区可被复用（现场 `w2` label = `nao-todo` = slug）。
4. 成本最低：改动面 = spawn 一处键 + 用例/文案；零配置迁移；顺带关闭遗留 `O2`（`fleet_scope_slug` 未接生产）。

## 对照过的备选模式

1. **维持现状**（label = scope，空 ⇒ 会话名）—— 适用：单仓单 workspace；代价：跨仓静默落错（已实测两种形态）；不采纳：即本缺陷。
2. **禁止跨仓 + fail loud**（不派生）—— 适用：每仓都愿声明 scope；代价：nao-skills 自身未声明 ⇒ 从任意 cwd `ensure` 立即受限，且「调用方 workspace 属于哪仓」在 herdr 0.9.1 无 workspace cwd 字段（本机 `workspace list` 实测），只能靠 pane cwd 启发式（`cd` 到别仓再 `ensure` 仍可绕过）；不采纳：把确定的事变成配置负担，判据仍非全域可靠。
3. **scope 总是派生（命名也带 `@slug`）** —— 适用：愿接受会话改名；代价：破 BR1（`pm` → `pm@slug`）、用例/文档/下游全量改、旧会话双名期；不采纳：与 A 同收益，代价高一个量级。
4. **采纳：双键分离**（见决策）。

## 后果与风险

- 正面：跨仓落错由结构消除（不再存在「调用方 workspace」这一概念）；workspace 与用户认知、herdr 原生行为一致；关闭 `O2`。
- 负面：workspace label 不再等于 scope（自定义 label 的用户需改用 slug 或 `workspace rename`）；同 slug 两仓（同名仓 / 截断撞名）仍共用一个 workspace。
- 迁移：已存在的 scope 命名 workspace（如 `todo`）升级后不再复用 ⇒ 每仓最多人工关闭一个旧 workspace；运行中会话不受影响（`status`/`close` 不按 workspace 判归属）。

## 限制与已知边界

- 非 git 仓 slug = 目录名；>16 字符截断或同名仓可能撞键（不做自动探测，靠声明 scope 或改目录名）。
- 不改命名契约语法，不改 `status`/`close` 的归属判据（pane label + pane cwd）。

## 相关指针

- 复现步骤 / 候选对比 / 影响面：`docs/reports/T545-scope-isolation-arch.md`
- 落实闸门与用例集：同报告 §四（实施类按 `deliverable-docs.md` §四 下沉，不进本 ADR）

## 参考来源

- [herdr CLI reference](https://herdr.dev/tui/docs/cli-reference/) · 访问 2026-11-13 · workspace = 顶层项目/工作上下文，创建即带根 tab/根 pane；`cwd` 字段用于 label 与 follow-cwd。
- [herdr v0.9.1（release）](https://github.com/herdrdev/herdr/releases/tag/v0.9.1) · 访问 2026-11-13 · 本机版本锚点（`herdr 0.9.1`，protocol 22）。
- [herdr-workspace-renamer（社区插件）](https://github.com/ryanlewis/herdr-workspace-renamer) · 访问 2026-11-13 · 「workspace label 默认取根 pane 的目录名」= 仓名即 label 的既有惯例。
