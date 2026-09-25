# ADR：新增 `rd-infra`（工程基座）角色

- 状态：**提议**（用户已同意新增；本文由 arch-designer 出具设计方案，**不含代码实现**）
- 日期：2026-09-25 · 出具：arch-designer（`T303`）· 落地：RD（见文末「交接」）
- 关联：`.agents/roles.yaml`、`.agents/prompts/infra-engineer.md`（待建）、`.agents/checklists/rd-infra.md`（待建）、`.agents/scripts/nao-fleet.sh`
- 上游依据：PM `docs/tasks-state.md` 已登记「角色设计决策（用户 2026-09-25 同意）」

## 一、背景与问题

舰队现为 5 角色（pm / arch-designer / rd-fe / rd-be / qa）。实测出现一类**无专精角色**的工作：CI 与流水线、构建/发布工具、脚本与守卫（`guard:*`、`nao-fleet.sh`）、依赖与安全告警升级、仓库治理（分支/保护/清理/baseline 合并执行）、lint 与格式化工具链、跨项目安装器与分发、开发环境排障。

这些工作目前落在 **rd-be 兜底**（例：nao-skills `T301`/`T302` 由 rd-be 承担）。兜底带来三个可观测成本：

1. **职责漂移**：rd-be 卡（Golang DDD）与这类工作不匹配，卡里的红线/清单**全部不适用**，等于每次都在「无清单交付」。
2. **自查缺失**：这类工作真正要防的是**幂等 / 凭据泄漏 / 权限过大 / 不可自证 / 单项目假设**——没有卡就没有这些红线，只能靠个人记忆。
3. **路由歧义**：PM 无判据可依，每次都要临场决定派给谁（本单 `T303` 正是该歧义的产物）。

## 二、对照过的备选模式（含不采纳理由）

| # | 候选模式 | 适用条件 | 代价 | 结论 |
| :-- | :--- | :--- | :--- | :--- |
| ⓪ | **维持现状**：工程基座由 rd-be 兜底 | 该类工作偶发（<1 批次出现 1 次）、无沉淀价值 | 每次无卡交付；红线/清单不适用；路由靠临场判断 | **不采纳**：已连续两批（T301/T302）出现，且本单背景就是路由歧义 |
| ① | **新增通用开发角色**（generalist，什么都能干） | 出现第三种技术栈业务代码 / 文档成为独立需求流 / 跨角色越界 ≥3 次 / 通用 POC 常态化 | 角色边界失效（回到「一个会话什么都干」）；卡无专精红线 → 无清单可自查 | **不采纳**：PM 给出的四类触发判据**当前四者皆不满足**（判据留下备用） |
| ② | **并入既有角色**：把工程基座挂到 arch-designer 或 qa | 工作量小到可忽略、且与宿主角色同源 | arch 是**零代码**咨询角色（本文即由其出具）；qa 的独立性会被「自建守卫又自验」破坏 | **不采纳**：两者均与角色本质冲突 |
| ③ | **只写清单不改角色**（不新增会话） | 不想要更多会话 | 无专精会话 = 无稳定的决策上下文与缓存前缀；PM 仍要每次路由 | **不采纳**：不解决路由歧义 |
| ④ | **新增专职 `rd-infra`（工程基座）** | 该类工作**持续出现**且**判据明确** | 多一个角色卡/会话；需维护边界与路由纪律 | **采纳** |

> 判据来源：团队拓扑中的 **Platform Team**（为流对齐团队提供「内部产品」以加速交付）与 **Conway 定律**（组织沟通结构会复制到系统结构）——把「基座」从业务团队里切出来独立成角色，正是同一逻辑。（见「参考来源」）

## 三、决策

新增角色 **id = `rd-infra`**，别名 **`infra`**（`aliases: [infra, rd-infra]`，与 `arch-designer` 的「短别名在前 + id 也可解析」写法一致），角色卡 `.agents/prompts/infra-engineer.md`，交付清单 `.agents/checklists/rd-infra.md`。

### 3.1 职责边界（写入卡内）

