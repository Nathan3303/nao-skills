---
description: 按需技能——前端 DDD 骨架、场景速决、命名、误区
---

# 前端 DDD 详细规范

## 标准骨架

```ts
// Domain 实体
class Task {
  complete() {
    if (overdue) throw new DomainError()
    this.status = 'done'
  }
}

// 用例（依赖接口）
class UseCase {
  constructor(repo, gateway) {}
  async exec(id) {
    const e = await repo.find(id)
    e.complete()
    await repo.save(e)
    this.gateway.update(e)
  }
}

// DI 组装点（Composable/Hook）
function useX() {
  const store = useStore()
  const uc = new UseCase(new HttpRepo(), store)
  return { ... }
}

// Mapper（Infra 层）
class Mapper {
  static toEntity(dto): Entity
  static toDto(entity): Dto
}
```

## 场景速决

- **路由**：Views 仅透传 `params` 给 Hook；禁 `onMounted` 直接调 API/用例
- **筛选/分页**：属 UI 状态（UI Store/局部），传纯 DTO 给用例；禁传 `ref` 响应式对象
- **表单**：UI 只做轻校验（必填/格式）；复杂规则放实体 `validate()`；UI 捕获 `DomainError` 映射回表单
- **错误**：用例统一转 `DomainError`/`InfraError`；UI 通过 `useErrorHandler` 映射 Toast（禁 `alert`）
- **WebSocket**：消息 → 领域事件 → `SyncUseCase` → 更新 Store；禁 `socket.on` 直改 Store
- **API 类型生成（OpenAPI）**：生成的 DTO 仅限 Infra，必须经 Mapper 转实体进 Domain
- **性能**：Store 存 Map/Record；组件用 Selector 取子集；禁全量解构 Store

## 命名

`I{Entity}Repository` / `{Entity}HttpRepo` / `{Entity}UseCase` / `{Entity}Dto` + `Mapper` / `useXxx`

## UI 风格落地

> 视觉决策收敛到主题令牌，**禁硬编码色值/魔法数值**；不靠审美，靠约束。

- **单一事实来源**：`--nue-*` 令牌（颜色/间距/圆角/阴影/字号层级）+ 主题包（如 nue-ui-theme-shadlike）；暗色/hover/disabled 由主题语义提供，不自己造。
- **红线**：组件/样式内禁裸色值（`#fff`/`rgba()`/`#d4a72c`）、禁无令牌的魔法尺寸/圆角/阴影——一律 `var(--nue-*)`；仅主题文件自身允许定义令牌。
- **组装**：新 UI 用组件库原语（Button/Input/Dialog…）组装，不新造组件外观；页面不另起风格。
- **四态覆盖**：加载/空/错误/成功 用组件库语义属性 + 令牌，与主题一致。
- **交付前**：跑 `bash "$NAO_SKILLS/.agents/scripts/ui-tokens-check.sh" <repo>` 确认零硬编码色值（进 CI 则自动拦截）。

## 测试

Domain：Vitest 纯单测；Application：Mock 端口；Infra：MSW；Pres：VTU/Testing-Library

## 误区

- DDD ≠ 重框架；规模不到 L1 用 DDD 反是负担
- 把业务规则写进 store 或组件
- 让 DTO 直接进 Domain
- 让 Store 调多个仓储做编排（应下沉 UseCase）
