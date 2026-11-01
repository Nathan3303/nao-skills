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
   pi install --local npm:@nathan33/nao-skill@0.18.4   # 声明 pin + 把机制包物化到项目内 .pi/npm
   npx @nathan33/nao-skill init                        # 写入转发 shim + 生成 AGENTS.md
   ```

2. **装协作插件**（多会话派活必需）：

   ```bash
   npx @nathan33/nao-skill plugins install-all
   ```

升级：改 `.pi/settings.json` 里的 pin 版本，再 `pi update --extensions`（机制以包为准，项目里只有 shim）。

### CodeGraph（可选增强，不装也能干活）

插件 `@sean_pedersen/pi-codegraph` 给角色一个原生定位入口，但**三者齐备才生效**：插件已声明 + `codegraph` CLI 在 PATH + 当前仓有 `.codegraph/` 索引。缺任一 ⇒ 自动回退 CLI / `grep -rn` + 行段，`check -v` 会告诉你缺什么（**全部只是提示，永不进退出码**）。

```bash
npm install -g @colbymchenry/codegraph     # CLI（实测 1.6.2）
codegraph telemetry off                    # 关匿名遥测（舰队 session 由 nao 自动注入 CODEGRAPH_TELEMETRY=0）
cd <repo> && codegraph init                # 建索引（不带 -i；该 flag 已废弃）
```

**资源**：sidecar 内存口径 = 进程树全集 **PSS 之和**（RSS 求和会重复计共享页）。本机实测同一仓 6 会话全集 **PSS 675.7MB**、同仓边际 **+70–90MB/会话**、**每新增一个有索引的仓 ≈ +155MB**（daemon + watchdog，按仓共享）⇒ 成本跟**仓数**走，不跟会话数线性放大。默认 `check` 不 fork CLI（零外部进程），`-v` / `ensure` 才每仓跑一次 `codegraph status`（约 0.4s）。

**副产物与 daemon**（已知边界，nao 不代清理）：

- `.pi/APPEND_SYSTEM.md` 由插件生成 —— 正常会话退出会删，但**任何加载扩展的非会话 `pi` 调用**（`pi list` / `pi install` / `pi --help -e`）会写完就残留 ⇒ 已加进本仓 `.gitignore`（单文件）；需清理时**自己** `rm -f .pi/APPEND_SYSTEM.md`。
- 已建索引的仓内做个非会话 `pi` 动作，可能留下 1 棵孤儿 `codegraph` daemon（约 177MB RSS）。规避：**在非索引 cwd 执行** —— `( cd /tmp && pi list )`（实测 0 副作用）；已泄漏用 `codegraph daemons`（交互选停）。nao 不会去杀它（daemon 的 argv 不含仓库身份，`pkill` 会跨仓误杀）。

**老项目迁移**（曾在项目里铺开整套 `.agents/` 的）：执行 `npx @nathan33/nao-skill migrate` 即可，细则见文末「老用户迁移与维护者注记」。

## 用起来（3 步）

```bash
.agents/scripts/nao-fleet.sh check                          # 体检：一行 OK 就能开工
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra   # 拉起 6 个角色会话
```

角色名可以写**别名**或**规范名**（两者等价）：`arch` = `arch-designer`、`infra` = `rd-infra`；上例里两者混用也照常拉起。完整别名表见 `.agents/roles.yaml` 或 `nao-fleet.sh --help`。

**必须在 tmux 里用**：舰队在 tmux 会话内以派生 pane 拉起（`ensure` / `status` / `close` 都只接受 tmux 内，同时要求 `pi ≥ 1.4.0`），不再提供终端窗口 / 后台会话等多宿主路径。非 tmux 环境会直接报错（`exit 3` + 一行提示 `tmux new -s nao`），**不会**建任何窗口或会话。旧版用 `--background` / screen 拉起过的会话，本版起 `status` 看不到、`close` 收不回，先 `screen -ls` 手工清一次。

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

## 按需角色会话（用你自己仓里的角色卡）

常驻的 6 个角色不用改清单就能再加一个**按需角色**（Code Review、数据核对之类）：把卡放进你的项目仓 `.agents/prompts/<名字>.md`，一条命令拉起，它就和常驻角色一样被管起来——分屏托管、`status` 看得到、`close` 收得回——但**不写进 `roles.yaml`，也不算常驻**。

```bash
.agents/scripts/nao-fleet.sh ensure --card .agents/prompts/code-reviewer.md --task T537   # 拉起一次性 Code Review 会话
.agents/scripts/nao-fleet.sh status                                                      # 派生节里能看到 code-reviewer-T537
.agents/scripts/nao-fleet.sh close  --task T537 code-reviewer                             # 用完直接回收
```

卡的要求很直白：必须在**当前仓**的 `.agents/prompts/` 里、是普通 `.md` 文件（≤256 KiB），frontmatter 有 `role`（缺省用文件名）和 `description`。`role` 是会话名的来源，所以不能与常驻角色撞名或抢前缀（`qa`、`qa-audit` 这类都会被拒，只能改卡内 `role`），也不能用 `subagent-` / `nao-` 开头；`--as` 只能**在同一张卡内区分会话**，名字必须等于卡 `role` 或以 `<role>-` 为前缀（`--as code-reviewer-notes` ✓，`--as audit` ✗ —— 舰队按前缀识别身份，改名脱离前缀就等于「起得来但管不到」）。写错了不用猜：失败信息都是**一行原因 + 该怎么办**，`check` 也会在「下游角色卡」节提前指出（内容类只提醒、机制类直接红）。

两点边界值得知道：

- **`--card` 只作用于紧跟它的那个目标**：`ensure qa --card x.md` 是「常驻 `qa`」+「卡 `x.md`」两个会话，不会整批串味；命令末尾悬挂 `--card`、或把它递给 `check`/`status`/`close`，都按用法错误处理。
- **卡正文就是系统提示**，所以它是**完全可信输入**（能写你仓库的人本来就能定义角色）；fleet 只校验目录、文件类型、大小与命名的一致性，不做内容安全审查。卡同样可以被 pi-subagents 当项目 agent 用（加 `name:` 即可），但那条路径没有「环境锚点」行，卡正文别依赖 `@.agents/...` 引用才自洽。若你已经在用 overlay 清单（`NAO_SKILLS` 指向自己的清单目录），同一仓别两法并用。

## 为什么它省 token（这是本项目的核心追求）

和 AI 聊天，钱花在「它每轮要读多少字」。所以：

- **常驻的东西尽量小**：每个角色卡只留最硬的红线，细节放到用到时才读的文件里。
- **按需才读**：设计规范、检查清单、读代码手册，都是在需要那一刻才读进上下文。
- **不靠聊天记录记事**：任务状态和待办写在 `docs/` 文件里；会话重开先读文件恢复状态。
- **查代码用索引**：配了 CodeGraph 就一次拿到相关代码块，比全文搜索省一个数量级。它**不是硬依赖** —— 插件 / CLI / 索引缺任一就自动回退 `grep -rn` + 行段，`check` 的 codegraph 行永远只是提示（不进退出码）。

一句话概括定位：这是在给 AI 做「上下文工程」——决定每个会话**该看到什么、不该看到什么**；在这之上再叠了多会话协作和交付纪律。它自己不跑 AI，产出的是给 AI 读的 Markdown。

## 常见问题

**会改我的代码库吗？** 只会新增项目根 `AGENTS.md`、`.pi/settings.json`，以及一个转发入口 `.agents/scripts/nao-fleet.sh`；角色卡、清单、技能这些机制文件都在依赖包内，**不再铺进你的仓库**，也不碰你原有文件。

**只能用 pi 吗？** 角色卡和技能本质就是 Markdown，Claude Code 等也能读；但"派活 / 回执"这种多会话协作依赖 pi + pi-intercom 插件。

**它会在 GitHub 上开 PR 吗？** 会——每个需求一条分支、一个 PR（Draft 早开、CI 早跑），你确认验收后由研发角色 squash 合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。

**跑完的会话要留着吗？** 后台派生会话验收完可以回收：`nao-fleet.sh close --task T1 rd-be`（等价写法 `nao-fleet.sh close rd-be-T1`，直接用派生会话名即可）；常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留。目标在别的项目里也能回收——`close` 会按名册/窗口标题跨项目定位；定位不到时会**非 0 退出并打印诊断**，不会假装已回收。实验/夹具用的隔离 tmux server 用 `nao-fleet.sh cleanup -S <socket>` 清理：**强制显式 socket**，不带 `-S` 或指向生产默认 socket 一律 exit 2 拒绝，绝不会连坐你正在用的真实 server。

**为什么要装 tmux？** **必须装**（v0.19.0 起唯一的运行前提）：

- **布局可控**：6 个角色会话在 tmux 里按三种布局自动排布（`main-row2` / `main-col` / `grid`），间距与列宽可用 `NAO_TMUX_*` 变量调，不会把桌面铺满一圈窗口。
- **句柄完整**：`status` 查残留、`close` 跨项目回收都按会话名册与 pane 标题定位；tmux 宿主下句柄稳定可寻，没有「查不到就只能猜」的分支。
- **SSH 也能用**：不挑图形环境，起一个 tmux 会话就能拉起整套舰队。

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

## 老用户迁移与维护者注记（新用户可跳过）

本节面向**已有旧版安装**或需要维护使用机制的仓库 CI 的读者，新用户可以直接跳到「想深入」。

### 老项目迁移（migrate）

```bash
npx @nathan33/nao-skill migrate   # 旧文件备份到 .agents/.nao-obsolete/，再按需写入转发入口
```

迁移默认按**判定式**决定是否写转发入口（shim）：仓里还有旧的 `nao-fleet.sh`、或已存在 shim、或全仓有 `nao-fleet` / `nao-skill` / `NAO_SKILLS` 引用，就写；**无脚本、无引用的纯文档仓会被判定跳过**，并打印一行告知。要改变判定结果，显式加 `--shim`（强制写）或 `--no-shim`（强制不写），两者不能同时给（`exit 2`）。旧版的 `.agents/.nao-migrated` 标记**已废弃**：迁移不再读写它，可安全删除。`.agents/.nao-version` 的语义是「本机已安装机制包版本」（供升级检测），**不表达迁移状态**——迁移状态由「是否还有旧资产」推断。

### 发布形态与完整性判据（0.12 起有变化）

**从 0.12 起，机制不再铺进项目**：项目里只留一个转发入口，机制的**单一事实来源**是 npm 包 `@nathan33/nao-skill` 内的 `.agents/`。

- **旧的完整性判据已失效**：以前靠「项目内 `.agents/**` 与包内逐字节 sha 一致」证明机制没漏没改；现在项目内不再有机制副本，这条判据不再适用。
- **新的完整性判据：以 pin 的包版本为准**。`.pi/settings.json` 记录版本，`pi install/update` 从包物化；包里是什么就是什么，不存在「项目内被就地改动」的问题。转发入口是生成的固定文本，可用 `npx @nathan33/nao-skill init` 幂等重写核对。
- **版本权威口径**：`.pi/settings.json` 里的 pin 是**唯一权威**（`pi install/update` 据此物化到 `.pi/npm`）；`.agents/.nao-version` 的语义是**本机已安装机制包版本**（供升级检测），**不表达迁移状态**、**不作为版本依据**；两者不一致时**以 pin 为准**。
- **fmt 边界**：包内 `.agents/**` 按原始存储形态发布（部分 YAML / Markdown / MTS 未按 oxfmt / prettier 归一）。迁移期仍持有旧版全套 `.agents/**` 的仓库，继续把 `.agents/**` 排除出 fmt 校验即可，⛔ **不要为过 fmt 就地格式化**；新形态项目内只有转发入口，无需再处理。

### 物化与离线（CI / 无 pi 环境必读）

- `.pi/npm/` 由 pi 管理并 **gitignore**。因此 **fresh clone 上没有 `.pi/npm/package.json` 与 lockfile**，`npm ci --prefix .pi/npm` 当前**不可用**。
- 物化只有一条路：**显式执行** `pi install -l --approve npm:@nathan33/nao-skill@<pin>`（需要 pi 与网络，是有意为之的一步）。
- **联动条款**：若某个仓库想把机制体检 `check` 放进 CI，**必须同时**用 `git add -f` 把 `.pi/npm/package.json`、`.pi/npm/package-lock.json` 纳入版本控制，`npm ci` 才有输入。
- **pi 启动的隐式安装**：当 `.pi/npm/node_modules` 缺失时，pi 启动会隐式执行 `npm install --prefix .pi/npm --legacy-peer-deps`；离线且缓存为空会得到可读的 npm 报错，并让 pi 以非 0 退出（不会静默假装成功）。
- **运行纪律**：**先显式物化，再 `PI_OFFLINE=1` 运行**。nao 机制自身（转发入口 / fleet / CLI / check）**零网络调用**；入口找不到机制包时不静默成功，而是 `exit 2` 并打印一行 `DEGRADED:` + 恢复命令。

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
