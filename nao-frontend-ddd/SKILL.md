---
name: "nao-frontend-ddd"
description: "Frontend Domain-Driven Design architecture guide based on Vue 3 + TypeScript + Pinia. Invoke when user wants to implement DDD, create new domains, or refactor project structure."
---

# Frontend DDD Architecture Skill (重构版)

## When Invoked

遵循以下决策工作流：

1. **评估项目规模**（代码行数、团队人数、功能数量、跨应用数量）。
2. **根据评估选择对应的 DDD 等级**（1级/2级/3级）。
3. **应用该等级对应的最小化结构**。
4. **提供该等级的代码模式**。
5. **当达到明确的量化指标时，建议升级**。

---

## 架构哲学：依赖倒置与端口-适配器

### 五层分层（自底向上）

| 层级               | 职责                                                                                | 示例目录                   | 关键规则                                                                |
| :----------------- | :---------------------------------------------------------------------------------- | :------------------------- | :---------------------------------------------------------------------- |
| **Infrastructure** | **防腐层实现**：HTTP Client、LocalStorage、IndexedDB、第三方 SDK                    | `packages/infrastructure/` | 实现 Domain 层定义的 **Repository 接口**                                |
| **Domain**         | **核心业务逻辑**：聚合根、实体、值对象、领域服务、**仓储接口（Ports）**             | `packages/domain/`         | **零外部依赖**（无 Vue、无 Axios、无 Pinia）                            |
| **Application**    | **用例编排**：实现业务工作流，协调 Domain 实体，**定义 UI 所需的状态接口（Ports）** | `packages/application/`    | 依赖 Domain，但**不依赖 UI 框架**；定义 `IPresenter` 或 `IStateGateway` |
| **Presentation**   | **UI 适配层**：Vue 组件、Pinia Store（实现状态端口）、Composables                   | `packages/presentation/`   | 依赖 Domain + Application；**实现** Application 定义的状态端口          |
| **Views**          | **页面组装层**：路由页面，仅组装 Presentation 组件，**不含业务逻辑**                | `apps/web/src/views/`      | 仅依赖 Presentation                                                     |

**依赖方向**：Views → Presentation → Application → Domain ← Infrastructure（依赖倒置，Domain 定义接口，Infrastructure 实现）

---

## Monorepo 结构 (Level 3+)

```text
project-root/
├── packages/
│   ├── core-utils/                      # 【纯 TS】通用工具（日期、防抖、类型工具），零前端框架依赖
│   │   └── src/
│   │       ├── date/
│   │       └── debounce/
│   │
│   ├── ui-kit/                          # 【Vue组件库】通用纯UI组件（Button, Input, Modal），无业务逻辑
│   │   └── src/
│   │       ├── components/
│   │       └── hooks/                   # 仅 UI 交互钩子（如 useClickOutside）
│   │
│   ├── domain/                          # 【纯 TS】领域层
│   │   ├── task/
│   │   │   ├── aggregates/              # 【新增】聚合根（TaskList）
│   │   │   ├── entities/                # 实体（Task, Comment）
│   │   │   ├── valueobjects/            # 值对象（TaskPriority, TaskStatus）
│   │   │   ├── repositories/            # 【端口接口】ITaskRepository
│   │   │   └── services/                # 纯业务领域服务
│   │   └── user/
│   │       └── ...
│   │
│   ├── application/                     # 【纯 TS】应用层
│   │   ├── task/
│   │   │   ├── usecases/                # TaskUseCase（编排逻辑）
│   │   │   ├── ports/                   # 【端口】ITaskStateGateway (由Presentation实现)
│   │   │   └── dtos/                    # 数据传输对象（原 viewobjects）
│   │   └── ...
│   │
│   ├── infrastructure/                  # 【TS + 外部依赖】基础设施层
│   │   ├── repositories/
│   │   │   ├── HttpTaskRepository.ts    # 实现 ITaskRepository（调用 Axios）
│   │   │   └── LocalTaskRepository.ts   # 实现 ITaskRepository（调用 LocalStorage）
│   │   └── http/
│   │       └── client.ts
│   │
│   └── presentation/                    # 【Vue/Pinia】表现层
│       ├── task/
│       │   ├── components/              # TaskCard, TaskEditor（依赖领域实体）
│       │   ├── store/
│       │   │   ├── useTaskStore.ts      # 【业务状态】管理 Task 聚合
│       │   │   └── useTaskUiStore.ts    # 【UI状态】管理 loading, filter, selectedId
│       │   └── composables/
│       │       └── useTask.ts           # 组装 UseCase + Repository，暴露给组件
│       └── ...
│
└── apps/
    ├── web/
    └── desktop/
```

