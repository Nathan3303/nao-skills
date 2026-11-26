<!--
  舰队预览：Hero 之后放一段 24 秒无声录屏，让访客第一眼看到「七个角色在一个界面里同时干活」。
  视频与海报都在 public/ 下（无外链、无第三方播放器）；文案留在 content/index.md 的 frontmatter.home.preview（AC2 单一源）。
  资源路径一律走 withBase：CI 构建带 --base /nao-skills/，写死 /xxx.mp4 会 404。
-->
<script setup lang="ts">
import { withBase } from 'vitepress'
import type { HomePreview as HomePreviewData } from './types'

const props = defineProps<{ preview: HomePreviewData }>()

const videoSrc = withBase('/nao-fleet-preview.mp4')
const posterSrc = withBase('/nao-fleet-preview-poster.jpg')
</script>

<template>
  <section class="preview" aria-labelledby="preview-title">
    <div class="wrap">
      <p class="kicker">{{ props.preview.kicker }}</p>
      <h2 id="preview-title">{{ props.preview.title }}</h2>
      <p class="preview-lead">{{ props.preview.lead }}</p>
      <figure class="preview-frame">
        <video
          class="preview-video"
          :poster="posterSrc"
          autoplay
          loop
          muted
          playsinline
          preload="metadata"
          :aria-label="props.preview.alt"
        >
          <source :src="videoSrc" type="video/mp4" />
          <p>
            {{ props.preview.fallback }}
            <a :href="videoSrc">下载这段录屏</a>
          </p>
        </video>
      </figure>
      <p class="preview-note">{{ props.preview.note }}</p>
    </div>
  </section>
</template>
