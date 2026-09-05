# Devlog 2026-09-05 —— 个人极简 Todo：产品经理 → 前端 → 测试 多会话协作交付

> 一条完整需求从澄清到验收终签的全流程记录：**grill-me 澄清 → 5 Whys → PRD → 多会话委托开发 → 第三方独立测试 → 缺陷修补闭环 → 终签归档**。
> 交付物：`/home/nathan/Project/nao-todo-minimal`（独立 git 仓库，与本 skills 仓库隔离）。

---

## 0. 场景与角色

| 角色会话 | 职责 | 最终状态 |
| :--- | :--- | :--- |
| `naoskill-product-manager`（本会话） | 需求澄清、PRD、委托编排、缺陷裁决、终签 | 闭环 |
| `naoskill-frontend-developer` | 落地方案 + L1 DDD 实现 + 自验 | ✅ 交付 `c12c5d8` + `5001390` |
| `naoskill-test-engineer` | 第三方独立测试 + 回归复测 | ✅ 归档 `/tmp/nao-todo-e2e/` |

---

## 1. 需求阶段

### 1.1 grill-me 逐层澄清（一次一问，模糊输入禁止臆测）

原始需求仅一句「做一个简单的 Todo 应用」→ 按 PM 角色约束触发澄清，5 问结论：

| # | 澄清项 | 结论 |
| :--- | :--- | :--- |
| ① | 目标用户 | 个人自己，无账号体系 |
| ② | 使用场景 | 电脑浏览器（桌面端），无移动端需求 |
| ③ | 核心流程 | 最简生命周期：新建 → 标记完成 → 删除 |
| ③' | 数据持久化 | 需要长期保存（localStorage） |
| ④ | 边界/异常 | 删除带「撤销」按钮即可，不做回收站 |
| ⑤ | 成功标准 | **工程质量**：按前端 DDD 规范、可单测可演进；本地运行，不部署 |

### 1.2 5 Whys 深层需求

表面诉求「做 Todo」→ 深层需求：**打开即记、极简专注、数据归己**的个人任务收件箱，兼作前端 DDD 工程样板。
可验证假设：满足「零打扰、5 秒内记录、数据本地留存」时用户会持续使用。

### 1.3 PRD v0.1 要点（9 模块表格化）

- **功能范围（做）**：新建、完成/取消完成切换、删除 + 单级撤销（5s 窗口）、localStorage 持久化、空态、DDD L1 分层 + 领域单测
- **范围（不做）**：账号、标题编辑、分类/清单、搜索、截止日/提醒、优先级、子任务、重复任务、移动端/多端、回收站、多人、后端/云、主题
- **业务规则**：标题 trim 非空 ≤200 字符、允许重复；`pending ⇄ completed` 双向切换；删除=软删（置 `deletedAt`）UI 隐藏；撤销仅单级、5s 窗口、恢复原状态（含已完成态）；刷新清理 `deletedAt`（撤销不跨刷新=无回收站语义）
- **NFRs**：<1k 条规模；千条级无感知；损坏兜底（JSON 解析失败→备份 `.bak` 键→重置+提示）；渲染转义禁 `innerHTML`
- **架构对齐**：预估 <2k LOC → `nao-frontend-ddd` **L1 轻量框架**
- 用户评审：**通过**

---

## 2. 委托落地（frontend-developer）

### 2.1 关键决策与风险规避

- **目录冲突拦截**：委托初定路径 `/home/nathan/Project/nao-todo` 已存在 = **现网已部署的 NaoTodo monorepo**（apps/web+desktop+mobile、todo.nathanap.space）→ 前端主动拦截，绝不写入；裁决新建 **`/home/nathan/Project/nao-todo-minimal`**（独立 git、不部署）
- **框架选型**：Vite 8 + Vue 3.5 + TS strict + Pinia 4（无 router、无 UI 库，手写极简样式）
- **L1 结构**：`src/domain`（零框架 Task 充血实体 + DomainError + `ITaskRepository` 端口）→ `src/infrastructure`（Mapper + LocalStorage 仓储）→ `src/stores` → `src/composables/use-todo.ts`（DI 唯一入口）→ `src/views` + 纯展示组件

### 2.2 交付

- **commit `c12c5d8`**（主体）
- 自验：Vitest 51/51（domain 13 / infra 15 / store 13 / TodoView 10）+ vue-tsc + build + dev 冒烟 200
- 红线自检：domain 零框架、无 `v-html`/`innerHTML`、`new 仓储` 仅 composable、视图无业务分支

### 2.3 实现中技术决策（记录备查）

1. **Pinia UnwrapRef 扁平化** → 仓储写路径收结构化 `TaskState`（领域已有类型），测试核验无静默类型丢失、运行时实体能力完整
2. **撤销槽 = 软删行保留（内存+LS）+ load 时 purge**（非"立即删除+快照"），严格对齐 PRD 刷新语义

---

## 3. 第三方独立测试（test-engineer）

### 3.1 首轮测试结论

