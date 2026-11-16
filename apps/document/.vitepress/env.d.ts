/** `.vue` 单文件组件的类型声明（构建期由 Vite 编译，tsc 只做静态检查）。 */
declare module '*.vue' {
  import type { DefineComponent } from 'vue'

  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
