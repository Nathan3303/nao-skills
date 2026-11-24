# #170 收口批（T563）实现报告

> 范围：`check` 文案去「唯一后端」· 缺 `labels` 的 `ensure` 判重 fail-closed · 静态闸关键字位 · warn 恰一行 · `ensure` 全败 rc=1。
> 分支 `nao/t563-followups-170`（base `6e4b396`）。行号均取自本轮工作区实测（`grep -n`），不引用裸号转述。

## AC4 · `check` 文案去「唯一后端」

`nao-fleet.sh` 两处（默认摘要 + `-v` 报告）同文案，实测两路一致（`check` / `check -v` 各跑一次，`grep 生效后端` 同一行）：

```
· 生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app；#96 二期 B4：…）
```

**golden 未位移**：`--case 28` 未改记录值即 PASS —— 该 golden 只哈希 `status` 渲染，本批不动 `status`。故不需要两树对照（无位移可证）。

### 保留处逐条归口（`grep -n '唯一后端'`）

PM 判「可保留」的 6 处（内部叙述 = herdr **程序**唯一、tmux 已删）本轮**改写为准确表述但保留语义**，不是照抄原文：

| 行 | 性质 | 处理 |
|---|---|---|
| `:6` `:7` | 文件头契约叙述 | 改「唯一后端**程序** = herdr（形态 TUI / app）」——原文「只用于拒绝旧值」在 `app` 合法后已失真 |
| `:117` | `:-` 语义说明 | 同上加「（形态 TUI / app）」 |
| `:231` `:232` | 实现区抬头 | 同上加形态 |
| `:1201` `:1209` | 用户可见指路（pane 过窄） | 「（唯一后端 = herdr…）」→「（后端 = herdr…）」：去掉已失真的「唯一」断言，保留「tmux 已移除」 |
| `:2360` | fail-loud 诊断 | 「唯一后端 = %s」→「唯一后端程序 = %s」 |
| `:5298` | 内部注释 | 改「herdr 形态（默认）⇒ 恒打印」 |

**超出 PM 保留清单的订正（显式报备）**：`:77`（`--help` 的 `NAO_TERMINAL=<值>` 行）原文是**契约陈述**而非历史叙述——「唯一后端 = herdr（未设/空串 = herdr）；给其他任何值…」，在 `NAO_TERMINAL=app` 合法后**事实错误**（`--help` 里说 app 应当被拒）。按 AC4 本意（用户可见错话）改为「后端形态：herdr（TUI，默认）/ app（desktop app）」。`--help` 实测 4 处 `唯一后端` 已全部归口（0 处失真断言）。

**AC1 允许面**：新增第 5 类「`check` 生效后端文案行」（仅此一行 ×2 处）。

## AC2 · 缺 `labels` ⇒ `ensure` 判重 fail-closed

- `running_verdict` 由二态扩为 **same | unknown | absent**：`unknown` 由 `term_liveness` 的「有名字、无放置键」态直传，**不再落 absent**。
- `cmd_ensure` 相位 2：`unknown` ⇒ 一行 warn 拒绝 + `SPAWN_FAIL++` + `continue`，**不自动拉起**（否则同名多命中，`close` 随即拒）。
- 该 warn **不被静默**：判重查询保留 stderr（与 `status` 的布尔探针静默策略区分开，互不干扰）。
- 用例：`cases/44` ⑬ —— 缺 labels ⇒ `rc=1` + 点名「无法确认放置归属」 + `--force` 出口 + **终端数不变**；负控 labels 齐全 ⇒ 无该行且纯跳过 `rc=0`。

## AC1 · 静态闸关键字位

`tests/t4/lib.sh::t4_scan_app_bare_hc` 前缀组补 `if|then|else|elif|while|until|do|!` 与 `command -<opt>`；入口结构断言（`^_term_app_exec\(\) \{` 恰 1 处）保持不弱化。

先红后绿（旧闸 vs 新闸，同一批变异样本）：

| 变异 | 旧闸 | 新闸 |
|---|---|---|
| 区间首插 `hc schema` | 红 | 红 |
| `command hc schema` | **绿（漏检）** | 红 |
| `HC_SOCKET=x hc ls` | **绿（漏检）** | 红 |
| 入口改名 | **绿（漏检）** | 红（`MISSING_ENTRY`） |
| `if / then / ! / while / command -p` + `hc` | **绿（漏检）** | 红（带行号） |

负控（白名单不空转，`cases/44` ① 末条）：`hc_ls` / `_hc_wrapper` / `command -v hc` 插入后扫描仍为空。

## AC3 · warn 恰一行

`cases/44` ⑫ 子形态新增 `grep -c '集成缺 labels' == 1`。该断言能承重的原因是先修了「同一名字被问两次」：`status` 的可投递布尔探针改为 `2>/dev/null`（告警归证据面），证据面仍打一行。

## AC5 · `ensure` 全败 rc=1（行为契约变更，PM 裁定）

