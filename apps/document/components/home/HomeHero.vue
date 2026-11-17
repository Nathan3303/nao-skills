<!-- Hero：定位 + 安装命令（复制）+ 双入口 + 终端示意（§一）。 -->
<script setup lang="ts">
import { withBase } from 'vitepress'
import CopyButton from '../CopyButton.vue'
import TerminalMock from './TerminalMock.vue'
import type { HomeData } from './types'

defineProps<{ home: HomeData }>()
</script>

<template>
  <section class="hero" aria-labelledby="hero-title">
    <div class="wrap hero-inner">
      <div class="hero-copy">
        <p class="kicker">{{ home.kicker }}</p>
        <h1 id="hero-title">
          <template v-for="(line, index) in home.title" :key="index">
            {{ line }}<br v-if="index < home.title.length - 1" />
          </template>
        </h1>
        <p class="lead">
          <template v-for="(line, index) in home.lead" :key="index">
            {{ line }}<br v-if="index < home.lead.length - 1" />
          </template>
        </p>

        <div class="cmd">
          <div class="cmd-box">
            <code id="install-cmd" class="cmd-code">{{ home.command }}</code>
            <p class="cmd-note">
              {{ home.commandNote }}
              <a :href="home.commandNoteHref" target="_blank" rel="noopener">{{ home.commandNoteLinkText }}</a>
            </p>
          </div>
          <CopyButton :text="home.command" select-id="install-cmd" />
        </div>

        <div class="cta-row">
          <template v-for="cta in home.cta" :key="cta.text">
            <a
              v-if="cta.style === 'solid'"
              class="pill pill-solid"
              :href="cta.external ? cta.href : withBase(cta.href)"
              :target="cta.external ? '_blank' : undefined"
              :rel="cta.external ? 'noopener' : undefined"
            >
              {{ cta.text }}
            </a>
            <a
              v-else
              class="cta-text"
              :href="cta.external ? cta.href : withBase(cta.href)"
              :target="cta.external ? '_blank' : undefined"
              :rel="cta.external ? 'noopener' : undefined"
            >
              {{ cta.text }}
            </a>
          </template>
        </div>
        <p class="trust">{{ home.trust }}</p>
      </div>

      <TerminalMock :lines="home.terminal" />
    </div>
  </section>
</template>
