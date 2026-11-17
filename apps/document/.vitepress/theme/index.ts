import { h } from 'vue'
import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme-without-fonts'
import PortalHome from '../../components/PortalHome.vue'
import SidebarAria from '../../components/SidebarAria.vue'
import './styles/tokens.css'
import './styles/base.css'
import './styles/home.css'
import './styles/content.css'

export default {
  extends: DefaultTheme,
  // 只在侧栏底部挂一个无视觉输出的无障碍补丁；其余沿用默认主题布局
  Layout: () =>
    h(DefaultTheme.Layout, null, {
      'sidebar-nav-after': () => h(SidebarAria),
    }),
  enhanceApp({ app }) {
    // 首页壳由 content/index.md 直接使用（PM 只填正文，壳归 rd-fe）
    app.component('PortalHome', PortalHome)
  },
} satisfies Theme
