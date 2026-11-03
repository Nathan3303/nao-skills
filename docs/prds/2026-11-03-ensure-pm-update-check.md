# 机制批：`ensure pm` 下游版本自检（仅提示，不自动升级）

> 日期：2026-11-03 · 分支：`feat/74-update-check`（Issue [#74](https://github.com/Nathan3303/nao-skills/issues/74)）· 不单独发版（随下次发布进 release notes）

## 一、问题证据

- **用户需求（2026-11-03）**：下游项目装好机制后，升级要靠人记得去改 `.pi/settings.json` 的 pin 再 `pi update --extensions`；希望 **`ensure pm` 的时候**顺手做一次「作为下游，更新 nao-skills 版本（如果有）」。
- **用户补充口径（同日）**：**仅提示**——提示要说清「更新了什么 / 会更新什么」，由用户决定；用户同意后由 PM 会话执行升级动作（**不由 fleet 自动升级**）。默认开启；触发范围**仅 `ensure pm`**。
- **机制现状取证**：`nao-fleet.sh` 中 spawn 的唯一入口是 `build_inner` 的 `exec pi --name <name> --append-system-prompt <card>`（`.agents/scripts/nao-fleet.sh:1106`）；`pi` 的 CLI 形如 `pi [options] [--] [files...] [messages...]`，**支持启动时传入首条用户消息**，因此「PM 起来先做一件事」无需新机制。
- **零网络红线**：机制自身（转发入口 / fleet / CLI / `check`）零网络调用（`grep` 无 `npm view` / registry 引用）。版本查询必须发生在**PM 会话内**，不能由 fleet 执行。

## 二、目标指标

- **北极星**：下游项目「机制包落后于 npm latest」的平均滞留时间从「无感知，可能跨多个批次」降至 **每次 `ensure pm` 一次感知**（有新版即一行提示）。
- **辅助指标**：`ensure` 主路径耗时**不增加**（注入不执行任何外部命令）；非 `pm` 目标的 `exec pi` 命令行**逐字不变**（零回归）。

## 三、范围 / 非范围

**范围**

- `.agents/scripts/nao-fleet.sh`：`build_inner` 在目标为 `pm` 且开关开启时，于 `--append-system-prompt` 之后追加一条**固定文本**的首条用户消息（用 `--` 与其余 options 分隔）。
- `.agents/skills/pm-operations.md`（或 `product-manager.md` 对应小节）：写清 PM 侧行为契约（检查顺序、五种降级情形的输出、**未获同意前零文件改动**、同意后的动作序列与「请重开会话」提醒）。
- `tests/t4/`：新增用例覆盖「含 pm 注入 / 不含 pm 不注入 / 开关关闭不注入 / 非 pm 目标命令行逐字不变」。
- `docs/tasks-state.md`：登记本批（随本 PR）。

**非范围**

- **不做自动升级**：fleet 不改 `.pi/settings.json`、不执行 `pi install` / `pi update`；升级只在用户明确同意后由 PM 会话执行。
- **不轮询、不后台、不联网**：fleet 内零网络；无定时任务。
- 不改 `bin/nao-skill.js`（`init` / `migrate` 语义不变）。
- 不接管生产部署/灰度/监控（延续 #72 的 out-of-scope）。

## 四、用户场景

- **场景 1（有新版）**：用户 `ensure pm` → PM 起来第一句：`当前 0.21.3 → 可升 0.22.0：修 bug 不再需要写完整 PRD；ensure 支持 fix/ 分支。要升吗？` → 用户说「升」→ PM 执行 pin 更新 + `pi update --extensions` → 提示「本轮会话仍是旧角色卡，建议重开」。
- **场景 2（已最新）**：`版本检查：已是最新 0.21.3。` 一行后正常待命。
- **场景 3（离线/超时）**：`版本检查：离线或超时，跳过（可稍后手动 npx @nathan33/nao-skill --version 核对）。` 不阻塞。
- **场景 4（本仓这种非下游安装）**：`.pi/settings.json` 无 `@nathan33/nao-skill` pin ⇒ `版本检查：未检测到下游 pin（本仓为机制源），跳过。`
- **场景 5（无 `gh`）**：只报版本号 + Releases 页链接，不说「更新了什么」。

## 五、业务规则

- **R1 注入条件**：解析后的目标列表含 `pm`（含别名/规范名解析后为 `pm`）**且** `NAO_UPDATE_ON_ENSURE` 未设为 `0`/`false`。
- **R2 注入位置**：必须在该目标的 `--append-system-prompt` 之后、以 `--` 分隔后追加；消息文本整体经 `printf %q` 转义（禁止拼接未转义文本）。
- **R3 注入文本固定**：文本是常量（便于 `grep` 自证），内容须含：① 读本地 pin 与 `npm view`（**5s 超时**）② 有新版取 `gh release view` 要点并**压成不超过两句** ③ **一行询问** ④ 五种降级情形各一行 ⑤ **硬约束句：「未获我同意前不要改任何文件、不要升级」** ⑥ 同意后的动作序列 + 「请重开会话」提醒。
- **R4 不影响拉起**：注入失败（文本构造异常等）必须**不改变三态输出契约**（该目标仍按实际情况打印唯一一条结果行）；非 `pm` 目标的 `exec pi` 命令行**逐字不变**。
- **R5 零文件改动保证**：检查阶段只读（`npm view` / `gh release view` / 读 `.pi/settings.json`）；任何写操作只在用户明确同意后发生。
- **R6 开关**：`NAO_UPDATE_ON_ENSURE=0` ⇒ 行为与本批之前**逐字等价**（可 diff 自证）。

## 六、NFRs

- **`ensure` 主路径耗时不变**：注入只拼字符串，不执行外部命令；不得引入 `npm`/`gh` 调用到 fleet 进程。
- **零网络**：fleet 进程零网络请求（沿用既有红线）。
- **可自证**：注入文本是常量 → `grep -c` 可判定；三条「不注入」路径可用测试桩验证。
- **门禁不降级**：`check` + `npm test` 全量 rc=0；现有 `tests/t4` 用例零回归。

## 七、验收标准（AC）

- **AC1 注入条件正确**：`ensure pm` 与 `ensure pm arch ...`（含 pm）注入；`ensure rd-be`（不含 pm）不注入；`NAO_UPDATE_ON_ENSURE=0` 时 `ensure pm` 也不注入。三条各有用例或桩证据。
- **AC2 注入文本可自证且含硬约束**：文本为常量，`grep` 能定位；必须含「未获我同意前不要改任何文件」与「5s」超时口径。
- **AC3 分隔与转义**：消息位于 `--` 之后且经 `printf %q`；构造后的命令行里消息不会被解析为 `@file` 或选项（用例断言命令行形态）。
- **AC4 零回归**：非 `pm` 目标（如 `rd-be`、`arch`）的 `exec pi` 命令行与本批前**逐字一致**（用例逐字比对）；`NAO_UPDATE_ON_ENSURE=0` 下 `ensure pm` 的命令行亦逐字一致。
- **AC5 契约不变**：注入路径下仍沿用 T539 三态输出（成功/跳过/失败各一行），失败不打印假成功。
- **AC6 文档契约落地**：PM 侧规则（五种降级输出 + 未同意零改动 + 同意后动作序列 + 重开会话提醒）写进按需文档，且不与「不可逆动作须 ask-me」冲突（升级本身即 ask-me 对象）。
- **AC7 门禁与零网络**：`check` rc=0 · `npm test` rc=0 · 新增用例 PASS · `grep` 证明 fleet 内无新增网络命令（无 `npm view` / `curl` / `gh` 调用）。

## 八、上线闭环

- 不涉及部署。合并后随下次发布进 release notes（面向用户一句话：`ensure pm` 会顺带告诉你机制包有没有新版）。
- 观察项（合并后 30 天）：注入是否造成「每次开 PM 都多一次无意义查问」——若用户抱怨噪音，改为「距上次检查 <24h 则跳过」（需新增本地状态文件，届时另立需求）。

## 九、变更治理

- **冻结点**：本 PRD 定稿（开工确认卡确认时）。
- **裁定权**：注入文案以本 PRD R3 的六要素为准；文案措辞可微调但六要素不得删。
- **回退**：单条 squash 提交 `git revert` 即整批回退；开关 `NAO_UPDATE_ON_ENSURE=0` 可即时关闭而无需回退。
