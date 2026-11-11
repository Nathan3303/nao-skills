# #96 三期 P2 · herdr 转默认（交付报告）

> 分支 `feat/96p3-default`（base main `5d424fa`）· 范围 = PRD `docs/prds/2026-11-10-herdr-base.md` **附三**（三期裁定）
> + **§五 BR1 已改写的三期口径** + **§七 AC3.3**。前批报告 `docs/reports/96p3-layout-p1.md`（P1 布局 A）。
>
> 本报告只给契约、判据与**本机实测数字**；实现差异逐条在 §八 列出（5 处，均给依据）。

## 一、交付面（一句话）

`NAO_TERMINAL` 默认从 `tmux` 翻到 **herdr**（只改那一行）；测试基座按后端**显式**导出 `NAO_TERMINAL`
（用例不再依赖默认值）；双 golden 分离（显式 `=tmux` ⇒ 旧 golden / 未设 ⇒ herdr golden）+ **反向断言两者必须不同**
+ 「把默认改回 tmux」变异必红；herdr 侧每条 `exit 3` 文案补齐 `NAO_TERMINAL=tmux` 回退指路（8 站点全扫）；
`check` 两种模式渲染各自口径（herdr 打印「生效后端」、显式 `=tmux` 逐字等于旧 md5）。

## 二、默认值切换（1 行）

```
$ grep -cE '^NAO_TERMINAL=' .agents/scripts/nao-fleet.sh
1
$ grep -E '^NAO_TERMINAL=' .agents/scripts/nao-fleet.sh
NAO_TERMINAL="${NAO_TERMINAL:-herdr}"
```

`:-` 语义 ⇒ **未设与空串都落 herdr**（不是「未设=herdr、空串=非法」）。本机实测（`check` 尾行，同一棵树）：

| 环境 | `check` 尾行 | rc |
| :-- | :-- | :-- |
| `env -u NAO_TERMINAL` | `· 生效后端 NAO_TERMINAL=herdr（默认后端；…）` | 0 |
| `env NAO_TERMINAL=`（空串） | 同上（逐字相同） | 0 |
| `NAO_TERMINAL=herdr` | 同上（逐字相同） | 0 |
| `NAO_TERMINAL=tmux` | **无**「生效后端」行（末行 = `✓ codegraph 齐备…`） | 0 |

## 三、双 golden 分离 + 反向断言（BR1 三期改写）

### 3.1 旧 golden（显式 `=tmux`）——五处，逐字未动

| golden | 值 | 取数 |
| :-- | :-- | :-- |
| `status` 全文 | `144f3447c9ff406d6aed828d9c9720e5` | `cases/28` C2①（基线 fixture 场，15 行） |
| `ensure` blob（`已拉起` 行 + pi `--name` 值） | `c2de6533a1826dbf470dcc401cb29063` | `cases/28` C2②（9 + 9） |
| tmux close 句柄层 | `9549f513b7a66fbced68bc1a1fa1dc10` | `cases/28` B3①（静态段） |
| tmux cleanup 体 | `d8937134bb3ed4ceca29fb581d4acf2c` | 同上 |
| 生产默认 socket 候选表 | `e4950f3897670a97d7baaea8f54727c3` | 同上 |
| `check` 摘要（本文件 §六） | `31b5978e95e7f5b4dc7a9fd861548065` | 显式 `=tmux` |

`cases/28` B1① 现在**钉住** `144f3447…`（不再只与动态基线 fixture 自比），C2② 钉住 `c2de6533…`。

### 3.2 新 herdr golden（未设）——**由夹具生成，禁手抄**

生成命令（就是用例里那次 invocation，两次跑次同源）：

```bash
# 夹具：cases/28 的 herdr 替身（pane list 7 项 / agent list 5 项）+ 私有 XDG 根
env NAO_TERMINAL=herdr  HERDR_ENV=1 HERDR_SESSION=nao-b1-status \
    XDG_CONFIG_HOME=$LAB/cfg HERDR_SOCKET_PATH=$LAB/cfg/herdr/sessions/nao-b1-status/herdr.sock \
    NAO_SKILLS=$LAB TMPDIR=$LAB/tmp PI_CODING_AGENT_DIR=$LAB/pi-empty PATH=$LAB/bin:$PATH \
    bash $LAB/.agents/scripts/nao-fleet.sh status | md5sum
# ⇒ 123bf85ba92783fb4210b19126849c42   （herdr 侧有后端专有头行「== 终端证据异常（herdr 后端…」）
```

