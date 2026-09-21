---
description: pi-intercom 多会话协作协议（常驻引用）
---

# 多会话协作协议（pi-intercom）

## 角色与接入

- 会话由 `nao-fleet.sh` 以 `--name <别名>` 拉起，角色卡经 `--append-system-prompt` 启动期注入。
- **角色 id / 别名 / 卡片映射以 `.agents/roles.yaml` 为唯一事实来源**（下表为当前快照，改动先改 roles.yaml）。
- 被点名先回执：`已按 <role> 角色执行`。
- 仅当消息明确要求、且确认未注入时，才自行读取 `@.agents/prompts/<role>.md`（跨仓库会话用启动期注入的环境锚点绝对路径）。

## 别名与工作区（fleet.sh，以 .agents/roles.yaml 为准）

| 别名 | 角色卡 | 默认工作区 |
| :--- | :--- | :--- |
| `pm` | product-manager | 当前项目目录 |
| `arch` / `arch-designer`（同义） | architecture-designer | 当前项目目录 |
| `rd-fe` | frontend-developer | 当前项目目录 |
| `rd-be` | backend-developer | 前后端分离时显式 `rd-be@<repo>` |
| `qa` | test-engineer | 当前项目目录 |

拉起：`bash .agents/scripts/nao-fleet.sh ensure <别名>[@<repo>]`

- **判重**：脚本以 `--name <别名>` 判在线；已运行则跳过并 warn。确需重开加 `--force`。
- **tmux 宿主**：`$TMUX` 存在时在当前窗口分屏拉起（默认布局 `main-row2`：
  首 pane 全高占左，后续每角色往右开列、每列上下 2 个）；不在 tmux 内则创建
  detached 会话，需 `tmux attach -t nao-<别名>`。
- **模型规则**：用户未指定则**禁止传 `--model`**，也禁止继承 PM 自身模型。
  显式指定时由 `NAO_MODEL_WHITELIST` 在**命令行入口解析阶段**即校验，
  不命中直接 `die`，无部分拉起；PM 只需如实转达用户 `-m` 指定。

## 开工前自检（派发闸门）

派发前跑一次：

```bash
bash .agents/scripts/nao-fleet.sh check
```

- 目录/角色卡/common/skills 齐备、roles.yaml 可解析且与卡片 frontmatter（role/version）一致、卡片交叉引用文件齐备、布局合法 → 继续
- 白名单脏（重复 / `*` / 空条目）→ 提醒用户清理
- 常驻卡超阈值 → 记 TODO，不阻塞
- **退出码非 0**（硬错误：目录缺失 / 布局非法 / checksum 失败）→ **停止派发**

## 线程纪律

- `ask` 提问 → `reply` 保持线程。
- 同会话一次只挂一个 `ask`；遇 `Already waiting` 降级 `send`。
- 长任务：`send` 分派 + worker 定期短汇报。
- `ask` 默认超时 10 分钟。
- `list` 确认目标在线后再派发。

## 终态回执（硬性闸门，所有角色适用）

- 每次派发的任务（含架构评审）**必须以终态回执结束**：按 output-format「回执模板」`[编号] done | <role>`，经 intercom `send` 回 PM。
- 短消息（≤150 字摘要 + 结论/决策点 + 详情落盘路径）；**禁止**把长报告全文 `send` 污染线程（output-format「反模式」）。
- arch 评审回执至少含：可行性结论、ADR 路径、待 PM 拍板决策点。
- `send` 失败（目标离线 / 会话不存在）→ 尝试 `ask`；仍失败 → 降级交付并注明，见「降级」。
- PM 侧：派发后未收到回执 → 主动追讨（`ask`/`send`），**不默认成功**；`nao-fleet.sh status` + `intercom list` 辅助确认在线名单。

## 角色卡版本与同步

- 每张卡 frontmatter 的 `version` / `updated` 是唯一事实；`.agents/roles.yaml` 只维护 aliases→id→card，不重复版本。
- 修改角色卡：bump `version`、更新 `updated`；PM 经 intercom 广播**短消息** `card <role> v<N+1>（摘要）`——不贴全文。
- worker 接任务前核对自身注入版本；发现 stale → 重读 `@.agents/prompts/<role>.md`（跨仓库会话用注入的环境锚点绝对路径）。
- `nao-fleet.sh check` 校验：manifest 可解析、frontmatter 与 manifest 一致、交叉引用文件存在。

## 输入信封（凡评审/派发前核对，缺项先索要）

- 主题/编号、范围与非范围
- NFR 基线（缺失必须反问）
- 约束清单（成本/团队/时间/合规）
- 目标里程碑
- 关联仓库路径（前后端分离时给双根）

## 输出信封

- 评审类：① 可行性结论（可行/有条件可行/不可行）② 风险清单（影响+应对）③ 技术取舍及理由 ④ **需 PM 拍板的决策点列表**
- 设计类：需求分析 → 架构模式 → 技术选型 → 分阶段里程碑
- 实现类：`回执模板`（见 output-format）

## 降级

- **前置判定**：先 `status`/`list` 确认 PM 是否可达；**PM 可达必须回执，不降级**；仅当 intercom 不可用或无法送达 PM 时才降级。
- intercom 不可用或未被调度：
  - PM → 直接输出 PRD/人工分派清单，**绝不亲自写码**。
  - 架构师 → 本会话直接输出完整评审报告，由用户转交 PM。
  - RD/测试 → 本会话正常执行，产出交用户转交。

## 归档约定

- PRD：`docs/prds/YYYY-MM-DD-<主题>.md`，索引 `docs/prds/README.md`。
- ADR：`docs/adr/YYYY-MM-DD-<主题>.md`，索引 `docs/adr/README.md`。
- 评审/测试报告：`docs/reports/<编号>-<主题>.md`（按需）。

## 跨会话反模式

- 粘贴 PRD/角色卡/输入信封全文。
- 无信封直接派发。
- 对未标角色的会话猜测前后端/测试身份。
- PM/RD/QA 越权改代码。
- `check` 非 0 仍强行派发。
- 在 tmux 内拉起前未评估宿主窗口被重排的影响。
- 派发后静默消失（无终态回执）。
- 改卡不 bump `version` / 不广播变更。
