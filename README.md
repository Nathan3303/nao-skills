<h1 align="center">nao-fleet</h1>

<p align="center"><b>给你的 pi 配一支「开发小队」——你提需求，它自己找人干活、自己验收交付。</b></p>

<p align="center">
  <a href="https://www.npmjs.com/package/nao-fleet"><img src="https://img.shields.io/npm/v/nao-fleet?label=npm&color=cb3837&logo=npm&logoColor=white" alt="npm version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Nathan3303/nao-fleet?label=license&color=3da639" alt="license: MIT"></a>
  <img src="https://img.shields.io/badge/node-%E2%89%A518-3c873a?logo=nodedotjs&logoColor=white" alt="node >= 18">
  <a href="https://pi.dev"><img src="https://img.shields.io/badge/host-pi%20only-6e56cf" alt="host: pi only"></a>
</p>

[前置环境](#前置环境) · [三步装好](#三步装好) · [第一次跑起来](#第一次跑起来) · [七个角色](#七个角色) · [常见问题](#常见问题) · [想深入](#想深入) · [官网](https://nathan3303.github.io/nao-fleet/)

## 这是什么

nao-fleet 给你的项目装一支由 AI 组成的开发小队：**角色卡 + 协作规矩 + 小工具**。

装上以后，项目里会有 7 个分工明确的 AI 会话。产品经理拆需求、派活、验收。架构师把关方案。设计师管界面与交互。前端、后端、测试各自干活。工程基座管构建、发布与仓库治理。

你只做两件事：回答问题、点确认。

推荐配合模型 `deepseek-v4.1-flash`。舰队是 7 个常驻会话加长链路交接（派活 → **回执** → 验收；回执就是干完交给 PM 的结论单，写明改了什么、验过什么），这个模型在长上下文稳定性和单轮成本上实测最省心。换成别的模型也能跑，只是纪律遵守和回执质量会有差异。

## 前置环境

不满足这些条件就装不起来。

nao **只支持 pi**。它不为其他编程 Agent（Claude Code / Codex / Cursor 等）做适配，也不承诺在那类工具里能用。多会话派活、回执、回收整套机制都建立在 pi 之上。

除 pi 之外还需要：

- **pi ≥ 1.4.0**。舰队依赖它的多会话能力，版本低了体检直接报红。
- **herdr ≥ 0.9.1**，两种形态任选：
  - **herdr TUI（默认）**：在专用会话里跑。另需装 pi 集成：`herdr integration install pi`。
  - **herdr desktop app**：在桌面版窗口里跑。切换前 `export NAO_TERMINAL=app`，并确保桌面版开着、`hc` 命令可用。
  - 两种形态**不共享会话**：TUI 里起的舰队，桌面版里看不到，反之亦然。
  - 更多细节：前提链、空间判据、把版本锁回旧版。见 [docs/INSTALL.md](docs/INSTALL.md) 的「herdr 后端」与「desktop app 后端」两节。
- **Node.js ≥ 18**。命令入口是 Node 脚本。
- **git**，建议顺手装 **GitHub CLI `gh`**。分支、PR、发版都走它。没有 `gh` 时这些步骤降级成手动或本地操作，流程不变。

30 秒自检：

```bash
pi --version && node -v && git --version && herdr --version
```

缺什么补什么：pi 见 [pi.dev](https://pi.dev)；herdr 见 [herdr.dev](https://herdr.dev)（装完还要跑上面那条集成命令）；Node 用 [nvm](https://github.com/nvm-sh/nvm) 或系统包管理器。

## 它解决什么问题

一个人对着 AI 写代码，常见三个毛病：

| 毛病 | nao-fleet 的做法 |
| --- | --- |
| 一个会话什么都干，聊到后面就糊涂了 | 拆成 7 个专业角色，各管一段，互不干扰 |
| 需求没问清楚就开写，写完发现不对 | PM 先追问、写清目标和验收标准，你点头才开工 |
| 干完不知道算不算干完 | 每个任务必须回执并按清单自查，PM 逐条验收才归档 |

## 三步装好

1. **装好前置**（pi / herdr / Node，见上一节）。

2. **把机制装进你的项目**。装项目级，把版本号 pin 写进仓库（pin＝把版本锁死），团队 clone 下来就是同款：

   ```bash
   cd 你的项目
   pi install --local npm:nao-fleet@0.37.0   # 声明 pin，并把机制包物化到项目内 .pi/npm（版本随发版更新）
   npx nao-fleet init                        # 写入转发入口 + 生成 AGENTS.md
   ```

   只想跟最新版就省略 `@0.37.0`：`pi install --local npm:nao-fleet`。

3. **装协作插件**（多会话派活必需）：

   ```bash
   npx nao-fleet plugins install-all
   ```

升级同理：改 `.pi/settings.json` 里的 pin（锁定的版本号），再跑 `pi update --extensions`。机制以 npm 包为准，项目里只有转发入口，你不用手动同步文件。

## 第一次跑起来

```bash
cd 你的项目
.agents/scripts/nao-fleet.sh check                                    # 体检：exit 0 就能开工（有提示行时加 -v 看明细）
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra uiux    # 拉起 7 个会话
```

角色名可以写**别名**或规范名，两者等价：`arch` 就是 `arch-designer`，`infra` 就是 `rd-infra`。上例混着写也照常拉起。完整别名见 `.agents/roles.yaml` 或 `nao-fleet.sh --help`。

会话名形如 `pm`、`qa2`、`rd-be`：重名时自动加数字后缀，`>9` 直接报错。**名字里不含仓库位置**——绑定单位是 herdr workspace（herdr 里的工作空间，一个仓一个）。

**TUI 形态下**两个仓各跑各的、不撞车。**桌面 app 形态（`NAO_TERMINAL=app`）终端名字全局唯一**，两个仓同时起同名角色会报 `name_taken`，需要给第二个仓让号（`pm2`…）。跨仓发消息时用会话 id，不要用名字。

会话命名、任务派生、多仓细节见 [docs/INSTALL.md](docs/INSTALL.md)「会话命名与多仓」。

**多仓编队（可选）**：在仓根写 `.agents/fleet.yaml`，内容就是「联动仓短代号 → 路径」的映射。之后可以把角色派到联动仓干活，仍住在同一个 workspace。用法是 `ensure rd-be@api`，其中 `@api` 是「去哪个仓干活」的选择符，不是名字的一部分。旧写法 `slug:` 已弃用，读到只提示、不生效。不写这个文件，行为与以前完全一致。详见 [docs/INSTALL.md](docs/INSTALL.md)「联动仓 manifest」。

然后在 **PM 会话里说需求**就行，剩下的它自己流转。大概长这样：

```text
你：想加个「导出 CSV」功能
PM：问几个问题 → 给出需求说明 + 优先级 + 开工确认卡
你：开工
PM：拉起缺的角色 → 让 qa 先写用例 → 指派给 rd-be
rd-be：（做完）[T1] done | 测试：npm test exit=0 128例/0红 | PR #12     ← 数字随你的项目变
PM：在 PR 核验收标准并评论 → 验收通过（授权合并）→ rd-be 压成一条提交合并 → 归档 → 回收临时会话
```

每个任务完成后，`docs/` 里都会留下痕迹（需求说明、任务状态、回执），不依赖聊天记录。所以会话聊久了可以直接重开，不会丢事。

## 七个角色

| 角色 | 帮你干什么 |
| --- | --- |
| 产品经理 | 澄清需求、调研同类产品、写需求说明、定优先级、派活、验收、归档、管 Issue 与发版。唯一的调度者，不写代码、不合并 |
| 架构师 | 技术选型与方案评审，出决策记录，评影响面 |
| UI/UX 设计师 | 信息架构、交互流程、视觉规范、状态与断点、可用性与无障碍。没有原型工具时交文字规格，不阻塞 |
| 前端 / 后端研发 | 各自实现，写完自己跑测试再回执 |
| 工程基座 | CI、构建与发布工具、脚本与护栏、依赖升级、仓库治理 |
| 测试工程师 | 按验收标准出用例、跑门禁、报缺陷 |

不想要哪个角色，删掉对应文件即可。只留 PM 加一个研发角色也能跑。

## 常见问题

**会改我的代码库吗？** 只新增三样：项目根 `AGENTS.md`、`.pi/settings.json`、转发入口 `.agents/scripts/nao-fleet.sh`。角色卡、清单、技能这些机制文件都在依赖包里，不铺进你的仓库。原有文件不动；已有 `AGENTS.md` 时是合并追加，不覆盖。

**除了 pi，能配别的编程 Agent 吗？** 不能。机制文件本身是 Markdown，别的工具理论上读得懂。但派活、回执、回收全依赖 pi 和 pi-intercom，其他 Agent 不在支持范围内。

**它会在 GitHub 上开 PR 吗？** 会。每个需求一条分支、一个 PR，早早开成草案让检查先跑。你确认验收后，由研发角色把分支压成一条提交再合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。

**跑完的会话要留着吗？** 任务临时开的会话（派生会话）验收完就回收：`nao-fleet.sh close --task T1 rd-be`。它按会话记录里的任务号精确匹配，旧名 `rd-be(T1)` / `rd-be-T1` 仍能被识别和回收。常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留。目标在别的项目里也能回收；定位不到时**非 0 退出并打印诊断**，不会假装已回收。

**为什么需要终端后端？** 舰队要把 7 个角色会话放进终端，还要能可靠地「找回来」和「收掉」。

- 唯一后端是 herdr。每个角色一个 tab，身份靠结构化事实判定（终端窗格标签 + agent 状态），不依赖终端标题。需要 `herdr integration install pi`，命令要在 herdr 的终端窗格里执行。
- tmux 后端已在 v0.28.0 移除。`NAO_TERMINAL=tmux` 会 **rc=2 并给一行指路**，不会静默按 herdr 跑。还需要 tmux 的话，把旧包 `@nathan33/nao-skill` pin 回 `≤0.27.x`；新包 `nao-fleet` 从 0.37.0 起没有这个后端。
- **不会自动回落**：静默换后端会让同一条命令在不同机器上跑出不同结果。所以移除时也选了明确报错，而不是悄悄换掉。

**它会自己上网查吗？** 会，但有分工。产品经理查同类功能的产品形态（功能点、属性、视图、协作方式）；架构师对照业界成熟的架构模式。两者都要把来源和「适不适用于本项目」写成文件放在 `docs/research/`，抓来的网页内容不进聊天记录。技术选型仍只由架构师定。

**装完之后项目里多了什么？**

```text
你的项目/
├── AGENTS.md              # 项目级约定（PM 维护，AI 每次都会读）
├── .github/               # PR 模板（PM 建，GitHub Flow 用）
├── .pi/
│   ├── settings.json      # 记录机制包锁定的版本（进仓库）
│   └── npm/               # pi 把机制包物化在这里（pi 自建 gitignore，不提交）
└── .agents/
    └── scripts/
        └── nao-fleet.sh    # 转发入口：自动定位包内机制并转发
```

## 从旧版升级

**仓名和包名变了。** 2026-11-27 起，仓名从 `nao-skills` 改成 `nao-fleet`。npm 包名同样是 `nao-fleet`，旧包 `@nathan33/nao-skill` 已停用，安装时会看到迁移提示。装法随之改成 `pi install --local npm:nao-fleet`。

**命令没变**。仍然是 `nao-fleet.sh`，下游项目调用的是这个文件名，改名不影响调用方式。

**安装器命令有两个名字。** 主名 `nao-fleet`（如 `npx nao-fleet init`），兼容别名 `nao-skill`。两者指向同一个文件，旧名一个版本后弃用。

**包根变量也有两个名字**：`NAO_FLEET`（新，优先）和 `NAO_SKILLS`（兼容别名，一个版本后弃用）。两者同时存在时以 `NAO_FLEET` 为准。

## 想深入

| 想看什么 | 去哪看 |
| --- | --- |
| 完整安装手册：CodeGraph 资源占用、按需角色 `--card`、herdr 后端与迁移、老项目迁移、CI / 离线、完整性判据 | [docs/INSTALL.md](docs/INSTALL.md) |
| 整体架构、分层与设计取舍 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 派活 / 回执 / 忙闲与回收规矩 | `$NAO_SKILLS/.agents/common/intercom-protocol.md` |
| 输出格式与回执红线 | `$NAO_SKILLS/.agents/common/output-format.md`、`$NAO_SKILLS/.agents/checklists/comm-templates.md` |
| 角色怎么定义 | `$NAO_SKILLS/.agents/prompts/*.md` |
| 各角色的红线与交付清单 | `$NAO_SKILLS/.agents/checklists/*.md` |
| 工具命令 | `bash .agents/scripts/nao-fleet.sh --help` |
| 项目自己的约定 | 项目根 `AGENTS.md` |

`$NAO_SKILLS` 指机制包的根目录，也就是 npm 包 `nao-fleet` 的安装位置；会话里 fleet 会自动注入这个变量。

想**本地起文档站**：先跑一次 `npm install --prefix apps/document` 装依赖（独立私有包，不进发布包）。之后用 `npm run docs:dev` 预览，用 `npm run docs:build` 构建。站点的内容与用法以[官网](https://nathan3303.github.io/nao-fleet/)为准。

## 为什么它省 token

聊 AI 的钱花在「它每轮要读多少字」。所以每张角色卡只留最硬的规矩，细节放到用到时才读的文件里。任务状态写在 `docs/` 而不是聊天记录里，会话重开先读文件恢复状态。查代码用 CodeGraph 索引一次拿到相关代码块（**可选**，不装就回退到 grep 加行段读取）。

一句话概括定位：这是在给 AI 做「上下文工程」——决定每个会话该看到什么、不该看到什么；在这之上再叠多会话协作和交付纪律。它自己不跑 AI，产出的是给 AI 读的 Markdown。

## 设计技能与致谢

设计方法吸收了 `oil-oil/oil-ui`、`gustavo-henriq/antislop-ui-ux-skill` 与 [heydamir/unslop](https://github.com/heydamir/unslop) 的思路（unslop 作者 Damir Sokolovsky，CC-BY-4.0）。本仓只取方法、用中文重写，未复制其文本、图片或脚本（访问日期 2026-11-24）。

`.agents/skills/frontend-design/SKILL.md` 来自 [anthropics/skills](https://github.com/anthropics/skills/tree/main/skills/frontend-design)，条款见其 `LICENSE.txt`。

## License

MIT © 2026 Nathan Lee