- **通过验收**；AC 7 项浏览器实走全满足；无阻塞/严重级缺陷
- 覆盖：Vitest 复跑 51/51 ✓｜vue-tsc/build/dev ✓｜**真实浏览器手工验收 49/49**（dev + dist 双面）｜边界/异常 9/9｜红线静态复核全过
- NFR 实测：损坏兜底 PASS、XSS 载荷零执行 PASS、千条级加载 ~500ms/勾选 ~62ms PASS
- 范围外扫描：无越界功能、无外部网络请求、依赖仅 vue+pinia
- 技术决策专项核验：①② 均与 PRD 语义一致，未引入缺陷

### 3.2 缺陷与处置

| 缺陷 | 级别 | 描述 | 裁决 |
| :--- | :--- | :--- | :--- |
| **TODO-TEST-001** | P3 | localStorage 写失败（配额满/被禁）时提示失败但任务残留列表、刷新即失（内存/磁盘分叉，幽灵任务） | **A 打回修补**（工单 FIX-001） |

---

## 4. 修补闭环（FIX-001）

### 4.1 修复方案

写命令统一改为 **「变更前全量快照（含撤销槽）→ Store 领域变更 → 落盘 → 失败则 `restoreSnapshot` 回滚内存态并上抛 `StorageWriteError`」** —— 落盘成功内存态才生效，从根上杜绝幽灵任务；撤销槽进行中状态随回滚复原，语义与成功路径一致。

- commit `5001390`；新增 composable 层测试；全量 **65/65**（原 51 零回归 + 新增 14）
- 变更：domain `errors.ts` 增 `StorageWriteError`｜infra `saveAll` 抛错包装、load 清洗写回失败静默重试｜store 深拷贝快照 + `snapshotAll`/`restoreSnapshot`｜composable 四写路径统一 `persistOrRollback`｜TodoView 新增可关闭「保存失败」错误条

### 4.2 回归复测结论

- **主目标闭环**：添加失败无幽灵 ✓｜删除失败回滚+无撤销槽残留+恢复后可重删 ✓｜撤销失败槽复原 ✓｜连删 A,B 单级语义不污染 ✓｜双提示通道互不干扰 ✓
- 全量零回归：dev+dist 浏览器 49/49 持平基线、边界 8/8、损坏兜底/XSS/性能/范围外扫描全过
- 范围外干净：package.json / pnpm-lock 零变更

### 4.3 复测发现新缺陷（二次裁决）

| 缺陷 | 级别 | 描述 | 裁决 |
| :--- | :--- | :--- | :--- |
| **FIX-001-REG-01** | P3 | 勾选失败回滚后**复选框视觉与模型分叉**（无划线但勾选态滞留 / 有划线但未勾选）；二次点击/刷新自愈，无数据丢失；根因为 Vue 同 key 列表替换时 `:checked` 未回写 | **B 记录接受**（Known Issue，极端触发场景，不修补随版归档） |

---

## 5. 终签与归档

- **终签结论**：✅ 通过 —— PRD v0.1 功能/规则/NFR/AC 全部满足；无阻塞/严重级缺陷；数据一致性目标达成；零功能回归
- **覆盖终稿**：Vitest 65/65 ｜ dev+dist 浏览器各 49/49 ｜ FIX-001 定向回归 26/27（1 项→Known Issue）｜边界 8/8 ｜ AC 7/7 实走
- **遗留项（全非阻塞）**：REG-01 视觉分叉（自愈）｜多标签并发写最后覆盖（多端范围外）｜重复 id 不去重（理论可达）｜深度休眠 toast 滞后（墙钟校验兜底）｜千条性能单点采样
- **归档**：`/tmp/nao-todo-e2e/FINAL-ACCEPTANCE-ARCHIVE.md`（+ defects.md + evidence/*.png 截图）

---

## 6. 资产清单

| 资产 | 位置 |
| :--- | :--- |
| 交付仓库（2 commits） | `/home/nathan/Project/nao-todo-minimal` |
| 测试报告与缺陷单 | `/tmp/nao-todo-e2e/test-report.md`、`defects.md` |
| 证据截图（9 张） | `/tmp/nao-todo-e2e/evidence/*.png` |
| 最终验收归档 | `/tmp/nao-todo-e2e/FINAL-ACCEPTANCE-ARCHIVE.md` |

---

## 7. 复盘要点

1. **模糊需求先澄清再产出**：一次一问的 grill-me 把"简单 Todo"收敛为可验收的五要素，杜绝需求蔓延
2. **委托前置风险排查有效**：目录冲突（现网 nao-todo）在开工前被拦截，避免污染生产仓库——委托信息必须含明确目录约束
3. **第三方独立测试价值显著**：自验 51/51 全绿 ≠ 无缺陷——浏览器实走 + 异常注入才暴露 TODO-TEST-001 幽灵任务与 REG-01 视觉分叉
4. **缺陷治理闭环**：P0–P2 必须修；P3 按「数据一致性影响 / 触发概率 / 自愈性」裁决 A 打回或 B 记录接受，全部随版归档可追溯
5. **技术决策留痕**：实现中的框架行为决策（UnwrapRef、Vue `:checked` 回写）记录在案，供复测定向核验与后续排期参考
