---
name: "backend-ddd"
description: "Backend Domain-Driven Design architecture guide based on NestJS / Spring Boot. Invoke when user wants to implement DDD, create new domains, or refactor project structure."
---

# Backend DDD Architecture Skill (NestJS / Spring Boot 通用)

## When Invoked

遵循以下决策工作流：

1. **评估系统规模**（预期 QPS、团队人数、业务领域数量、是否需分布式）。
2. **选择对应的 DDD 等级**（1级单体 / 2级模块化单体 / 3级微服务）。
3. **应用该等级对应的最小化结构**。
4. **提供代码模式**（聚合、仓储、应用服务、领域事件）。
5. **当达到明确的量化指标时，建议升级**。

---

## 架构哲学：领域隔离与依赖倒置

### 四层经典分层（自外向内）

| 层级               | 职责                                                                                                           | 示例目录 (NestJS)                                               | 示例目录 (Java)                                                     | 关键规则                                                                       |
| :----------------- | :------------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------- | :------------------------------------------------------------------ | :----------------------------------------------------------------------------- |
| **Interface**      | **输入适配器**：REST/GraphQL Controllers, gRPC Servers, 消息队列消费者 (Kafka/RabbitMQ)                        | `src/interfaces/controllers/`, `src/interfaces/consumers/`      | `com.xxx.interfaces.controller`, `com.xxx.interfaces.listener`      | **不包含业务逻辑**，只做参数校验（DTO）、格式转换、权限过滤                    |
| **Application**    | **用例编排**：事务管理、跨聚合协调、发布领域事件、调用外部 RPC                                                 | `src/application/services/`, `src/application/commands/`        | `com.xxx.application.service`, `com.xxx.application.command`        | **不包含业务规则**；业务规则在 Domain 层；使用 `@Transactional()` 管理事务边界 |
| **Domain**         | **核心业务逻辑**：聚合根（Aggregate）、实体（Entity）、值对象（Value Object）、领域服务、**仓储接口（Ports）** | `src/domain/aggregates/`, `src/domain/repositories/`            | `com.xxx.domain.aggregate`, `com.xxx.domain.repository`             | **零外部依赖**（无数据库 ORM、无 HTTP 客户端）；只依赖 JDK/Node.js 原生库      |
| **Infrastructure** | **输出适配器**：数据库（ORM/ODM）实现、Redis 缓存、第三方 API 客户端、消息队列发送器                           | `src/infrastructure/repositories/`, `src/infrastructure/cache/` | `com.xxx.infrastructure.repository`, `com.xxx.infrastructure.cache` | **实现 Domain 层定义的仓储接口**，处理具体技术细节（SQL、Redis 命令）          |

**依赖方向**：Interface → Application → Domain ← Infrastructure（依赖倒置）

> **核心铁律**：Domain 层定义接口（`ITaskRepository`），Infrastructure 层实现（`TaskRepositoryImpl`）。高层模块（Application）依赖抽象（Domain 接口），不依赖具体实现（Infrastructure）。

---

## 项目结构 (Level 3 完整版)

```text
project-root/
├── apps/                                    # 【应用入口】
│   ├── api/                                 # REST API 服务
│   │   ├── src/
│   │   │   ├── interfaces/                  # 控制器、守卫、拦截器
│   │   │   ├── main.ts
│   │   │   └── app.module.ts
│   ├── consumer/                            # 消息队列消费者（独立部署）
│   │   └── src/
│   │       └── interfaces/consumers/
│   └── scheduler/                           # 定时任务（独立部署）
│
├── libs/                                    # 【共享库 Monorepo】
│   ├── core-utils/                          # 纯 TS 工具（加密、日期、UUID）
│   │
│   ├── domain/                              # 【领域层】
│   │   ├── order/                           # 订单上下文
│   │   │   ├── aggregates/                  # Order 聚合根
│   │   │   ├── entities/                    # OrderItem 实体
│   │   │   ├── value-objects/               # Money, Address
│   │   │   ├── repositories/                # IOrderRepository 接口
│   │   │   ├── services/                    # IOrderDiscountDomainService
│   │   │   └── events/                      # OrderCreatedEvent, OrderPaidEvent
│   │   └── payment/                         # 支付上下文
│   │
│   ├── application/                         # 【应用层】
│   │   ├── order/
│   │   │   ├── commands/                    # CreateOrderCommand, PayOrderCommand
│   │   │   ├── handlers/                    # CreateOrderHandler (实现 CQRS)
│   │   │   ├── services/                    # OrderApplicationService (门面)
│   │   │   ├── dtos/                        # CreateOrderRequest, OrderResponse
│   │   │   └── ports/                       # 【出站端口】IOrderEventPublisher, IInventoryRpcClient
│   │   └── ...
│   │
│   ├── infrastructure/                      # 【基础设施层】
│   │   ├── persistence/                     # 数据库实现
│   │   │   ├── entities/                    # TypeORM / Prisma 表实体
│   │   │   ├── mappers/                     # 数据库实体 <-> 领域实体 转换器
│   │   │   └── repositories/                # OrderRepositoryImpl (实现 IOrderRepository)
│   │   ├── messaging/                       # 消息队列
│   │   │   ├── publishers/                  # OrderEventPublisher (实现 IOrderEventPublisher)
│   │   │   └── consumers/
│   │   └── clients/                         # RPC / HTTP 客户端
│   │       └── InventoryRpcClient (实现 IInventoryRpcClient)
│   └── ...
```

