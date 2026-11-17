<!--
  侧栏当前页无障碍标注：默认主题只给 `.VPSidebarItem.is-active` 类，不写 `aria-current`。
  设计 §五 要求侧栏当前页 `aria-current="page"`，这里在每次路由/侧栏重渲染后补齐（无视觉输出）。
-->
<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, watch } from 'vue'
import { useRoute } from 'vitepress'

const route = useRoute()
let observer: MutationObserver | undefined

function sync() {
  const sidebar = document.querySelector('.VPSidebar')
  if (!sidebar) return

  for (const el of sidebar.querySelectorAll('[aria-current="page"]')) {
    el.removeAttribute('aria-current')
  }
  for (const active of sidebar.querySelectorAll('.VPSidebarItem.is-active > .item a')) {
    active.setAttribute('aria-current', 'page')
  }
}

function schedule() {
  nextTick(sync)
  window.setTimeout(sync, 60)
}

onMounted(() => {
  schedule()
  const sidebar = document.querySelector('.VPSidebar')
  if (sidebar && 'MutationObserver' in window) {
    observer = new MutationObserver(schedule)
    observer.observe(sidebar, { childList: true, subtree: true })
  }
})

watch(
  () => route.path,
  () => schedule(),
)

onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <span hidden></span>
</template>
