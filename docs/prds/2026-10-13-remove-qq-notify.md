# T514 PRD：移除 qq-notify 能力（机制包 + 文档全清除）

- **日期**：2026-10-13 · **负责人**：PM · **实施**：rd-infra（单 PR · 单波）
- **版本**：**0.15.0**（MINOR，0.x 破坏性变更口径）· **Issue**：#22（复用为其载体，分支 `feat/22-remove-qq-notify`）
- **状态**：已拍板（用户 2026-10-13 三项确认）

## TL;DR

- **做什么**：把 qq-notify 全部移除——包内脚本 + skill 文档 + PM 角色卡 §十四 + README 节 + CLI legacy 白名单 2 行；发 0.15.0（tag + Release），关闭 #22。
- **给谁**：机制包使用者与维护者。
- **成功标准**：非归档文件 0 引用、`check` exit 0 roles=6、init/migrate 幂等不变、main 恰 1 条 squash 提交。
- **不做什么**：不动外部项目 `pi-agent-qqbot`；不改历史归档（docs/releases/**、docs/reports/**）；不重构 migrate 判定式；不通知下游三仓。

## 一、问题证据

- Issue #22（2026-10-08）：`qq-notify.md` 仍有 **12 处项目内路径**引用 + 第 86–87 行**事实失实**（迁移后机制已不在项目内）；对照组 `ui-tokens-check.sh` 引用形态已全部正确。
- 5 Whys：文档失实 → 无人回归该能力 → 该能力在迁移后已无使用场景 → 无使用者的可选能力持续产生维护税与漂移 → **与其修文档口径，不如整体移除**。

## 二、决策记录（用户 2026-10-13 三项拍板）

- **D1** 移除范围：**全删**（包内资产 + 提及面 + CLI 白名单）。
- **D2** 版本：**0.15.0** 发版（tag + Release）。
- **D3** Issue #22 随本需求落地后关闭，原「修文档」候选撤销。

## 三、战略筛子 / 优先级 / RICE（结论 + 指针）

- 战略筛子：**通过**——与「省 token / 机制单一事实来源」战略一致，删减无使用者的可选面。
- MoSCoW：**Must**（用户明示）· RICE：Reach 低（可选能力）· Impact 中（除维护税与失实源）· Confidence 高 · Effort 小 → 优先级高。
- 打分过程与明细不展开（≤1 log 行，见台账）。

## 四、范围

**做**：
- 删 `.agents/scripts/qq-notify`、`.agents/skills/qq-notify.md`。
- 删 `.agents/prompts/product-manager.md` §十四 QQ 推送节（含悬空 `@.agents/skills/qq-notify.md` 引用）。
- 删 `bin/nao-skill.js` 中 `LEGACY_SCRIPT_FILES` / `LEGACY_SKILL_ENTRIES` 的 `qq-notify` 两项（迁移判定白名单收敛）。
- 删 README「可选：关键节点 QQ 主动推送」整节。
- `package.json` → 0.15.0；Release 落 `docs/releases/v0.15.0.md`（用户可读：「本次更新」置顶）。
- #22 关闭评论留痕；`docs/tasks-state.md`、`docs/prds/README.md` 索引随批更新。

**不做**：调用面之外的外部项目；`docs/releases/v0.8*/v0.9.2.md`、`docs/reports/*` 历史归档；tmux / 其他能力；下游三仓通知（bug 无行为依赖，pin 升级自愈）。

## 五、用户场景

- **画像**：使用 nao 机制的单人开发者。
- **新装用户**：README 不再出现 QQ 推送节，可选能力面更聚焦。
- **已用 QQ 推送的用户**：升级 0.15.0 后该能力消失；指南——停留在 ≤0.14.0 pin 或自行对接 `pi-agent-qqbot`。
- **维护者**：包体与 skill 注册表 -1 项，check/migrate/init 行为不变。
- 页面状态清单：不适用（无 UI；文档生命周期已由上述三类覆盖）。

## 六、业务规则（不变量）

- 机制单一事实来源 = npm 包内 `.agents/**`；版本权威 = `.pi/settings.json` pin。
- 历史归档文档不改（长期既定口径）。
- `check` 恒 exit 0 且 roles=6；`init` / `migrate` 幂等；无新增网络调用。
- 0.x 阶段破坏性移除走 MINOR。

## 七、NFRs

- 兼容性：存量 0.14 用户升级后旧入口失效——Release notes 必须一行说明；不提供兼容垫片。
- 可维护性：非归档全仓 qq 引用清零（含 tmux 之外的口令面）。
- 性能/体积：影响几 KB 量级，无基准要求。

## 八、验收标准（AC）

- **AC1**：Given 包内 `.agents/`，When `find .agents -iname '*qq*'`，Then 0 结果。
- **AC2**：Given 全仓排除 `docs/releases/** docs/reports/** docs/prds/** docs/tasks-state.md`，When `rg -i 'qq-notify|qqbot|QQ 主动推送'`，Then 0 命中。
- **AC3**：Given `bin/nao-skill.js`，When 核对两处 legacy 白名单，Then 无 `qq-notify` 项且 `init` 幂等重写正常（对无 qq 资产仓判定不变）。
- **AC4**：Given PM 角色卡，When 读 `.agents/prompts/product-manager.md`，Then 无 QQ 推送节与悬空 @ 引用，排版连续。
- **AC5**：Given README，When 浏览目录与全文，Then 无 QQ 节，主线导航完整。
- **AC6**：Given 机制门禁，When `bash .agents/scripts/nao-fleet.sh check`，Then exit 0 roles=6；`pi skills` 注册数变化（-1）已记录在回执。
- **AC7**：Given 发版，When 核对，Then `package.json`=0.15.0、tag `v0.15.0` 指向 main 合并提交、release notes 用户可读且落盘。
- **AC8**：Given #22，When 本 PR 合并后，Then PM 关闭 #22 并留处置评论。
- **AC9**：Given main，When 核对，Then 本需求恰 1 条 squash 提交、无 `wip()`、分支已删。
- **AC10**：Given 下游三仓，When `rg -i 'qq-notify|qqbot'`，Then 0 命中（预期 0；有命中仅报告不开新工作）。

## 九、上线闭环

- 无灰度（开发工具包）；监控 = GitHub Issues + npm 下载反馈。
- 回滚预案：revert 合并提交 → 发 0.15.1 补包；tag 不删。
- npm publish 仍由用户执行（历史惯例，PM 发 tag + Release）。

## 十、变更治理

- 本单变更经用户三项拍板（§二），无口头未落盘项。
- Hotfix：不预登记；发生按 24h 补单。