---

## Level 1：轻量级 DDD（小型项目，<5k LOC）

### 适用场景

- 1-2 名开发者，5-10 个页面。
- 业务逻辑相对简单，但**仍需保障核心业务规则内聚**。

### 最小化结构（保留充血模型）

```text
src/
├── core/                                # 核心业务逻辑（零依赖 Vue）
│   ├── entities/                        # 【强制】实体类（充血模型）
│   │   └── Task.ts                      # 包含 isOverdue(), complete() 等方法
│   ├── value-objects/                   # 值对象（如 TaskStatus）
│   └── repositories/                    # 仓储接口（用于依赖倒置）
│       └── ITaskRepository.ts
│
├── infrastructure/                      # 基础设施实现（API调用）
│   └── HttpTaskRepository.ts            # 实现 ITaskRepository
│
├── composables/                         # Vue 组合式函数（业务组装 + UI状态）
│   ├── useTask.ts                       # 初始化 Repository，暴露 CRUD 方法
│   └── useTaskFilters.ts                # UI 筛选状态
│
├── components/                          # UI 组件（纯展示 + 调用 composable）
├── views/                               # 页面
└── main.ts
```

### 核心模式：充血实体类

**不要**直接使用 API 返回的 Plain Object。必须实例化 Entity 类。

```typescript
// core/entities/Task.ts
export class Task {
    constructor(
        public readonly id: string,
        public title: string,
        public done: boolean,
        public dueDate: Date,
    ) {}

    // 业务规则封装在实体内部
    public complete(): void {
        if (this.done) throw new Error("Task already completed");
        this.done = true;
    }

    public isOverdue(): boolean {
        return !this.done && this.dueDate < new Date();
    }
}
```

### 量化升级指标（Level 1 → 2）

- 单个 `core/entities` 文件超过 **300 行**。
- 存在 **3 个以上** 相互关联的实体（如 Task、List、Tag）。
- 出现跨实体的复杂业务校验（需要引入聚合根）。

---

## Level 2：基础 DDD（中型项目，5k-20k LOC）

### 适用场景

- 3-5 名开发者，10-30 个功能。
- 多个关联实体，存在明确的聚合根。

### 结构增强

```text
src/
├── domains/
│   └── task/
│       ├── aggregates/                  # 【新增】聚合根
│       │   └── TaskList.ts              # 管理 Task 实体，确保一致性
│       ├── entities/
│       │   └── Task.ts
│       ├── value-objects/
│       ├── repositories/
│       │   └── ITaskRepository.ts
│       └── services/                    # 跨聚合的业务服务
│
├── application/                         # 【新增】应用层
│   └── task/
│       ├── usecases/
│       │   └── TaskUseCase.ts
│       └── dtos/
│           └── TaskDTO.ts
│
├── infrastructure/
│   └── repositories/
│       └── HttpTaskRepository.ts
│
├── presentation/                        # 【新增】表现层（区分 UI 状态）
│   ├── task/
│   │   ├── components/
│   │   ├── store/
│   │   │   ├── useTaskStore.ts          # 业务状态（持有 TaskList 聚合）
│   │   │   └── useTaskUiStore.ts        # UI 状态（loading, keyword, selectedIds）
│   │   └── composables/
│   │       └── useTask.ts
└── ...
```

### 关键模式：聚合根（Aggregate Root）

外部只能通过聚合根操作内部实体，保证业务不变式（Invariants）。

```typescript
// domains/task/aggregates/TaskList.ts
import { Task } from "../entities/Task";

export class TaskList {
    private tasks: Task[] = [];

    constructor(tasks: Task[]) {
        this.tasks = tasks;
    }

    // 聚合根负责添加任务并触发领域事件（可选）
    public addTask(task: Task): void {
        if (this.tasks.some((t) => t.id === task.id)) {
            throw new Error("Duplicate task ID");
        }
        this.tasks.push(task);
    }

    public completeTask(id: string): void {
        const task = this.tasks.find((t) => t.id === id);
        if (!task) throw new Error("Task not found");
        task.complete(); // 委托给实体
    }

    public getOverdueTasks(): Task[] {
        return this.tasks.filter((t) => t.isOverdue());
    }
}
```

