# nao-skills

> 给你的 AI 编程助手配一支「开发小队」：你提需求，它自己找人干活、自己验收交付。

nao-skills 是一套 **角色卡 + 协作规矩 + 小工具**。装上以后，你的项目里会有 5 个分工明确的 AI 会话——产品经理负责拆需求、派活、验收；前端、后端、测试各自干活。你只做两件事：**回答问题**、**点确认**。

基于 [pi](https://pi.dev)。Made by [Nathan Lee](https://github.com/nathan)。

## 它解决什么问题

一个人对着 AI 写代码，常见三个毛病：

| 毛病 | nao-skills 的做法 |
| --- | --- |
| 一个会话什么都干，聊到后面就糊涂了 | 拆成 5 个专业角色，各管一段，互不干扰 |
| 需求没问清楚就开写，写完发现不对 | PM 先追问、写清 PRD 和目标，你点头才开工 |
| 干完不知道算不算干完 | 每个任务必须「回执」并按清单自查，PM 逐条验收才归档 |

## 安装（1 分钟）

```bash
npm install -g @nathan33/nao-skill
cd 你的项目
nao-skill install            # 装 .agents/ 并生成 AGENTS.md（已有则提示按规则追加，不覆盖原文）
nao-skill plugins install-all   # 装协作插件（intercom 等），多会话派活必需
```

升级用 `nao-skill update`（机制文件以包为准，你自己的改动会保留）。

> 前置依赖：[pi](https://pi.dev)。没装 pi 也能看到这套文件，但跑不起来舰队。

## 用起来（3 步）

```bash
.agents/scripts/nao-fleet.sh check                          # 体检：一行 OK 就能开工
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa   # 拉起 5 个角色会话
```

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

## 五个角色

| 角色 | 帮你干什么 |
| --- | --- |
| 产品经理 | 澄清需求、**调研同类产品形态**、写 PRD、定优先级、派活、验收、归档、**管 Issue 与发版**（PR 验收评论、tag/release，优先 `gh`；唯一的调度者，不写代码、不合并） |
| 架构师 | 技术选型与方案评审（**对照业界成熟模式**并写明为何不采纳），出 ADR，评影响面 |
| 前端 / 后端研发 | 各自实现，写完自己跑测试再回执 |
| 测试工程师 | 按验收标准出用例、跑门禁、报缺陷 |

不想要哪个角色，删掉对应文件即可；只留 PM + 一个研发角色也能跑。

## 为什么它省 token（这是本项目的核心追求）

和 AI 聊天，钱花在「它每轮要读多少字」。所以：

- **常驻的东西尽量小**：每个角色卡只留最硬的红线，细节放到用到时才读的文件里。
- **按需才读**：设计规范、检查清单、读代码手册，都是在需要那一刻才读进上下文。
- **不靠聊天记录记事**：任务状态和待办写在 `docs/` 文件里；会话重开先读文件恢复状态。
- **查代码用索引**：配了 CodeGraph 就一次拿到相关代码块，比全文搜索省一个数量级。

一句话概括定位：这是在给 AI 做「上下文工程」——决定每个会话**该看到什么、不该看到什么**；在这之上再叠了多会话协作和交付纪律。它自己不跑 AI，产出的是给 AI 读的 Markdown。

## 常见问题

**会改我的代码库吗？** 只新增 `.agents/` 和项目根 `AGENTS.md`（已存在则在末尾追加一小段，可手动删掉回退），不碰你原有文件。

**只能用 pi 吗？** 角色卡和技能本质就是 Markdown，Claude Code 等也能读；但"派活 / 回执"这种多会话协作依赖 pi + pi-intercom 插件。

**它会在 GitHub 上开 PR 吗？** 会——每个需求一条分支、一个 PR（Draft 早开、CI 早跑），你确认验收后由研发角色 squash 合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。

**跑完的会话要留着吗？** 后台派生会话验收完可以回收：`nao-fleet.sh close --task T1 rd-be`；常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留。

**它会自己上网查吗？** 会，但有分工：产品经理查同类功能的**产品形态**（有哪些功能点、属性、视图、协作方式），架构师对照**业界成熟的架构模式**。两者都必须把来源和「适不适用本项目」落成文件（`docs/research/`），抓来的网页内容不会堆进聊天记录；技术选型仍然只由架构师定。

**装完之后项目里多了什么？**

```text
你的项目/
├── AGENTS.md              # 项目级约定（PM 维护，AI 每次都会读）
├── .github/               # PR 模板（PM 建，GitHub Flow 用）
└── .agents/
    ├── prompts/           # 5 张角色卡
    ├── common/            # 协作规矩、输出与回执规范
    ├── checklists/        # 各角色红线 / 交付清单 / 回执模板（按需读）
    ├── skills/            # 按需技能（DDD 细节、代码定位、提交规范…）
    ├── templates/         # 项目接入用的骨架文件
    └── scripts/           # nao-fleet.sh 等小工具
```

## 想深入

README 只讲怎么用。真正的机制都在上面那个 `.agents/` 里，想改就从这几处入手：

| 想看什么 | 去哪看 |
| --- | --- |
| 整体架构、分层与设计取舍 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 派活 / 回执 / 忙闲与回收规矩 | `.agents/common/intercom-protocol.md` |
| 输出格式与回执红线 | `.agents/common/output-format.md`、`.agents/checklists/comm-templates.md` |
| 角色怎么定义 | `.agents/prompts/*.md` |
| 各角色的红线与交付清单 | `.agents/checklists/*.md` |
| 工具命令 | `bash .agents/scripts/nao-fleet.sh --help` |
| 项目自己的约定 | 项目根 `AGENTS.md` |

## License

MIT © 2026 Nathan Lee
