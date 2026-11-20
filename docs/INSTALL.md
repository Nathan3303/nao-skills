# 安装与进阶配置

> 面向**已经决定要用 nao** 的读者：装什么、怎么升级、可选增强怎么配、CI/离线怎么跑、老项目怎么迁。
> 只想知道「这东西是什么、怎么在 3 分钟内跑起来」的，看 [README](../README.md)。

## 前置环境（硬性）

缺任何一项都跑不起来，且不会「降级偷偷跑」——`check` / `ensure` 会直接报错退出。

> **模型可选，但有推荐**：舰队推荐配合 **`deepseek-v4.1-flash`**（7 个常驻会话 + 长链路交接，长上下文稳定性与单轮成本更省心）。这不是硬依赖——换成别的模型也能跑，差异在纪律遵守与回执质量。

- **pi（≥ 1.4.0）**：唯一的运行宿主。本机制**只支持 pi**，不为其他编程 Agent（Claude Code / Codex / Cursor 等）提供适配或支持承诺。
- **终端后端（二选一）**：
  - **herdr（≥ 0.9.1，0.23 起默认）**：7 个会话落在 herdr 的专用 session 里，每个角色一个 tab。装法见 [herdr.dev](https://herdr.dev)；装完还要 **`herdr integration install pi`**（舰队靠它判「会话是否就绪」）。
  - **tmux（任意版本，回退）**：7 个会话作为 tmux pane 在当前窗口里分屏拉起；`export NAO_TERMINAL=tmux` 切回。
- **Node.js（≥ 18）**：`nao-skill` CLI 与 `nao-fleet.sh` 的转发入口都是 Node 脚本。
- **git**：任务分支、提交、PR 全靠它；装了 **GitHub CLI（`gh`）** 则额外支持自动开 Issue / PR / Release，没有 `gh` 也能跑，只是这些步骤降级为本地操作。

自检：

```bash
pi --version                          # 需 ≥ 1.4.0
herdr --version || tmux -V            # 二选一：herdr ≥ 0.9.1（默认）或 tmux
node -v                               # 需 ≥ 18
git --version
gh --version                          # 可选
```

不满足时的表现（都是 fail loud，不静默回落）：

- 默认 herdr 但**没装 herdr** ⇒ `check` 打红 `rc=1`（给「装 herdr」与「`export NAO_TERMINAL=tmux` 回退」两条命令）；`ensure` / `status` / `close` ⇒ `exit 3`。
- 默认 herdr 但**不在 herdr pane 内**（例如你在 tmux 里跑，且 `HERDR_ENV` 未被继承时）⇒ `exit 3` + 一行提示（去 herdr 会话的 pane 内重试，或 `export NAO_TERMINAL=tmux` 回退）。
- 选了 tmux 后端但不在 tmux 里 ⇒ `exit 3` + 一行提示 `tmux new -s nao`（不建任何窗口、不留副作用）。
- pi 版本低于 1.4.0 ⇒ `check` 该项打红并 `rc=1`。

## 安装（项目级）

机制以 npm 包 `@nathan33/nao-skill` 为**单一事实来源**，你的项目里只留一个转发入口。版本 pin 写在 `.pi/settings.json`，团队 clone 后按同一个 pin 物化，天然同款。

```bash
cd <你的项目>
pi install --local npm:@nathan33/nao-skill@0.21.3   # 声明 pin + 把机制包物化到 .pi/npm
npx @nathan33/nao-skill init                        # 写转发 shim + 生成 AGENTS.md
npx @nathan33/nao-skill plugins install-all         # 装协作插件（多会话派活必需）
```

**升级**：把 `.pi/settings.json` 里的 pin 改成新版本，再执行 `pi update --extensions`。机制以包为准，项目里没有需要你手动同步的副本。

**卸载**：删掉 `.pi/settings.json` 里对应条目、`.agents/scripts/nao-fleet.sh` 与 `.pi/npm/` 即可；`AGENTS.md` 里若已被追加过「nao 舰队接入」区块，可整段删除。

### 装完之后项目里多了什么

```text
你的项目/
├── AGENTS.md              # 项目级约定（PM 维护，pi 每次都会读）
├── .github/               # PR 模板（PM 建，GitHub Flow 用）
├── .pi/
│   ├── settings.json      # 记录机制包的 pin 版本（进仓库）
│   └── npm/               # pi 把机制包物化在这里（pi 自建 gitignore，不提交）
└── .agents/
    └── scripts/
        └── nao-fleet.sh    # 转发入口（shim）：自动定位包内机制并转发
```

机制本体（角色卡、协作规矩、清单、按需技能、工具）都在 npm 包的 `.agents/` 里——**包里是什么就是什么**，项目里不留副本。若你项目里已有 `AGENTS.md`，`init` 是**合并追加**「nao 舰队接入」区块，不覆盖原文。

### 术语表

- **机制包 / 包根**：npm 包 `@nathan33/nao-skill` 的安装目录，会话里用环境变量 `NAO_SKILLS` 指向它。凡是文档里出现 `$NAO_SKILLS/.agents/...` 的路径，都相对包根解析。
- **shim（转发入口）**：项目里那一个 `.agents/scripts/nao-fleet.sh`，不含机制，只负责找到包内的真脚本并转发。
- **物化**：`pi install` 把 npm 包内容落盘到 `.pi/npm/` 的过程。这一步需要 pi 与网络，是有意为之的显式动作。
- **派生会话**：由 `ensure` 在 tmux 里新拉起的会话（例如 `ensure --task T1 rd-be`），任务结束即可回收。
- **回执**：worker 做完任务后必须发回的结构化结果（`[编号] done(lite|full)`），PM 按它验收。

## 可选增强：CodeGraph

不装也能干活。装了以后角色多一个「一次拿到相关代码块」的原生入口，比 grep + 读全文省一个数量级。

**生效条件三者齐备**：插件已声明 + `codegraph` CLI 在 PATH + 当前仓有 `.codegraph/` 索引。缺任一项自动回退 CLI / `grep -rn` + 行段读取，`check -v` 会告诉你缺什么（这些**全部只是提示，永不进退出码**）。

```bash
npm install -g @colbymchenry/codegraph     # CLI（实测 1.6.2）
codegraph telemetry off                    # 关匿名遥测（舰队 session 由 nao 自动注入 CODEGRAPH_TELEMETRY=0）
cd <repo> && codegraph init                # 建索引（不带 -i；该 flag 已废弃）
```

**资源口径**：sidecar 内存 = 进程树全集 **PSS 之和**（RSS 求和会重复计共享页）。本机实测同仓 6 会话全集 **PSS 675.7MB**、同仓边际 **+70–90MB/会话**、每新增一个有索引的仓 **≈ +155MB**（daemon + watchdog，按仓共享）⇒ 成本跟**仓数**走，不跟会话数线性放大。默认 `check` 不 fork CLI（零外部进程），`-v` / `ensure` 才每仓跑一次 `codegraph status`（约 0.4s）。

**副产物与 daemon**（已知边界，nao 不代清理）：

- `.pi/APPEND_SYSTEM.md` 由插件生成——正常会话退出会删，但**任何加载扩展的非会话 `pi` 调用**（`pi list` / `pi install` / `pi --help -e`）会写完就残留 ⇒ 已加进 `.gitignore`（单文件）；需清理时自己 `rm -f .pi/APPEND_SYSTEM.md`。
- 已建索引的仓里做非会话 `pi` 动作，可能留下 1 棵孤儿 `codegraph` daemon（约 177MB RSS）。规避：**在非索引 cwd 执行**——`( cd /tmp && pi list )`（实测 0 副作用）；已泄漏用 `codegraph daemons`（交互选停）。nao 不会去杀它（daemon 的 argv 不含仓库身份，`pkill` 会跨仓误杀）。

## 进阶用法：按需角色会话（`--card`）

常驻的 7 个角色不用改清单，就能再加一个**按需角色**（Code Review、数据核对之类）：把卡放进你项目仓 `.agents/prompts/<名字>.md`，一条命令拉起。它和常驻角色一样被管起来——分屏托管、`status` 看得到、`close` 收得回——但**不写进 `roles.yaml`，也不算常驻**。

```bash
.agents/scripts/nao-fleet.sh ensure --card .agents/prompts/code-reviewer.md --task T537   # 拉起一次性 Code Review 会话
.agents/scripts/nao-fleet.sh status                                                      # 派生节里能看到 code-reviewer-T537
.agents/scripts/nao-fleet.sh close  --task T537 code-reviewer                             # 用完直接回收
```

对卡的要求：

- 必须在**当前仓**的 `.agents/prompts/` 下，是普通 `.md` 文件（≤256 KiB），frontmatter 有 `role`（缺省用文件名）和 `description`。
- `role` 是会话名来源，不能与常驻角色撞名或抢前缀（`qa`、`qa-audit` 这类会被拒），也不能用 `subagent-` / `nao-` 开头。
- `--as` 只能**在同一张卡内区分会话**，名字必须等于卡 `role` 或以 `<role>-` 为前缀（`--as code-reviewer-notes` ✓，`--as audit` ✗——舰队按前缀识别身份，改名等于「起得来但管不到」）。
- 失败信息都是**一行原因 + 该怎么办**；`check` 会在「下游角色卡」节提前指出（内容类只提醒、机制类直接红）。

两点边界：

- **`--card` 只作用于紧跟它的那个目标**：`ensure qa --card x.md` 是「常驻 `qa`」+「卡 `x.md`」两个会话，不会整批串味；命令末尾悬挂 `--card`、或把它递给 `check`/`status`/`close`，都按用法错误处理。
- **卡正文就是系统提示**，属于**完全可信输入**（能写你仓库的人本来就能定义角色）。fleet 只校验目录、文件类型、大小与命名一致性，不做内容安全审查。卡同样可以被 pi-subagents 当项目 agent 用（加 `name:` 即可），但那条路径没有「环境锚点」行，卡正文别依赖 `@.agents/...` 引用才自洽。若你已在使用 overlay 清单（`NAO_SKILLS` 指向自己的清单目录），同一仓别两法并用。

## 会话命名与多仓舰队（`--fleet` / `.agents/fleet-scope`）

舰队会话名是**路由标签**（不是身份证明），统一形如 `<core>@<fleet>`：

- `core` = `<role>[-<task>]` —— 常驻角色 id（或别名解析后的 id）或下游卡 `role`；`--task` 追加 `-<编号>`。
- `fleet` = 舰队身份 slug，**末位、`@` 分隔、恒非空**。新会话一定带 `@<fleet>`（升级前的裸名会话仍会在场，见下「并存期」）。
- fleet 语法：`^[a-z0-9][a-z0-9_-]{0,15}$`（≤16 字符、不以 `-` 结尾、禁 `@` `.` `:` 与空白）。**保留前缀 `subagent-` / `nao-` 只限 core**，fleet 位不再受限（`nao-skills` 这类目录名可直接当 fleet）。
- 预算：**卡会话** `core` ≤32 字符（普通角色 id 更短），**总名长 ≤48**。
- 名字只由脚本内唯一一对纯函数生成与解析（`fleet_name_build` / `fleet_name_parse`），语法冻结。

fleet 值从哪来（优先级从高到低）：

1. `ensure --fleet <slug>` —— 显式给定即**静默胜出**（覆盖文件；来源 tier 在 `-v`/体检面可见）。
2. `<目标仓>/.agents/fleet-scope` —— 单行文本，就一个 slug。读取对象是**目标仓**（`--card …@<仓>` 取卡的仓），不是调用者当前目录。它现在的语义是「**覆盖默认值**」。
3. 都没有 ⇒ **目标仓 slug**（默认 tier）。

同一个 fleet 值**同时**决定三件事：会话名里的 scope、herdr workspace 的放置键、单例边界（同 fleet 内同 core 只能有一个）。

```bash
# 两个仓同时跑同一套角色：零配置即可，各自默认取仓 slug
cd ~/proj/api && .agents/scripts/nao-fleet.sh ensure rd-be    # → rd-be@api，落 label=api 的 workspace
cd ~/proj/web && .agents/scripts/nao-fleet.sh ensure rd-be    # → rd-be@web，落 label=web 的 workspace
```

**两仓并发不再需要写任何文件。** 只有当两仓**算出同一个 fleet 值**时才会撞车（例如目录同名、都写了相同的 `fleet-scope`、或显式给了同一个 `--fleet`），此时第二仓 `ensure` 同一个 core 会 **fail loud** 并列出在场会话——这是故意的：同名会话会互相顶掉，静默拉起等于给你一个「看起来有两个、其实只有一个」的舰队。要分开就 `--fleet <不同值>`。

失败一律 loud，不静默回落：

- `fleet-scope` 缺失 ⇒ 用仓 slug（默认 tier，唯一允许的静默分支）。
- 空文件 / 只有空白 / 多行 ⇒ 拒绝（「声明了却没值」或歧义多半是 typo）。
- 非法字符 / 超 16 / 尾 `-` ⇒ 拒绝并回显规则；CRLF 会先剥 `\r` 再校验（换行风格归 `check` 管）。
- 不是普通文件（目录、fifo）/ 不可读 / symlink 逃出该仓 ⇒ 拒绝（与角色卡同一套边界口径）。
- `--fleet ""`（给了参数但是空）⇒ 拒绝；想用默认值**别写**这个参数。
- `--fleet` 与 `--scope` 同时给 ⇒ 拒绝（二者等价，歧义）。

名长与截短：

- **默认 tier**（仓 slug）超 48 时**自动截短**到剩下能放的长度，并打**恰一行**提示（不需要 `-v`）。
- **显式 tier**（`--fleet` / 文件）超长 ⇒ fail loud，并点明该缩哪一段。想稳就先在 `fleet-scope` 里给短名。

`--scope` **已弃用**（下一 MINOR 移除）：等价 `--fleet`，会打一条弃用提示，不报错。

回收与查看：

- `status` **不读** fleet 文件 —— 它从会话名解析。带 fleet 的常驻会话显示为 `✓ rd-be 在线（--name rd-be@api；…）·fleet=api`。
- `close rd-be`（裸别名/裸派生名）= 用**调用方所在仓推导出的 fleet**；同仓存在升级前的裸名会话时按 legacy 等价命中它（**不会**假报「未运行」）；`close rd-be@api`（全名）= 用它自己带的 fleet，**忽略** fleet 文件。
- 同 core 的带 fleet 会话不止一个、而你又只给了裸名 ⇒ 拒绝并列出候选（用全名指定，不猜）。

并存期（升级后第一次跑）：

- 升级前起的裸名会话（`pm`、`rd-be`）**不会被自动回收或顶掉**；在对应仓内 `close pm` 能命中（同仓等价规则），不会误伤 `pm@api`。
- 同仓内裸名 `pm` 与 `pm@<该仓 slug>` 视为**同一会话**：不会因此起出第二个 PM。

## 联动仓 manifest（`.agents/fleet.yaml`，0.26 起）

单仓单舰队不需要它（不写 = 与 0.25 完全一致）。要「一支舰队声明它能派到哪些仓」，在**主仓根**写 `.agents/fleet.yaml`：

```yaml
slug: alpha            # 舰队名（放置键）；≤16，同 fleet-scope 语法
repos:
  - code: api          # 仓短代号（≤16）⇒ 会话名里的 scope
    path: ../api       # 相对主仓根；也可写绝对路径
  - code: web
    path: ../web
```

然后 `ensure rd-be@api` ⇒ 会话名 `rd-be@api`、pane cwd = api 仓、**与主仓同住 label=alpha 的 workspace**；tab 标签为 `api/rd-be@api`（主仓会话是 `main/<name>`，`main` 是保留组前缀）。`ensure rd-be`（不带 `@`）= 主仓会话。

规则与边界：

- **放置键 = `slug`**（不再按目标仓分裂 workspace）；名字 scope = `code`（联动仓）或 `slug`（主仓）——两者只在主仓会话上相同。
- `@<段>` 四步解析（唯一顺序）：① 命中 `code` ⇒ 联动仓；② 否则按**既有仓路径**语义（`ensure rd-be@../api` 照旧）；③ 两者都命中但物理路径不同 ⇒ **fail loud**；④ 都未命中 ⇒ fail loud 并列出可用 code。**不猜**。
- 校验（解析期就拒，**零 pane**）：`slug` 必填；`code` 不得重复、不得为 `main`、不得等于 `slug`、≤16 且 `^[a-z0-9][a-z0-9_-]*$`；`path` 必须存在且是目录；看似仓内却经 symlink 逃出仓根 ⇒ 拒绝（显式 `../` / 绝对路径才允许出仓）；未知键 / 锚点 / 别名 / 流式 / 多文档 / 制表符缩进 ⇒ 拒绝。报错恒为 `文件:行号 字段 原因`。
- 与 `.agents/fleet-scope` 共存：同值放行；**分歧 fail loud**（点名两文件两值）。`--fleet` 与 manifest `slug` 不一致 ⇒ fail loud（同一 manifest 只有一支舰队名）。
- 三预算不放宽：`code` ≤16 / 卡 core ≤32 / 总名长 ≤48；撞线 fail loud，**不**自动截短 code。
- 名长：manifest 派生（`code`/`slug`）与显式 tier 一样**不自动截短**；只有默认 tier（仓 slug）保留既有截短。
- 源 = **调用方仓根**的 `.agents/fleet.yaml`：不做向上查找、不自动发现联动仓；在联动仓里 `ensure` 无 manifest 语义（= 单仓行为，已知边界）。
- 每次命令重新读文件（**无落盘缓存**）：运行期改坏 manifest ⇒ 下一次调用即 fail loud。
- `status` 对 code scope 同时显示 `·fleet=<slug> ·code=<code>`（manifest 不可读时 `·fleet=?`，显式不可知）；`close <core>@<code>` 的期望仓回落 = manifest 的 code → path（候选 >1 仍拒绝、零回收）。
- tmux 后端没有 tab 模型 ⇒ 分组只是标签命名空间，**不**追求 tab 物理相邻（herdr 0.9.x 也没有 tab 重排）。

## 体检（`check`）的提示面

`check` 有**三类提示**，都不改退出码（rc 仍可用于闸门）；`rc=0` 但有提示时用 `-v` 看明细。

- **端前提声明一致性**：项目里的说明文件（`AGENTS.md` / 协议）声明的终端后端与实现默认值不一致时提示，并点名 `文件:行`。修法 = 改声明或改实现（同一事实勿双源）。文件不存在或没有声明行 ⇒ **不提示**（不适用）。
- **暂存改动滞留**：仓库里有超过 `NAO_STASH_WARN_HOURS`（默认 **6**）小时的 `git stash` 时提示 —— 合并后的事实不该长期压在暂存里。当天存取的不会打扰。
- **卡预算基线**（`-v` 与失败时的完整报告可见）：常驻角色卡最大行数与阈值占比（阈值 `CARD_MAX_LINES`，默认 200）；超阈值只打 `!`，不改 rc。

## herdr 后端（0.23 起为默认后端）

舰队支持两种终端后端：**`herdr`（0.23 起默认）** 与 `tmux`（回退）。用 `NAO_TERMINAL` 切换：

```bash
NAO_TERMINAL=herdr .agents/scripts/nao-fleet.sh status
```

**前提链（缺一环就起不来，按顺序做）**：

1. 装 **herdr ≥ 0.9.1**（`herdr --version` 可查；协议须为 22）。
2. 装 pi 集成：`herdr integration install pi` —— 舰队靠它拿 `agent_session` 与生命周期钩子权威判「会话是否就绪」；不装则就绪门永远超时并逐条报缺。
3. 起专用会话：`nao-fleet.sh session-start --session <名>`（清宿主终端句柄 + 起 server + 轮询就绪）。
4. **在该会话的 pane 内**跑 `ensure`：herdr 后端只在其 pane 内运行（外部调用会 `exit 3`，这是有意的隔离）。

**空间判据**：herdr 不报「空间不足」，所以舰队放置后会量测每个 pane 的 `rect`；小于 `60×10` 会 **warn + 给可执行指路**（调 herdr 的 `[server] headless_cols/headless_rows`、attach 后重排、或切回 tmux），**不中断拉起**；但出现 **0 行/0 列 pane**（实际读不了）会**计入失败**而不是报成功。

**回退**：`export NAO_TERMINAL=tmux` 一条命令即可回到 tmux 后端（**不删任何文件**）。回退开关会保留**至少 2 个 MINOR 且 ≥90 天**；真要移除时会先发一个 MINOR 的弃用说明，不静默删。

**CI / 自动化固定后端**：在流水线里显式 `export NAO_TERMINAL=tmux`（或 `herdr`），不要依赖默认值 —— 默认值会随版本演进。

## tmux 布局

舰队在你当前窗口内分屏，三种布局：

- **main-row2**（默认）：主会话占左，其余往右分列。
- **main-col**：其余在右列竖排。
- **grid**：等大网格。

窗口太窄时 `main-row2` 会**自动回退** `main-col`、仍不够再退 `grid`，并打印带数字的提示（不中断拉起）。用 `NAO_TMUX_LAYOUT` / `NAO_TMUX_MAIN_WIDTH` / `NAO_TMUX_MIN_PANE_WIDTH` 调整，完整参数见 `bash .agents/scripts/nao-fleet.sh --help`。

## 老项目迁移（曾在项目里铺开整套 `.agents/`）

```bash
npx @nathan33/nao-skill migrate   # 旧文件备份到 .agents/.nao-obsolete/，再按需写入转发入口
```

迁移默认按**判定式**决定是否写 shim：仓里还有旧的 `nao-fleet.sh`、或已存在 shim、或全仓有 `nao-fleet` / `nao-skill` / `NAO_SKILLS` 引用，就写；**无脚本、无引用的纯文档仓会被判定跳过**，并打印一行告知。要改变判定结果，显式加 `--shim`（强制写）或 `--no-shim`（强制不写），两者不能同时给（`exit 2`）。

旧版的 `.agents/.nao-migrated` 标记**已废弃**：迁移不再读写它，可安全删除。`.agents/.nao-version` 的语义是「本机已安装机制包版本」（供升级检测），**不表达迁移状态**——迁移状态由「是否还有旧资产」推断。

## 发布形态与完整性判据（0.12 起有变化）

**从 0.12 起，机制不再铺进项目**：项目里只留转发入口，单一事实来源是 npm 包内的 `.agents/`。

- **旧的完整性判据已失效**：以前靠「项目内 `.agents/**` 与包内逐字节 sha 一致」证明机制没漏没改；现在项目内没有机制副本，这条判据不再适用。
- **新的完整性判据：以 pin 的包版本为准**。`.pi/settings.json` 记录版本，`pi install/update` 从包物化；包里是什么就是什么，不存在「项目内被就地改动」。转发入口是生成的固定文本，可用 `npx @nathan33/nao-skill init` 幂等重写核对。
- **版本权威口径**：`.pi/settings.json` 的 pin 是**唯一权威**；`.agents/.nao-version` 的语义是「本机已安装机制包版本」，**不作为版本依据**；两者不一致时以 pin 为准。
- **fmt 边界**：包内 `.agents/**` 按原始存储形态发布（部分 YAML / Markdown / MTS 未按 oxfmt / prettier 归一）。仍持有旧版全套 `.agents/**` 的仓库，继续把 `.agents/**` 排除出 fmt 校验即可，⛔ **不要为过 fmt 就地格式化**；新形态项目内只有转发入口，无需处理。

## 文档站（`apps/document`）

- **形态**：独立私有包（不进发布包——`npm pack` 白名单不含 `apps/`），VitePress 1.6 + Vue 3 + TS；CI 与 `.nvmrc` 锁 Node 22（根 `engines>=18` 不变）。
- **本地**：`npm install --prefix apps/document` → `npm run docs:dev`（预览）/ `npm run docs:build`（产物 `apps/document/.vitepress/dist/`）。
- **顺序（易错）**：`check:types → build → check:cards → check:links`；后两者读 `dist`，**先跑必红**。
- **内容单一源**：角色卡正文由构建期从 `.agents/prompts/*.md` 注入（禁手抄）；其余文案在 `apps/document/content/**`；缺 `.agents/prompts` 时降级为一条告警，`--strict` 则失败。
- **部署**：`.github/workflows/pages.yml` 构建后上传 dist（`--base /nao-skills/`），失败必红、不回传旧产物；`paths` 含 `.agents/prompts/**` 与 `roles.yaml`（改卡即重建，否则线上静默过期）。

## 物化与离线（CI / 无 pi 环境必读）

- `.pi/npm/` 由 pi 管理并 **gitignore**。因此 **fresh clone 上没有 `.pi/npm/package.json` 与 lockfile**，`npm ci --prefix .pi/npm` 当前**不可用**。
- 物化只有一条路：**显式执行** `pi install -l --approve npm:@nathan33/nao-skill@<pin>`（需要 pi 与网络，是有意为之的一步）。
- **联动条款**：若某个仓库想把机制体检 `check` 放进 CI，**必须同时**用 `git add -f` 把 `.pi/npm/package.json`、`.pi/npm/package-lock.json` 纳入版本控制，`npm ci` 才有输入。
- **pi 启动的隐式安装**：当 `.pi/npm/node_modules` 缺失时，pi 启动会隐式执行 `npm install --prefix .pi/npm --legacy-peer-deps`；离线且缓存为空会得到可读的 npm 报错，并让 pi 以非 0 退出（不会静默假装成功）。
- **运行纪律**：**先显式物化，再 `PI_OFFLINE=1` 运行**。nao 机制自身（转发入口 / fleet / CLI / check）**零网络调用**；入口找不到机制包时不静默成功，而是 `exit 2` 并打印一行 `DEGRADED:` + 恢复命令。