- **运行期生成 + 记录值双保险**：用例先算 `GOLD_HERDR_MD5`（夹具生成），再断言它等于**记录的**
  `123bf85ba92783fb4210b19126849c42`（跨两次独立跑次实测同值：lab 路径含 `$$` 但 herdr `status` 不回显路径）。
- 与未设拼写同源：`env -u NAO_TERMINAL` 那次 status 的 md5 **逐字等于** `123bf85b…`。
- **反向断言（防 flip 未生效仍全绿）**：`herdr golden(123bf85b…) ≠ tmux golden(144f3447…)`；且未设拼写
  `≠` 旧 tmux golden（旧口径「双拼写相等」按设计失效，不假绿）。
- **反向负控（不静默回落）**：在 **tmux 夹具场**里未设 ⇒ `exit 3`，文案点名 `HERDR_ENV=1 缺失` + `NAO_TERMINAL=tmux` 指路
  （若默认还是 tmux 这里会 rc=0 ⇒ 判据必红）。
- **变异自证**：把副本默认改回 `tmux`（`sed 's/:-herdr/:-tmux/'`）⇒ ① 未设不再等于 herdr golden ② herdr 场未设 rc≠0。
  两条都在用例里跑，实测 PASS（`cases/28` 日志 `P2① 变异自证：…`）。

## 四、测试**不依赖默认值**（本批最大风险面）

### 4.1 基座（两处，单点）

| 位置 | 改动 | 作用 |
| :-- | :-- | :-- |
| `tests/t4/run.sh` | `export NAO_TERMINAL="$BACKEND"`（在解析后端之后、跑用例之前） | 每个用例脚本继承**确定**后端 |
| `tests/t4/lib-backend.sh::be_fleet_handles` | tmux 侧新增 `NAO_TERMINAL=tmux`（herdr 侧原本就有） | 走 `be_run_fleet` 的用例两后端都显式 |

后端解析同口径（两处实现，`cases/27` 覆盖）：`NAO_TEST_TERMINAL` > `NAO_TERMINAL` > **默认 herdr**；`auto` = herdr。
⇒ `npm test`（什么都不设）= herdr（AC3.3 的「未设 ⇒ herdr」在门禁上成立）；`NAO_TERMINAL=tmux npm test` = 回退通道全量。

### 4.2 静态断言（一条扫全部 31 例 + 双向负控）

`lib.sh::t4_scan_nao_terminal_default_probe` 逐行扫 `tests/t4/cases/*.sh`：**标记块外**
`unset NAO_TERMINAL` / `env -u NAO_TERMINAL` / 空串赋值 = **0 命中**（当前实测空串）。
唯一白名单 = 包在 `# >>> default-value-probe BEGIN/END` 内的段，当前**恰 2 个文件**：

- `cases/06`：默认值探针（未设 / 空串两段）
- `cases/28`：B1① 反向断言（未设跑 herdr golden · tmux 场未设 ⇒ exit 3 · 变异自证）

双向负控：块外注入 `unset` / `env -u` ⇒ 必红并点名行号+形态；同一份内容包进标记块 ⇒ 放行（白名单不是空话）。

### 4.3 31 例 × 后端 × `NAO_TERMINAL` 对照

> 口径：`tmux 跑次` = `NAO_TEST_TERMINAL=tmux`（或 `NAO_TERMINAL=tmux`）；`herdr 跑次` = 未设（默认 herdr）。
> 「继承」= 由 4.1 基座显式导出（不是 unset）。

