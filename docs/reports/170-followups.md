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
