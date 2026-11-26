# 安装与进阶配置

> 面向**已经决定要用 nao** 的读者：装什么、怎么升级、可选增强怎么配、CI/离线怎么跑、老项目怎么迁。
> 只想知道「这东西是什么、怎么在 3 分钟内跑起来」的，看 [README](../README.md)。

## 前置环境（硬性）

缺任何一项都跑不起来，且不会「降级偷偷跑」——`check` / `ensure` 会直接报错退出。

> **模型可选，但有推荐**：舰队推荐配合 **`deepseek-v4.1-flash`**（7 个常驻会话 + 长链路交接，长上下文稳定性与单轮成本更省心）。这不是硬依赖——换成别的模型也能跑，差异在纪律遵守与回执质量。

- **pi（≥ 1.4.0）**：唯一的运行宿主。本机制**只支持 pi**，不为其他编程 Agent（Claude Code / Codex / Cursor 等）提供适配或支持承诺。
- **终端后端 = herdr（≥ 0.9.1，唯一后端）**：7 个会话落在 herdr 的专用 session 里，每个角色一个 tab。装法见 [herdr.dev](https://herdr.dev)；装完还要 **`herdr integration install pi`**（舰队靠它判「会话是否就绪」）。
- **旧 tmux 后端已在 v0.28.0 移除**：`NAO_TERMINAL=tmux` ⇒ `rc=2` + 一行指路，不静默回退（迁移逐条见下方「herdr 后端」一节，退路 = pin 回 `0.27.x`）。
- **Node.js（≥ 18）**：`nao-skill` CLI 与 `nao-fleet.sh` 的转发入口都是 Node 脚本。
- **git**：任务分支、提交、PR 全靠它；装了 **GitHub CLI（`gh`）** 则额外支持自动开 Issue / PR / Release，没有 `gh` 也能跑，只是这些步骤降级为本地操作。

自检：

```bash
pi --version                          # 需 ≥ 1.4.0
herdr --version                       # 需 ≥ 0.9.1（唯一后端）
node -v                               # 需 ≥ 18
git --version
gh --version                          # 可选
```

不满足时的表现（都是 fail loud，不静默回落）：

- 没装 herdr ⇒ `check` 打红 `rc=1`（给「装 herdr」一条命令）；`ensure` / `status` / `close` ⇒ `exit 3`。
- **不在 herdr pane 内**（例如你在 tmux 里跑，且 `HERDR_ENV` 未被继承时）⇒ `exit 3` + 一行提示（去 herdr 会话的 pane 内重试）。
- **给了已移除的旧后端**（`NAO_TERMINAL=tmux` 或其他值）⇒ `check` / `ensure` / `status` / `close` / `cleanup` 均 **`rc=2`** + 恰一行 stderr（点名「已移除 tmux 后端」+ 迁移指路），PATH 为 `herdr` 桩时 0 命中（零副作用）。
- `cleanup -S <socket>` ⇒ **`rc=2`** + 指路 `cleanup --session <名>`（`-S` 随 tmux 后端一起移除）。
- pi 版本低于 1.4.0 ⇒ `check` 该项打红并 `rc=1`。

## 安装（项目级）

机制以 npm 包 `@nathan33/nao-skill` 为**单一事实来源**，你的项目里只留一个转发入口。版本 pin 写在 `.pi/settings.json`，团队 clone 后按同一个 pin 物化，天然同款。

```bash
cd <你的项目>
pi install --local npm:@nathan33/nao-skill@0.29.1   # 声明 pin + 把机制包物化到 .pi/npm
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
- **派生会话**：由 `ensure` 在 herdr 里新拉起的会话（例如 `ensure --task T1 rd-be`），任务结束即可回收。
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

## 会话命名与多仓（v3 命名 · 1 仓 1 workspace）

会话名是**路由标签**（不是身份证明），形如 **`<role>[<N>]`**（task 不进名字，只落元数据）：

- 常驻：`<role>[<N>]` —— `pm`、`qa`、`qa2`（`N` 空 = 槽位 1；同 workspace 内重名自动加数字，`>9` 直接 fail loud）。
- 任务：`ensure --task <编号>` 的会话名仍是 `<role>[<N>]` —— 如 `rd-be`、`qa2`；task 只落元数据（app label / herdr sidecar），`status` 尾注 `task=<id>`、`status --json` 提供 `task` 字段。只读旧形 `<role>(<task>)` / `<role>-<task>` / `<role>-<task>@<scope>` 仍可被 `status`/`close` 识别，新会话不再生成。
- **名字不含位置**：不再有 `@<fleet>` 段。绑定单位 = herdr **workspace**（1 仓 1 workspace，label = 仓基键；同机同基名两仓自动加序号）。
- 预算：卡会话 core ≤32、总名长 ≤48；撞线 fail loud，**不自动截短**。

**`ensure <角色>@<段>` 里的 `@` 是「目标仓选择符」，不是名字的一部分**（四步解析，唯一顺序）：① 命中 `.agents/fleet.yaml` 的 `code` ⇒ 联动仓；② 否则按**既有仓路径**语义（`ensure rd-be@../api` 照旧）；③ 两者都命中但物理路径不同 ⇒ **fail loud**；④ 都未命中 ⇒ fail loud 并列出可用 code。**不猜**。

### 已弃用（v0.27.0 起，仍有 warn 但不生效）

| 旧入口 | 现在 |
| --- | --- |
| `ensure --fleet <slug>` | 给参只打一条 warn，**忽略**；放置键恒为仓基键 |
| `ensure --scope <slug>` | 同上 |
| `.agents/fleet-scope` | 读到时只 warn，**忽略**；放置键恒为仓基键 |
| `fleet.yaml` 的 `slug:` | 同上（`repos:` 仍有效，见下节） |
| 会话名带 `@<fleet>` | 新会话**不再产生**；在场遗留会话仍能被 `list`/`status` 看见，`ask` 可按精确名命中，但 **`send`/`handover` 会把含 `@` 的 `to` 当跨机地址 ⇒ 本机不可达** |

> **迁移**：想继续用旧语义 ⇒ 把机制版本 pin 回 `≤0.27.x`。不想迁移 ⇒ 删掉 `--fleet`/`--scope` 调用与 `.agents/fleet-scope` 文件即可，其余不动也能跑。

## session 记录存放与保留（`logs`）

舰队会话的 **Pi session 记录不落 `~/.pi/agent/sessions/`**，而是落舰队自有状态目录 —— 这样用户的 `/resume` 主列表里只剩自己的会话，一天多次重开角色也不会有噪音。

- **位置**：`${NAO_FLEET_META_DIR:-~/.local/state}/nao-fleet/sessions/--<编码 cwd>--/`（**一仓一子目录**，目录名与 Pi 默认布局同款编码：去掉首 `/`、再把 `/` 与 `:` 换成 `-`）。与 herdr sidecar `session-meta/` 同处一个状态根；`NAO_FLEET_META_DIR` 一起搬家。
- **范围**：**全部**舰队会话（常驻 `pm`/`qa`/… 与 `--task` 派生）都由 `ensure` 带 `--session-dir` 落这里；Pi 一旦拒绝该参数或目录不可建 ⇒ **fail loud**（不会静默落回主目录）。
- **保留（按结果分级，按文件 mtime 判寿命）**：
  - **正常交付**（该 role/task 有 `done` 回执 `docs/queue/<id>.receipt.json`，或 `close` 判定正常）⇒ **24 小时**
  - **异常**（无回执 / `close --force` / 崩溃 / 判不出）⇒ **7 天**，并在该会话 cwd 的 `docs/tasks-state.md` 留一行 `- [session-retention] …` 点名（角色 + 任务 + 路径；重复跑不重复写）
  - 近 1 小时有写入的记录一律跳过（可能仍在跑）；清理失败只 warn，不改 rc
- **查看**：
  ```bash
  bash .agents/scripts/nao-fleet.sh logs rd-infra            # turn 摘要（user 首行 + assistant 首行 + 工具名）
  bash .agents/scripts/nao-fleet.sh logs rd-infra --raw      # 原样
  bash .agents/scripts/nao-fleet.sh logs rd-infra --list     # 仓 / 日期 / 角色 / 大小 / 路径
  bash .agents/scripts/nao-fleet.sh logs --purge             # 按分级清理（默认只清当前仓）
  bash .agents/scripts/nao-fleet.sh logs --purge --repo all --days 3   # 跨仓 + 一次性统一保质期
  ```
  默认作用域 = **当前仓**（`git rev-parse --show-toplevel` → 仓基键）；`--repo <仓名>` 看/清指定仓，`--repo all` 看/清全部。无记录 ⇒ `rc=0` + 一行提示（不是错误）。
- **不做长期归档**：Pi session 会被 compaction 截断、单条可达数 MB 且 90% 是 thinking/工具输出。真档案 = `docs/queue/<id>.receipt.json` + `docs/reports/` + intercom 回执 + `docs/tasks-state.md`。

## 联动仓 manifest（`.agents/fleet.yaml`）

单仓不需要它（不写 = 与以前完全一致）。要让角色能被派到**其它仓**干活、但仍住同一个 workspace，在**主仓根**写：

```yaml
repos:
  - code: api          # 仓短代号（≤16）⇒ `ensure rd-be@api` 的 `@` 段
    path: ../api       # 相对主仓根；也可写绝对路径
  - code: web
    path: ../web
```

然后 `ensure rd-be@api` ⇒ pane cwd = api 仓、tab label 前缀 `api/`（主仓会话是 `main/`）；**放置键仍是调用方仓基键**（联动仓的会话也住在主仓 workspace 里）。

规则与边界：

- **顶层只认 `repos`**；`slug:` 为**弃用键**：读到只打一条 warn 后忽略（放置键恒为仓基键）。
- 校验（解析期就拒，**零 pane**）：`code` 必填、不重复、不为 `main`、≤16 且 `^[a-z0-9][a-z0-9_-]*$`；`path` 必须存在且是目录；看似仓内却经 symlink 逃出仓根 ⇒ 拒绝（显式 `../` / 绝对路径才允许出仓）；未知键 / 锚点 / 别名 / 流式 / 多文档 / 制表符缩进 ⇒ 拒绝。报错恒为 `文件:行号 字段 原因`。
- 源 = **调用方仓根**的 `.agents/fleet.yaml`：不做向上查找、不自动发现联动仓；在联动仓里 `ensure` 无 manifest 语义（= 单仓行为，已知边界）。
- 每次命令重新读文件（**无落盘缓存**）：运行期改坏 manifest ⇒ 下一次调用即 fail loud。
- `status` 对 code scope 显示 `·fleet=<仓基键> ·code=<code>`；`close <core>@<code>` 的期望仓回落 = manifest 的 code → path（候选 >1 仍拒绝、零回收）。
- herdr 没有 tab 重排 API ⇒ 分组只是 tab label 前缀命名空间，**不**追求 tab 物理相邻。

## 体检（`check`）的提示面

`check` 有**三类提示**，都不改退出码（rc 仍可用于闸门）；`rc=0` 但有提示时用 `-v` 看明细。

- **端前提声明一致性**：项目里的说明文件（`AGENTS.md` / 协议）声明的终端后端与实现默认值不一致时提示，并点名 `文件:行`。修法 = 改声明或改实现（同一事实勿双源）。文件不存在或没有声明行 ⇒ **不提示**（不适用）。
- **暂存改动滞留**：仓库里有超过 `NAO_STASH_WARN_HOURS`（默认 **6**）小时的 `git stash` 时提示 —— 合并后的事实不该长期压在暂存里。当天存取的不会打扰。
- **卡预算基线**（`-v` 与失败时的完整报告可见）：常驻角色卡最大行数与阈值占比（阈值 `CARD_MAX_LINES`，默认 200）；超阈值只打 `!`，不改 rc。

## herdr 后端（TUI · 默认形态）

`herdr` 是**默认终端形态**（TUI）。`NAO_TERMINAL` 可显式赋 `herdr`（未设/空串也是 herdr）或 `app`（桌面版，见下节）；给**其他任何值**（包括已移除的 `tmux`）⇒ `rc=2` + 恰一行 stderr 指路。

```bash
NAO_TERMINAL=herdr .agents/scripts/nao-fleet.sh status
```

**前提链（缺一环就起不来，按顺序做）**：

1. 装 **herdr ≥ 0.9.1**（`herdr --version` 可查；协议须为 22）。
2. 装 pi 集成：`herdr integration install pi` —— 舰队靠它拿 `agent_session` 与生命周期钩子权威判「会话是否就绪」；不装则就绪门永远超时并逐条报缺。
3. 起专用会话：`nao-fleet.sh session-start --session <名>`（清宿主终端句柄 + 起 server + 轮询就绪）。
4. **在该会话的 pane 内**跑 `ensure`：herdr 后端只在其 pane 内运行（外部调用会 `exit 3`，这是有意的隔离）。

**空间判据**：herdr 不报「空间不足」，所以舰队放置后会量测每个 pane 的 `rect`；小于 `60×10` 会 **warn + 给可执行指路**（调 herdr 的 `[server] headless_cols/headless_rows`、attach 后重排、或换更大窗口后 attach），**不中断拉起**；但出现 **0 行/0 列 pane**（实际读不了）会**计入失败**而不是报成功。

**从 tmux 迁过来（v0.28.0 破坏性变更）**：

- `NAO_TERMINAL=tmux` ⇒ **`rc=2`** + 一行指路（不会静默改用 herdr）。**还需要 tmux 就 pin 回 `@nathan33/nao-skill@≤0.27.x`**（`pi install -l npm:@nathan33/nao-skill@0.27.0`）。
- `NAO_TMUX_LAYOUT` / `NAO_TMUX_MAIN_WIDTH` / `NAO_TMUX_MIN_PANE_WIDTH` 三个变量与 `check` 的「tmux 布局」节**整组删除**（布局改由 herdr 的 tab 拓扑决定，不再有几何算式与窄列回退）。
- `cleanup -S <socket>` **已移除**（`-S` 是 tmux 调用面）⇒ 改用 `cleanup --session <名>`；`-S` 现在是 `rc=2` + 指路。
- 自检命令统一为 `herdr --version`（旧的 `herdr --version || tmux -V` 写法随回退面一起作废，见上节自检）。
- **CI / 自动化**：不要再固定 `NAO_TERMINAL=tmux`；显式 `NAO_TERMINAL=herdr` 或直接不设。
- **能力边界（已声明退役面）**：tmux 专有用例 12 / 25 退役（宿主窗口显式寻址、列宽算式）；herdr 侧的放置 / 隔离 / 回收由用例 28–33、37–41 覆盖。

## desktop app 后端（`NAO_TERMINAL=app`）

除 herdr TUI 之外，舰队也能跑在 **herdr desktop app** 里。两者是**并列的两种形态**，默认仍是 TUI：

```bash
export NAO_TERMINAL=app     # 切到桌面版后端；不设 = TUI
```

三件套前提（缺任一项 ⇒ `exit 3` + 一行指路，不会瞎猜）：

1. **桌面版窗口在跑**（`herdr-app status` 能读到窗口）。窗口没开 ⇒ `ensure` 直接 `exit 3` 并让你先开窗 —— 因为桌面版的 space/tab 由窗口写，窗口不在时**放置永远不成立**。
2. 在一个 **`hc` 起的终端里**（环境里有 `HC_SCOPE` / `HC_TERMINAL_ID` / `HC_TERMINAL_SOCKET`）。
3. `hc` 在 PATH（`hc --help` 可用）。

**放置**：space = 仓、tab = 角色/任务。舰队通过给新建终端打 `herdr.space` / `herdr.tab` 两个标签把会话「收养」进目标 space/tab（未知 id 会让桌面版自动新建）。写完之后**读回 `doc.get herdr-app` 结构**确认终端真的在目标 tab 里；对不上就**回滚（关掉刚建的终端）+ 报错**，不会留孤儿。

**状态与忙闲**：读 `hc get <终端> --json` 的 `status`（pi 通过 OSC 7501 上报：`working` / `idle` / `blocked` / `done`）与 `turn`；**就绪判据 = `status.app=pi` 且 `state=idle`**。注意 `turn` 只在完成时 +1，**不是** TUI 的 `state_change_seq` 等价物。

**回收**：`close` 走 `kill` → `rm`（对仍在跑的终端直接 `rm` 会失败）。`--keep` 的语义是「core 丢失后原地换一个 shell、标签保留」——所以它可能留下「看起来在、其实没程序」的终端，`status` 不会仅凭标签就判它活着。

### 两套形态不共享会话（务必知道）

herdr TUI 与 desktop app **各自管理自己的终端**：TUI 里起的舰队，在桌面版的 `status` 里看不到；桌面版起的，TUI 里也看不到。这不是缺陷，是官方设计。所以：

- 同一台机器可以两边各跑一套（互不干扰），也可以只挑一种用。
- 想换形态 ⇒ 在旧形态里 `close` 收干净，再在新形态里 `ensure`（没有自动迁移）。
- 测试与 CI 一律建议用 TUI 或**私有 core**（`XDG_RUNTIME_DIR` / `XDG_STATE_HOME` / `HC_SESSION` 指向临时目录），不要连到你自己正在用的桌面版。

## 旧 tmux 布局去哪了

`main-row2` / `main-col` / `grid` 三布局、窄列回退与对应三个变量随 tmux 后端一起删除（v0.28.0）。herdr 下没有「在同一窗口里分屏」这个概念：1 仓 = 1 workspace、1 角色 = 1 tab，窗口太窄时该做的是**把窗口/显示器换大**或调 herdr 的 `[server] headless_cols/headless_rows`，而不是切布局。迁移逐条见上一节。

## 老项目迁移（曾在项目里铺开整套 `.agents/`）

```bash
npx @nathan33/nao-skill migrate   # 旧文件备份到 .agents/.nao-obsolete/，再按需写入转发入口
```

迁移默认按**判定式**决定是否写 shim：仓里还有旧的 `nao-fleet.sh`、或已存在 shim、或全仓有 `nao-fleet` / `nao-skill` / `NAO_SKILLS` 引用，就写；**无脚本、无引用的纯文档仓会被判定跳过**，并打印一行告知。要改变判定结果，显式加 `--shim`（强制写）或 `--no-shim`（强制不写），两者不能同时给（`exit 2`）。

**已知边界（按目录名判定）**：迁移把 `.agents/{prompts,common,checklists,templates}` 按**目录名**视为旧版 nao 资产 —— 项目自有的同名目录也会被备份后移除（备份在 `.agents/.nao-obsolete/`，可回滚）。操作前先预演：`npx @nathan33/nao-skill migrate --dry-run`（`init --dry-run` 同口径）—— 只打印将备份/移除的清单与目标，**盘面零写入**；与 `--force` 互斥（`exit 2`）。去掉 `--dry-run` 才真跑，预演清单与真跑动作逐项一致。

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