- 判据 = **实际拉起成功数 == 0 且确有失败**：`SPAWN_OK == 0 && SPAWN_FAIL > 0` ⇒ `rc=1` + 一行汇总（`全部 N 个角色均未拉起`）。
- 纯跳过（全都在运行）⇒ `rc=0`：幂等重跑 effect=0 不得报失败（`cases/44` ⑬ 负控）。
- 不复用 `2`（用法/后端拒绝）与 `3`（前置不可用）。
- 连带：3 个用例共 9 处旧断言以「失败计 SPAWN_FAIL 但不是 crash ⇒ rc=0」钉住旧语义，按新契约改为**精确 `1`**（不是「非零」）：`06:918`、`28:970/1012/1053/1090/1172`。

## 门禁（日志落盘，未过滤）

| 项 | 结果 | 日志 |
|---|---|---|
| `check` | rc=0 · roles=7 · files=53 | `/tmp/rd-t563-check.log` |
| `--case 44` | PASS · 83 断言 | `/tmp/rd-t563-44b.log` |
| `--case 06` | PASS · 331 断言（NOTE=2 白名单） | `/tmp/rd-t563-06b.log` |
| `--case 28` | PASS · 380 断言（golden 未改） | `/tmp/rd-t563-28b.log` |

按加速令**未跑全量**（合并前由 PM 跑一次）。

## 遗留三出口

1. **关闭**：AC1–AC5 五条全部落地并有断言承重（含负控）。
2. **接受（含到期）**：`--help` / `:77` 类「唯一后端」措辞的**进一步统一**（例如把 `herdr 程序唯一` 与 `形态` 拆成两个术语）留给下一次口径批次；本批已消除全部**失真**断言。
3. **转办**：`hc schema` 字段级校验（当前只判可执行 + doc version ≥10）仍为 follow-up（PM 已登记，本批不做）。

---

## 第二轮（QA `CONDITIONAL(P2-1)` 收口 · 2026-11-24）

> 起点 `209170f`（= QA 复核对象）。三件：**P2-1 必修**（`cases/44` ⑬ 纯跳过空转绿）+ P3-1（反引号未转义）+ P3-2（静态闸两类盲区）。
> 另发现一处**本批遗留红**（AC5 涟漪漏改 3 个用例），一并处置并单列证据。

### P2-1 `cases/44` ⑬ 纯跳过：由「空转绿」改为真覆盖（先红后绿）

旧断言 `已在运行 ⇒ 纯跳过 ⇒ rc=0（幂等 effect=0）` 的实测事实（QA 已证）：常驻重复 `ensure` **递增槽位**（S3 既有设计）⇒ 该场景真起了 `rd-fe2`，rc=0 来自「成功」而非「跳过」。

改法（`tests/t4/cases/44-app-backend.sh`）：按既有口径构造真跳过 = **同 role+task 派生**的二次 `ensure`（与 `cases/22` AC2 同形态），并补「第二次跑后终端数不变」断言。共 9 条断言（3 夹具 + 6 判据）：

```
⑬ 纯跳过夹具：首次 ensure（派生 T1）rc=0 / 首次恰 1 行 [app] 已拉起 / 场面上恰 1 个终端
⑬ 纯跳过：二次 ensure ⇒ rc=0 · 零假行（不另起第二个终端）· warn 点名「已在运行」/「跳过」
           · 摘要三类 = 0/1/0 · 终端数不变（effect=0）
```

**先红后绿（两次独立变异，均为临时改 `.agents/scripts/nao-fleet.sh`，跑完 `git checkout --` 还原并逐字节比对）**：

| 变异 | 手法 | 结果 | 日志 |
|---|---|---|---|
| M-a「跳过被改坏」 | `running_verdict` 的 `online) printf 'same'` → `'absent'` | **3 红**：`rc=0`（实际 1）· warn「已在运行」缺失 · 摘要 `0/1/0` 缺失 ⇒ `RESULT: FAIL (3 项)` | `/tmp/rd-t563-p21-red44.log` |
| M-b「另起一个」 | `_ensure_task_name_in_ws` 首行 `return 0`（派生判重永远查不到） | **5 红**：零假行（0→1 行）· warn「已在运行」· warn「跳过」· 摘要 · **终端数不变（期望=1 实际=2）** ⇒ `RESULT: FAIL (5 项)` | `/tmp/rd-t563-p21-red44b.log` |

- M-a 下「终端数不变」仍 PASS 的原因**已查明并如实记录**：重复拉起在放置读回阶段失败 ⇒ 回滚（kill→rm）后终端数回到 1 ⇒ 该条断言**不是** M-a 的证人（M-a 的证人是 rc/warn/摘要三条）。为此另跑 M-b 专证「终端数不变」承重（1 → 2 直接红）。
- 还原后复绿：`--case 44` **PASS · 95 / 0 FAIL**（83 → 95，+12）。

### P3-1 `cases/44:72` 反引号未转义 —— 已修

`"…唯一入口 \`_term_app_exec\` 恰 1 处…"`（与同文件 `:118`/`:129` 同写法）。证据：修前日志有 `行 72: _term_app_exec: 未找到命令` + 标签被吃成「唯一入口  恰 1 处」；修后同日志：

