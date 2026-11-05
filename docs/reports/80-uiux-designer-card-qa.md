# #80 UI/UX 设计师常驻角色（第 7 角色）—— QA 独立复核报告

- 状态：**CONDITIONAL（GO 待处置 1 项 P2 文档/口径订正 + 2 项既有缺陷登记）**
- 更新：2026-11-05 · Owner：qa · 分支 `feat/80-uiux-designer-card` · 复核 HEAD **`8af96e5`**
- 指针：PRD `docs/prds/2026-11-05-uiux-designer-role.md`（§五 BR1–BR6/BR2a · §六 NFR · §七 AC1–AC7 · §九）· 卡 `.agents/prompts/uiux-designer.md` v1 · 技能 `.agents/skills/uiux-design.md` · 样例 `docs/designs/2026-11-05-sample-export-panel.md`
- 口径：**全部数字自跑**（未复用 RD/PM 回执）；不 live、不碰生产 tmux；唯一新增 = 本报告。

## TL;DR

- **功能面全过**：AC1–AC7 判定 7/7（AC1/AC4 走自建夹具，AC2/AC3/AC5 看产物，AC6 grep，AC7 门禁）。
- **门禁**：`check` rc=0（roles=7 · files=54 · 连跑 2 次逐字相同）· `npm test` rc=0 · `test:t4:full` rc=0（SKIP=0 / DEGRADE=0 / 非白名单 NOTE=0）· 例数 23 · 断言 868。
- **得改口径（P2-1）**：PRD §六 NFR 与 arch 结论「7 pane 零新增 warn / n=6 与 n=7 同为 3 列、几何逐字相同」**不成立**——含调用者后 7 角色 = **8 pane** ⇒ 4 列；`152×34`（T517 golden）下**回落 main-col + 1 条 warn**，7 个右侧 pane 各 **102×4（4 行高）**；对照 6 角色仍 main-row2 且 33×16。边界实测：**≥184 列**才保持 main-row2。
- **反假绿缺口（P2-2，既有）**：摘掉 `roles.yaml` 的 `uiux-designer`（卡仍在）或删一个别名 ⇒ `check` 仍 **rc=0**（roles=6 / 孤儿卡只 `!` warn），`cases/09`、`cases/17` 均仍绿 ⇒ 真实清单的角色数/别名集**无任何门禁守护**。
- **发布建议**：**CONDITIONAL GO** —— 角色功能、口径文档、门禁均达标；合并前 PM 需二选一：① 订正 PRD NFR（把「零新增 warn」改为「≥184 列零新增 warn；137–183 列回落 main-col」并为下批留 fix 项）② 明确接受该已知边界。P2-2 与既有 `case 12` 夹具踩踏登记下批，不阻断本批。

