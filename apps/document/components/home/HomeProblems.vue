<!-- 段二：一个人对着 AI 写代码的三个毛病。 -->
<script setup lang="ts">
import { inlineHtml } from './inline'
import type { HomeData } from './types'

defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="why" class="section" aria-labelledby="why-title">
    <div class="wrap">
      <p class="kicker">{{ home.problemsKicker }}</p>
      <h2 id="why-title">{{ home.problemsTitle }}</h2>
      <p class="lead">{{ home.problemsLead }}</p>
      <ul class="cards">
        <li v-for="problem in home.problems" :key="problem.index" class="card problem">
          <p class="card-idx">{{ problem.index }}</p>
          <h3>{{ problem.title }}</h3>
          <p v-html="inlineHtml(problem.body)"></p>
        </li>
      </ul>
    </div>
  </section>
</template>
