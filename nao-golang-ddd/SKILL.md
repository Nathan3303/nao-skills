---
name: "nao-golang-ddd"
description: "Backend Domain-Driven Design architecture guide based on Golang. Invoke when user wants to implement DDD, create new domains, or refactor project structure."
---

# Backend DDD Architecture Skill for Golang

## When Invoked

遵循以下决策工作流：

1. **评估系统规模**（预期 QPS、团队人数、业务领域数量）。
2. **选择对应的 DDD 等级**（1级单体 / 2级模块化单体 / 3级微服务）。
3. **应用该等级对应的最小化结构**。
4. **提供 Go 惯用代码模式**（显式 DI、Context、错误处理）。
5. **当达到明确的量化指标时，建议升级**。

---

## 架构哲学：纯净领域与显式依赖

### 四层分层（Go 标准布局）

| 层级               | 职责                                                                                       | Go 目录                    | 关键规则                                                            |
| :----------------- | :----------------------------------------------------------------------------------------- | :------------------------- | :------------------------------------------------------------------ |
| **Interface**      | **输入适配器**：HTTP/gRPC 控制器、消息队列消费者                                           | `internal/interfaces/`     | 仅做参数绑定、DTO 转换、权限校验；**不包含业务逻辑**                |
| **Application**    | **用例编排**：事务管理、跨聚合协调、发布领域事件                                           | `internal/application/`    | **不包含业务规则**；通过接口调用 Domain 层；管理 `context` 事务传递 |
| **Domain**         | **核心业务逻辑**：聚合根（Aggregate）、实体（Entity）、值对象（VO）、**仓储接口（Ports）** | `internal/domain/`         | **零外部依赖**（无 GORM、无 HTTP Client）；仅依赖 Go 标准库         |
| **Infrastructure** | **输出适配器**：数据库实现、缓存、消息队列、第三方 RPC                                     | `internal/infrastructure/` | **实现 Domain 层定义的接口**；处理具体技术细节                      |

**依赖方向（核心铁律）**：

```text
Interface → Application → Domain ← Infrastructure
```

> **高层模块（Application）依赖抽象（Domain 接口），具体实现（Infrastructure）也依赖抽象（Domain 接口）。** 这就是 Go 接口的威力——隐式实现，无需显式声明继承。

---

## 项目结构（Level 3 完整版）

```text
project-root/
├── cmd/
│   ├── api/                                 # REST API 服务入口
│   │   └── main.go                          # 依赖组装（Wire 或手动）
│   └── worker/                              # 消息队列消费者入口
│       └── main.go
│
├── internal/                                # 【私有代码】外部不可 import
│   ├── domain/                              # 【领域层】纯业务逻辑
│   │   ├── order/                           # 订单上下文
│   │   │   ├── aggregate.go                 # Order 聚合根（struct + 业务方法）
│   │   │   ├── entity.go                    # OrderItem 实体
│   │   │   ├── value_object.go              # Money, Address (值对象)
│   │   │   ├── repository.go                # 定义 OrderRepository 接口
│   │   │   ├── service.go                   # 跨聚合的领域服务（如折扣引擎）
│   │   │   └── event.go                     # OrderCreatedEvent 定义
│   │   ├── shared/                          # 共享内核（被多领域引用）
│   │   │   ├── errors.go                    # 哨兵错误（Sentinel Errors）
│   │   │   └── value_objects/               # 通用 VO（如 UserID, Money）
│   │   └── ...
│   │
│   ├── application/                         # 【应用层】用例实现
│   │   ├── order/
│   │   │   ├── command.go                   # 入参/出参 DTO
│   │   │   ├── handler.go                   # 用例实现（依赖 domain 接口）
│   │   │   ├── assembler.go                 # DTO <-> Domain 转换器
│   │   │   └── port.go                      # 【出站端口】定义外部依赖（如 EventPublisher）
│   │   └── ...
│   │
│   ├── infrastructure/                      # 【基础设施层】实现接口
│   │   ├── persistence/                     # 数据库实现
│   │   │   ├── postgres/
│   │   │   │   ├── order_repo_impl.go       # 实现 domain.OrderRepository
│   │   │   │   ├── transaction.go           # 事务管理器实现
│   │   │   │   └── model.go                 # DB 表结构（GORM tag 或 sqlx tag）
│   │   │   └── mapper.go                    # DB Model <-> Domain Entity 转换
│   │   ├── bus/                             # 消息队列
│   │   │   └── rabbitmq_publisher.go        # 实现 application.port.EventPublisher
│   │   └── client/                          # RPC 客户端
│   │       └── inventory_rpc.go
│   │
│   └── interfaces/                          # 【接口适配层】
│       ├── http/
│       │   ├── handler.go                   # Gin/Echo 控制器
│       │   └── dto.go                       # JSON 请求/响应结构体
│       └── consumer/
│           └── order_consumer.go
│
├── pkg/                                     # 【可公开】供其他微服务复用的契约
│   └── contracts/                           # Protobuf / OpenAPI / Plain DTO
│       └── order_dto.go                     # 纯数据结构，不含业务方法
│
├── go.mod
└── wire/                                    # 【可选】依赖注入生成代码
    └── wire.go
```