### 关键模式：UI 状态与业务状态分离

**禁止**在业务 Store 中混入 UI 状态。

```typescript
// store/useTaskStore.ts (业务)
export const useTaskStore = defineStore("task", () => {
    const taskList = ref<TaskList>(new TaskList([]));
    const add = (task: Task) => {
        taskList.value.addTask(task);
    };
    return { taskList, add };
});

// store/useTaskUiStore.ts (UI)
export const useTaskUiStore = defineStore("taskUi", () => {
    const isLoading = ref(false);
    const keyword = ref("");
    const selectedId = ref<string | null>(null);
    return { isLoading, keyword, selectedId };
});
```

### 量化升级指标（Level 2 → 3）

- 代码库超过 **20k LOC**。
- 领域数量超过 **3 个**（Task, User, Payment, etc.）。
- 出现跨域 Store 直接引入（`import ... from '../user/store'`）超过 **3 次**。
- 需要开发 **2 个以上** 独立应用（Web + Desktop + Mobile），需要 Monorepo。

---

## Level 3：完整 DDD + 端口-适配器（大型/企业项目）

### 适用场景

- 5+ 名开发者，多团队协同。
- 微前端或微服务后端架构，独立部署需求。
- 多应用（Web、Desktop、Mobile）共享核心逻辑。

### 核心原则：依赖倒置 (Dependency Inversion)

**Domain** 和 **Application** 层定义接口（Ports），**Infrastructure** 和 **Presentation** 层实现接口（Adapters）。

### 实现模式：在 Composable 中组装依赖

#### 1. 定义端口（Application/Ports）

应用层定义 UI 层需要实现的状态网关，**不包含任何 Vue/Pinia 类型**。

```typescript
// application/task/ports/ITaskStateGateway.ts
import type { TaskList } from "@nao-todo/domain/task";

export interface ITaskStateGateway {
    getState(): TaskList;
    updateState(list: TaskList): void;
}
```

#### 2. 实现用例（Application/UseCases）

用例接收端口，不直接依赖 Store。

```typescript
// application/task/usecases/TaskUseCase.ts
import type { ITaskRepository } from "@nao-todo/domain/task/repositories";
import type { ITaskStateGateway } from "../ports/ITaskStateGateway";

export class TaskUseCase {
    constructor(
        private repo: ITaskRepository,
        private gateway: ITaskStateGateway,
    ) {}

    async loadTasks() {
        const tasks = await this.repo.findAll();
        const list = new TaskList(tasks);
        this.gateway.updateState(list);
    }

    async completeTask(id: string) {
        const list = this.gateway.getState();
        list.completeTask(id); // 聚合根执行业务逻辑
        await this.repo.save(list.getTasks());
        this.gateway.updateState(list);
    }
}
```

#### 3. 实现适配器（Presentation/Store）

Pinia Store 实现应用层定义的网关接口。

```typescript
// presentation/task/store/useTaskStore.ts
import type { ITaskStateGateway } from "@nao-todo/application/task/ports";

export const useTaskStore = defineStore("task", () => {
    const taskList = ref<TaskList>(new TaskList([]));

    // 实现 ITaskStateGateway 接口
    const gateway: ITaskStateGateway = {
        getState: () => taskList.value,
        updateState: (list) => {
            taskList.value = list;
        },
    };

    return { taskList, gateway };
});
```

#### 4. 组装层（Presentation/Composables）

在 Composable 中实例化 UseCase，注入具体的 Repository（Infrastructure）和 Gateway（Store）。

```typescript
// presentation/task/composables/useTask.ts
import { HttpTaskRepository } from "@nao-todo/infrastructure/repositories";
import { TaskUseCase } from "@nao-todo/application/task/usecases";
import { useTaskStore } from "../store/useTaskStore";

export function useTask() {
    const store = useTaskStore();

    // 依赖注入组装点
    const useCase = new TaskUseCase(
        new HttpTaskRepository(), // Infrastructure 实现
        store.gateway, // Presentation 实现
    );

    const load = async () => {
        await useCase.loadTasks();
    };
    const complete = async (id: string) => {
        await useCase.completeTask(id);
    };

    return {
        tasks: store.taskList,
        load,
        complete,
    };
}
```

---

## 组件归属决策表

