<!--
  首页壳：六段结构固定（Hero / 三个毛病 / 七个角色 / 三步装好 / 常见问题 / 页脚），
  文案全部来自 content/index.md 的 frontmatter.home —— 这里只做包裹与取值（AC2 单一源）。
-->
<script setup lang="ts">
import { useData } from 'vitepress'
import HomeBanner from './home/HomeBanner.vue'
import HomeFaq from './home/HomeFaq.vue'
import HomeFooter from './home/HomeFooter.vue'
import HomeHero from './home/HomeHero.vue'
import HomeCompare from './home/HomeCompare.vue'
import HomeFlow from './home/HomeFlow.vue'
import HomeProblems from './home/HomeProblems.vue'
import HomeResult from './home/HomeResult.vue'
import HomeRoles from './home/HomeRoles.vue'
import HomeSteps from './home/HomeSteps.vue'
import JumpNav from './home/JumpNav.vue'
import type { HomeData } from './home/types'

const { frontmatter } = useData()
const home = frontmatter.value.home as HomeData | undefined

if (!home) {
  throw new Error('content/index.md 缺少 frontmatter.home：首页文案必须留在 content 侧（AC2 单一源）')
}
</script>

<template>
  <main id="main" class="nh">
    <HomeHero :home="home" />
    <HomeBanner :banner="home.banner" />
    <JumpNav :items="home.jumpNav" />
    <HomeProblems :home="home" />
    <HomeRoles :home="home" />
    <HomeFlow :flow="home.flow" />
    <HomeCompare :home="home" />
    <HomeResult :home="home" />
    <HomeSteps :home="home" />
    <HomeFaq :home="home" />
  </main>
  <HomeFooter :footer="home.footer" />
</template>
