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
[编号] done(lite) | <role> | 清单：未过<项 或 无> | 测试：<命令> exit=<n> <文件数>/<例数>/<红数> | 变更：<f1,f2（>3 个写前 3 + "等 N 个"）> | 遗留：<无 | n 项 → 台账|tasks-state|Issue|接受(到期)> | commit=<短 hash 或 —> | 详情：docs/reports/<编号>.md
```

> `commit=`（仅 git 流程任务）：work 分支最新提交短 hash，便于 PM 核对归因（commit.md 约定）；无 push/纯文档任务写 `commit=—`。
> `遗留：` 取值枚举 `无 | <n> 项 → <台账|tasks-state|Issue|接受(到期)>`；零遗留写 `无`，禁省略字段（三出口定义见 @.agents/skills/task-completion.md §四）。

## 回执 done(full)：出现阻塞/风险/需决策，或 PM 指定

```text
[编号] done(full) | <role>
摘要：≤150字
清单：已核对 checklists/<role>.md；未过：<项 或 无>
变更：<文件/模块级>
测试：<命令 + exit code + 文件数/例数/红数（或错误数）>
commit：<短 hash 或 —>
遗留：<无 | n 项 → 台账|tasks-state|Issue|接受(到期)>（每条附出处与 owner；接受类必须带到期日）
风险/阻塞：<无 或 列出>
详情：<路径>
```