| | 内容 |
| :-- | :--- |
| **负责** | CI 与流水线 · 构建/发布工具 · **脚本与守卫**（`guard:*`、fleet 脚本） · **依赖与安全告警升级** · **仓库治理**（分支/保护/清理/baseline 合并执行） · **lint 与格式化工具链** · **跨项目安装器与分发** · 开发环境/工具链排障 |
| **不负责** | 业务代码（`rd-fe`/`rd-be`） · 架构决策（`arch-designer`） · 测试断言与独立验收（`qa`） · 需求拆解与验收口径（`pm`） |

### 3.2 判定口诀（必须写进卡里，供 PM 路由）

> **改「业务行为」⇒ `rd-fe`/`rd-be`；改「怎么构建 / 怎么验 / 怎么发 / 怎么治理」⇒ `rd-infra`。**

三条例外（避免口诀被滥用）：

- 架构取舍（选型、分层、契约）**先经 `arch-designer`**，`rd-infra` 只落地已定方案；
- 验收口径与断言归属 `qa`/`pm`，`rd-infra` **不自验自己的守卫**（须由 qa 或 PM 独立核）；
- 工程基座改动**触碰业务语义**时拆单：业务语义部分回 `rd-fe`/`rd-be`。

### 3.3 卡内自检清单要点（PM 指定，写入 `checklists/rd-infra.md`）

| 要点 | 判据（可核） |
| :--- | :--- |
| **幂等** | 同命令连跑 2 次，第 2 次 effect = 0 且 rc=0；重复执行不产生重复条目 |
| **零密钥/零机器特定值入仓** | 仓库内 grep 无 token/私钥/绝对家目录路径；本机值只从环境变量/配置读 |
| **最小权限** | 新增的 CI 权限/scope/Secret 逐项给出「为什么必需」；不申请 `*`/admin |
| **可自证（含失败演练）** | 正常路径 rc=0；**故意破坏 ⇒ 校验/守卫必须报错 ⇒ 还原后复绿**（三段证据齐） |
| **跨项目兼容** | 不做单项目假设（不写死仓库名/相对路径/包管理器）；至少在第二个仓或临时目录验证 |
| **不动红线** | 不改项目 `AGENTS.md` 红线、不改业务源码/测试断言、不改他人未提交文件 |
| **精确提交** | 路径级暂存（禁 `-A`/`.`/`-a`）；只提自己文件时用 `git commit --only <paths>` 并先 `git diff --cached --name-only` 核对 |
| **前后对照数字** | 每项给「改动前 → 改动后」的数字（耗时/体积/条数/宽度…），单跑不算，须对照 |

### 3.4 frontmatter 规格（与既有卡对齐）

```yaml
---
description: 工程基座工程师角色 Prompt（短常驻）——CI/构建发布/脚本守卫/依赖安全/仓库治理
role: rd-infra
version: 1
updated: 2026-09-25
---
```

> `version` 从 `1` 起（新卡）；`nao-fleet.sh check` 会校验 `role` 与 `roles.yaml` 的角色 id 一致、`version` 为整数、`updated` 非空。

## 四、接线清单（逐处，落地时逐条核对）

