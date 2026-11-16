import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme-without-fonts'
import PortalHome from '../../components/PortalHome.vue'
import './styles/tokens.css'
import './styles/base.css'
import './styles/home.css'
import './styles/content.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    // 首页壳由 content/index.md 直接使用（PM 只填正文，壳归 rd-fe）
    app.component('PortalHome', PortalHome)
  },
} satisfies Theme