---

## Level 1：轻量级 DDD（小型单体，<5k LOC）

### 适用场景

- 业务逻辑简单，但**必须保有核心业务规则**（如任务不可重复完成）。
- 团队规模小，预期未来可能演进。

### 最小化结构（贫血 → 充血过渡）

```text
internal/
├── domain/
│   └── task/
│       ├── entity.go          # Task 结构体 + Complete() 方法
│       └── repository.go      # TaskRepository 接口
├── infrastructure/
│   └── task_repo_impl.go      # 简单内存/数据库实现
├── application/
│   └── task_service.go        # 编排逻辑，管理事务
└── interfaces/
    └── http/
        └── task_handler.go
```

### 核心模式：充血实体 + 哨兵错误

```go
// internal/domain/task/entity.go
package task

import "errors"

// 定义哨兵错误（领域异常）
var (
    ErrTaskAlreadyCompleted = errors.New("task already completed")
    ErrOverdueTaskCannotComplete = errors.New("overdue task cannot be completed without review")
)

type Task struct {
    ID      string
    Title   string
    Status  StatusEnum
    DueDate time.Time
}

// 充血模型：业务逻辑封装在方法内
func (t *Task) Complete() error {
    if t.Status == StatusDone {
        return ErrTaskAlreadyCompleted
    }
    if time.Now().After(t.DueDate) && t.Status != StatusDone {
        return ErrOverdueTaskCannotComplete
    }
    t.Status = StatusDone
    return nil
}
```

### 显式依赖注入（无框架容器）

```go
// cmd/api/main.go
func main() {
    db := connectDB()

    // 显式手动组装依赖（清晰、可测试）
    taskRepo := infrastructure.NewTaskRepository(db)
    taskService := application.NewTaskService(taskRepo)
    handler := http.NewTaskHandler(taskService)

    // 启动路由
    r := gin.Default()
    r.POST("/tasks/:id/complete", handler.Complete)
    r.Run()
}
```

### 量化升级指标（Level 1 → 2）

- 单个实体关联子实体超过 **3 个**（如 Order 关联 OrderItems）。
- 跨实体的复杂校验出现（需要引入**聚合根**）。
- 团队人数超过 **3 人**。

---

## Level 2：标准 DDD（模块化单体，5k-20k LOC）

### 关键模式：聚合根（Aggregate Root）与事务边界

聚合根是事务一致性边界。修改 Order 及其 Items 必须在**同一个数据库事务**中完成。

```go
// internal/domain/order/aggregate.go
package order

type Order struct {
    ID      string
    UserID  string
    Status  StatusEnum
    items   []*OrderItem  // 私有字段，必须通过方法修改
    version int           // 乐观锁
}

// 聚合根负责添加子实体，保证业务不变量
func (o *Order) AddItem(productID string, price Money, qty int) error {
    if o.Status != StatusPending {
        return ErrOrderNotPending
    }
    if qty <= 0 {
        return ErrNegativeQuantity
    }
    item := NewOrderItem(productID, price, qty)
    o.items = append(o.items, item)
    return nil
}

// 计算总金额（遍历子实体）
func (o *Order) Total() Money {
    total := MoneyZero()
    for _, item := range o.items {
        total = total.Add(item.Subtotal())
    }
    return total
}
```

### 核心模式：应用服务管理事务（使用闭包）

Go 无法像 Java 那样使用 `@Transactional` 注解。标准做法是使用 **`context` 传递事务句柄**，配合闭包管理事务边界。

```go
// internal/application/order/handler.go
package order

type TransactionManager interface {
    Do(ctx context.Context, fn func(txCtx context.Context) error) error
}

type Handler struct {
    repo      domain.OrderRepository
    txManager TransactionManager
    publisher EventPublisher
}

func (h *Handler) AddItem(ctx context.Context, cmd AddItemCommand) error {
    // 事务边界在此定义
    return h.txManager.Do(ctx, func(txCtx context.Context) error {
        // 1. 获取聚合（仓储使用 txCtx 中的连接）
        agg, err := h.repo.FindByID(txCtx, cmd.OrderID)
        if err != nil {
            return err
        }

        // 2. 执行业务逻辑（聚合根内部校验）
        money := domain.NewMoney(cmd.Price, cmd.Currency)
        if err := agg.AddItem(cmd.ProductID, money, cmd.Qty); err != nil {
            return err  // 触发回滚
        }

        // 3. 保存聚合（同一事务）
        if err := h.repo.Save(txCtx, agg); err != nil {
            return err
        }

        // 4. 发布领域事件（事务提交后，保证最终一致性）
        // 注意：真正的发布动作应放在 AfterCommit 钩子中
        return h.publisher.Publish(txCtx, agg.Events())
    })
}
```