| # | 文件 | 落点 | 改动 |
| :-- | :--- | :--- | :--- |
| 1 | `.agents/roles.yaml` | `roles:` 末条 | 新增 `rd-infra:` + `aliases: [infra, rd-infra]` + `card: infra-engineer.md` + `workspace: .`（缩进 2/4，禁 Tab） |
| 2 | `.agents/prompts/infra-engineer.md` | 新建 | 按 §3 写卡 |
| 3 | `.agents/checklists/rd-infra.md` | 新建 | 按 §3.3 + `rd-be.md` 的结构与粒度（红线 + 自检 + 交付清单） |
| 4 | `README.md` | L5 / L15 | 「5 个分工明确的 AI 会话」/「5 个专业角色」→ **6** |
| 5 | `README.md` | L36 | `ensure` 示例加 `rd-infra` |
| 6 | `README.md` | L52 标题 + 表格 | 「## 五个角色」→「## 六个角色」；表格加一行（工程基座/CI/发布/守卫） |
| 7 | `README.md` | L104 | 目录树注释「5 张角色卡」→ **6 张** |
| 8 | `.agents/common/intercom-protocol.md` | 别名表 | 加一行：`infra` / `rd-infra` → `infra-engineer` → 当前项目目录 |
| 9 | `docs/ARCHITECTURE.md` | L40 | 「5 张角色卡（74–160 行）」→ 6 张（并复核行数区间） |
| 10 | `.agents/scripts/nao-fleet.sh` | L17 usage 注释 | 「当前：pm / arch-designer(arch) / rd-fe / rd-be / qa」→ 追加 `rd-infra(infra)` |
| 11 | `.agents/prompts/product-manager.md` | §六 | 新增「**路由纪律**」：工程基座类**派 `rd-infra`，不再由 rd-be 兜底**；无匹配角色时按 PM 卡 §九「兜底纪律」显式声明 + 台账登记 |
| 12 | `.agents/prompts/product-manager.md` | §九「转发对象」 | 追加：CI/构建/发布/脚本守卫/依赖安全/仓库治理 → `rd-infra` |
| 13 | `.agents/prompts/product-manager.md` | frontmatter | `version: 19 → 20`、`updated` 更新（改卡必须 bump） |
| 14 | `.agents/checklists/pm.md` | 交付清单 | 加一条路由核对项（工程基座类未误派 rd-be） |
| 15 | `bin/nao-skill.js` | L17 / L184 | 注释与 `ensure` 示例加 `rd-infra` |
| 16 | `package.json` | `version` | `0.8.1 → 0.9.0`（新增能力 = minor） |
| 17 | `docs/releases/v0.9.0.md` | 新建 | 按 `docs/releases/v0.8.x.md` 结构：一句话/亮点/行为/限制/升级注意/回滚 |

**不需要改的地方（已核实）**：`nao-fleet.sh` 的**角色解析与校验全部由 `roles.yaml` 驱动**——`load_manifest()` 动态填充 `ROLE_ORDER`/`ALIAS_ROLE`，`cmd_check()` 遍历 `ROLE_ORDER` 校验 frontmatter（`role`/`version`/`updated`），`check_cross_refs()` 扫描目录。**无硬编码角色表**；唯一硬编码是 usage 注释（第 10 项）。

### 4.1 连带同步清单（含 Owner）

本次决策**改变既有条款**（角色数 5 → 6、PM 新增路由纪律）⇒ 下表列出**所有持有该结论的文档**与各自 Owner；落地时逐项同步，并通知对应 Owner。

| 持有该结论的文档 | Owner | 同步方式 |
| :--- | :--- | :--- |
| `.agents/roles.yaml` · `.agents/prompts/infra-engineer.md` · `.agents/checklists/rd-infra.md` | nao-skills 团队级资产（PM 审批） | 本单落地（同 PR） |
| `.agents/prompts/product-manager.md`（§六 路由纪律 / §九 转发对象 / `version 19→20`）· `.agents/checklists/pm.md` | **PM**（角色卡与清单维护者） | 本单落地；**改卡须 bump version 并按协议广播** `card pm v20` |
| `.agents/common/intercom-protocol.md`（别名表） | nao-skills 团队级资产（PM 审批） | 本单落地 |
| `README.md`（4 处计数 + 角色表）· `docs/ARCHITECTURE.md`（L40 常驻层计数） | nao-skills PM（仓库治理） | 本单落地 |
| `.agents/scripts/nao-fleet.sh`（usage 注释）· `bin/nao-skill.js`（注释与示例） | nao-skills 工具层（PM 审批） | 本单落地 |
| `package.json` `version` · `docs/releases/v0.9.0.md` | nao-skills PM（发版） | 本单落地；tag 指向 main 合并提交 |
| **`nao-todo/AGENTS.md` L95**（硬写 `（pm / arch-designer / rd-fe / rd-be / qa）`） | **nao-todo PM**（项目层文件，**`nao-skill update` 不会改**） | **跨仓：须另派 update 单**（见 §七） |

