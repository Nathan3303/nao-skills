<!-- 段六：页脚横幅（仅首页出现；文档页不重复营销 CTA）。 -->
<script setup lang="ts">
import { inlineHtml } from './inline'
import type { HomeFooter } from './types'

defineProps<{ footer: HomeFooter }>()
</script>

<template>
  <footer class="nh-footer">
    <div class="wrap">
      <h2>{{ footer.title }}</h2>
      <p class="lead" v-html="inlineHtml(footer.lead)"></p>
      <div class="cta-row">
        <template v-for="item in footer.cta" :key="item.text">
          <a
            v-if="item.style === 'solid'"
            class="pill"
            :href="item.href"
            :target="item.external ? '_blank' : undefined"
            :rel="item.external ? 'noopener' : undefined"
          >
            {{ item.text }}
          </a>
          <a
            v-else-if="item.style === 'ghost'"
            class="pill pill-ghost"
            :href="item.href"
            :target="item.external ? '_blank' : undefined"
            :rel="item.external ? 'noopener' : undefined"
          >
            {{ item.text }}
          </a>
          <a
            v-else
            class="cta-text"
            :href="item.href"
            :target="item.external ? '_blank' : undefined"
            :rel="item.external ? 'noopener' : undefined"
          >
            {{ item.text }}
          </a>
        </template>
      </div>
      <p class="legal">{{ footer.legal }}</p>
    </div>
  </footer>
</template>
