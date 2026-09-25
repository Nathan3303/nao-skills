# ADR：舰队 tmux 布局——新增 `main-col` 与「窄列」守卫

- 状态：**提议**（本文由 arch-designer 出具设计方案 + 实测证据，**不含代码实现**）
- 日期：2026-09-25 · 出具：arch-designer（`T303`）· 落地：RD
- 关联：`.agents/scripts/nao-fleet.sh`（`apply_tmux_layout()` / `build_main_row2_layout()` / `cmd_check()` / usage 头）、`README.md`、`.agents/common/intercom-protocol.md`
- 触发：用户反馈「舰队布局 4 列太挤」，实测 4 pane 时出现 **16 列宽**的不可用 pane

## 一、问题复现（实测，非推断）

设备：tmux 3.6。方法：detached 会话固定 `-x W -y 34`，`split-window -h` 造 N pane，套用**现行** `build_main_row2_layout`（`NAO_TMUX_MAIN_WIDTH=35`），读 `list-panes -F '#{pane_width}x#{pane_height}'`。

**现行 `main-row2` 的「非主 pane 最窄宽度」矩阵**（`-` = 只有主+右一列，不适用）：

| pane 数 \ 窗口宽 | 80 | 100 | 120 | 152 | 160 |
| :-- | --: | --: | --: | --: | --: |
| 3 | 52 | 65 | 78 | 104 | 104 |
| 4 | **25** | 32 | 38 | 51 | 51 |
| 5 | **25** | 32 | 38 | 51 | 51 |
| 6 | **16** | **21** | **25** | 34 | 34 |

⇒ 根因确认：公式把右侧区域切成 `ceil((N-1)/2)` **列**（N=6 → 3 列），列宽随 pane 数线性塌陷；`W=80 & N=6` 恰为 **16 列**（用户所报数字）。窄窗口下 N=4 同样命中（`W=52` 时 16 列）。

## 二、对照过的备选模式（实测对照，含不采纳理由）

固定 `W=100 / H=34`，`main-row2` 用现行公式；内建布局用 `select-layout`。

| # | 模式 | N=5 实测（宽 × 高 @位置） | 宽度下限（W=80，N=3..7） | 代价 | 结论 |
| :-- | :--- | :--- | :--- | :--- | :--- |
| ⓪ | **`main-row2`（现行默认）** | `34×34` + `32×16×2` + `32×17×2` | **16**（N=6） | 窄列不可读；宽度随 pane 数塌陷 | **保留为默认**（不破坏既有习惯），但**必须加守卫** |
| ① | **`main-col` = tmux 内建 `main-vertical`** | `40×34` + `59×10/9/9/9` | **39** | 主 pane 宽度需显式设（默认 80 格！） | **采纳**（新增可选模式） |
| ② | **`grid` = tmux 内建 `tiled`** | `39×12 40×12 39×12 40×12 80×14` | **39** | 无「主 pane」概念，全员等大 | **采纳为兜底**（宽度最优、tmux 自动平衡行列） |
| ③ | `even-vertical`（全员纵向堆叠，无主 pane） | `100×8/7/7/7/7` | 100 | 无主 pane；pane 多时高度塌陷更早 | 不采纳：丢失主 pane 语义，与「PM 主视角」不符 |
| ④ | `main-horizontal`（主 pane 占上，其余在下排） | `100×19` + 下排 `33/33/32` | 33 | 单行横排 ⇒ 角色一多就重新变窄（与现状同病） | 不采纳：未解决横向塌陷；仅适合「宽而矮」终端，留作未来可选 |
| ⑤ | **每角色一个 tmux window / session** | —— | —— | 失去「一屏看全队」；切窗成本高 | 不采纳：与舰队「同屏协同」目标冲突 |
| ⑥ | **手搓 `main-col` layout 串**（照 `build_main_row2_layout` 写法） | —— | 39 | 需自算几何 + checksum；resize 行为需自证 | 不采纳：tmux **已有同名内建布局**，自搓属重复实现（§四.1） |

**内建 `main-vertical` 关键实测（tmux 3.6）**：