---

## Level 1：轻量级 DDD（小型单体，< 5k LOC / 简单 CRUD）

### 适用场景

- 简单管理系统，业务逻辑不复杂，但**必须保有核心业务规则**。
- 团队规模小，预期未来不会拆分为微服务。

### 最小化结构（贫血模型 → 充血模型过渡）

```text
src/
├── domain/
│   ├── task/
│   │   ├── Task.entity.ts          # 充血实体：包含 complete(), isOverdue()
│   │   ├── TaskStatus.enum.ts
│   │   └── ITaskRepository.ts      # 仓储接口
├── infrastructure/
│   └── TaskRepositoryImpl.ts       # 简单实现（TypeORM 或 Prisma）
├── application/
│   └── TaskService.ts              # 应用服务，编排逻辑，管理事务
├── interfaces/
│   └── TaskController.ts           # REST 端点
└── main.ts
```

### 核心模式：充血实体 + 简单注入

**严禁**在 Service 中编写 `if (task.dueDate < now)`，必须在 `Task.complete()` 中封装。

```typescript
// domain/task/Task.entity.ts (NestJS 示例)
export class Task {
    constructor(
        public readonly id: string,
        public title: string,
        public status: TaskStatus,
        public dueDate: Date,
    ) {}

    // 【领域业务规则】
    public complete(): void {
        if (this.status === TaskStatus.DONE) {
            throw new DomainError("Task already completed");
        }
        if (this.dueDate < new Date() && this.status !== TaskStatus.DONE) {
            throw new DomainError(
                "Cannot complete overdue task without review",
            );
        }
        this.status = TaskStatus.DONE;
    }
}
```

### 量化升级指标（Level 1 → 2）

- 单个领域实体关联的子实体超过 **3 个**（如 Order 关联 OrderItems, Shipments）。
- 跨实体的业务规则不再适合放在单个实体中（需要引入**聚合根**）。
- 团队人数超过 **3 人**，代码合并冲突频繁。

---

## Level 2：标准 DDD（模块化单体，5k-20k LOC）

### 适用场景

- 中大型项目，具有明显的 **限界上下文（Bounded Context）**（订单、用户、库存）。
- 采用模块化单体架构，便于未来拆分为微服务。

### 关键模式：聚合根（Aggregate Root）与事务边界

**聚合根是事务一致性边界**。修改 Order 及其 OrderItems 必须在 **同一个数据库事务** 中完成。

```typescript
// domain/order/aggregates/Order.aggregate.ts
import { OrderItem } from "../entities/OrderItem.entity";
import { Money } from "../value-objects/Money.value-object";

export class Order {
    private items: OrderItem[] = [];

    constructor(
        public readonly id: string,
        public userId: string,
        public status: OrderStatus,
    ) {}

    // 聚合根负责添加子实体，并保证业务不变量（如总金额不能为负）
    public addItem(productId: string, price: Money, quantity: number): void {
        if (this.status !== OrderStatus.PENDING) {
            throw new DomainError("Cannot add items to non-pending order");
        }
        const item = new OrderItem(productId, price, quantity);
        this.items.push(item);
    }

    // 计算总金额（遍历子实体）
    public getTotal(): Money {
        return this.items.reduce(
            (sum, item) => sum.add(item.getSubtotal()),
            Money.ZERO,
        );
    }
}
```

### 关键模式：应用服务（Application Service）管理事务

应用服务负责：

1. 通过 **仓储** 获取聚合根。
2. 调用聚合根的业务方法。
3. 通过 **仓储** 保存聚合根。
4. 发布领域事件。