### 基础设施实现事务管理器

```go
// internal/infrastructure/persistence/postgres/transaction.go
type TxManager struct {
    db *sql.DB
}

func (m *TxManager) Do(ctx context.Context, fn func(context.Context) error) error {
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return err
    }

    // 将 *sql.Tx 存入 context，供 Repository 获取
    txCtx := context.WithValue(ctx, "tx", tx)

    if err := fn(txCtx); err != nil {
        tx.Rollback()
        return err
    }
    return tx.Commit()
}

// Repository 从 context 中获取事务连接
func (r *PostgresRepo) Save(ctx context.Context, agg *domain.Order) error {
    tx, ok := ctx.Value("tx").(*sql.Tx)
    if ok {
        // 使用事务连接执行
        _, err := tx.ExecContext(ctx, "INSERT ...", ...)
        return err
    }
    // 降级使用普通连接（非事务场景）
    _, err := r.db.ExecContext(ctx, "INSERT ...", ...)
    return err
}
```

### 量化升级指标（Level 2 → 3）

- 模块需要**独立部署**或**独立数据库**。
- 跨上下文需要**最终一致性**（引入消息队列）。
- 单个模块 QPS > 1000，需要水平扩展。

---

## Level 3：完整 DDD + 微服务（分布式）

### 核心原则：最终一致性 + 领域事件驱动

微服务间**绝对禁止**共享数据库。通过消息队列实现最终一致性。

### 模式：跨服务通信（使用 Ports & Adapters）

**Step 1: 在 Application 层定义出站端口**

```go
// internal/application/order/port.go
package order

type InventoryRPCClient interface {
    ReserveStock(ctx context.Context, productID string, qty int) error
}
```

**Step 2: 应用服务编排（发布事件）**

```go
func (h *Handler) HandlePaymentSuccess(ctx context.Context, orderID string) error {
    return h.txManager.Do(ctx, func(txCtx context.Context) error {
        agg, _ := h.repo.FindByID(txCtx, orderID)
        agg.MarkAsPaid()  // 聚合根状态变更
        h.repo.Save(txCtx, agg)

        // 发布事件（最终由 Outbox 或后台协程发送）
        return h.publisher.Publish(txCtx, &OrderPaidEvent{OrderID: orderID})
    })
}
```

**Step 3: 消费者独立部署（在 `cmd/worker` 中）**

```go
// internal/interfaces/consumer/order_consumer.go
type OrderPaidConsumer struct {
    inventoryClient application.InventoryRPCClient
}

func (c *OrderPaidConsumer) Handle(msg []byte) error {
    var event OrderPaidEvent
    json.Unmarshal(msg, &event)

    // 调用库存服务的 RPC（最终一致性）
    for _, item := range event.Items {
        c.inventoryClient.ReserveStock(ctx, item.ProductID, item.Qty)
    }
    return nil
}
```

### 并发控制：乐观锁（在聚合根中加版本号）

```go
// internal/domain/order/aggregate.go
type Order struct {
    Version int // 每次更新 +1
}

// internal/infrastructure/persistence/postgres/order_repo_impl.go
func (r *PostgresRepo) Save(ctx context.Context, agg *domain.Order) error {
    result, err := tx.ExecContext(ctx, `
        UPDATE orders SET status=$1, version=$2
        WHERE id=$3 AND version=$4
    `, agg.Status, agg.Version+1, agg.ID, agg.Version)

    if rows, _ := result.RowsAffected(); rows == 0 {
        return domain.ErrOptimisticLock  // 并发冲突，让上层重试
    }
    agg.Version++
    return nil
}
```

---

## 领域包复用（Go 特有策略）

### 策略 1：单体内部复用（源码依赖）

将通用值对象放入 `internal/domain/shared/`，各领域包通过 `import` 引用。

```go
// internal/domain/order/aggregate.go
import "my-project/internal/domain/shared"

func (o *Order) SetAddress(addr shared.Address) {
    o.Address = addr
}
```

### 策略 2：微服务间复用（契约包）

**绝对禁止**微服务 A import 微服务 B 的 `internal/domain`。在项目根目录创建 `pkg/contracts/`，仅放纯 DTO 结构体（无业务方法）。

```go
// pkg/contracts/order_dto.go (可被所有服务引用)
package contracts

type OrderCreatedEvent struct {
    OrderID string
    Total   float64
}
```

### 策略 3：跨语言复用（Protobuf）

在 `api/proto/` 定义 `.proto` 文件，使用 `protoc` 生成各语言代码。