| 条件                                           | 归属位置                                     |
| :--------------------------------------------- | :------------------------------------------- |
| 组件**依赖**领域实体（Task, User）或业务 Store | `packages/presentation/<domain>/components/` |
| 组件**无业务含义**（Button, Input, Card）      | `packages/ui-kit/`                           |
| 组件被 **≥2 个领域** 复用且无业务逻辑          | `packages/ui-kit/`                           |
| 纯 TS 工具函数（日期、数学、类型体操）         | `packages/core-utils/`                       |

---

## 迁移路径

### Level 1 → Level 2

1. 识别聚合根（如 `TaskList`），将 `entities/` 中的逻辑上提到 `aggregates/`。
2. 将 API 调用从 Composable 剥离，下沉至 `infrastructure/repositories/`。
3. 引入 `application/usecases/`，将 Composable 中的业务编排逻辑移入 UseCase。
4. 拆分 Store：业务逻辑保留，UI 状态（Loading、Filter）移至新 Store 或局部 ref。

### Level 2 → Level 3

1. 创建 `packages/` 目录，配置 pnpm workspace。
2. 将 `domains/` 迁移至 `packages/domain/`，确保零前端依赖。
3. 将 `application/` 迁移至 `packages/application/`，定义 Ports 接口。
4. 将 `infrastructure/` 迁移至 `packages/infrastructure/`。
5. 将 `presentation/` 迁移至 `packages/presentation/`，实现 Ports 接口。
6. 拆分 `shared/` 为 `core-utils` (纯TS) 和 `ui-kit` (Vue组件)。

---

## 禁止事项（红线）

- ❌ **禁止**在 Domain 层导入 Vue、Pinia、Axios 等框架库。
- ❌ **禁止**在 Application 层导入 Vue 或 Pinia（只能导入纯 TS）。
- ❌ **禁止**组件直接调用 `axios` 或 `localStorage`（必须通过 Repository 接口）。
- ❌ **禁止**在 Page 组件中写 `if/else` 业务逻辑（Page 只做组装）。
- ❌ **禁止**将 UI 状态（Loading, ModalVisible）放入业务 Store。
- ❌ **禁止**跨域直接导入 Store（`from '../user/store'`），应通过 Application 层协调。

---

## 架构审查清单 (Code Review)

- [ ] Domain 层是否零依赖（`package.json` 无 Vue/Pinia/Axios）？
- [ ] 实体是否为**充血模型**（包含业务方法，而非贫血 getter/setter）？
- [ ] 聚合根是否保证了业务不变式（如不能重复添加 ID）？
- [ ] Application 层的 UseCase 是否只依赖 Ports（接口），而非具体实现？
- [ ] Infrastructure 层是否实现了 Domain 定义的 Repository 接口？
- [ ] Store 是否拆分为了业务状态（`useXxxStore`）和 UI 状态（`useXxxUiStore`）？
- [ ] Composable 是否是依赖注入的组装工厂（`new UseCase(new Repo(), store.gateway)`）？
- [ ] `ui-kit` 是否仅包含纯展示组件，不包含 `import { useTaskStore }`？

---

## 常见问题 (FAQ)

**Q1：如果我只有 5 个页面，真的需要实体类吗？**
A：**需要**。哪怕只有 1 个实体，将 `isOverdue()` 逻辑封装在 `Task` 类中，也比散落在组件中好得多。这不会增加复杂度，反而提升了可测试性。

**Q2：Pinia Store 和 Aggregate Root 职责如何区分？**
A：**Aggregate Root** 是纯 TypeScript 逻辑，负责业务规则（如 `completeTask` 校验）。**Pinia Store** 是 Vue 的响应式容器，负责持有 Aggregate Root 实例并驱动 UI 更新。业务规则必须写在 Aggregate 里，Store 只做转发。

**Q3：如果不使用 Monorepo（Level 3），如何实现依赖倒置？**
A：在 Level 2 中，可以简化为在 `domains/task/repositories/` 定义接口，在 `infrastructure/` 中实现，并在 `composables/` 中手动 `new HttpTaskRepository()` 传入。无需 Monorepo 也能实践端口-适配器模式。

**Q4：如何处理跨域通信（Task 完成后通知 User）？**
A：在 **Application 层**的 UseCase 中协调，**严禁**在 Presentation 层跨域导入 Store。例如，`TaskUseCase` 可以接收 `ITaskCompleteNotifier` 端口，由 `User` 领域实现通知逻辑，或通过全局事件总线（`mitt`）解耦。
