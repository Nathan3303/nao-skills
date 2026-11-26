<!--
  段六：跑完之后你收到什么（一条提交 + 一份 QA 回执）。
  补上「产物证据」：前面都在讲它会怎么做，这里给出做完的样子。
  文案来自 content/index.md 的 frontmatter.home.result*（AC2 单一源）。
-->
<script setup lang="ts">
import type { HomeData } from './types'

const props = defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="result" class="section" aria-labelledby="result-title">
    <div class="wrap">
      <p class="kicker">{{ props.home.resultKicker }}</p>
      <h2 id="result-title">{{ props.home.resultTitle }}</h2>
      <p class="lead">{{ props.home.resultLead }}</p>
      <div class="results">
        <article v-for="item in props.home.result" :key="item.label" class="result">
          <p class="result-label">{{ item.label }}</p>
          <p class="result-head">{{ item.head }}</p>
          <ul class="result-lines">
            <li
              v-for="(line, i) in item.lines"
              :key="i"
              class="result-line"
              :class="`is-${line.kind}`"
            >
              {{ line.text }}
            </li>
          </ul>
        </article>
      </div>
    </div>
  </section>
</template>
