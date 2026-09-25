# nao-todo `.agents/` 同步盘点（3-way inventory）

- 日期：2026-09-25 · 任务：T302 · 角色：rd-be
- 目标：在跑 `nao-skill update`（源优先覆盖）前，找出 nao-todo 相对上游的**本地独有改动**，避免把项目沉淀冲掉。
- 落盘位置说明：nao-skills 原无 `reports/` 目录，本单首次建立 `docs/reports/`（PM 指定路径亦为 `docs/reports/`）。

## 基线与方法

| 角色 | 来源 | 版本 |
| :--- | :--- | :--- |
| **base** | nao-skills tag `v0.7.1` → `.agents/` | 0.7.1（nao-todo `.nao-version` 记录的安装版本） |
| **cur** | nao-skills `main` @ `6caa25b` → `.agents/` | 0.8.0（T301 合并后） |
| **loc** | `nao-todo/.agents/` | 0.7.1 + 本地改动 |

方法：三方路径集合比对（`comm`，`LC_ALL=C`）+ 逐文件内容比对（`cmp`）+ 权限位比对（`stat`）。排除 `.nao-obsolete/`（本次为空）。

复现命令：

```bash
git -C /home/nathan/Project/nao-skills archive v0.7.1 .agents | tar -x -C /tmp/t302/base
diff -rq /home/nathan/Project/nao-todo/.agents /home/nathan/Project/nao-skills/.agents
```

## 结论摘要

- **本地独有改动仅 1 处**：`.agents/skills/test-design.md`（+9 行「反事实守卫」小节），即 PM 已核出的那处。
- **无本地删除**、**无本地新增资产**（仅 `.nao-version` 元数据）、**无权限位漂移**。
- 上游 v0.8.0 相对 v0.7.1 新增：`scripts/qq-notify`、`skills/qq-notify.md`；修改：`prompts/product-manager.md`、`scripts/nao-fleet.sh`。这些在 nao-todo 尚缺失 ⇒ 本单 `update` 的目标。

| 分类 | 数量 | 明细 |
| :--- | :--- | :--- |
| **(u) 应上游化** | 1 | `skills/test-design.md` → 「反事实守卫」小节 |
| **(d) 应丢弃** | 0 | — |
| **(p) 项目特有应保留** | 0 | — |

## 逐文件差异矩阵

| 文件 | loc vs base(0.7.1) | base vs cur(0.8.0) | loc vs cur | 分类 |
| :--- | :--- | :--- | :--- | :--- |
| `.nao-version` | 仅存在于 loc（安装元数据） | — | 版本号 0.7.1 vs 0.8.0 | 非资产（update 会重写） |
| `skills/test-design.md` | **DIFF（+9 行）** | 无变化 | DIFF | **(u)** |
| `prompts/product-manager.md` | 无变化 | DIFF（v18→v19，§十四） | DIFF（纯上游变化） | 随 update 收敛 |
| `scripts/nao-fleet.sh` | 无变化 | DIFF（qq-notify 校验） | DIFF（纯上游变化） | 随 update 收敛 |
| `scripts/qq-notify` | — | 新增 | 上游独有 | 随 update 引入 |
| `skills/qq-notify.md` | — | 新增 | 上游独有 | 随 update 引入 |
| 其余 29 文件 | 一致 | 一致 | 一致 | — |

## (u) 明细与原文证据

`nao-todo/.agents/skills/test-design.md` 在「用例设计方法」之后、`## DDD 分层对齐表` 之前插入一节（**保留原文措辞，上游化时不得重写**）：

```diff
@@ -12,6 +12,15 @@
 - **场景法**：主路径 + 异常 + 边界
 - **错误推测**：并发、超时、断网、重复提交、空值、超长输入
 
+## 反事实守卫（把静态推断升级为实测结论）
+
+当要验证的是「实现/契约的静态推断」而非现成行为时，用**两段式探针**，避免只在单侧证据上下结论：
+
+- **S1 实际链路**：用**真实现 + 真编排**（如真 repo + 真 SyncService）跑端到端；mock 只复现**外部系统**（服务端/网络）的**真源语义**——引源码行号，不复制逻辑；有源码仓时优先临时单测直调真源函数（如 Go converter），测后删除。
+- **S2 反事实分支**：独立断言「假设推断成立」时的后果。两段合读才能区分：**命题为假** / **命题为真** / **命题的前置在上游先行被阻断**（最常见误区：推断的上游前提不成立）。
+- **守卫化**：S2 保留为**反事实守卫**（当前绿）——修复后它应**转红**，届时改为**正向不变量**（如「往返后必须命中」）并在文件头注明；放 `__tests__/**`，红/绿分列说明。
+- **绑定版本**：结论显式绑定被测外部系统版本（commit）；版本一变结论可能翻转（如服务端对齐修法）。
+
 ## DDD 分层对齐表
```

判定为 **(u)** 依据：内容为**通用测试方法论**（静态推断的两段式探针、守卫化、绑定被测版本），与项目业务无关，可复用于任何接入舰队的仓；nao-todo 侧无业务特有名词（`SyncService` 仅为举例）。故应上游化而非保留为项目层资产。

## (p) 判定说明

本次**无** (p) 项。nao-todo`.agents/` 下不存在项目特有文件（如自定义角色卡、项目专属技能）；项目特有的约定落在 **nao-todo/AGENTS.md**（PM 维护，不属 `.agents/` 同步范围），例如 `AGENTS.md` 中已登记的 qq-notify 推送约定（nao-todo commit `d5069120`，仅改 `AGENTS.md`）。因此 update 不会触碰项目层约定。

## 处置顺序建议

1. **先上游化**（本单 ②）：把「反事实守卫」小节**原文**补进 nao-skills `.agents/skills/test-design.md`；版本 0.8.0 → **0.8.1（patch）**，理由：既有 skill 文档补充知识资产 + 新增盘点报告，无新增命令/分发文件、无角色卡语义与行为变化。
2. **再同步**（本单 ③，待上游 PR 合并）：`node <nao-skills>/bin/nao-skill.js update /home/nathan/Project/nao-todo`。
3. **验证**：`diff -rq` 仅剩合理差异（`.nao-version` 版本号）；「反事实守卫」节仍在；两侧 `nao-fleet.sh check` rc=0；nao-todo 守卫与受影响面 rc=0。
4. nao-todo 侧走 PR `chore/agents-sync-v0.8.1`，不直推 main。
