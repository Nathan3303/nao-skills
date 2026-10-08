# PRD：nao-skills 单 SKILL 化 + pi 原生分发

> Issue：[#18](https://github.com/Nathan3303/nao-skills/issues/18) · 分支：`feat/18-pi-package` · 目标版本：**0.12.0**（MINOR，含兼容层）
> 状态：已开工（T1 前置验证中）· PM 维护 · 正文为权威（Issue 只放摘要与指针）

## 0. 背景与决策留痕

用户诉求：安装后机制平铺到 `.agents/` 下多个顶层目录，**不够内聚**，希望改成一个 SKILL。

澄清结论（2026-10-08）：

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 主目标 | **pi 原生安装**（skill 走 pi package 分发） | 用户选择：不只目录内聚，要原生化安装/升级 |
| 安装作用域 | **项目级 `--local`**（`.pi/settings.json` 记录 pin 版本） | 团队 clone 即得、版本可 pin、CI 可复现 |
| 本次深度 | **分阶段：只原生化分发** | fleet 编排（1289 行 / 87 处 tmux / 62 处 pi·intercom）搬进 extension 会破坏无 pi 环境的 CI 体检，且生命周期模型与「常驻 pane」冲突 |
| 下游兼容 | **保留转发层** | 下游 4 仓（nao-todo / nao-todo-minimal / nao-todo-server / nue-ui）迁移期零改动 |
| 角色模型 | **不变**（6 会话） | SKILL 只做入口 + 说明书，不合并角色 |

## 1. 问题证据（实测）

| 证据 | 数据 |
| --- | --- |
| 安装后项目根平铺 6 项 | `.agents/{prompts,common,checklists,skills,templates,scripts}` + `AGENTS.md` |
| 无单一 AI 入口 | pi skill 列表中无舰队入口（仅第三方 `frontend-design`） |
| 自研安装器维护面 | `bin/nao-skill.js` 303 行（install / 合并 / 废弃清理） |
| 迁移成本 | 334 处 `.agents/…` 引用，散在 34 个文件（skills 98 / scripts 58 / checklists 54 / common 31 / prompts 20 / templates 16 / roles.yaml 12） |
| 兼容约束 | `README.md`：下游完整性判据 =「脚本与上游逐字节 sha 一致」；`check` 被 `npm test` / `prepack` / 下游 CI 调用 |

## 2. 目标指标

| 指标 | 现状 | 目标 |
| --- | --- | --- |
| 项目内机制足迹 | 6 项平铺 | ≤2 项：`.pi/settings.json` + `.agents/`（仅 shim） |
| AI 入口 | 无 | 普通 pi 会话可发现并加载舰队说明书 |
| 升级方式 | `nao-skill update` 覆盖项目内文件 | `pi install/update`；升级后项目 `git status` 干净 |
| 下游兼容 | — | 旧路径 100% 可用，下游仓零改动 |

## 3. 范围 / 非范围

| IN | OUT（本次不做） |
| --- | --- |
| pi package 化（`pi` manifest + 单 `SKILL.md`） | ❌ fleet 编排重写为 extension（独立 Issue） |
| 机制目录重排为包内命名空间 | ❌ 角色卡注入方式变更（**必须**保持常驻注入） |
| 薄 CLI：`init` / `exec` / 迁移 | ❌ 角色数量与职责变更 |
| `.agents/` 兼容转发 shim + 一次性迁移提示 | ❌ tmux 布局与闸门语义变更 |
| 334 处引用重写 + `check` 交叉引用绿 | ❌ 下游 4 仓的**实际改造**（仅只读兼容验证，改造另立 Issue） |
| README / ARCHITECTURE.md / 模板同步 | ❌ 移除兼容层（留给 1.0.0） |

## 4. 用户场景

| # | 场景 | 期望 |
| --- | --- | --- |
| S1 | 新项目接入 | `pi install --local npm:@nathan33/nao-skill@0.12.0` + `npx @nathan33/nao-skill init` → 2 项足迹，`check` 绿 |
| S2 | 老用户升级 | 迁移命令 → 旧机制文件备份 `.agents/.nao-obsolete/`、shim 就位、旧命令照跑、提示一次 |
| S3 | 团队 / CI | `.pi/settings.json` 带 pin 版本进仓库；CI 有明确机制获取步骤，结果与今天一致 |
| S4 | 普通 pi 会话 | 用户说「想加个导出功能」→ 路由到舰队 skill → 引导拉起舰队 |

## 5. 业务规则

| # | 规则 |
| --- | --- |
| BR1 | **角色仍是 6 个独立会话**；SKILL 只做入口与说明书，不合并角色 |
| BR2 | 角色卡**必须**继续 `--append-system-prompt` 常驻注入；不得改为按需 skill 加载（会丢红线常驻） |
| BR3 | 项目根 `AGENTS.md` 仍是项目级单一事实来源，由 PM 维护、pi 自动注入 |
| BR4 | 迁移期旧路径可用；每条旧路径提示迁移，每版本最多一次（禁刷屏） |
| BR5 | 机制文件单一事实来源在 npm 包内；项目内不存机制副本（shim 除外） |
| BR6 | `.pi/settings.json` 记录 pin 版本，不用浮动版本 |

## 6. NFRs（业务视角基线 → 待架构师转译技术指标并回执）

| # | 业务 NFR | 可接受下限 |
| --- | --- | --- |
| NFR1 | 迁移期下游可用性 | 下游 4 仓零改动，`check` 仍绿 |
| NFR2 | CI 可复现性 | **定稿**：给定 pin + **一条显式物化步骤**（`pi install -l --approve …`）后结果可复现；**nao 机制自身（shim / fleet / check / CLI）零网络调用**；pi 自身的隐式 `npm install` 属**对外边界**（ADR + README 显式记录，不计入 nao 的隐式网络依赖） |
| NFR3 | 离线可用性 | **定稿**：nao 机制未物化 ⇒ `exit 2` + 可读错误 + 可复制恢复命令，**不静默**；pi 未装/离线由 pi 自身报错（可读、非 0 退出），nao 不做二次包装 |
| NFR4 | 常驻 token 增量 | 仅 +1 条 skill description（≤1024 字符）；角色卡不回归膨胀 |
| NFR5 | 安装/升级耗时 | 不引入需人工介入的多步流程 |

> **已定稿**（2026-10-08，按 arch 终签口径）。

## 7. AC

| AC | 类型 | Given / When / Then |
| --- | --- | --- |
| AC1 | 主路径 | Given 干净项目，When `pi install --local` + `init`，Then 足迹 = `AGENTS.md` + `.pi/settings.json` + `.pi/npm/`（**未跟踪**，pi 自建 `.gitignore`）+ `.agents/`(shim)，且 `bash .agents/scripts/nao-fleet.sh check` exit=0；**注册 skill 数恰为 2 且无 collision 诊断** |
| AC2 | 主路径 | Given 普通 pi 会话（未跑 fleet），When 用户提需求，Then 舰队 skill 可被发现/加载，并给出「拉起舰队」指引 |
| AC3 | 异常 | Given pi 未装 / npm 不可达，When 执行 `init` 或 shim，Then 可读错误 + 降级指引 + 非 0 exit（不静默成功） |
| AC4 | 边界 | Given 已装旧版（全套 `.agents/` + `.nao-version`），When 迁移，Then 旧文件备份 `.agents/.nao-obsolete/`、shim 就位、旧路径全部可用、迁移提示仅一次 |
| AC5 | 负向闭环 | Given 下游 nao-todo 与 nue-ui（**不改任何文件**），When 跑 `check`/`ensure`，Then 正常；main 上本需求恰好 1 条提交、无 `wip()` |
| AC6 | 设计一致性 | Then 全仓 `.agents/**` 引用与 `check` 交叉引用校验一致；README / ARCHITECTURE.md / 模板与新形态对齐 |
| AC7 | 治理 | Then 作为一次明确基线变更发布：sha 基线变化说明 + 下游通知清单 + 迁移指引落 `docs/` |
| AC8 | 非范围守护 | Then diff 审查确认：角色数量、注入方式、闸门语义未变（BR1/BR2） |

## 8. 待验证项（前置，不验证不实现）

| # | 待验证 | 影响 |
| --- | --- | --- |
| V1 | pi 项目级 npm 包**实际落盘路径**；`PI_PACKAGE_DIR` 能否稳定解析 | 决定 shim / `exec` 实现 |
| V2 | skill 目录内 `references/*.md` 是否被登记为独立 skill | 决定 checklists 能否内聚（现行决策是「移出 skills/ 避注册」） |
| V3 | **无 pi 会话的 CI** 如何跑 `check`（npx 转发 / 本地缓存 / 最小副本） | 决定 NFR2 与下游 CI 影响面 |

## 9. 上线闭环 / 变更治理

| 项 | 内容 |
| --- | --- |
| 闭环 | Issue #18 → `feat/18-pi-package` Draft PR → CI 绿 → PM 核 AC → RD squash 合并 → tag `v0.12.0` + release notes → 下游通知 |
| 降级 | 无 `gh`/无远端时本地 `merge --squash`，流程不变，`tasks-state` 标注降级 |
| 治理 | shim 保留 **2 个 MINOR**；移除 = `1.0.0`；extension 化独立立项 |

## 10. 优先级

| 环节 | 结论 |
| --- | --- |
| 战略筛子 | **通过（工程基座类）**——不属于「Token 优先」主轴，不宣称 token 收益 |
| MoSCoW | Must：包化 + skill 入口 + 兼容 shim + 引用重写；Should：CLI 迁移命令；Could：pi gallery 元数据；Won't：extension 化 |
| RICE | R=6 · I=1（中）· **C=0.85**（E2/E5 实测抬升）· E=4 人周 → **≈1.3** |
| Kano | 目录内聚 = Must-be；skill 入口 = Attractive |

---

# 附：决策台账与实施闸门（2026-10-08 定稿）

> 本区由 PM 维护；来源：用户决策（D1/D2）+ PM 裁定（D3–D8）+ arch-designer 终签（T0 二审）。ADR 正文见 `docs/adr/2026-10-08-nao-skills-single-skill-pi-package.md`。

## 11. 决策台账

| # | 决策 | 内容 | 来源 |
| :--- | :--- | :--- | :--- |
| D1 | 包内布局 | **A′**：机制单一事实来源在包内 `.agents/`，项目 `.agents/` 仅 shim；`NAO_SKILLS` 语义 = **机制包根** | 用户 |
| D2 | `.pi/npm/` Git | **gitignore**（pi 自建 `.gitignore` 已忽略）；代价 = clone 即得不成立，需一条显式物化命令 | 用户 |
| D3 | skill 声明 | **按文件声明两个**：`./.agents/skills/nao-fleet/SKILL.md` + `./.agents/skills/frontend-design/SKILL.md`（注册数 1→2，**增量恰 +1**）；不声明 `pi.prompts`（BR2） | PM |
| D4 | 下游 CI | **维持 0 改动**（实测 4 仓 CI 不调用 `check`） | PM |
| D5 | 不可运行退出码 | **`exit 2` + 单行 `DEGRADED:`**（与「能跑但失败 = 1」区分）；T1 建议的 70 作废 | PM |
| D6 | shim 解析序 | `NAO_SKILLS`(显式) → `.pi/npm`(项目 pin，主) → `~/.pi/agent/npm`(须校验版本 == pin) → 显式失败；用 **node resolve** 定位，不硬编码包名 | PM |
| D7 | shim 防重入 | **硬要求**：marker env（`NAO_SHIM_ENTERED`）命中即 `exit 2`；**并**校验解析出的包根 ≠ shim 自身所属项目根（双重防护） | PM |
| D8 | 环境锚点 | **落点三处**（已校正）：① `nao-fleet.sh` `build_system_prompt()` 的锚点语义/取值（`NAO_SKILLS` 由「项目根/角色卡根」→「机制包根」）+ 与 D7 配套（写入值不得使 shim 自指）；② `.agents/templates/AGENTS.md.example` §指针 + 各角色卡/技能内 `$NAO_SKILLS/.agents/...` 表述；③ **不主动往下游 `AGENTS.md` 写入锚点**（保持零改动；实测 4 仓 `AGENTS.md` 中 `NAO_SKILLS` 出现 0 次） | PM 修正 |

### 已被证伪 / 作废的判断（留痕，避免复用）

| 判断 | 结论 |
| --- | --- |
| 「下游 CI 依赖 `check`」 | **作废**：4 仓 workflows grep `nao-fleet` / `nao-skill` / `.agents` **0 命中** |
| 「下游 `AGENTS.md` 记录了 `NAO_SKILLS` 环境锚点」 | **作废**：4 仓 `AGENTS.md` 中 `NAO_SKILLS` **0 次**；锚点由 `build_system_prompt()` 注入**系统提示**（`nao-fleet.sh:821-827`），fleet 也**不 export** `NAO_SKILLS` |
| `PI_PACKAGE_DIR` 可定位用户包 | **证伪**（T1 V1）：它是 pi **自身**包根 override，会话内未导出 |
| 「`checklists` 必须移出 `skills/` 才能避注册」 | **放宽**（T1 V2）：置于**含 `SKILL.md` 的 skill 目录之下**即安全；但 `.agents/skills/`（mode=agents）下**无 `SKILL.md` 的子目录**裸 `.md` **会**注册 |

## 12. T2 实施闸门（arch 终签条件，完成/合并前必须落实）

| 闸门 | 要求 |
| :--- | :--- |
| **A** | **D2∧D4 后果写入 ADR/README**：`.pi/npm/` 全 gitignore ⇒ fresh clone 上 `npm ci --prefix .pi/npm` **不可用**（无 package.json/lockfile）⇒ 无 pi 环境的物化路径**当前不存在**，物化只能靠 `pi install -l --approve`。**联动条款（已认可）**：将来任一仓要把 `check` 进 CI（D4 变更）⇒ **必须同时改 D2**（`git add -f .pi/npm/package.json .pi/npm/package-lock.json`） |
| **B** | **pi 隐式安装边界**：ADR + README 记录「pi 启动隐式 `npm install --prefix .pi/npm --legacy-peer-deps`，离线空缓存 → 可读 npm 报错 + `pi exit 1`」与纪律「**先显式物化，再 `PI_OFFLINE=1` 运行**」；nao 机制零网络需**可执行断言**（无网环境 `check` exit 0；删 `.pi/npm` 后 exit 2 + `DEGRADED:`） |
| **C** | **D3 去重规则**：迁移删项目 `.agents/skills/frontend-design/`（备份 `.nao-obsolete/`）；使用 `skills-lock.json` 的仓（nue-ui / nao-todo-server）定义**唯一权威来源**（采纳：nao 包为唯一来源，移除 lock 侧重复项）；T2 验证「注册数 == 2 且无 collision 诊断」 |
| **D** | **迁移精准删除**：`.agents/skills/` 为**共享目录**（nue-ui 另有 `nue-ui-dev` / `agent-browser` / `find-skills` / `skill-creator`；nao-todo 另有 `nue-ui`）⇒ **禁止整目录删除**，只删已知 nao 资产并备份 |

## 13. 特例与待办

- **`nao-todo-minimal` 特例裁定**（已确认）：无脚本、nao-fleet 引用 0 命中、仅 `.agents/{commands,prompts}` ⇒ **不建 shim、不进 CI 范围**；迁移为纯文档/指针处理，纳入 T3 但零 shim。T3 需确认 `.agents/commands/` 非 pi skill 扫描面。
- **T2 收尾**：清理 `/tmp/t1` 临时目录。
- **D4→D2 联动条款**：已认可，作为变更治理条款长期有效（见 §12-A）。
