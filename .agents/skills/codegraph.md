---
description: 按需技能——CodeGraph 代码定位（三段阶梯：原生入口 → CLI → grep + 行段）
---

# CodeGraph 代码定位（三段阶梯）

> 目标不变：图谱精确命中符号/调用链/影响面，**替代「grep 全文 + cat 大文件」**——上下文只进相关代码块。
> 口径按阶梯降级：**① 原生入口 → ② CLI → ③ `grep -rn` + 行段**。任一步不可用即顺延，**不需审批**；
> 「**禁 cat 全文**」永久有效。

## ① 原生入口（首选）

- 唯一硬编码工具名 = **`codegraph_explore`**（上游默认只暴露它；其余工具名**不写死** —— 是否出现随
  CLI 版本 / `CODEGRAPH_MCP_TOOLS` 变化，需用时先看会话工具列表）。
- 一次调用拿「相关符号源码 + 调用路径」，等价于 `codegraph explore`。
- 生效前提（三者齐备）：插件已声明 + CLI 在 PATH + 当前仓有 `.codegraph/` 索引。
  **有插件无索引 / 无 CLI ⇒ 不生效**（插件激活条件 = cwd 存在 `.codegraph/`，否则静默 no-op）。
- **插件不供 system prompt 指引（截至 pi 1.4.0 / pi-codegraph 0.1.0）** —— 舰队恒带
  `--append-system-prompt`，该开关抑制插件的指引注入 ⇒ 口径由**本技能**承载（不要期待自动注入）。

## ② CLI（原生入口不可用时的回退）

真实命令（`codegraph 1.6.2` 实测；**上游 README 与本机 CLI 冲突时以实测为准**）：

- `codegraph status` — 索引健康（无索引 → `codegraph init`；有改动 → `codegraph sync`）
- `codegraph status --json` — 同上（机器读；`pendingChanges` / `index.state`）
- `codegraph explore "<查询>"` — 相关符号源码 + 调用路径（= 原生入口同款输出）
- `codegraph query "<符号>"` — 精确定位符号
- `codegraph context "<任务描述>"` — 任务上下文：相关符号 + 关系 + 代码块
- `codegraph node <符号>` — 符号源码 + caller/callee 调用链
- `codegraph node --file <f> --offset <n> --limit <m>` — 读文件行段（带行号）
- `codegraph callers <符号>` / `codegraph callees <符号>` — 调用追踪
- `codegraph impact <符号>` — 改动影响分析（**改前必跑**）
- `codegraph affected <文件...>` — 受影响的测试文件
- `codegraph files` — 项目文件结构
- `codegraph init` — 首次建索引（**不带 `-i`**：该 flag 已废弃，仅向后兼容）
- `codegraph sync` — 增量同步（写完代码提交前跑一次）

## ③ `grep -rn` + 行段（保底，永不过期）

- `grep -rn "<关键词>" --include=<扩展名> <目录>` 定位，再 `sed -n '<起>,<止>p' <文件>` 读**精确行段**；
  **禁止 cat 全文**。
- 非代码内容（配置/字符串/日志/文档）直接 grep，不绕道。
- 查询无结果先换关键词再试一次，仍无 ⇒ 回退（写明原因即可，不需要审批）。

## Token 纪律（省的是上下文累积）

- 一次 `explore` / `context` 拿全，不再 grep + cat 同一段代码；拿到的代码块不重复读取。
- 输出过大用 `-n <num>` 限符号数；只看结构用 `--no-code`。
- 大任务拆成多个子问题分别查，不做一次超大查询。

## 索引维护（项目级）

- 索引是**项目级**的：在对应 repo 目录跑（舰队会话 cwd 即 repo）；跨仓用 `-p <路径>`。
- 首次进新仓：`codegraph status` → 无索引则 `codegraph init`（一次性，之后只 `sync`）。
- 索引未同步（`codegraph status` 报 `Pending Changes:`）不影响本技能可用性，提交前 `codegraph sync`。
- `check` 的 codegraph 行**全是提示，永不进退出码**：`-v` 才看索引新鲜度（默认只报是否齐备）。

## 副产物与 daemon（已知边界，机制不代跑）

- 插件在项目根创建 `.pi/APPEND_SYSTEM.md`，正常会话退出时删除；但**任何加载扩展的非会话 `pi` 调用**
  （`pi list` / `pi install` / `pi --help -e`）也会写它且不触发清理 ⇒ 残留。本仓 `.gitignore` 已覆盖该单文件；
  需要清理时**用户手工** `rm -f .pi/APPEND_SYSTEM.md`（nao 不写、不删 —— 无法区分用户自建）。
- 已建索引的仓内，非会话 `pi` 动作可能留下 1 棵孤儿 `codegraph` daemon（约 177MB RSS）。规避：
  `( cd /tmp && pi list )` 在**非索引 cwd** 执行（实测 0 副作用）；已泄漏则 `codegraph daemons`（交互选停）
  或 `kill <pid>`。nao 侧**不杀 daemon**（daemon argv 不含仓库身份 ⇒ `pkill` 会跨仓误杀）。