- `main-pane-width` **接受百分比**：设 `35%` ⇒ W=100 时主 pane `34×40`、右侧 `65` 宽（与现行 `NAO_TMUX_MAIN_WIDTH=35` 语义一致）。
- **默认 `main-pane-width` = 80（格！）** ⇒ 不显式设置时 W=100 会给主 pane 80 格、其余只剩 19 格。**必须显式设**。
- 主 pane = **`pane_index` 最小（最早创建）** 的 pane，**与当前 active pane 无关**（切 active 后重排不变）⇒ 与现行 `build_main_row2_layout` 的 `panes[0]` 语义**一致**，无行为漂移。
- 宽度**与 pane 数无关**（只压高度）：N=3..7 时右侧始终 `W-主宽-1`；N=7 & H=40 时右列 pane 高度降到 6 行（**宽度达标、高度不足**，见限制）。

## 三、决策

### 3.1 新增可选布局 `NAO_TMUX_LAYOUT=main-col`

- 语义：**主 pane 左侧全高 + 其余 pane 在右列纵向堆叠**（`1 | 2 / 1 | 3 / 1 | 4 / …`）。
- 实现：**委托 tmux 内建 `main-vertical`**，并显式 `set-window-option main-pane-width "<NAO_TMUX_MAIN_WIDTH>%"`。**不再手搓布局串**（复用内建 ⇒ 无 checksum/几何代码、resize 由 tmux 负责、百分比原生支持）。
- 默认值**不变**：`NAO_TMUX_LAYOUT` 缺省仍是 `main-row2`（① 用户既有习惯不变）。

### 3.2 `main-row2` 窄列守卫 + 回退阶梯

新增**单一常量** `NAO_TMUX_MIN_PANE_WIDTH`（默认 **30**，合法域 `10..80`），在应用 `main-row2` 前判定：

1. 计算 `main-row2` 在「当前窗口宽 + 当前 pane 数」下的**最窄非主 pane 宽度**；
2. `≥ 阈值` ⇒ **照旧应用 `main-row2`**（默认路径零变化）；
3. `< 阈值` ⇒ **warn（带数字）** 并回退 **`main-col`**（保留主 pane 语义，右列宽度 = `W-主宽-1`，通常一次到位）；
4. 若回退后**右列宽仍 < 阈值**（窗口本身太窄）⇒ 再 warn 并回退 **`grid`（`tiled`）**——tmux 动态平衡行列，实测宽度最优（W=45/N=6 ⇒ 22 列；W=64/N=6 ⇒ 31 列）。

提示文案需含**三个数字**（实测最窄列 / 阈值 / 实际生效布局），例如：
`[fleet] 6 pane @ 80 列：main-row2 最窄列 16 < 最小 30 → 回退 main-col`。

### 3.3 常量单一来源（防三处漂移）

| 常量 | 默认 | 来源 | 消费点 |
| :--- | --: | :--- | :--- |
| `TMUX_MAIN_WIDTH_DEFAULT` | 35 | 既有（复用） | 主 pane 宽度百分比（`main-row2` 与 `main-col` 共用） |
| `TMUX_MIN_PANE_WIDTH_DEFAULT` | 30 | **新增** | 窄列守卫；`cmd_check()` 同步校验优先级：非法→回退默认值 |

守卫与构建**必须共用同一段几何计算**（建议抽出 `main_row2_min_col()` 或等价函数），禁止在守卫里重写宽度公式（否则两处漂移，正是本次要防的）。

### 3.4 附带健壮性（同区域、低成本，建议一并修）

`spawn_tmux()` 的 `tmux split-window -h` 目前在 `set -e` 下**无 `|| true`**：窄窗口时 tmux 会回 `no space for new pane`（实测 W=60/N=6 触发），脚本将**中断整轮 ensure**。建议改为捕获失败 → warn（说明 pane 已达宿主上限）+ 继续后续角色，保持「不因一个 pane 失败吞掉整批」。

### 3.5 `check` 与文档同步点

> 影响面核查：nao-skills **无 CodeGraph 索引**（实测 `codegraph status` → `Not initialized`）⇒ 按卡内约定回退 `grep -rn`（布局相关符号：`TMUX_LAYOUT` / `main-row2` / `apply_tmux_layout` / `build_main_row2_layout`）+ 定向读取命中文件（禁 `cat` 全文）。命中点即下表三处，**无其他持有者**。

