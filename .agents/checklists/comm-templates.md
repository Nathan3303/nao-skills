---
description: 派发消息与回执模板（按需，派发/回执前读取）
---

# 派发消息与回执模板（按需）

> 按需读取：**派发前**（PM）、**回执前**（worker / 评审角色）。
> 硬性红线常驻在 @.agents/common/output-format.md「回执硬性」；本文件只给可直接复制的形态。

## 派发消息（PM → worker）

```text
[编号/主题] | to=<会话> | role=<角色> | repo=<路径>
范围：做 X；不做 Y
引用：docs/...md#section（禁止贴全文）
交付：<产物类型>；长文落盘路径
回执级别：lite（默认）| full
摘要：≤150字
阻塞/决策点：<无 或 列出>
```

## 回执 done(lite)：默认（无阻塞、无风险的常规任务，单行）

```text
[编号] done(lite) | <role> | 清单：未过<项 或 无> | 测试：HEAD=<跑门禁时短 sha> · 工作区=<静默|非静默(原因)> · <命令> exit=<n> <文件数>/<例数>/<红数>（每个计数数字后跟「命令 → 输出」） | 变更：<f1,f2（>3 个写前 3 + "等 N 个"）> | 遗留：<无 | n 项 → 台账|tasks-state|Issue|接受(到期)> | commit=<交付提交短 hash，≠ 门禁 HEAD；无则 —> | 详情：docs/reports/<编号>.md
```

> `commit=`（仅 git 流程任务）：work 分支最新提交短 hash，便于 PM 核对归因（commit.md 约定）；无 push/纯文档任务写 `commit=—`。
> `遗留：` 取值枚举 `无 | <n> 项 → <台账|tasks-state|Issue|接受(到期)>`；零遗留写 `无`，禁省略字段（三出口定义见 @.agents/skills/task-completion.md §四）。
> **`测试：` 段三件套（静默工作区 / HEAD sha / 命令 + 输出）口径单源见 @.agents/common/output-format.md「回执硬性」第 3 条** —— 本文件只给可复制形态，**不复写三件套全文**（PM / QA / RD 三侧同源）。
> **`HEAD=` ≠ `commit=`**：前者 = **跑门禁时**的 HEAD（数字的归属），后者 = **交付提交**（归因）；门禁后又补提交时两者必然不同 —— 混用即「同一命令两种结论」的根源。

## 回执 done(full)：出现阻塞/风险/需决策，或 PM 指定

```text
[编号] done(full) | <role>
摘要：≤150字
清单：已核对 checklists/<role>.md；未过：<项 或 无>
变更：<文件/模块级>
测试：HEAD=<跑门禁时短 sha> · 工作区=<静默（`git status --porcelain` 空 + 本会话独占 worktree）| 非静默(原因)> · <命令> exit=<n> · <文件数>/<例数>/<红数>（每个计数数字后跟「命令 → 输出」）
commit：<交付提交短 hash（**≠ 门禁 HEAD**；本分支最新交付提交）或 —>
遗留：<无 | n 项 → 台账|tasks-state|Issue|接受(到期)>（每条附出处与 owner；接受类必须带到期日）
风险/阻塞：<无 或 列出>
详情：<路径>
```
