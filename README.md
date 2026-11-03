<h1 align="center">nao-skills</h1>

<p align="center"><b>给你的 pi 配一支「开发小队」——你提需求，它自己找人干活、自己验收交付。</b></p>

<p align="center">
  <a href="https://www.npmjs.com/package/@nathan33/nao-skill"><img src="https://img.shields.io/npm/v/@nathan33/nao-skill?label=npm&color=cb3837&logo=npm&logoColor=white" alt="npm version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Nathan3303/nao-skills?label=license&color=3da639" alt="license: MIT"></a>
  <img src="https://img.shields.io/badge/node-%E2%89%A518-3c873a?logo=nodedotjs&logoColor=white" alt="node >= 18">
  <a href="https://pi.dev"><img src="https://img.shields.io/badge/host-pi%20only-6e56cf" alt="host: pi only"></a>
</p>

<p align="center"><sub>推荐配合模型 <b>deepseek-v4.1-flash</b> · 基于 <a href="https://pi.dev">pi</a> · Made by <a href="https://github.com/nathan">Nathan Lee</a></sub></p>

[前置环境](#前置环境) · [三步装好](#三步装好) · [第一次跑起来](#第一次跑起来) · [六个角色](#六个角色) · [常见问题](#常见问题) · [想深入](#想深入)

nao-skills 是一套 **角色卡 + 协作规矩 + 小工具**。装上以后，你的项目里会有 6 个分工明确的 AI 会话——产品经理负责拆需求、派活、验收；前端、后端、测试各自干活；工程基座管构建发布与治理。你只做两件事：**回答问题**、**点确认**。

> **推荐配合模型：`deepseek-v4.1-flash`。** 舰队是 6 个常驻会话 + 长链路交接（派活 → 回执 → 验收），这个模型在长上下文稳定性和单轮成本上实测最省心；换成别的模型也能跑，只是纪律遵守与回执质量会有差异。

## 前置环境

> **不满足就装不起来。**

**nao 只支持 pi。** 不为其他编程 Agent（Claude Code / Codex / Cursor 等）做适配，也不承诺在那类工具里能用——多会话派活、回执、回收整套机制都建立在 pi 之上。

除 pi 之外还需要：

- **pi ≥ 1.4.0** —— 舰队依赖它的多会话能力，版本低了体检直接报红。
- **tmux** —— 6 个角色会话在你当前窗口里分屏跑；`ensure` / `status` / `close` 都必须在 tmux 会话内执行。
- **Node.js ≥ 18** —— 命令入口是 Node 脚本。
- **git**（建议顺手装 **GitHub CLI `gh`**）—— 分支、PR、发版都走它；没有 `gh` 时这些步骤降级成手动/本地操作，流程不变。

30 秒自检：

```bash
pi --version && tmux -V && node -v && git --version
```

缺了什么都能在第一步装：pi 见 [pi.dev](https://pi.dev)，tmux 用系统包管理器（`brew install tmux` / `apt install tmux`），Node 用 [nvm](https://github.com/nvm-sh/nvm) 或系统包管理器。

## 它解决什么问题

一个人对着 AI 写代码，常见三个毛病：

| 毛病 | nao-skills 的做法 |
| --- | --- |
| 一个会话什么都干，聊到后面就糊涂了 | 拆成 6 个专业角色，各管一段，互不干扰 |
| 需求没问清楚就开写，写完发现不对 | PM 先追问、写清 PRD 和目标，你点头才开工 |
| 干完不知道算不算干完 | 每个任务必须「回执」并按清单自查，PM 逐条验收才归档 |

## 三步装好

1. **装好上面的前置**（pi / tmux / Node）。

2. **把机制装进你的项目**（项目级；版本 pin 在仓库里，团队 clone 即得同款）：

   ```bash
   cd 你的项目
   pi install --local npm:@nathan33/nao-skill@0.21.3   # 声明 pin，并把机制包物化到项目内 .pi/npm
   npx @nathan33/nao-skill init                        # 写入转发入口 shim + 生成 AGENTS.md
   ```

3. **装协作插件**（多会话派活必需）：

   ```bash
   npx @nathan33/nao-skill plugins install-all
   ```

升级同理：改 `.pi/settings.json` 里的 pin 版本，再 `pi update --extensions`。机制以 npm 包为准，项目里只有转发入口，不需要你手动同步文件。

## 第一次跑起来

```bash
cd 你的项目
.agents/scripts/nao-fleet.sh check                                    # 体检：exit 0 就能开工
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra    # 在当前 tmux 窗口里拉起 6 个会话
```

角色名可以写**别名**或**规范名**（两者等价）：`arch` = `arch-designer`、`infra` = `rd-infra`；上例混用也照常拉起。完整别名见 `.agents/roles.yaml` 或 `nao-fleet.sh --help`。

然后**在 PM 会话里说需求**就行，剩下的它自己流转。大概长这样：

```text
你：想加个「导出 CSV」功能
PM：问几个问题 → 给出 PRD + 优先级 + 开工确认卡
你：开工
PM：拉起缺的角色 → 让 qa 先写用例 → 指派给 rd-be
rd-be：（做完）[T1] done | 测试：npm test exit=0 128例/0红 | PR #12
PM：在 PR 核 AC 并评论 → 验收通过（授权合并）→ rd-be squash 合并 → 归档 docs/prds/ → 回收派生会话
```

每个任务完成后都能在 `docs/` 里找到痕迹（PRD、任务状态、回报），不依赖聊天记录——所以会话聊久了可以直接重开，不会丢事。

## 六个角色

| 角色 | 帮你干什么 |
| --- | --- |
| 产品经理 | 澄清需求、调研同类产品形态、写 PRD、定优先级、派活、验收、归档、管 Issue 与发版（唯一的调度者，不写代码、不合并） |
| 架构师 | 技术选型与方案评审（对照业界成熟模式，写明为何不采纳），出 ADR，评影响面 |
| 前端 / 后端研发 | 各自实现，写完自己跑测试再回执 |
| 工程基座 | CI 与流水线、构建/发布工具、脚本与守卫、依赖与安全告警升级、仓库治理 |
| 测试工程师 | 按验收标准出用例、跑门禁、报缺陷 |

不想要哪个角色，删掉对应文件即可；只留 PM + 一个研发角色也能跑。

## 常见问题

**会改我的代码库吗？** 只会新增项目根 `AGENTS.md`、`.pi/settings.json`，以及一个转发入口 `.agents/scripts/nao-fleet.sh`；角色卡、清单、技能这些机制文件都在依赖包内，**不铺进你的仓库**，也不碰你原有文件（已有 `AGENTS.md` 时是合并追加，不覆盖）。

**除了 pi，能配别的编程 Agent 吗？** 不能。机制文件本身是 Markdown，理论上别的工具也能读，但 nao 的派活 / 回执 / 回收全依赖 pi + pi-intercom，其他 Agent 不在支持范围内。

**它会在 GitHub 上开 PR 吗？** 会——每个需求一条分支、一个 PR（Draft 早开、CI 早跑），你确认验收后由研发角色 squash 合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。

**跑完的会话要留着吗？** 派生会话验收完就回收：`nao-fleet.sh close --task T1 rd-be`（等价写法 `nao-fleet.sh close rd-be-T1`，直接用派生会话名即可）；常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留。目标在别的项目里也能回收——定位不到时会**非 0 退出并打印诊断**，不会假装已回收。

**为什么一定要 tmux？** 它同时解决三件事：**布局可控**（三种布局自动排布，不会把桌面铺满一圈窗口）、**句柄完整**（`status` 查残留、`close` 跨项目回收都靠会话名册与 pane 标题定位）、**SSH 可用**（没有图形环境也能拉起整套舰队）。

**它会自己上网查吗？** 会，但有分工：产品经理查同类功能的**产品形态**（功能点、属性、视图、协作方式），架构师对照**业界成熟的架构模式**。两者都必须把来源和「适不适用于本项目」落成文件（`docs/research/`），抓来的网页内容不进聊天记录；技术选型仍只由架构师定。

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

## 为什么它省 token

和 AI 聊天，钱花在「它每轮要读多少字」。所以每一个角色卡只留最硬的红线，细节放到用到时才读的文件里；任务状态写在 `docs/` 而不是聊天记录里，会话重开先读文件恢复状态；查代码用 CodeGraph 索引一次拿到相关代码块（**可选**，不装就回退 grep + 行段读取）。

一句话概括定位：这是在给 AI 做「上下文工程」——决定每个会话**该看到什么、不该看到什么**；在这之上再叠了多会话协作和交付纪律。它自己不跑 AI，产出的是给 AI 读的 Markdown。

## 想深入

| 想看什么 | 去哪看 |
| --- | --- |
| 完整安装手册：CodeGraph 资源口径、按需角色 `--card`、tmux 布局、老项目迁移、CI / 离线、完整性判据 | [docs/INSTALL.md](docs/INSTALL.md) |
| 整体架构、分层与设计取舍 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 派活 / 回执 / 忙闲与回收规矩 | `$NAO_SKILLS/.agents/common/intercom-protocol.md` |
| 输出格式与回执红线 | `$NAO_SKILLS/.agents/common/output-format.md`、`$NAO_SKILLS/.agents/checklists/comm-templates.md` |
| 角色怎么定义 | `$NAO_SKILLS/.agents/prompts/*.md` |
| 各角色的红线与交付清单 | `$NAO_SKILLS/.agents/checklists/*.md` |
| 工具命令 | `bash .agents/scripts/nao-fleet.sh --help`（转发入口） |
| 项目自己的约定 | 项目根 `AGENTS.md` |

`$NAO_SKILLS` 指机制包根目录（会话里 fleet 会自动注入该变量），也就是 npm 包 `@nathan33/nao-skill` 的安装位置。

## License

MIT © 2026 Nathan Lee
