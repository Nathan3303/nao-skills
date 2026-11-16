<!-- 段四：三步装好（命令块与快速开始页同源，不在页面里重写命令）。 -->
<script setup lang="ts">
import type { HomeData } from './types'

defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="install" class="section" aria-labelledby="install-title">
    <div class="wrap">
      <p class="kicker">{{ home.stepsKicker }}</p>
      <h2 id="install-title">{{ home.stepsTitle }}</h2>
      <ol class="steps">
        <li v-for="step in home.steps" :key="step.num" class="step">
          <p class="step-num" aria-hidden="true">{{ step.num }}</p>
          <div class="step-body">
            <h3>{{ step.title }}</h3>
            <p>{{ step.body }}</p>
            <div class="code"><code>{{ step.code.join('\n') }}</code></div>
          </div>
        </li>
      </ol>
    </div>
  </section>
</template>
