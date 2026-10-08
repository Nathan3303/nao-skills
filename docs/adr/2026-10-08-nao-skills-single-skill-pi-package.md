# ADR：nao-skills 单 SKILL 化 + pi 原生分发

- 状态：**已接受** · 日期：2026-10-08 · 出具：arch-designer（T0 终签）· 落地：rd-infra
- 指针：PRD `docs/prds/2026-10-08-nao-skills-pi-package.md` · 验证 `docs/reports/2026-10-08-T1-pi-package-verify.md` · Issue #18 · PR #20

## 背景

- 安装后机制平铺项目根 `.agents/` 6 项、无单一 AI 入口；自研安装器 303 行；`@.agents/**` 引用 290 处/45 文件。
- 目标：机制单源迁入包内、项目仅留 shim；pi 原生安装/升级；下游 4 仓迁移期零改动。约束：项目级 `--local`；角色仍 6 会话；角色卡继续 `--append-system-prompt` 常驻注入（BR1/BR2）。

## 决策

机制单一事实来源 = npm 包内 `.agents/` 命名空间（A′）；项目 `.agents/` 仅转发 shim；pi 按**文件**声明 2 个 skill；`NAO_SKILLS` 语义改为「机制包根」。包内 skill 路径 `.agents/skills/nao-fleet/SKILL.md`。

## 理由（四步法要点）

- 业务匹配：命中「内聚 + 原生安装」诉求；角色模型与注入方式不变，风险面最小。
- 技术成熟：pi 1.1.0 已证实项目级 npm 落盘 `<proj>/.pi/npm/node_modules/<pkg>`；按文件声明使注册数确定（T1 V1/V2）。
- 团队能力/成本：fleet 已支持 `NAO_SKILLS` 覆盖根 ⇒ 引用零重写、`check_cross_refs` 天然绿；省安装器维护面，换取一层 shim + 一条显式物化步骤。

## 已拍板决策（D1–D8；来源：用户 D1/D2，PM D3–D8）

- **D1 包内布局** = A′：保留 `.agents/` 命名空间，引用零重写。
- **D2 `.pi/npm/` Git 策略** = gitignore（pi 自建 `.gitignore` 默认忽略）。代价：clone 即得不成立，需一条显式物化命令。
- **D3 skill 归属** = 包内按文件声明 `nao-fleet` + `frontend-design`，注册数 1→2，增量仍恰 +1。前置：迁移须删项目内 `.agents/skills/frontend-design/`，并把 `skills-lock.json` 的重复来源收敛为唯一权威。
- **D4 下游 CI** = 维持 0 改动（4 仓 workflows grep `nao-fleet|nao-skill|.agents` 0 命中）。
- **D5 不可运行** = `exit 2` + 单行 `DEGRADED:`（与「能跑但失败 = 1」区分；T1 建议的 70 不采纳）。
- **D6 shim 解析序** = `NAO_SKILLS`(显式) → `.pi/npm`(项目 pin，主) → `~/.pi/agent/npm`(须校验版本 == pin) → 显式失败；用 node resolve 定位，不硬编码包名。
- **D7 防重入** = marker env（`NAO_SHIM_ENTERED=1`）命中即 `exit 2`；并校验解析出的包根 ≠ shim 自身项目根。
- **D8 环境锚点** = 三处落点（见下），**不主动写下游 `AGENTS.md`**。

## 对照过的备选模式（含不采纳理由）

- ⓪ **维持现状**（`nao-skill install` 复制 `.agents/`）：不采纳为终态（用户诉求 + 安装器维护面），留作迁移期兼容基线。
- ① **单 SKILL pi package + 转发 shim**：**采纳**。
- ② **pi extension 承载编排**：不采纳——破坏无 pi 环境的 CI 体检，生命周期与常驻 pane 冲突；独立立项。
- ③ **git submodule / vendor `.agents/`**：不采纳——无 skill 注册、无 pin 语义、升级面差。
- ④ **全局 npm install + 绝对路径引用**：不采纳——违项目级 `--local` 约束，不可复现。
- shim 解析：`PI_PACKAGE_DIR`（不采纳，T1 V1 证伪为 pi 自身包根）/ npx（不采纳为主路径，隐式网络 + 缓存不确定）/ 提交 lockfile（当前不采纳，见联动条款）。
- checklists 归属：独立顶层（不采纳为长期）/ 内聚 skill 子目录（采纳；T1 V2「含 SKILL.md 即停递归」⇒ 子目录 `.md` 不注册）。
- **硬约束**：项目 `.agents/` shim 禁 symlink 暴露 `.agents/skills/**`——mode=agents 下「无 `SKILL.md` 子目录」的裸 `.md` 会被注册，NFR4 破裂。

