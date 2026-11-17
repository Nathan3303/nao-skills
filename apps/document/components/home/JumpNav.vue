<!-- 跳读条：原顶栏 4 锚点降级到 Hero 下方；<720 一行横滑（§一 / §五）。 -->
<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

const props = defineProps<{ items: { text: string; href: string }[] }>()

const activeId = ref('')
let observer: IntersectionObserver | undefined

onMounted(() => {
  if (!('IntersectionObserver' in window)) return

  const targets = props.items
    .map((item) => document.getElementById(item.href.slice(1)))
    .filter((el): el is HTMLElement => Boolean(el))
  if (!targets.length) return

  const visible = new Map<string, boolean>()
  observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        visible.set(entry.target.id, entry.isIntersecting)
      }
      const current = targets.find((target) => visible.get(target.id))
      activeId.value = current ? current.id : ''
    },
    { rootMargin: '-45% 0px -50% 0px' },
  )
  targets.forEach((target) => observer?.observe(target))
})

onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <nav class="jumpnav" aria-label="页内跳转">
    <div class="wrap">
      <ul class="jumpnav-list">
        <li v-for="item in items" :key="item.href">
          <a
            class="jumpnav-link"
            :href="item.href"
            :aria-current="activeId === item.href.slice(1) ? 'true' : undefined"
          >
            {{ item.text }}
          </a>
        </li>
      </ul>
    </div>
  </nav>
</template>