```typescript
// application/order/services/OrderApplicationService.ts
@Injectable()
export class OrderApplicationService {
    constructor(
        private orderRepo: IOrderRepository, // 依赖接口（由 Infrastructure 注入）
        private eventPublisher: IEventPublisher, // 依赖接口
    ) {}

    @Transactional() // NestJS / Spring 事务注解
    async addItemToOrder(
        orderId: string,
        productId: string,
        price: number,
        qty: number,
    ): Promise<void> {
        // 1. 获取聚合
        const order = await this.orderRepo.findById(orderId);
        if (!order) throw new NotFoundError("Order not found");

        // 2. 执行业务逻辑（聚合根内部校验）
        order.addItem(productId, new Money(price), qty);

        // 3. 保存（事务提交）
        await this.orderRepo.save(order);

        // 4. 发布事件（事务提交后，确保最终一致性）
        await this.eventPublisher.publish(
            new OrderItemAddedEvent(order.id, productId),
        );
    }
}
```

### 量化升级指标（Level 2 → 3）

- 模块间需要**独立部署**或**独立数据库**（数据库拆分）。
- 不同限界上下文之间需要**最终一致性**（引入消息队列）。
- 单个模块的 QPS > 1000，需要水平扩展特定服务。

---

## Level 3：完整 DDD + 微服务 / 分布式（大型系统）

### 核心原则：最终一致性（Event-Driven）与 CQRS

当系统拆分为微服务后，**不能使用分布式事务**。跨上下文的操作必须通过 **领域事件（Domain Events）** 实现最终一致性。

### 模式 1：跨上下文通信（通过消息队列）

**场景**：订单支付成功后，需扣减库存。库存是独立的微服务（有界上下文）。

**Step 1: 定义出站端口（Application/Ports）**

```typescript
// application/order/ports/IInventoryRpcClient.ts
export interface IInventoryRpcClient {
    reserveStock(productId: string, quantity: number): Promise<void>;
}
```

**Step 2: 应用服务编排（发布事件或调用 RPC）**

```typescript
// application/order/services/PaymentHandler.ts
@Injectable()
export class PaymentHandler {
    constructor(
        private orderRepo: IOrderRepository,
        private inventoryClient: IInventoryRpcClient, // RPC 客户端
        private eventBus: IEventBus,
    ) {}

    @Transactional()
    async handlePaymentSuccess(orderId: string) {
        const order = await this.orderRepo.findById(orderId);
        order.markAsPaid(); // 聚合根改变状态

        // 1. 先保存本地（本地事务）
        await this.orderRepo.save(order);

        // 2. 发布事件（本地事务提交后，由 Outbox 模式或消息库保证可靠性）
        await this.eventBus.publish(
            new OrderPaidEvent(orderId, order.getItems()),
        );
    }
}

// infrastructure/messaging/consumers/OrderPaidConsumer.ts
@Injectable()
export class OrderPaidConsumer {
    constructor(private inventoryClient: IInventoryRpcClient) {}

    @RabbitSubscribe()
    async onOrderPaid(event: OrderPaidEvent) {
        // 库存服务最终会扣减库存
        for (const item of event.items) {
            await this.inventoryClient.reserveStock(
                item.productId,
                item.quantity,
            );
        }
    }
}
```

### 模式 2：CQRS（命令查询职责分离）

对于读写复杂的系统，分离 Command（写）和 Query（读）模型。

```text
application/order/
├── commands/                # 写操作（变更状态）
│   ├── CreateOrderCommand.ts
│   └── handlers/
│       └── CreateOrderHandler.ts
├── queries/                 # 读操作（不改变状态）
│   ├── GetOrderQuery.ts
│   └── handlers/
│       └── GetOrderHandler.ts (直接查询读库或 ElasticSearch)
└── dtos/
    ├── OrderWriteDTO.ts
    └── OrderReadDTO.ts       # 可能与写模型结构完全不同
```

### 模式 3：乐观锁（处理并发）

在聚合根中增加 `version` 字段，防止并发修改。

```typescript
// domain/order/aggregates/Order.aggregate.ts
export class Order {
  constructor(public version: number) {}
  // ...
}

// infrastructure/persistence/repositories/OrderRepositoryImpl.ts
async save(order: Order): Promise<void> {
  const result = await this.db.update(
    { id: order.id, version: order.version },  // where 条件包含 version
    { ...order, version: order.version + 1 }   // 更新时 version+1
  );
  if (result.affected === 0) throw new OptimisticLockException();
}
```

---

## 依赖注入（DI）与模块组装

在 NestJS 中，通过在 **基础设施模块** 中注册实现，替换 Domain 接口。

```typescript
// infrastructure/modules/OrderInfrastructureModule.ts
@Module({
    providers: [
        {
            provide: "IOrderRepository", // Token（接口标识）
            useClass: OrderRepositoryImpl, // 具体实现
        },
        {
            provide: "IEventPublisher",
            useClass: RabbitMQEventPublisher,
        },
    ],
    exports: ["IOrderRepository", "IEventPublisher"],
})
export class OrderInfrastructureModule {}

// application/modules/OrderApplicationModule.ts
@Module({
    imports: [OrderInfrastructureModule], // 导入基础设施，注入具体实现
    providers: [OrderApplicationService, PaymentHandler],
    exports: [OrderApplicationService],
})
export class OrderApplicationModule {}
```

