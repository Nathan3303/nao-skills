<!--
  段四：和「自己多开几个 pi 窗口」的区别（回答最大的质疑）。
  文案来自 content/index.md 的 frontmatter.home.compare（AC2 单一源）。
-->
<script setup lang="ts">
import type { HomeData } from './types'

const props = defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="diff" class="section" aria-labelledby="diff-title">
    <div class="wrap">
      <p class="kicker">{{ props.home.compareKicker }}</p>
      <h2 id="diff-title">{{ props.home.compareTitle }}</h2>
      <p class="lead">{{ props.home.compareLead }}</p>
      <ul class="diffs">
        <li v-for="item in props.home.compare" :key="item.title" class="diff">
          <h3>{{ item.title }}</h3>
          <p>{{ item.body }}</p>
        </li>
      </ul>
    </div>
  </section>
</template>
