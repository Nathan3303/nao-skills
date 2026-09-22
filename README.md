# nao-skills

多角色 AI 开发舰队的**角色卡 / 技能 / 协作协议 / 工具链**包，基于 [pi](https://pi.dev)（Agent Skills 标准 + pi-intercom 多会话）。Made by [Nathan Lee](https://github.com/nathan)。

核心命题：**用最少的 Token，把多个专业 Agent 会话组织成一个可靠交付的团队**——常驻精简、按需加载、机器强制、终态回执。

## 整体架构

```text
┌──────────────────────────────────────────────────────────────────┐
│ 项目级上下文   AGENTS.md（PM 维护 · pi 自动注入所有会话 · 最高优先级）│
├──────────────────────────────────────────────────────────────────┤
│ 协作层    pi-intercom：派发 / ask-reply / 终态回执闸门             │
│          PM=状态权威：忙闲闸门 → 排队/抢占 → 验收 → 归档            │
├──────────────────────────────────────────────────────────────────┤
│ 单一事实来源   roles.yaml（aliases→id→card）· 卡片 frontmatter     │
├──────────────────────────────────────────────────────────────────┤
│ 常驻层（每轮计费，刻意精简）                                      │
│          角色卡：身份/职责/2-3 条最硬红线/按需指针                  │
│          common/：output-format + intercom-protocol              │
├──────────────────────────────────────────────────────────────────┤
│ 按需层（渐进式披露，零常驻 token）                                │
│          skills/   DDD 细节 · codegraph · commit                 │
│          checklists/（独立于 skills/，避 pi 注册）· frontend-design/│
│          templates/   frontend-ui · AGENTS.md · tasks-state 骨架 │
├──────────────────────────────────────────────────────────────────┤
│ 工具层    nao-fleet.sh（ensure/check/status）+ ui-tokens-check   │
├──────────────────────────────────────────────────────────────────┤
│ 外部能力  CodeGraph 索引（代码定位，替代 grep 全文扫描）           │
└──────────────────────────────────────────────────────────────────┘
```

### 分层职责

| 层 | 内容 | Token 特性 |
| --- | --- | --- |
| **项目级** | 项目根 `AGENTS.md`（PM 维护 §七）：项目属性/约束，pi 自动注入所有会话 | 常驻（限 <120 行） |
| **协作层** | pi-intercom：`--name` 注册身份，send/ask/reply 线程化；终态回执闸门（`[编号] done \| <role>` 必回） | 消息短、详情落盘 |
| **单一事实来源** | `roles.yaml` 管别名→角色；卡片 frontmatter `version` 管版本；两处互相校验（`check`） | 无重复维护 |
| **常驻层** | 5 张角色卡（60–112 行）+ 2 份 common 规范——每轮每会话计费，**刻意保持最小** | 最贵，最小化 |
| **按需层** | skills + checklists + templates：只有 description 常驻，完整指令按需读取（Agent Skills 标准渐进式披露） | 常态零成本 |
| **工具层** | fleet 拉起/体检/状态；ui-tokens-check 硬编码色值扫描（可接 CI） | 一次性执行 |
| **外部能力** | CodeGraph：`context` 一次返回相关符号+代码块（实测约 1/17 于 grep+全文） | 查找精准化 |

## 核心设计：Token 优先

1. **常驻最小化**：红线/清单/速查表全部按需化到 `checklists/`（独立目录，避开 pi skill 扫描），卡片只留最硬红线 + 指针。
2. **按需加载**：Agent Skills 渐进式披露——DDD 细节、官方 frontend-design、checklists 均按需读，不占常驻。
3. **缓存友好**：system prompt 稳定 = 前缀缓存命中（cacheRead 约 1/10 价）；改卡**批量一次到位**，易变内容放消息体不进卡片；`cacheWarming: "idle"` + `/session` 观察。
4. **查找精准**：CodeGraph `context`/`node`/`callers`/`impact` 替代 grep+cat 全文；不可用时降级 grep + `sed` 行段读取（禁 cat 全文）。
5. **上下文生命周期**：任务闭环 → `ensure --force` 重开会话（优于自动压缩）；PM 靠 `docs/` 落盘延续，不靠历史消息堆叠。

## 上下文三层分层

| 层 | 载体 | 维护者 | 内容 |
| --- | --- | --- | --- |
| **项目级（最高）** | 项目根 `AGENTS.md` | PM（§七） | 项目属性/约束/机制衔接；pi 自动注入所有会话，**优先于角色默认习惯** |
| **团队级** | `roles.yaml` + `common/` | nao-skills 仓库 | 角色清单、协作协议、终态回执、缓存纪律 |
| **角色级** | `prompts/` + `skills/` + `checklists/` | nao-skills 仓库 | 角色身份/边界、按需技能、交付清单 |

各层各写各的、不互相复制；项目已有非空 AGENTS.md 时**合并追加**（保留原文 + `## nao 舰队接入` 区块，可回退），不覆盖。

## 协作闭环（PM 为 leader）

```
用户提需求 → PM grill-me 澄清 → 9 模块 PRD + RICE
  → 开工确认卡（用户确认）→ AGENTS.md 项目上下文就绪（新建/合并）
  → fleet ensure 拉起缺线角色 → 架构评审闸门（arch 签字 / ADR）
  → send 派发（忙闲闸门：idle 才派 / 忙则排队 / 紧急抢占）
  → worker 终态回执 `[编号] done`（未回执 PM 主动追讨）
  → 验收闭环（AC 五覆盖）→ tasks-state.md 更新 → docs/prds 当日归档
```

## 任务调度：状态机 + 忙闲闸门 + 可恢复

PM 是任务状态权威，以状态机驱动执行：

| 状态 | 转移条件 |
| --- | --- |
| `queued`（待派发） | 目标忙碌（`thinking`/`tool:*`），记入 `docs/tasks-state.md` |
| `dispatched`（进行中） | `list` 显示目标 `idle` 才派完整任务 |
| `done`（已回执） | worker 回 `[编号] done`；PM 校验后进入验收 |
| `verified`（已验收） | AC 五覆盖核对通过，归档 `docs/prds` |

- **忙闲闸门**：`list` 的 live status（`idle`/`thinking`/`tool:*`）为判定依据；忙时**不 send 任务内容**（非交互拒收 / 交互 steer 打断），直接排队；紧急才抢占（交互可 steer 注入 + 注明挂起，非交互只能排队）。
- **状态外部化**：`docs/tasks-state.md` 五栏（待派发/进行中/待验收/挂起/已归档）随每次派发·回执·验收更新；PM 会话重开先读文件重建状态，不依赖历史消息。

- **终态回执硬闸门**：所有角色（含 arch 评审）必须以回执模板结束任务；`send` 失败降级 `ask` → 再失败才降级交付。
- **卡片版本同步**：改卡 bump `version` 并广播 `card <role> vN`（不贴全文）；worker 接任务前核对版本，stale 则重读。
- **降级**：PM 可达必须回执；intercom 不可用才允许"本会话直接产出 + 用户转交"。

## 代码定位（CodeGraph）

`@.agents/skills/codegraph.md`（按需）——`query`/`context`/`node`/`callers`/`callees`/`impact`/`affected` 速查 + token 纪律 + 降级 grep 规则。索引项目级维护：`status` → `init`/`sync`；`nao-fleet.sh` 的 `check`/`ensure` 自动探测索引健康并提醒。

## UI/UX 落地（三层，不绑定组件库）

| 层 | 载体 | 职责 |
| --- | --- | --- |
| 设计质量层 | 官方 `frontend-design` skill（按需） | 视觉方向、反 AI 味、typography |
| 约束层 | Design Tokens（`--<prefix>-*`）+ UX Playbook + `ui-tokens-check.sh` | 令牌收敛、四态/反馈一致、机器扫描 |
| 验收层 | checklist rd-fe / qa | 交付前核对 + QA 视觉验收 |

模板：`templates/frontend-ui/`（tokens.css + ux-playbook 骨架，任意项目复制裁剪）。

## 角色卡（常驻 system prompt）

| Prompt | Role | 核心职责 |
| --- | --- | --- |
| `product-manager.md` | 产品经理（调度者） | 需求全生命周期、9 模块 PRD、RICE、多会话调度、终态回执闸门、**§七 AGENTS.md 项目上下文治理**、§十一 docs/prds 归档 |
| `architecture-designer.md` | 系统架构师（评审/咨询） | 技术选型四步法、评审签字 + ADR、终态回执 PM、降级规则 |
| `frontend-developer.md` | 前端研发 | 前端 DDD 五层、UI/UX 三层落地（引用 frontend-design） |
| `backend-developer.md` | 后端研发 | Go DDD 四层、依赖倒置、事务/事件/错误约定 |
| `test-engineer.md` | 测试工程师 | 测试金字塔、AC=用例、缺陷闭环、视觉验收 |

所有角色卡头部均声明：**项目根 `AGENTS.md` 已由 pi 注入、最高优先级、优先于本卡默认习惯**（含各自执行点：arch 评审输入、RD 命令纪律、QA 环境运行）。

## 按需技能

| Skill | 用途 |
| --- | --- |
| `frontend-ddd-details.md` | 前端 DDD 骨架/场景速决/命名/误区 + UI/UX 落地 |
| `backend-ddd-details.md` | 后端 DDD 骨架/事务/事件/命名/误区 |
| `arch-patterns.md` | 架构模式、ADR 模板 |
| `pm-rice.md` / `pm-grill.md` | RICE 优先级 / 需求澄清 |
| `test-design.md` | 用例设计、缺陷管理、分层对齐 |
| `codegraph.md` | 代码定位（替代 grep 全文） |
| `commit.md` | git commit 规范（仅提交前读） |
| `frontend-design/` | 官方视觉方向 skill（设计类任务先读） |
| `checklists/*.md` | 各角色完整红线 + 交付检查清单（交付前读） |

## 工具链

```bash
.agents/scripts/nao-fleet.sh check                    # 体检：roles.yaml/卡片/交叉引用/白名单/布局/CodeGraph
.agents/scripts/nao-fleet.sh status                   # 角色在线状态（权威名单见 intercom list）
.agents/scripts/nao-fleet.sh ensure arch rd-fe        # 拉起缺失角色
.agents/scripts/nao-fleet.sh ensure rd-be@/path/repo  # 指定后端 repo（含 CodeGraph 索引提醒）
.agents/scripts/ui-tokens-check.sh <repo>             # 扫 UI 硬编码色值（绕过 Design Tokens）
```

## 安装（npm 发布）

发布为 **`@nathan33/nao-skill`**，提供 `nao-skill install` CLI 一键接入项目：

```bash
npm install -g @nathan33/nao-skill          # 全局安装 CLI
# 或在任意项目里直接：npx @nathan33/nao-skill install

nao-skill install                            # 安装到当前目录
nao-skill install /path/to/proj --force      # 指定目录；--force 覆盖同名文件
```

- **安装内容**：`.agents/` 全套（角色卡 / 技能 / 交付清单 / 协议 / roles.yaml / 工具链 / 模板）+ 生成 `AGENTS.md`（已存在则提示按 §七 合并，不覆盖）。
- **合并策略**：目标已有同名文件默认保留项目既有（避免覆盖自定义）；`--force` 备份后覆盖。
- **发布**：`npm publish --access public`（scope 包需 `--access public`）。

## 目录结构

```text
nao-skills/
└── .agents/
    ├── common/                    # 常驻规范（全部角色引用）
    │   ├── output-format.md       # 输出/回执模板、反模式
    │   └── intercom-protocol.md   # 多会话协议、终态回执、版本同步、缓存纪律
    ├── roles.yaml                 # 角色清单（aliases→id→card，单一事实来源）
    ├── prompts/                   # 角色卡（frontmatter: role/version/updated）
    │   ├── product-manager.md     └── architecture-designer.md
    │   ├── frontend-developer.md  └── backend-developer.md
    │   └── test-engineer.md
    ├── checklists/                 # 红线+交付清单（交付前读；独立于 skills/ 避免被 pi 注册为同名 skill）
    │   ├── pm.md / architecture-designer.md / rd-be.md / rd-fe.md / qa.md
    ├── skills/                    # 按需技能（渐进式披露）
    │   ├── frontend-design/       # 官方设计方向 skill（按需）
    │   ├── frontend-ddd-details.md / backend-ddd-details.md
    │   ├── arch-patterns.md / pm-rice.md / pm-grill.md
    │   ├── test-design.md / codegraph.md / commit.md
    ├── templates/                  # 项目接入骨架（供复制裁剪）
    │   ├── AGENTS.md.example        # 项目级上下文（PM 维护，合并规则见 PM 卡 §七）
    │   ├── tasks-state.md.example   # 任务状态机落盘（待派发/进行中/待验收/挂起/已归档）
    │   └── frontend-ui/             # tokens.css + ux-playbook 骨架
    └── scripts/
        ├── nao-fleet.sh           # 会话拉起 / 在线状态 / 静态体检
        └── ui-tokens-check.sh     # UI 硬编码色值扫描
```

## License

MIT © 2026 Nathan Lee
