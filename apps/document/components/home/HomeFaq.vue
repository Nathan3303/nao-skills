<!-- 段五：常见问题（默认 5 条全收起，展开 + → −；与 FAQ 页同源）。 -->
<script setup lang="ts">
import { inlineHtml } from './inline'
import type { HomeData } from './types'

defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="faq" class="section" aria-labelledby="faq-title">
    <div class="wrap">
      <p class="kicker">{{ home.faqKicker }}</p>
      <h2 id="faq-title">{{ home.faqTitle }}</h2>
      <div class="faq">
        <details v-for="item in home.faq" :key="item.q">
          <summary>{{ item.q }}</summary>
          <div class="faq-body">
            <p v-html="inlineHtml(item.a)"></p>
          </div>
        </details>
      </div>
    </div>
  </section>
</template>