## NFR 定稿口径

- **NFR2**：给定 pin + **一条显式物化步骤**后结果可复现；nao 机制自身（shim / fleet / check / CLI）**零网络**；pi 启动的隐式 `npm install` 属**对外边界**。
- **NFR3**：nao 机制未物化 ⇒ `exit 2` + 可读错误 + 可复制恢复命令，**不静默**；pi 未装/离线由 pi 自身报错（可读、非 0），nao 不二次包装。

## pi 隐式安装边界与运行纪律

- 事实（T1 V3）：`.pi/npm/node_modules` 缺失时 pi 启动会隐式 `npm install --prefix .pi/npm --legacy-peer-deps`；离线空缓存 ⇒ npm `ENOTCACHED` + **pi exit 1**。
- 纪律：**先显式物化，再离线运行**——物化用 `pi install -l --approve npm:@nathan33/nao-skill@<pin>`；物化后可置 `PI_OFFLINE=1`。
- **联动条款**：D2 ∧ D4 ⇒ fresh clone 无 `.pi/npm` lockfile ⇒ 无 pi 环境的 `npm ci --prefix .pi/npm` 路径**当前不存在**；**若任一仓要把 `check` 进 CI（D4 变更），必须同时改 D2**（`git add -f .pi/npm/package.json .pi/npm/package-lock.json`）。

## D8 落点（三处）

1. `nao-fleet.sh build_system_prompt()` 的 `NAO_SKILLS` 锚点语义与取值（项目根 → 机制包根），与 D7 守卫配套。
2. `.agents/templates/AGENTS.md.example` §指针 + 角色卡/技能内 `$NAO_SKILLS/.agents/...` 表述（A′ 下路径形态不变，仅语义说明）。
3. **不主动写下游 `AGENTS.md`**：实测 4 仓 `NAO_SKILLS` 0 命中；现有 `bash .agents/scripts/nao-fleet.sh ...` 经 shim 仍有效，无需改。

## 后果与风险

- 正面：项目足迹收敛、机制单源、升级走 `pi install/update`。
- 风险：多一层 shim 与一条物化步骤；shim 依赖 `@nathan33/nao-skill` 与 `.pi/npm` 布局（不依赖 `PI_PACKAGE_DIR`，版本不符即失败）；`.agents/skills/` 为共享目录（含项目自有 skill）⇒ 禁整目录删，只精准删 nao 资产并备份 `.nao-obsolete/`。
- 治理：shim 保留 2 个 MINOR（0.12.x / 0.13.x），移除 = 1.0.0。

## 连带同步清单（含 Owner）

- `README.md`（发布形态 / sha 判据 / 目录树）——rd-infra
- `docs/ARCHITECTURE.md`（分层表 checklists 决策 + 机制细节表）——rd-infra
- `docs/adr/README.md` 索引——rd-infra
- `package.json`（`pi` / `files` / `keywords`）+ `bin/nao-skill.js`——rd-infra
- 4 仓迁移指引 + release notes——rd-infra；各仓 `AGENTS.md`——各仓 PM
- `nao-todo-minimal` 特例：无脚本、nao-fleet 引用 0 ⇒ 零 shim、纯文档/指针迁移

## 参考来源

- [Pi Packages](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md) · [Pi Skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md) · 访问 2026-10-08
- pi 1.1.0 `dist/config.js`（`getPackageDir`/`CONFIG_DIR_NAME`）· `dist/core/package-manager.js:207`（`collectSkillEntries`）· `dist/bundle/chunks/chunk-OIM2DMFI.js`（`getManagedNpmInstallPath`/`loadSkillsFromDirInternal`）
- [Agent Skills Specification](https://agentskills.io/specification) · 访问 2026-10-08

## 相关指针

- PRD `docs/prds/2026-10-08-nao-skills-pi-package.md` · 验证报告 `docs/reports/2026-10-08-T1-pi-package-verify.md`（PR #20）

- 修订：2026-10-08 首版（D1–D8 终签 + NFR2/NFR3 定稿 + pi 隐式安装边界）
