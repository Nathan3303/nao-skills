<!--
  段一之后：15 秒真实舰队会话录屏，作 Hero 的「画面证据」（最终形态：docs/T587-home-banner/design.md §变更记录）。
  纯装饰画面：<figure> + <picture> + <img>，无 figcaption / 无 h2 / 无播放按钮 / 无遮罩 / 无下载链接 / 无可见文案。
  介质是动画 WebP（1280w · 12fps · 循环）；prefers-reduced-motion 走 <source media> 换成静态 jpg —— 不裁切、不改内容。
  文案只在 content/index.md 的 frontmatter.home.banner（AC2 单一源）：alt 作无障碍名，fallback 仅读屏可见。
  资源路径一律走 withBase：CI 构建带 --base /nao-skills/，写死 /xxx.webp 会 404。
-->
<script setup lang="ts">
import { withBase } from 'vitepress'
import type { HomeBanner as HomeBannerData } from './types'

const props = defineProps<{ banner: HomeBannerData }>()

const animatedSrc = withBase('/nao-fleet-demo.webp')
const staticSrc = withBase('/nao-fleet-demo-static.jpg')
</script>

<template>
  <section id="preview" class="banner">
    <div class="wrap">
      <figure class="banner-figure">
        <picture>
          <source media="(prefers-reduced-motion: reduce)" :srcset="staticSrc" />
          <img
            class="banner-image"
            :src="animatedSrc"
            :alt="props.banner.alt"
            width="1280"
            height="696"
            loading="lazy"
            decoding="async"
          />
        </picture>
        <span class="banner-fallback">{{ props.banner.fallback }}</span>
      </figure>
    </div>
  </section>
</template>