### 4.2 影响面核查方式（CodeGraph 回退已注明）

nao-skills **无 CodeGraph 索引**（实测 `codegraph status` → `Not initialized`）⇒ 按卡内约定回退 `grep -rn` + 定向读取（禁 `cat` 全文）。核查口径：全仓 grep 角色枚举（`rd-be` / `rd-fe` / `test-engineer` / `5 个` / `五个` 等）+ 逐处读取命中文件，得到 §四 清单。`nao-todo` 侧索引存在（`.codegraph/`），但其 `.agents/` 是上游镜像，**改动仍以上游为准**。

## 五、后果 / 风险

- **收益**：路由歧义消除（口诀 + 例外）；工程基座工作首次拥有可核红线（幂等/凭据/权限/自证/跨项目）。
- **风险 ①：角色膨胀**。缓解：四类判据写入 PM 卡，**不满足就不加通用角色**；`rd-infra` 是「专精类」而非「兜底类」。
- **风险 ②：与 qa 的自验边界**。缓解：`rd-infra` 建守卫，**验收由 qa/PM 独立执行**（例外条款已写入卡）。
- **风险 ③：缓存代价**。新增卡会改变该会话的 system prompt；按缓存纪律**批量一次到位**，不改两遍。
- **风险 ④（本项目特有）**：`rd-infra` 落地前，`T303` 本身仍是「基座工作」——**先由 `rd-be` 落地，之后才生效**（鸡生蛋，见交接）。

## 六、参考来源

| 来源 | 链接 | 访问日期 |
| :--- | :--- | :--- |
| Team Topologies — Key concepts（Platform team 定义：为流对齐团队提供「内部产品」以加速交付） | https://teamtopologies.com/key-concepts | 2026-09-25 |
| Martin Fowler — Team Topologies 书评（团队形态与交互模式） | https://martinfowler.com/bliki/TeamTopologies.html | 2026-09-25 |
| Martin Fowler — Conway's Law（组织沟通结构复制到系统结构） | https://martinfowler.com/bliki/ConwaysLaw.html | 2026-09-25 |
| PM 台账（内部）：`/home/nathan/Project/nao-todo/docs/tasks-state.md` —「角色设计决策（用户 2026-09-25 同意）」 | 本机文件（非外部） | 2026-09-25 |

## 七、交接（**本 ADR 不含实现**）

按 arch-designer 角色边界（`.agents/prompts/architecture-designer.md` §二 零代码红线），本文只出方案，**未修改任何代码/机制文件**。落地请派 **RD**：

- 建议角色：`rd-infra` 尚不存在 ⇒ 由 **`rd-be`** 落地（与 `T301`/`T302` 同一模式：nao-skills 机制工作）；`rd-infra` 建卡后即接管同类工作。
- 建议分支/流程：`feat/rd-infra` + Draft PR（正文引本 ADR），**不 merge commit**。
- 建议门禁：`bash .agents/scripts/nao-fleet.sh check` rc=0 + `npm test` rc=0 + 「失败演练」（`roles.yaml` id 与卡 `role` 故意错配 ⇒ `check` 必须 rc=1 ⇒ 还原）。

**落地里程碑（分 3 阶段，每阶段可独立自证）**

| 阶段 | 范围 | 出口判据 |
| :-- | :--- | :--- |
| **P1 角色资产** | 第 1–3 项（`roles.yaml` + 卡 + 清单） | `check` rc=0 且报告 `roles=6`；新卡 frontmatter 三字段校验通过 |
| **P2 接线** | 第 4–15 项（文档计数、别名表、PM 卡路由纪律、脚本注释、示例） | `check` rc=0；全仓 grep 不再有「5 个/五个角色」残留；交叉引用齐备 |
| **P3 版本与发布** | 第 16–17 项 + 演练 | `check` rc=0 + `npm test` rc=0 + 错配演练 rc=1（还原后复绿）+ release notes 落盘；**版本 `0.9.0`，tag 待 PM 在合并后推** |