---

## 禁止事项（红线）

- ❌ **禁止**在 Domain 层导入 TypeORM / Prisma / Mongoose 等 ORM 注解或类。
- ❌ **禁止**在 Domain 层导入 NestJS/Spring 的 `@Injectable()` 或 `@Transactional`（这些属于框架基础设施）。
- ❌ **禁止**在 Application 层编写 `if (order.status === 'PAID')` 这类业务规则（必须移至 Domain 实体方法）。
- ❌ **禁止**Controller 直接调用 Repository（必须经过 Application Service）。
- ❌ **禁止**使用 **分布式事务（如 2PC）** 跨上下文（请使用 Saga / 最终一致性）。
- ❌ **禁止**将数据库实体（Table Entity）直接返回给前端（必须转换为 DTO，防止领域泄露）。

---

## 领域事件最佳实践

1. **事件命名**：使用过去式（`OrderCreated`, `PaymentConfirmed`）。
2. **事件内容**：仅包含必要标识（`orderId`）和变更数据（`newStatus`），不包含完整聚合快照（避免过大）。
3. **可靠性**：
    - 使用 **Transaction Outbox 模式**：本地事务中存事件表，后台进程发布到 MQ，保证至少一次投递。
    - 或使用 Spring 的 `@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)`。

---

## 架构审查清单 (Code Review)

- [ ] Domain 层 `package.json` / `pom.xml` 是否无数据库驱动、无消息队列客户端？
- [ ] 聚合根的公共方法是否都在修改内部状态前进行了**业务不变量校验**？
- [ ] 跨聚合的操作是否仅在 Application 层编排，且**不跨越多个数据库事务**（除非使用 Saga）？
- [ ] 仓储接口是否定义在 Domain 层，实现在 Infrastructure 层？
- [ ] 并发控制（乐观锁/悲观锁）是否在聚合根版本号上体现？
- [ ] Controller 是否只做 DTO 转换，不包含 `if/else` 业务分支？
- [ ] 领域事件是否在 **事务提交后** 发布（防止本地回滚导致虚假事件）？

---

## 常见问题 (FAQ)

**Q1：领域服务（Domain Service）和应用服务（Application Service）有什么区别？**
A：**领域服务**解决单个实体/聚合根无法处理的纯业务逻辑（如转账：`MoneyTransferService` 操作两个账户聚合根），它属于 Domain 层。**应用服务**解决用例调度、事务管理、外部 RPC 调用，属于 Application 层。原则：能用实体方法解决的，绝不用领域服务；领域服务无法跨事务。

**Q2：我应该用 ORM 的实体做 Domain Entity 吗？**
A：**绝对不要**。ORM 实体（如 `@Entity()` 注解的类）耦合了数据库框架，应放在 `Infrastructure` 层。Repository 实现负责将 ORM 实体 **转换为 Domain 实体**（Mapper）。这增加了代码量，但保证了 Domain 层的纯净和可测试性。

**Q3：如何处理“查询”操作（不需要复杂业务规则）？**
A：对于高性能查询，**可以不经过 Domain 层**。Controller 可以直接调用专门的 QueryHandler 或直接查读库（Read Model），避免加载整个聚合根。这就是 CQRS 的核心思想：写用 Domain，读用 DTO。

**Q4：如何初始化一个复杂的聚合根？**
A：使用 **工厂方法** 或 **Builder 模式** 放在 Domain 层。例如 `Order.create(userId, items)` 静态方法，内部包含创建时的不变量校验。

**Q5：如果我不用 Spring/NestJS，而是 Go / Python (FastAPI)？**
A：架构原则完全一致。Go 中可将 Domain 作为独立 `internal/domain` 包，Infrastructure 作为 `internal/infrastructure` 包，通过接口实现依赖注入（手动组装）。Python 中可将 Domain 定义为 `dataclass` 并抛出自定义 `DomainException`。**DDD 是逻辑架构，不依赖编程语言**。

---

## 迁移路径

### Level 1 → 2

1. 识别 **聚合根**（如 `Order` 管理 `OrderItem`）。
2. 将 `Service` 中的校验逻辑 **上移** 到实体/聚合根的方法中。
3. 将 `Repository` 接口从 `infrastructure` 抽取到 `domain/repositories/`，实现依赖倒置。

### Level 2 → 3

1. 识别 **限界上下文**（如 Order, Payment, Inventory），拆分代码包。
2. 将同步 RPC 调用 **改造** 为异步事件（引入消息队列）。
3. 实现 **Outbox 模式** 保证事件发布的可靠性。
4. 引入 **CQRS** 解决高并发读瓶颈。
