<!--
  段一之后：15 秒真实舰队会话录屏，作 Hero 的「画面证据」（最终形态：docs/T587-home-banner/design.md §变更记录）。
  纯装饰画面：<figure> + <picture> + <img>，无 figcaption / 无 h2 / 无播放按钮 / 无遮罩 / 无下载链接 / 无可见文案。
  介质是动画 WebP（1280w · 12fps · 循环）；prefers-reduced-motion 走 <source media> 换成静态 jpg —— 不裁切、不改内容。
  纯装饰，读屏跳过（img 收 alt="" + aria-hidden）：content/index.md 的 frontmatter.home.banner 只留 fallback，
  仅在图片解码失败时以 sr-only 出现（正常路径 DOM 里没有这句，屏上也永远没有文字）。
  资源路径一律走 withBase：CI 构建带 --base /nao-fleet/，写死 /xxx.webp 会 404。
-->
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
import type { HomeBanner as HomeBannerData } from './types'

const props = defineProps<{ banner: HomeBannerData }>()

const animatedSrc = withBase('/nao-fleet-demo.webp')
const staticSrc = withBase('/nao-fleet-demo-static.jpg')

/** 只在解码失败时出现（正常路径不渲染任何文字）；见 design.md §八 */
const failed = ref(false)
const imageEl = ref<HTMLImageElement>()

onMounted(() => {
  // 竞态（T592）：lazy 图的请求可能早于水合，@error 已经错过 —— 那时 img.complete 为 true、
  // naturalWidth 为 0，但 failed 仍是 false。挂载后再判一次，把「水合前就失败」的路径补上。
  const img = imageEl.value
  if (img && img.complete && img.naturalWidth === 0) failed.value = true
})
</script>

<template>
  <section id="preview" class="banner">
    <div class="wrap">
      <figure class="banner-figure" :class="{ 'is-failed': failed }">
        <picture>
          <source media="(prefers-reduced-motion: reduce)" :srcset="staticSrc" />
          <img
            ref="imageEl"
            class="banner-image"
            :src="animatedSrc"
            alt=""
            aria-hidden="true"
            width="1280"
            height="696"
            loading="lazy"
            decoding="async"
            @error="failed = true"
          />
        </picture>
        <span v-if="failed" class="banner-fallback">{{ props.banner.fallback }}</span>
      </figure>
    </div>
  </section>
</template>
