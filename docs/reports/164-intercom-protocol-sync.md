# #164 `intercom-protocol` 常驻面同步 v2（`@` 旧名退场 · 回执寻址去裸名）

- 状态：待验收 · 更新：2026-11-23 · Owner：rd-infra
- 指针：Issue [#164](https://github.com/Nathan3303/nao-skills/issues/164) · 任务 T560 · 分支 `fix/164-intercom-protocol-sync`（基线 `e654cb4`）
- 上游：`#161`/T559（投递寻址硬化，单源 = @.agents/skills/pm-operations.md §一「投递寻址」）

## TL;DR

- `intercom-protocol.md` 是 worker **每个会话都读的常驻面**（`@` 注入），陈旧代价最高；本批把它从 v1 舰队口径拉齐到 **v2（workspace 为绑定单位 · 名字不含位置）**。
- 改动 **10 行**（同一文件，11 处编辑：首轮 9 + QA 复验后 3，其中 2 处是同一行再订），全是既有文本的增量订正，零新增正文文件、零角色卡改动 ⇒ 无 bump / 无广播。
- 终态回执段改为「回**派单方会话**：`to` 用会话 id（或 `to`+`cwd`），禁裸名」+ 指针，**不复述**完整名/前缀回退等细节（守住 #161 刚立的单源纪律）。
- 全文件 v1 残留自查 **16 条命中 → 改 7 / 不改 9**（逐条给理由，见 §三）；判据可 `grep`（见 §四，豁免 1 类共 3 处逐处说明）。
- **范围外发现**（本批不改，建议单开）：`README.md:83`、`docs/INSTALL.md:116-156`、`nao-fleet.sh` 用法头 `:32-46` 仍是 v1 `@<fleet>` 口径（见 §五）。

## 一、事实复核（未采信转述，逐条自测）

**v2 名字契约**（权威源：ADR `docs/adr/2026-11-20-workspace-as-binding-unit.md` §决策 1–4）

- 常驻 `<role>[<N>]` · 派生 `<role>[<N>](<task>)`；N 空 = 槽位 1，同 workspace 内重名加数字、`N>9` fail loud ——
  实现 `nao-fleet.sh::fleet_core_build`（`grep -n 'fleet_core_build()' ⇒ 2064`）。
- 解析分派：「含 `(` ⇒ 新形；含 `@` ⇒ legacy scope；否则旧形」—— `grep -n 'fleet_name_parse()' ⇒ 2100`。
- `@` 的**唯一现存语义** = `ensure <role>@<code>` 的**目标仓选择符**（不进名字）—— 实现 `grep -n 'role="${spec%%@\*}"' ⇒ 4264`，同源提示 `grep -n '名字不得含 @' ⇒ 3188`。
- `--fleet` / `--scope` / `.agents/fleet-scope` **已弃用**：给参只 warn、放置键恒为仓基键 —— `grep -n '"--fleet\|弃用：--fleet' ⇒ 2012`。

**现网实证**（`intercom list`，非推理）

```
rd-infra(T557) · pm(T555) · qa(T557) · qa2(T558)     ← v2：派生 <role>(<task>) + 槽位 2
pm@nao-todo · pm（nue-ui）                            ← 在场遗留：1 个 v1 @ 名 + 1 个 v2 常驻裸名
```

**对 PM 表述的一处精度订正**：PM 原话「旧 `@` 名**不再支持**」—— 实际是 **legacy 仍可解析、可与 v2 并存**（`pm@nao-todo` 在场即证；脚本注释 `grep -n '旧形不占 v2 槽位' ⇒ 4027` 明写「旧会话只读、可并存」）。
故落文用「**新会话不再产生 + `@` 形不作准**」，不用「不再支持」—— 否则 worker 见到在场旧会话会误判成异常。

**QA 二次复验把这条推深了一层（本处为订正后口径）**：`send` / `handover` 对**任何含 `@` 的 `to`** 一律按**跨机地址**处理（`index.ts:1827` `crossMachineTarget = Boolean(to?.includes("@"))`，分支在 `:1876`），本机无 remote machine ⇒ 报 **unreachable**、**不回落本地解析**；而 `ask`（`index.ts:2825-2860`）**没有这条分流**，走 `resolveSessionTarget` 本地解析。⇒ 旧名「**ask 可得、send 不可得**」。
所以「在场旧名在线 ⇒ 能当 `to` 用」**证明力不足**（在线 ≠ 可投），原文只写「不作准」不写「不支持」是对的，但**必须补半句硬事实**，否则 worker 在 `list` 里看到旧名会照抄 ⇒ 已补（`:11`）。

## 二、范围（10 行改动位置）

行号为现文件实测值；取数命令：`grep -n '<锚文本>' .agents/common/intercom-protocol.md`。

| 行 | 改动 | 对应 PM 项 |
| :--- | :--- | :--- |
| `11` | 会话名整行 v1→v2（`<role>[<N>](<task>)` · 同名是机制使然 · 跨仓用 id · 旧 `@` 退场）＋ 旧名实例改中性描述 ＋ 补「`send`/`handover` 把含 `@` 的 `to` 当跨机 ⇒ 本机不可达」 | ① · P3-1 · P3-3 |
| `16` | 节标题 `fleet.sh` → `nao-fleet.sh` | ③（自查） |
| `24` | `rd-be@<repo>` 加括注「= 目标仓 code，不进会话名」 | ③（消歧） |
| `28` | `ensure <别名>[@<repo>]` 加括注（目标仓选择符 + 显式槽位 `<role>2`…`<role>9`） | ③（消歧） |
| `30` | 派生会话名 `<角色>-<编号>` → `<role>(<任务>)`（槽位已占则 `<role>2(<任务>)`） | ① |
| `31` | 按需卡会话名 `<role>@<fleet>` → `<role>(<任务>)` / `<role><N>(<任务>)` ＋ 补「无 `--task` 时 `<role>` / `<role><N>`；`--as` 可自定义 core（须留卡 role 前缀、禁括号）」 | ① · P3-2 |
| `35` | 放置规则指针：废弃 ADR `2026-11-17-fleet-identity-source` → `2026-11-20-workspace-as-binding-unit` ＋ 「放置键 = 仓基键、名字不含位置」 | P2-1 |
| `83` | 单 PM 纪律：`pm@<fleet>` 判重 → workspace 内 core `pm` 在线即跳过；`pm2` 是另一槽位的另一 PM | ③（自查） |
| `88` | 终态回执：`回 PM` → 回**派单方会话**（`to` 用 id 或 `to`+`cwd`，禁裸名）+ 指针 | ② |
| `107` | `fleet.sh ensure --force` → `nao-fleet.sh ensure --force` | ③（自查） |

## 三、v1 残留自查表（逐条归口：重写 7 · 保留并加括注 2 · 其余不动）

取数命令：`grep -n -E '@<fleet>|@<repo>|回 PM|fleet\.sh|fleet-scope|--fleet' .agents/common/intercom-protocol.md`

**重写（7 条）**

1. `:11` 会话名 `<role>[-<task>]@<fleet>` + `--fleet`/`fleet-scope` 覆盖 + `status` parse fleet + `close` 裸名候选链 + 「口头寻址优先用全名」 ⇒ 全行重写为 v2（末句「优先用全名」与 #161 直接冲突，是**最危险的残留**：它教 worker 用名字而非 id）。
2. `:30` 派生名 `<角色>-<编号>`（v1 `-` 任务分隔） ⇒ v2 括号形。
3. `:31` 卡会话名 `<role>@<fleet>` ⇒ 括号形。
4. `:83` `pm@<fleet>` 判重 ⇒ workspace + pane label core 判重。
5. `:88` `回 PM` ⇒ 回派单方会话（+ 指针）。
6. `:16` 标题里的 `fleet.sh`（早已更名 `nao-fleet.sh`）。
7. `:107` 同上（`fleet.sh ensure --force`）。

**保留语义 + 加括注消歧（2 条）**

1. `:24` `rd-be@<repo>` = **`ensure` 的目标仓选择符**（`fleet.yaml` 的 `code`），v2 明确保留（ADR 决策 3：`@` 只选目标仓、不进名字）⇒ 保留并加括注「不进会话名」。
2. `:28` 同上是 `[@<repo>]` 用法位 ⇒ 保留并加括注（目标仓选择符 + 显式槽位写法）。

**不动（逐类理由）**

1. `:14` `:46` `:79` `:87` `:90` `:100` `:106` `:114` `:123` `:133` `:148` `:151` 等 `@.agents/...` = **pi 文件引用语法**，与会话名无关。
2. `:10` `--name <别名>` = ensure 传参实际形态（现行）。
3. `:31`「命名与目录约束见 `nao-fleet.sh --help`」中的 `--card` 段 = 现行功能（T537）。
4. `:35` 运行前提行（herdr / pi ≥1.4.0 / `exit 3`）= 现行实现，且 `check` 的端前提比对会读该行（改错会直接触发 warn）⇒ **前提部分不改**；其中「拉起落点」句附带一个**已废弃 ADR 指针**（`2026-11-17-fleet-identity-source`），属 v1 残留 ⇒ 第二轮照原意修改指针与措辞（P2-1），前提语义零变动。
5. `:92`「ADR 路径」= 回执字段名，非命名契约。
6. 文档骨架里的 `YYYY-MM-DD-<主题>.md` 等占位 = 归档约定。

（合计：重写 7 + 保留并加括注 2 = **9 处改动**，与 §二 表逐行对应；其余命中均属上「不动」六类。）

## 四、判据（机械可判，含豁免）

```bash
# 判据 A：名字模板里的 @ 位置段 = 0（v1 形态不再作为模板出现）
grep -cE '@<fleet>|\[-<task>\]@|<role>-<task>@' .agents/common/intercom-protocol.md   # ⇒ 0
# 判据 B：「回 PM」字面 = 0
grep -c '回 PM' .agents/common/intercom-protocol.md                                    # ⇒ 0
# 判据 C：旧命令名 fleet.sh（非 nao-fleet.sh）= 0
grep -cE '(^|[^-])fleet\.sh' .agents/common/intercom-protocol.md                        # ⇒ 0
# 判据 D：废弃 ADR 引用 = 0（放置规则已指向 2026-11-20 篇）
grep -c '2026-11-17-fleet-identity-source' .agents/common/intercom-protocol.md          # ⇒ 0
```

**豁免 1 类（3 处，`:24`/`:28`/`:30`）**：`@<repo>` —— `ensure` 的**目标仓选择符**（ADR 决策 3：`@` 只选目标仓、不进名字），v2 保留；判据 A 只匹配 `@<fleet>` 模板，不误伤它。

（首轮还有一处豁免：`:11` 的 `pm@nao-todo` 实例。QA P3-3 指出本文件随包发到别仓、写具体仓名像专有名词 ⇒ 已改中性描述「在场遗留的 v1 会话名字含 `@`」，豁免随之消失。）

判据的设计取向：**判「模板/教法」而不是判「字符 `@`」** —— 因为 `@` 在 pi 文件引用（`@.agents/...`）与 ensure 目标仓里是合法且必需的，按字符统计必然需要大量豁免、反而不可判。

## 五、范围外发现（本批不改，建议单开）

同一次全仓扫描发现**同一类陈旧**仍在别处，涉及面比本文件更大（README 是用户入口、INSTALL 是维护者口径），**不在本批范围**（PM 定为「常驻面 5 处」）：

1. `README.md:83`：会话名 `<role>[-<task>]@<fleet>` · `ensure --fleet <名>` · `.agents/fleet-scope` 覆盖 · 「同 fleet 撞车报错」——全是 v1，且与 v2 行为相反（`--fleet` 现在只 warn 并忽略）。
2. `docs/INSTALL.md:116-156`「会话命名与多仓舰队（`--fleet` / `.agents/fleet-scope`）」整节 v1。
3. `nao-fleet.sh` 用法头 `:32-46`（`会话名契约（BR8）：<role>[-<task>]@<fleet>`、`--fleet` 三档优先级）：**实现已 v2，注释仍 v1** —— 这与本批同一病因（文档落后于实现），但改 `nao-fleet.sh` 属非范围。

建议：三处合并为一条「v1 命名口径清理」Issue（文本为主，可一次改完；`:32-46` 顺手修正可避免 `--help` 继续教错）。

## 六、门禁

```bash
bash .agents/scripts/nao-fleet.sh check > /tmp/rd-t560-check.log 2>&1   # rc=0 · OK · roles=7 · files=53
npm test > /tmp/rd-t560-test.log 2>&1                                   # 数字见回执（日志落盘，未过滤）
```

- 零敏感值：改动仅文档措辞，无 token/私钥/绝对家目录路径。
- 幂等：纯文本订正，重跑无副作用。
- 角色卡未改 ⇒ 无 `version` bump、无 intercom 广播。

## 七、QA 复验后的 4 处修订（第二轮）

| 项 | 位置 | 修订 | 依据（自测） |
| :--- | :--- | :--- | :--- |
| P2-1 | `:35` | 废弃 ADR 指针 → `2026-11-20-workspace-as-binding-unit` | `docs/adr/README.md:26` 标「已废弃（被 2026-11-20 取代）」 |
| P3-1 | `:11` | 补「`send`/`handover` 把含 `@` 的 `to` 当跨机 ⇒ 本机不可达」 | `index.ts:1827`（`to.includes("@")`）+ `:1876` 分流；`ask` 无此分流（`:2825-2860`） |
| P3-2 | `:31` | 补「无 `--task` ⇒ `<role>` / `<role><N>`；`--as` 自定义 core（留卡 role 前缀、禁括号）」 | `nao-fleet.sh:2067`（`fleet_core_build`，无 `--task` 分支 `:2080-2082`）+ `:4276`（禁括号）+ `:4283-4284`（前缀约束） |
| P3-3 | `:11` | 删本机现场名 `pm@nao-todo` → 中性描述 | 本文件随包分发到别仓，具体仓名无通用性 |

仍在范围外的 4 项（PM 裁「单开」）：`intercom-protocol` 的其余 v1 措辞归 Issue [#164](https://github.com/Nathan3303/nao-skills/issues/164) 之后批次；`README.md` / `INSTALL.md` / 用法头归 Issue [#166](https://github.com/Nathan3303/nao-skills/issues/166)。