```
[PASS] ① AC7 结构断言：唯一入口 `_term_app_exec` 恰 1 处（删/改名必红，不靠「无命中」冒充绿）
grep -c 未找到命令 /tmp/rd-t563-44b.log = 0
```

### P3-2 静态闸补两类盲区（`sudo` 前缀 · case 分支位）—— 成功，无假阳

`tests/t4/lib.sh::t4_scan_app_bare_hc`：前缀组加 `sudo`；起始组加**受限**的 case 模式位 `^[[:space:]]*(case … in )?[^()[:space:];&]+\)`（`|` 允许出现在模式内：`up|down)` 亦收）。

| 探针 | 旧闸 | 新闸 |
|---|---|---|
| `up) hc ls` / `*) hc ls` / `up|down) hc ls` | 绿（漏检） | **红（带行号）** |
| `case "$x" in up) hc ls;; esac` | 绿（漏检） | **红** |
| `sudo hc ls` / `sudo hc run --bg …` / `up) sudo hc ls` | 绿（漏检） | **红** |
| 原五形态（`if/then/!/while/command -p`）+ 三种前缀（`command/env 赋值`）+ 裸调用 | 红 | 红（不回归） |

**硬条件（PM 点名）全部满足**：`hc_ls x` / `_hc_wrapper ls` / `command -v hc` / `t4_require_cmd hc` / `echo "hc ls"` / `hc_count=1` / `ls "$(command -v hc)"` / `case "$x" in *) :;; esac` / 注释里的 `# sudo hc ls` 与 `# up) hc ls` —— **9 类负控全绿**；真件基线 `t4_scan_app_bare_hc .agents/scripts/nao-fleet.sh` = **0 命中**（探针脚本 `/tmp/rd-t563-p32-probe.sh`）。
`cases/44` ① 已把这三类**固化成正控**（`sudo hc ls` / `up) hc ls` / `*) hc ls`），负控补 `t4_require_cmd hc` 与非 hc 的 case 分支 ⇒ 闸门加严有断言承重，不是一次性探针。

- 已知盲区（**登记，不偷偷放过**）：case 模式与其命令**分行**书写（`pat)` 下一行才是 `hc ls`）仍漏检（本闸逐行）；`)` 前**空模式**（`  ) hc ls`）不匹配 —— 后者是 shell 语法错误，非真实形态。

### 本批遗留红：AC5（全败 ⇒ rc=1）涟漪漏改 3 个用例 —— 已一并订正

`--case 22` 首次跑即红。**不是本轮引入**：在 `209170f` 的只读 worktree 复跑同型一致（证据 `/tmp/rd-t563-22base.log`），另抽查 30/31/43/23 ⇒ 31、23 同样已红：

| 用例 | 旧断言（BR4/D3 口径） | 实测（`209170f`） | 处置 |
|---|---|---|---|
| `22:146` AC3 失败路径 | rc 仍 0 | 实际 1 | 改精确 `1`（T563/AC5） |
| `22:223` J1 负控 0 尺寸 | rc 仍 0 | 实际 1 | 改精确 `1` |
| `31:57` 集成缺失 ensure | rc=0 | 实际 1 | 改精确 `1` |
| `23:386/394/402` P2-3①②③ 就绪门违反 | rc=0 ×3 | 实际 1 ×3 | 改精确 `1` ×3 |

均为**单目标全败**（`SPAWN_OK == 0 && SPAWN_FAIL > 0`）⇒ 按 PM 裁定的 AC5 判据即 `rc=1`；「部分成功 + 部分失败仍 rc=0」的断言（`22:164` AC4 混合、`23:368` 投递失败）**未动**（仍真）。
**PM 需裁决**：`docs/prds/2026-11-02-ensure-outcome-lines.md` 的 BR4/D3 正文仍是旧口径（本次未改 PRD，属 PM 文档边界）—— 建议在 PRD 里补一行「AC5 变更」指针，否则后来人会再次照旧文案写断言。

### 门禁（日志先落盘，未过滤）

| 项 | 结果 | 日志 |
|---|---|---|
| `check` | rc=0 · roles=7 · files=53 | `/tmp/rd-t563-check.log` |
| `--case 44` | PASS · 95 / 0 FAIL（83→95） | `/tmp/rd-t563-44b.log` |
| `--case 06` | PASS · 331 / 0 FAIL（NOTE=2 白名单） | `/tmp/rd-t563-06b.log` |
| `--case 22` | PASS · 62 / 0 FAIL | `/tmp/rd-t563-22b.log` |
| `--case 28` | PASS · 380 / 0 FAIL（golden 未改） | `/tmp/rd-t563-28b.log` |
| `--case 31`（涟漪复验） | PASS · 18 / 0 FAIL（NOTE=1 白名单） | `/tmp/rd-t563-31b.log` |
| `--case 23`（涟漪复验） | PASS · 104 / 0 FAIL | `/tmp/rd-t563-23b.log` |

按加速令**未跑全量**，合并前由 PM 跑一次。
