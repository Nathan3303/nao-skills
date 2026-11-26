<!--
  段三：一个需求怎么走完（五步 + 中间的真实消息流）。
  这一段补的是「怎么用」：前面讲了为什么需要、之后就讲有谁，中间缺一次完整流转。
  文案全部来自 content/index.md 的 frontmatter.home.flow（AC2 单一源）。
-->
<script setup lang="ts">
import type { HomeFlow as HomeFlowData } from './types'

const props = defineProps<{ flow: HomeFlowData }>()
</script>

<template>
  <section id="flow" class="section" aria-labelledby="flow-title">
    <div class="wrap">
      <p class="kicker">{{ props.flow.kicker }}</p>
      <h2 id="flow-title">{{ props.flow.title }}</h2>
      <p class="lead">{{ props.flow.lead }}</p>

      <ol class="flow-steps">
        <li
          v-for="step in props.flow.steps"
          :key="step.num"
          class="flow-step"
          :class="{ 'is-yours': step.yours, 'is-optional': step.optional }"
        >
          <p class="flow-num">{{ step.num }}</p>
          <h3>{{ step.title }}</h3>
          <p class="flow-body">{{ step.body }}</p>
          <p v-if="step.optional" class="flow-opt">{{ step.optionalNote }}</p>
          <p v-if="step.yours" class="flow-you">{{ step.you }}</p>
        </li>
      </ol>

      <div class="flow-log">
        <p class="flow-log-head">{{ props.flow.messagesTitle }}</p>
        <ul class="flow-msgs">
          <li v-for="(msg, i) in props.flow.messages" :key="i" class="flow-msg">
            <span class="flow-time">{{ msg.time ?? '' }}</span>
            <span class="flow-from">{{ msg.from }}</span>
            <span class="flow-arrow" aria-hidden="true">→</span>
            <span class="flow-to">{{ msg.to }}</span>
            <span class="flow-tag">{{ msg.tag ?? '' }}</span>
            <span class="flow-text">{{ msg.text }}</span>
          </li>
        </ul>
        <p v-if="props.flow.messagesNote" class="flow-note">{{ props.flow.messagesNote }}</p>
      </div>
    </div>
  </section>
</template>