## 一、环境与三件套（命令 + 输出）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=7 · files=54 · layout=main-row2` · **rc=0**（连跑 2 次 `diff` 为空）
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · **rc=0**（23 例全 PASS）
- `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2）` · **rc=0**；NOTE 2 条均 `06:static-contract`
- `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **23**；`bash tests/t4/run.sh | grep -c '\[PASS\]'` → **868**
- `git diff --shortstat main...HEAD` → `20 files changed, 389 insertions(+), 40 deletions(-)`（本报告为第 21 个文件）
- 敏感值复核：`docs/`/`.agents/`/`bin/`/`tests/` 无 JWT / 真实实例 URL / 绝对家目录路径 → **0 命中**（`.pi/mcp.json` 未读未抄）
- 串行纪律：每次门禁前 `ps` 确认无 `/tmp/t517-reg` 残留（见 §四 P3-1）

## 二、逐 AC

- **AC1 主路径（夹具）＝过（12/12）**：隔离 socket + 桩 `tmux`（落盘 fleet 交给 tmux 的原始命令串）+ 桩 `pi`（argv 逐参落盘、`--version` 1.4.0、不拉真会话）。`ensure uiux` ⇒ rc=0、恰 1 行 `[tmux] 已拉起 uiux-designer`、`--name uiux-designer`（见 §四 P3-2 口径）、提示文件 `nao-fleet-uiux-designer-<6>.md` = 卡正文**逐字**（diff 为空）+ 锚点行 `NAO_SKILLS=<lab>`。**未碰生产 tmux**（复核后 `tmux list-sessions` 仍 4 窗口，无 uiux）。
- **AC2 主路径 ＝过**：样例含 9 项骨架（信息架构/流程/视觉规范/token/状态/断点/可用性/无障碍/降级产物）· 79 行 ≤80 · 标题与状态行双重标注「示例 · 未实施需求」· 索引 `docs/designs/README.md` 同步。
- **AC3 异常（无 Penpot）＝过**：卡 §四 + 技能 §二 给逐档判据（① 数值化文字规格 ② ≤40×20 ASCII ③ 分步作图指令），样例实交付 ①+② 并注明「③ 未包含，因无画板」；卡/技能零网络、无 MCP 依赖 ⇒ 不阻塞。
- **AC4 边界（命名冲突）＝过（13/13）**：`ui-designer` 与 `arch-designer` 并存 `check` rc=0、`✗` 行 0；三别名全部解析到 `uiux-designer`（`uiux` / `ui-designer` / `uiux-designer`），`ui-designer` 不落 `arch-designer`、不报「未知角色」；`roles.yaml` 别名恰 `[uiux, ui-designer, uiux-designer]`（BR2 canonical 在内）。
- **AC5 负向闭环 ＝过（产物面）**：卡 §五 + 技能 §一 + PM 卡 v34 均要求 PASS/REJECT 带 AC 编号，无编号即打回；**BR2a 与 QA 责任无重叠**：设计产物（实现前）回设计师，实现后视觉一致性仍走 QA 用户验收清单，实现偏差回 `rd-fe`/`rd-be`。
- **AC6 口径统一 ＝过**：`六个角色` = **0**；扩展口径（`6 个角色|6个角色|6 角色|6角色|6 个常驻|六个常驻|6 个会话|6 个分工|roles=6|6 位角色`）同范围 = **0**。角色行一致性：`roles.yaml` 7 条 = `nao-fleet` SKILL description 7 条 = `intercom-protocol` 表 7 条（新增行 `uiux / ui-designer` → `uiux-designer`）= README「七个角色」表（含「UI/UX 设计师」行）= INSTALL 7 会话表述。
- **AC7 门禁 ＝过**：见 §一；`cases/09` roles 断言已为 7（负控见 §三）。

## 三、负控（自己构造，防假绿 / 防脚本崩溃骗红）

- **改 `cases/09` `roles=7`→`roles=6`** ⇒ `[FAIL] AC2: 正常态 check 报 roles=6（负控）（未包含: roles=6）`，`RESULT: FAIL (1 项)` ⇒ **精确翻红并点名**。
- **`cases/17` 参数化回退硬编码 `=== 6`**（4 处）⇒ 4 条点名 FAIL（`defs-count` / `registry-count` / `idempotent-start` / `escape-valve-reenable`）⇒ 该范围外改动**必要**（验证 PM 的「改前 4 条红」）。
- **摘 `roles.yaml` 的 `uiux-designer`**（卡保留）⇒ `check` **rc=0**、`roles=6`、仅 `! uiux-designer.md 未登记于 roles.yaml`；`cases/09`/`cases/17` 仍绿 ⇒ **不翻红**（既有设计：孤儿卡只 warn）。
- **删别名 `uiux`**（保 canonical）⇒ `check` **rc=0**；`cases/09` **PASS**（其 fixture 自带别名清单，不读真清单）；仅直测 `close --task NAOQA uiux` 报「未知角色」⇒ **不翻红**。
- **反向正控**：`roles.yaml` 声明 `card: ghost.md`（缺文件）⇒ `check` **rc=1** + 2 条命名错误（`✗ ghost.md 缺失`、canonical 未登记）；`cases/17` 3 条 FAIL ⇒ 机制侧缺卡/缺登记有红，**唯独「孤儿卡」这一侧假绿**。

## 四、缺陷与风险（分级）

- **P2-1（推定 P2 · 本批引入的口径错误，非功能故障）**：PRD §六 NFR「7 pane 零新增 warn、n=6 与 n=7 同为 3 列几何逐字相同」与实际不符。实测（隔离 socket 真拉起、3/3 复现同形）：`240 列` 7 角色 8 pane / 5 列（主 78 + 39,39,39,41）无 warn；`152 列` **回退 main-col + warn**（`8 pane @ 152 列：最窄列 24 < 最小 30`），右侧 7 pane 各 **102×4**；`120 列` 6/7 角色都 warn，7 角色多 1 条；阈值 **≥184 列** 保持 main-row2（6 角色约 ≥137）。功能无破损（rc=0、7 会话全拉起）。**处置**：PRD NFR/§九 订正为实测口径，或登记下批 fix（guard 阈值/列数按 `roles+1` 计）。
- **P2-2（既有 · 本次要求探到的假绿缺口）**：真实 `roles.yaml` 的角色数与别名集无门禁守护（§三第 3、4 条）。**建议**：`cases/06` 或 `cases/09` 增「真清单」断言（`roles=7` + 3 别名 + card 集 ↔ roles 双向），补齐 AC7 的可证伪性。**不计本批 AC 未过**（fixture 优于硬编码的设计取舍所致）。
- **P3-1（既有 · 已由 PM 登记）**：`cases/12` 固定夹具 `/tmp/t517-reg` ⇒ 并行/残留 tmux server 会踩踏（本次首轮 3 次红、清残留后单跑 36/36 全过，`main` 同条件亦红→非本批引入）。
- **P3-2（口径澄清）**：AC1 文案「会话名 = uiux-designer」在实现上是 **pi/intercom `--name`**（pane 属宿主窗口，tmux 会话名不变）；`cases/24` 同口径，非缺陷。
- **P3-3（既有）**：`tests/t4/cases/09` 只测 `uiux` / `ui-designer` 两别名，**canonical `uiux-designer` 未做别名探针**（由 BR2 canonical-in-aliases 间接覆盖）。

## 五、范围外 3 组文件判定（必要且最小）

- `.agents/templates/pi-subagents/intercom-bridge.md`：+1 行把 `uiux-designer` 纳入「不得冒名」枚举。**必要**（漏则子代理冒用新角色不算违规，防冒充面缺口）；**最小**。
- `bin/nao-skill.js`：**4 处**（PM 说 3 处，实为 header 用法 / install 下一步 / init 下一步 / `--help`）。**必要**（否则安装提示的 `ensure` 示例永不拉起设计师，新人按提示跑不到 7 角色 = 口径漏洞）；**最小**（纯字符串）。
- `tests/t4/cases/17-role-agents.sh`（4 处参数化）+ `tests/README.md`（1 行改描述）：**必要**（回退即 4 条红，§三已验证）；**最小**。残留提醒见 P2-2。
- **结论**：4 个范围外文件均必要且最小，无功能/口径漏洞；`tests/README.md` 与 `nao-skill.js` 的处数与 PM 表述略有差异（4 文件 / 4 处），建议回执按实。

## 六、未做与边界

- 真 `pi` 会话未拉起（桩 `pi`）；未验 pi 侧真实注入渲染（`cases/20/23/24` 已覆盖 argv 与提示文件字节）。
- 视觉/UI 呈现类验证本批无 UI 产出（样例为骨架文档），无需用户验收清单。
- 未改实现、未 push、未合并、未动 `.pi/mcp.json`；本报告为唯一新增文件。