| 例 | 生产路径调用方式 | tmux 跑次 | herdr 跑次 | 备注 |
| :-- | :-- | :-- | :-- | :-- |
| 01 | shim `check`（继承） | tmux | herdr | 只跑体检，不建后端场 |
| 02 | 无生产调用（真 `pi install`） | — | — | 纯布局/注册 |
| 03 | shim `check`（继承） | tmux | herdr | DEGRADED 夹具 |
| 04 | `check` ×4（继承） | tmux | herdr | 零网络 |
| 05 | `check`（继承） | tmux | herdr | migrate 面 |
| 06 | **显式**：herdr 段 `=herdr` / tmux 段 `=tmux` / 探针段 unset+空串（标记块） | tmux · herdr · unset | 同左 | 唯一有 unset 的用例之一（白名单） |
| 07 | 无生产调用 | — | — | 真 `pi install` 布局 |
| 08 | 无生产调用 | — | — | CLI lock/init |
| 09 | `be_run_fleet`（BE 句柄）+ 4 处裸 tmux 调用**显式 `=tmux`** | tmux | herdr（门面路径）+tmux（tmux 夹具） | herdr 跑次两段并存，各自显式 |
| 10 | 无生产调用 | — | — | shim 判定/锁去重 |
| 12 | tmux 专有（herdr 跑次 `[TMUX-ONLY]`） | 继承 tmux | 不跑 | 派生落点/宿主窗口 |
| 13 | **显式 `=tmux`**（前提闸门用假 socket） | tmux | tmux | tmux 语义用例；已不靠默认 |
| 14 | 无生产调用 | — | — | 夹具缓存生命周期 |
| 15 | `be_run_fleet`（BE 句柄） | tmux | herdr | tmux 侧 backend-gate 点名 |
| 16/17 | 无生产调用（Node 探针） | — | — | 契约只读 |
| 18 | `check`（继承） | tmux | herdr | codegraph 四态 |
| 19 | `be_run_fleet`（BE 句柄） | tmux | herdr | 归属三态 |
| 20 | `be_run_fleet` | tmux | herdr | `ensure --card` |
| 21 | `be_run_fleet` | tmux | herdr | 零副作用边界 |
| 22 | `be_run_fleet` + herdr 静态段 | tmux | herdr | 三态输出/摘要 |
| 23 | `be_run_fleet` | tmux | herdr | pm 版本自检 |
| 24 | `be_run_fleet` | tmux | herdr | 多目标卡 |
| 25 | tmux 专有（herdr 跑次 `[TMUX-ONLY]`） | **显式 `=tmux`** | 不跑 | 列宽算式 |
| 26 | 无生产调用（桩） | — | — | 冒烟重试护栏 |
| 27 | 测试侧 `be_*`（不跑生产路径） | — | — | 后端抽象自检 |
| 28 | **显式 `=tmux`**（tmux 夹具，`run_in` 注入）/ **显式 `=herdr`**（herdr 桩段）/ 探针 unset（标记块） | tmux · herdr · unset | 同左 | 双 golden 载体 |
| 29 | `be_run_fleet` | tmux → backend-gate | herdr | 就绪门反假阳性 |
| 30 | `be_run_fleet` | tmux → backend-gate | herdr | 幽灵 pane |
| 31 | `be_run_fleet` | tmux → backend-gate | herdr | 集成缺失 |
| 32 | **显式 `=herdr`**（真 herdr + 四件私有 env） | 不跑（backend-gate NOTE） | herdr | 真机整轮 |

**结论**：除 `cases/06`、`cases/28` 的标记块（验默认值 = 验收目标本身）之外，**没有任何用例在 unset 状态下跑生产路径**
（机械证明 = 4.2 的静态断言 + 4.1 的基座两点；`run_in`/`live_probe` 等夹具辅助函数也已显式注入）。

## 五、`exit 3` 文案（AC3.3）：全文 + 全扫

herdr 侧**每条**（实测 7 条；arch 枚举的 6 条 + `cmd_status` 的「需要 herdr server」1 条）都带 `NAO_TERMINAL=tmux`：

```
1 需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试，或 NAO_TERMINAL=tmux 回退）
2 需要 herdr pane：HERDR_ENV=1 缺失（herdr 后端只在其 pane 内运行；从外部推断会话名属猜测面，禁）—— 在该 herdr 会话的 pane 内重试，或 NAO_TERMINAL=tmux 回退
3 需要 herdr 会话：HERDR_SESSION=default 不可用（须非空、≠default、^[A-Za-z0-9._-]+$）—— 在有效 herdr 会话的 pane 内重试，或 NAO_TERMINAL=tmux 回退
4 需要 herdr 会话目录：HERDR_SOCKET_PATH=/tmp/elsewhere/s1/herdr.sock 不在目标根 /tmp/e3test/cfg/herdr/sessions/s1/ 下（stale/外贸 env ⇒ 拒绝，防串台）—— 在目标会话 pane 内重试，或 NAO_TERMINAL=tmux 回退
5 herdr api schema 不可用（server/CLI 异常）：无法校验 protocol ⇒ 拒绝执行（核对 herdr ≥0.9.1 / server 状态后重试，或 NAO_TERMINAL=tmux 回退）
6 herdr protocol=21 ≠ 22（破坏性变更 ⇒ fail loud，不静默降级；请升级 nao-skill 或回退 NAO_TERMINAL=tmux）
7 需要 herdr server：pane list / agent list 不可用（核对 `herdr --session s1 server` 是否在跑、protocol 是否 22）—— 修好后重试，或 NAO_TERMINAL=tmux 回退
```

