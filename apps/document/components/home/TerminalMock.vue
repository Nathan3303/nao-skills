<!-- 终端示意：纯 CSS 绘制、装饰性内容对辅助技术隐藏（§三 / §八）。 -->
<script setup lang="ts">
import type { TerminalLine } from './types'

defineProps<{ lines: TerminalLine[] }>()
</script>

<template>
  <div class="term" aria-hidden="true">
    <div class="term-bar">
      <span class="term-dot term-dot-r"></span>
      <span class="term-dot term-dot-y"></span>
      <span class="term-dot term-dot-g"></span>
    </div>
    <p
      v-for="(line, index) in lines"
      :key="index"
      class="term-line"
      :class="[
        line.kind === 'ok' ? 'term-ok' : '',
        line.kind === 'muted' ? 'term-muted' : '',
        line.gap ? 'term-gap' : '',
        line.more ? 'term-more' : '',
      ]"
    >
      <span v-if="line.kind === 'cmd'" class="term-prompt">$</span>{{ line.text }}
    </p>
  </div>
</template>