| 文件 | 落点 |
| :--- | :--- |
| `.agents/scripts/nao-fleet.sh` | 脚本头 usage（`NAO_TMUX_LAYOUT` 合法值 + 新变量）；`spawn_tmux`/`apply_tmux_layout` 的合法值分支；`cmd_check()` 的布局合法值列表 + `NAO_TMUX_MIN_PANE_WIDTH` 校验 |
| `README.md` | 布局说明（`main-row2` / `main-col` / `grid` 三选一 + 何时自动回退） |
| `.agents/common/intercom-protocol.md` | 「tmux 宿主」段（默认布局描述处补 `main-col` 与回退行为） |

## 四、限制 / 风险（须写入 release notes「限制」）

1. **只保证宽度，不保证高度**：`main-col` 下 pane 数多时右列高度会塌陷（N=7 / H=40 ⇒ 6 行/pane）。阈值只约束宽度。
2. **`main-pane-width` 是 window option**：脚本会写当前 window 的这一项；影响面限于该窗口的 `main-*` 布局（`main-horizontal` 用 `main-pane-height`，不受影响）。属**有意的副作用**，需在 release notes 声明。
3. **`other-pane-width` 优先级更高**（实测：`main=40` + `other=30` ⇒ 主 pane 89）：若用户自己设过 `other-pane-width`，主 pane 百分比会被它压过。脚本**不设**该选项；文档提示「两者不要同时用」。
4. **极窄窗口无解**：`W` 小到连 pane 都放不下时 tmux 直接拒绝 `split-window`（§3.4），任何布局都救不了 ⇒ 只能是 warn。
5. 阈值 30 是**经验值**（约等于可读代码的最小宽度），非硬约束；给 `NAO_TMUX_MIN_PANE_WIDTH` 留出用户覆盖口。

## 五、验收 / 演练设计（交 RD 执行）

1. **几何矩阵（4/5/6 pane × W=80/100/120/152）**：套用 `main-row2` 与 `main-col`，输出 `tmux list-panes -F '#{pane_width}x#{pane_height}'` —— **断言：任一新 pane 宽度 ≥ 30**，且 `main-row2`（宽窗口）行为与改动前逐值一致。
2. **回退演练**：`W=80 & N=6`（现行 16 列）⇒ 断言实际生效 = `main-col` 且 warn 含三数字（**故意制造窄列 ⇒ 必须回退报错/提示**）。
3. **极端窗口**：`W=45`、`W=60` ⇒ 断言不出现不可用窄列、脚本不中断（§3.4）。
4. **默认不变**：不设 `NAO_TMUX_LAYOUT` 时，宽窗口（如 `W=152`）几何与 `d9ebf09` 逐值相同。
5. 复现命令（本 ADR 证据即由此产生，RD 可直接复用）：`tmux new-session -d -s t -x <W> -y 34; for i in $(seq 2 <N>); do tmux split-window -h -t t; done; tmux select-layout -t t tiled; …; tmux list-panes -t t -F '#{pane_width}x#{pane_height}'`。

## 六、参考来源

| 来源 | 链接 | 访问日期 |
| :--- | :--- | :--- |
| tmux 手册（七种预设布局：`even-horizontal/even-vertical/main-horizontal(-mirrored)/main-vertical(-mirrored)/tiled`） | https://man.openbsd.org/tmux.1 | 2026-09-25 |
| tmux 源码 `layout-set.c`（`tiled` 动态计算行列、`PANE_MINIMUM` 参与最小尺寸） | https://github.com/tmux/tmux/blob/master/layout-set.c | 2026-09-25 |
| tmux 源码 `tmux.1`（`main-pane-width` 默认 80、`other-pane-width`） | https://github.com/tmux/tmux/blob/master/tmux.1 | 2026-09-25 |
| 本机实测：tmux 3.6（`main-pane-width` 百分比、主 pane = pane 1、`other-pane-width` 优先级） | 本机（非外部） | 2026-09-25 |

## 七、交接（**本 ADR 不含实现**）

按 arch-designer 角色边界（§二 零代码红线），本文只出方案与实测证据，**未修改 `nao-fleet.sh` 或任何代码**。落地请派 **RD**（`rd-infra` 落地前用 `rd-be`），随 `feat/rd-infra` 同一 PR 或独立 PR；门禁见 §五。