（以上 1–7 为本机逐条实测输出，rc 均 = 3；**PM 回执里的 `NAO_TMUX=tmux` 是笔误**，全仓无该变量，实施用 `NAO_TERMINAL=tmux`。）

**静态全扫（一条断言扫全部，不抽查）**：`cases/06` 取脚本内**每个真 `exit 3` 命令行**（注释不计），回看前 3 行的报文，
要求含 `NAO_TERMINAL=tmux`（herdr 侧）或 `tmux new -s nao`（tmux 前置，唯一豁免）。
实测：`exit 3` 站点 **8** 个（tmux 前置 1 + herdr 7）、含回退指路的 **7** 条、扫描 0 命中；
负控：`sed` 摘掉其中一条的指路 ⇒ 恰 **1** 条必红（判据非空转）。

## 六、`check` 两模式（AC3.3 后半）

| 模式 | 行数 | 内容 | md5 | rc |
| :-- | :-- | :-- | :-- | :-- |
| 默认（未设/空串/`=herdr`） | 3 | `check: OK · roles=7 · files=54 · layout=main-row2` + codegraph 态 + **`· 生效后端 NAO_TERMINAL=herdr（默认后端；…）`** | — | 0 |
| 显式 `=tmux` | 2 | 摘要 + codegraph 态（**零 `NAO_TERMINAL` 字样**） | **`31b5978e95e7f5b4dc7a9fd861548065`**（= 旧 golden） | 0 |

- 默认 herdr 而**缺 herdr 可执行**：`✗ herdr 缺失（status 将 exit 3）—— 装 herdr ≥0.9.1，或 export NAO_TERMINAL=tmux 回退`，**rc=1**（实测，`PATH` 中摘掉 herdr）。
- 未在 herdr pane 内（`HERDR_SESSION` 空）：只提示不置红（静态体检照跑），提示行同样带回退命令。

## 七、门禁与证据（本机实测）

| 项 | 结果 |
| :-- | :-- |
| `npm test`（**默认 = herdr**） | **rc=0** · 断言 **1738** · 31 例全 PASS · `SKIP=0 · DEGRADE=0 · NOTE=9`（全白名单） |
| 后端索引（herdr 跑次） | **共享 20 / 本后端专有 9 / tmux 专有 2 / PENDING 0**（对账 20+9+2+0 = 31） |
| `NAO_TERMINAL=tmux npm test` | **rc=0** · 断言 **1626** · `SKIP=0 · DEGRADE=0 · NOTE=8` |
| 用例数（唯一出处） | `bash tests/t4/run.sh --list \| tail -n +2 \| wc -l` = **31** |
| 断言增量（对 P1 报告基线） | tmux 1593 → **1626（+33）** · herdr 1705 → **1738（+33）**；新增断言集中在 `cases/06`（+~20：默认值/exit-3 全扫/测试不依赖默认值三组，含 5 条负控正控）与 `cases/28`（402 → **415**，+13） |
| 逐例断言（herdr / tmux） | 06 **218/218** · 09 35/47 · 15 41/47 · 19 60/67 · 22 61/39 · 23 48/52 · 27 64/44 · 28 **415/415** · 32 75/—（tmux-only 12/25：—/29） |
| BR1 五处 md5 | `status 144f3447…` · `ensure c2de6533…` · 句柄层 `9549f513…` · cleanup 体 `d8937134…` · socket 候选 `e4950f38…` —— **与 P1/B4 逐字相同** |
| 默认值 | `grep -cE '^NAO_TERMINAL='` = **1**，值 = `${NAO_TERMINAL:-herdr}` |
| herdr 区禁字 / 台账 | `t4_scan_term_herdr_forbidden` 0 命中 · `t4_scan_term_bare_calls` 台账仍 **0** 条 |
| 敏感/机器特定值 | 改动文件内**绝对家目录前缀**（两种 POSIX 家目录形态）、私钥、token 模式 **0 命中**（复算命令见回执） |
| `git diff --shortstat main...HEAD` | 以 PR head 为准（回执给数） |

## 八、与 PM 清单的偏差（5 处，均给依据）

1. **测试基座的后端默认也翻了**（`NAO_TEST_TERMINAL` 未设 ⇒ herdr，`auto` ⇒ herdr）。
   理由：AC3.3 要求「未设 `NAO_TERMINAL` 跑全部门禁 ⇒ herdr 为默认且全绿」。若基座仍默认 tmux，`npm test`
   会强插 `NAO_TERMINAL=tmux`，这条 AC 在门禁上**不可达**（只在不跑用例的探针里成立）。
   代价：`npm test` 现在跑 herdr 登记集（PENDING 0 / tmux-only 2）；tmux 侧回退通道命令两写法都有效
   （`NAO_TERMINAL=tmux npm test` / `NAO_TEST_TERMINAL=tmux npm test`）。