---

## 测试策略（Go 特色）

### 单元测试（使用 `mockgen` 生成 Mock）

```go
// internal/application/order/handler_test.go
func TestHandler_AddItem(t *testing.T) {
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    mockRepo := mocks.NewMockOrderRepository(ctrl)
    mockTx := mocks.NewMockTransactionManager(ctrl)

    // 模拟事务闭包直接执行
    mockTx.EXPECT().Do(gomock.Any(), gomock.Any()).DoAndReturn(
        func(ctx context.Context, fn func(context.Context) error) error {
            return fn(ctx)
        },
    )

    handler := NewHandler(mockRepo, mockTx)
    err := handler.AddItem(context.Background(), AddItemCommand{...})
    assert.NoError(t, err)
}
```

---

## 禁止事项（红线）

- ❌ **禁止**在 `internal/domain/` 中导入 `gorm`、`sqlx`、`gin`、`grpc` 等框架包。
- ❌ **禁止**在 `internal/domain/` 中使用 `context.Context`（除非用于传递用户身份等元数据，不允许传递 DB 连接）。
- ❌ **禁止**在 `internal/interfaces/`（Controller）中调用 `domain/repository.go` 接口。必须经过 `application` 层。
- ❌ **禁止**使用 `panic` 处理业务异常（必须返回 `error`）。
- ❌ **禁止**在多个微服务间复制粘贴领域代码。如需共享，提取到 `pkg/contracts` 或独立仓库。

---

## 架构审查清单 (Code Review for Go)

- [ ] `internal/domain/` 的 `go.mod` 是否仅依赖标准库？（检查 `import` 列表）
- [ ] 所有业务校验是否封装在实体/聚合根的方法中，而不是散落在 `application` 层？
- [ ] 仓储接口是否定义在 `internal/domain/`，实现在 `internal/infrastructure/`？
- [ ] 应用服务是否通过 **闭包（`func(txCtx context.Context) error`）** 管理事务边界？
- [ ] 并发控制（乐观锁）是否在聚合根版本号上体现？
- [ ] Controller 是否只做参数绑定和调用 `application.Handler`，不包含 `if/else` 业务分支？
- [ ] 跨微服务的通信是否使用 `pkg/contracts` 中的 DTO，而不是直接引用对方的 `internal` 包？

---

## 常见问题 (FAQ for Go)

**Q1：我可以在 Domain 层使用 GORM 的 `gorm.Model` 吗？**
A：**绝对不要**。GORM 的 tag（如 `gorm:"column:id"`）和 `gorm.Model` 属于基础设施层的实现细节。Domain 层必须是纯 Go 结构体，只有 `json` 或 `bson` tag 用于序列化（可选）。

**Q2：如何优雅地处理事务？一定要把 `*sql.Tx` 放 Context 吗？**
A：这是 Go 社区最主流的做法。另一种方式是使用 **函数式选项** 或 **Unit of Work 模式**。但 `context.WithValue` 传递事务句柄是最轻量、最符合 Go 习惯的方式（注意使用私有 key 类型防止冲突）。

**Q3：Go 如何实现依赖注入？需要学 Wire 吗？**
A：**Go 不强制使用 DI 容器**。对于中小型项目，在 `main.go` 中**手动显式组装**（如上面的例子）完全足够，且最清晰、最易调试。对于大型项目（>50 个依赖），可以使用 Google 的 `wire` 生成代码，但本质上还是“显式构建”，只是省去了手写构造函数传参的体力活。

**Q4：如何处理领域事件的事务内发布？**
A：在事务闭包内，将事件存入**内存队列切片**。事务提交成功后，再循环发送。如果担心进程崩溃导致事件丢失，需要实现 **Transaction Outbox 模式**（在本地事务中插事件表，后台进程扫表发布）。

**Q5：如果 I/O 操作很多（如调用 3 个外部 API），如何组织并发？**
A：在 `application` 层使用 `errgroup` 或 `sync.WaitGroup` 并发调用外部端口（Ports）。但注意：如果涉及写操作，必须确保它们在一个事务边界内，或者使用 Saga 模式补偿。

---

## 迁移路径

### Level 1 → 2

1. 识别 **聚合根**，将子实体设为私有字段，通过聚合根方法操作。
2. 将 `service.go` 中的校验逻辑 **上移** 到实体/聚合根方法中。
3. 将 `Repository` 接口从 `infrastructure` 抽取到 `domain/repositories/`。

### Level 2 → 3

1. 在 `application/port.go` 中定义 RPC/消息队列的出站接口。
2. 将同步调用（HTTP 直连）改造为**异步事件**（引入 `pkg/contracts`）。
3. 实现 **Outbox 模式** 保证事件发布的可靠性。
4. 拆分 `cmd/api` 和 `cmd/worker`，独立部署。
