<!--
  复制按钮（首页命令块）。行为沿用门户 app.js：
  成功「已复制 ✓」/ 失败自动全选并提示「已选中，请按 ⌘/Ctrl+C」，1.8s 复原；
  反馈走独立 aria-live 区，不靠颜色。
-->
<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'

const props = defineProps<{
  /** 要复制的文本 */
  text: string
  /** 失败时自动全选的元素 id */
  selectId?: string
  ariaLabel?: string
}>()

const IDLE = '复制'
const DONE = '已复制 ✓'
const FAIL = '已选中，请按 ⌘/Ctrl+C'
const HOLD_MS = 1800

const label = ref(IDLE)
const status = ref('')
let timer: ReturnType<typeof setTimeout> | undefined

function setState(next: string, note: string) {
  label.value = next
  status.value = note
}

function reset() {
  label.value = IDLE
  status.value = ''
}

function selectTarget() {
  if (!props.selectId) return
  const target = document.getElementById(props.selectId)
  if (!target) return
  const range = document.createRange()
  range.selectNodeContents(target)
  const selection = window.getSelection()
  if (!selection) return
  selection.removeAllRanges()
  selection.addRange(range)
}

async function copyText(): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(props.text)
      return true
    }
  } catch {
    /* 落到 execCommand 兜底 */
  }
  return legacyCopy()
}

function legacyCopy(): boolean {
  const area = document.createElement('textarea')
  area.value = props.text
  area.setAttribute('readonly', '')
  area.style.position = 'fixed'
  area.style.top = '0'
  area.style.left = '-9999px'
  document.body.appendChild(area)
  area.select()
  let ok = false
  try {
    ok = document.execCommand('copy')
  } catch {
    ok = false
  }
  document.body.removeChild(area)
  return ok
}

async function onCopy() {
  const ok = await copyText()
  if (ok) {
    setState(DONE, '已复制安装命令，回终端粘贴即可。')
  } else {
    setState(FAIL, '浏览器不允许自动复制，命令已选中，请按 ⌘ 或 Ctrl 加 C 复制。')
    selectTarget()
  }
  clearTimeout(timer)
  timer = setTimeout(reset, HOLD_MS)
}

onBeforeUnmount(() => clearTimeout(timer))
</script>

<template>
  <button
    class="pill pill-solid cmd-copy"
    type="button"
    :aria-label="ariaLabel ?? '复制安装命令'"
    @click="onCopy"
  >
    {{ label }}
  </button>
  <p class="copy-status" role="status" aria-live="polite">{{ status }}</p>
</template>