2. **exit 3 站点是 7 条 herdr 侧（不是 6）**：arch 枚举 6 条之外，`cmd_status` 还有一条
   「需要 herdr server：pane list / agent list 不可用」也是 `exit 3`。按 PM 的「herdr 侧**每条**都含指路」全扫，
   7 条全补，扫描覆盖 8 个站点（含 tmux 前置 1 条，豁免判据 = `tmux new -s nao`）。
3. **herdr golden 采用「运行期生成 + 记录值钉住」双保险**，而不是只钉一个字面量：md5 由夹具**生成**
   （禁手抄），同时断言等于记录的 `123bf85b…`（漂移即红）。给出生成命令（§3.2）。
4. **`check` 全输出 md5 只在「codegraph 齐备态」下断言**：该摘要第 2 行随环境变（无索引的机器/CI 打印别的态），
   无条件钉 md5 会跨机假红。故：**首行逐字 + 行数（2 行）恒定断言**，`codegraph 齐备` 时才追 md5 = `31b5978e…`。
5. **tmux 语义用例显式钉 `=tmux`**（13 / 25 / 09 的裸 tmux 段 / 28 的 tmux 夹具段）：它们构造的是 tmux 句柄/列宽算式，
   在 herdr 跑次里也必须走 tmux 实现（否则夹具自相矛盾）。这不改变登记集分类（13 仍 shared：不建后端场；
   25 仍 tmux-only），只是把「以前靠未设默认」换成「显式」。

## 九、改动面

| 文件 | 性质 |
| :-- | :-- |
| `.agents/scripts/nao-fleet.sh` | 生产：默认值 1 行 + 7 条 herdr 侧 exit 3 文案补回退指路 + `check` 生效后端行措辞（含「默认后端」）与缺可执行时的两条命令 + 头注释/环境变量文档 |
| `tests/t4/run.sh` | 后端解析改 `NAO_TEST_TERMINAL > NAO_TERMINAL > herdr`（`auto`=herdr）+ `export NAO_TERMINAL` |
| `tests/t4/lib-backend.sh` | `be_backend` 同口径 + `be_fleet_handles` tmux 侧显式 `NAO_TERMINAL=tmux` |
| `tests/t4/lib.sh` | 新增 `t4_scan_nao_terminal_default_probe`（标记块白名单扫描） |
| `tests/t4/cases/06` | 默认值断言翻新 + 未设/空串探针（标记块）+ `check` 旧 md5 钉值 + exit 3 全扫（含负控）+ 测试不依赖默认值静态断言（含双向负控） |
| `tests/t4/cases/28` | 双 golden 分离（`=tmux` 旧 golden 钉值 / herdr golden 记录值）+ 反向断言 + 反向负控 + 变异自证 + `run_in`/裸 tmux 段显式 `=tmux` |
| `tests/t4/cases/09` `13` `25` | tmux 夹具/算式段显式 `NAO_TERMINAL=tmux` |
| `tests/t4/cases/27` | 注释同步（后端默认口径） |
| `tests/README.md` | 新增「三期 P2 测试纪律」小节（基座/标记块/双 golden/exit 3 全扫）+ 后端开关默认口径改写 |

## 十、遗留与观察

1. **`check` 摘要 md5 的环境敏感性**（§八 4）：已用「首行 + 行数恒定」兜住，但 `roles=`/`files=` 变化时
   该 golden 也会失效 —— 属**预期**（机制文件增删需同步 golden），与 `cases/06` 的 `files=` 交叉断言同源。
2. **herdr golden 与 `cases/28` 的 herdr 渲染绑定**：`status` 的 herdr 专有节标题/列若有**有意**改动，需同步更新
   `GOLD_HERDR_MD5_RECORDED`（已写进注释；与 C2 tmux golden 同纪律）。
3. **`cases/13`/`25` 在 herdr 跑次里测的是 tmux 路径**（它们本就 tmux 语义）：登记集分类未变；
   若将来要求「同一断言面双后端」，需另立口径（不是本批范围）。
4. **`--force` 语义收紧、attach 重排、`pane move` 长稳**等 P1 遗留项不变（见 P1 报告 §八）。
5. **台账**：仍 **0**（本批未新增裸后端调用）。
