# nao-skills

> 给你的 AI 编程助手配一支「开发小队」：你提需求，它自己找人干活、自己验收交付。

nao-skills 是一套 **角色卡 + 协作规矩 + 小工具**。装上以后，你的项目里会有 6 个分工明确的 AI 会话——产品经理负责拆需求、派活、验收；前端、后端、测试各自干活；工程基座管构建发布与治理。你只做两件事：**回答问题**、**点确认**。

基于 [pi](https://pi.dev)。Made by [Nathan Lee](https://github.com/nathan)。

## 它解决什么问题

一个人对着 AI 写代码，常见三个毛病：

| 毛病 | nao-skills 的做法 |
| --- | --- |
| 一个会话什么都干，聊到后面就糊涂了 | 拆成 6 个专业角色，各管一段，互不干扰 |
| 需求没问清楚就开写，写完发现不对 | PM 先追问、写清 PRD 和目标，你点头才开工 |
| 干完不知道算不算干完 | 每个任务必须「回执」并按清单自查，PM 逐条验收才归档 |

## 安装（1 分钟）

> 前置依赖：[pi](https://pi.dev)。没装 pi 也能看到这套文件，但跑不起来舰队。

1. **把机制装进项目**（项目级，版本 pin 在仓库里，团队 clone 即得同款）：

   ```bash
   cd 你的项目
   pi install --local npm:@nathan33/nao-skill@0.12.0   # 声明 pin + 把机制包物化到项目内 .pi/npm
   npx @nathan33/nao-skill init                        # 写入转发 shim + 生成 AGENTS.md
   ```

2. **装协作插件**（多会话派活必需）：

   ```bash
   npx @nathan33/nao-skill plugins install-all
   ```

升级：改 `.pi/settings.json` 里的 pin 版本，再 `pi update --extensions`（机制以包为准，项目里只有 shim）。

**老项目迁移**（曾在项目里铺开整套 `.agents/` 的）：

```bash
npx @nathan33/nao-skill migrate   # 旧文件备份到 .agents/.nao-obsolete/，shim 就位，旧命令照跑
```

## 用起来（3 步）

```bash
.agents/scripts/nao-fleet.sh check                          # 体检：一行 OK 就能开工
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra   # 拉起 6 个角色会话
```

角色名可以写**别名**或**规范名**（两者等价）：`arch` = `arch-designer`、`infra` = `rd-infra`；上例里两者混用也照常拉起。完整别名表见 `.agents/roles.yaml` 或 `nao-fleet.sh --help`。

然后**在 PM 会话里说需求**就行，剩下的它自己流转。大概长这样：

```text
你：想加个「导出 CSV」功能
PM：问几个问题 → 给出 PRD + 优先级 + 开工确认卡
你：开工
PM：拉起缺的角色 → 让 qa 先写用例 → 指派给 rd-be
rd-be：（做完）[T1] done | 测试：npm test exit=0 128例/0红 | PR #12
PM：在 PR 核 AC 并评论 → 验收通过（授权合并）→ rd-be squash 合并 → 归档 docs/prds/ → 回收后台会话
```

每个任务完成后都能在 `docs/` 里找到痕迹（PRD、任务状态、回报），不依赖聊天记录——所以会话聊久了可以直接重开，不会丢事。

## 六个角色

| 角色 | 帮你干什么 |
| --- | --- |
| 产品经理 | 澄清需求、**调研同类产品形态**、写 PRD、定优先级、派活、验收、归档、**管 Issue 与发版**（PR 验收评论、tag/release，优先 `gh`；唯一的调度者，不写代码、不合并） |
| 架构师 | 技术选型与方案评审（**对照业界成熟模式**并写明为何不采纳），出 ADR，评影响面 |
| 前端 / 后端研发 | 各自实现，写完自己跑测试再回执 |
| 工程基座 | CI 与流水线、构建/发布工具、脚本与守卫、依赖与安全告警升级、仓库治理 |
| 测试工程师 | 按验收标准出用例、跑门禁、报缺陷 |

不想要哪个角色，删掉对应文件即可；只留 PM + 一个研发角色也能跑。

## 可选：关键节点 QQ 主动推送

装上 [`pi-agent-qqbot`](https://github.com/Nathan3303) 并配好 `~/.pi/agent/pi-agent-qqbot.json`（`appId` / `clientSecret` / `ownerOpenId` / `sandbox`）后，PM 可把**关键节点**主动推到你 QQ——批次进度汇总、验收结论、发版或合并完成、异常阻塞：

```bash
$NAO_SKILLS/.agents/scripts/qq-notify "[T301] 验收通过 · PR #4 已合并 · v0.8.0"
$NAO_SKILLS/.agents/scripts/qq-notify --dry-run "连通性自检"      # 只取 token、不发送
```

**为什么默认不主动打扰**：这是**可选能力**——没配 `pi-agent-qqbot` 就自动视为未启用；四类节点之外不发，一个节点最多一条（禁刷屏）；推送失败只记回执行风险项，**不阻断交付**。默认走 sandbox（测试环境），正式发布通知才考虑 prod。能力边界、退出码与纪律见 `$NAO_SKILLS/.agents/skills/qq-notify.md`。

## 为什么它省 token（这是本项目的核心追求）

和 AI 聊天，钱花在「它每轮要读多少字」。所以：

- **常驻的东西尽量小**：每个角色卡只留最硬的红线，细节放到用到时才读的文件里。
- **按需才读**：设计规范、检查清单、读代码手册，都是在需要那一刻才读进上下文。
- **不靠聊天记录记事**：任务状态和待办写在 `docs/` 文件里；会话重开先读文件恢复状态。
- **查代码用索引**：配了 CodeGraph 就一次拿到相关代码块，比全文搜索省一个数量级。

一句话概括定位：这是在给 AI 做「上下文工程」——决定每个会话**该看到什么、不该看到什么**；在这之上再叠了多会话协作和交付纪律。它自己不跑 AI，产出的是给 AI 读的 Markdown。

## 常见问题

**会改我的代码库吗？** 只会新增项目根 `AGENTS.md`、`.pi/settings.json`，以及一个转发入口 `.agents/scripts/nao-fleet.sh`；角色卡、清单、技能这些机制文件都在依赖包内，**不再铺进你的仓库**，也不碰你原有文件。

**只能用 pi 吗？** 角色卡和技能本质就是 Markdown，Claude Code 等也能读；但"派活 / 回执"这种多会话协作依赖 pi + pi-intercom 插件。

**它会在 GitHub 上开 PR 吗？** 会——每个需求一条分支、一个 PR（Draft 早开、CI 早跑），你确认验收后由研发角色 squash 合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。

**跑完的会话要留着吗？** 后台派生会话验收完可以回收：`nao-fleet.sh close --task T1 rd-be`（等价写法 `nao-fleet.sh close rd-be-T1`，直接用派生会话名即可）；常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留。目标在别的项目里也能回收——`close` 会按名册/窗口标题跨项目定位；定位不到时会**非 0 退出并打印诊断**，不会假装已回收。

**终端窗口太挤怎么办？** tmux 宿主支持三种布局：默认 `main-row2`（主会话占左，其余往右分列）、`main-col`（其余在右列竖排）、`grid`（等大网格）。窗口太窄时 `main-row2` 会**自动回退** `main-col`、仍不够再退 `grid`，并打印带数字的提示（不中断拉起）；用 `NAO_TMUX_LAYOUT` / `NAO_TMUX_MAIN_WIDTH` / `NAO_TMUX_MIN_PANE_WIDTH` 调整，详见 `bash .agents/scripts/nao-fleet.sh --help`。

**它会自己上网查吗？** 会，但有分工：产品经理查同类功能的**产品形态**（有哪些功能点、属性、视图、协作方式），架构师对照**业界成熟的架构模式**。两者都必须把来源和「适不适用本项目」落成文件（`docs/research/`），抓来的网页内容不会堆进聊天记录；技术选型仍然只由架构师定。

**装完之后项目里多了什么？**

```text
你的项目/
├── AGENTS.md              # 项目级约定（PM 维护，AI 每次都会读）
├── .github/               # PR 模板（PM 建，GitHub Flow 用）
├── .pi/
│   ├── settings.json      # 记录机制包的 pin 版本（进仓库）
│   └── npm/               # pi 把机制包物化在这里（pi 自建 gitignore，不提交）
└── .agents/
    └── scripts/
        └── nao-fleet.sh    # 转发入口（shim）：自动定位包内机制并转发
```

机制本体（6 张角色卡、协作规矩、清单、按需技能、小工具）都在 npm 包 `@nathan33/nao-skill` 的 `.agents/` 里——**包里是什么就是什么**，项目里不留副本。

## 发布形态与完整性判据（0.12 起有变化）

**从 0.12 起，机制不再铺进项目**：项目里只留一个转发入口，机制的**单一事实来源**是 npm 包 `@nathan33/nao-skill` 内的 `.agents/`。

- **旧的完整性判据已失效**：以前下游靠「项目内 `.agents/**` 与上游逐字节 sha 一致」证明机制没漏没改；现在项目内不再有机制副本，这条判据不再适用。
- **新的完整性判据：以 pin 的包版本为准**。`.pi/settings.json` 记录版本，`pi install/update` 从包物化；包里是什么就是什么，不存在「项目内被就地改动」的问题。转发入口是生成的固定文本，可用 `npx @nathan33/nao-skill init` 幂等重写核对。
- **版本权威口径**：`.pi/settings.json` 里的 pin 是**唯一权威**（`pi install/update` 据此物化到 `.pi/npm`）；`.agents/.nao-version` 只是本机安装标记（供升级检测与迁移提示），**不作为版本依据**；两者不一致时**以 pin 为准**。
- **fmt 边界**：包内 `.agents/**` 仍以上游原始存储形态发布（部分 YAML / Markdown / MTS 未按 oxfmt / prettier 归一）。迁移期仍持有旧版全套 `.agents/**` 的仓库，继续把 `.agents/**` 排除出 fmt 校验即可，⛔ **不要为过 fmt 就地格式化**；新形态项目内只有转发入口，无需再处理。

### 物化与离线（CI / 无 pi 环境必读）

- `.pi/npm/` 由 pi 管理并 **gitignore**。因此 **fresh clone 上没有 `.pi/npm/package.json` 与 lockfile**，`npm ci --prefix .pi/npm` 当前**不可用**。
- 物化只有一条路：**显式执行** `pi install -l --approve npm:@nathan33/nao-skill@<pin>`（需要 pi 与网络，是有意为之的一步）。
- **联动条款**：若某个仓库想把机制体检 `check` 放进 CI（即改变「下游 CI 零改动」的约定），**必须同时**用 `git add -f` 把 `.pi/npm/package.json`、`.pi/npm/package-lock.json` 纳入版本控制，`npm ci` 才有输入。
- **pi 启动的隐式安装**：当 `.pi/npm/node_modules` 缺失时，pi 启动会隐式执行 `npm install --prefix .pi/npm --legacy-peer-deps`；离线且缓存为空会得到可读的 npm 报错，并让 pi 以非 0 退出（不会静默假装成功）。
- **运行纪律**：**先显式物化，再 `PI_OFFLINE=1` 运行**。nao 机制自身（转发入口 / fleet / CLI / check）**零网络调用**；入口找不到机制包时不静默成功，而是 `exit 2` 并打印一行 `DEGRADED:` + 恢复命令。

## 下游仓库迁移（nao-todo / nao-todo-server / nue-ui）

- **迁移期零改动**：旧的全套 `.agents/scripts/nao-fleet.sh` 照常可用，这些仓库的 CI 目前不调用 `check`，不受影响。
- 想切到新形态时，在各仓执行 `npx @nathan33/nao-skill migrate`：只删**已知 nao 资产**（共享的 `.agents/skills/` 里项目自有的技能会保留），并把 `skills-lock.json` 里重复的 `frontend-design` 来源收敛为「机制包唯一来源」。
- **`nao-todo-minimal` 特例**：无脚本、无 nao-fleet 引用 ⇒ **不建转发入口**，按纯文档/指针迁移；它的 `.agents/commands/`、`.agents/prompts/` 不在 pi 的 skill 扫描面（pi 只扫 `.agents/skills/**`）。

## 想深入

README 只讲怎么用。真正的机制都在依赖包 `@nathan33/nao-skill` 的 `.agents/` 里（会话里以 `$NAO_SKILLS/.agents/` 指向），想改就从这几处入手：

| 想看什么 | 去哪看 |
| --- | --- |
| 整体架构、分层与设计取舍 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 派活 / 回执 / 忙闲与回收规矩 | `$NAO_SKILLS/.agents/common/intercom-protocol.md` |
| 输出格式与回执红线 | `$NAO_SKILLS/.agents/common/output-format.md`、`$NAO_SKILLS/.agents/checklists/comm-templates.md` |
| 角色怎么定义 | `$NAO_SKILLS/.agents/prompts/*.md` |
| 各角色的红线与交付清单 | `$NAO_SKILLS/.agents/checklists/*.md` |
| 工具命令 | `bash .agents/scripts/nao-fleet.sh --help`（转发入口） |
| 项目自己的约定 | 项目根 `AGENTS.md` |

## License

MIT © 2026 Nathan Lee
