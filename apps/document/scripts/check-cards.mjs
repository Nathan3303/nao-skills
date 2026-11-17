#!/usr/bin/env node
/**
 * AC3 自助核对：角色页正文是否与 `.agents/prompts/<card>.md` 正文逐段一致。
 *
 * 判据（ADR D3 / PRD AC3）：卡正文只在 `.agents/prompts`，站点页由构建期注入，不得有手抄副本。
 * 做法：把卡正文按空行切段，去掉代码围栏标记与行内 markdown 记号，逐段在 dist 对应页面里找
 * 归一化后的文本（HTML 去标签 + 去空白）。任何一段找不到 ⇒ rc=1。
 *
 * 用法：node scripts/check-cards.mjs（先 npm run docs:build）
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const DOCS_ROOT = path.resolve(HERE, '..')
const REPO_ROOT = path.resolve(DOCS_ROOT, '..', '..')
const PROMPTS_DIR = path.join(REPO_ROOT, '.agents', 'prompts')
const ROLES_FILE = path.join(REPO_ROOT, '.agents', 'roles.yaml')
const DIST = path.join(DOCS_ROOT, '.vitepress', 'dist')

function readRoles() {
  if (!fs.existsSync(ROLES_FILE)) return []
  const roles = []
  let inRoles = false
  let current = null
  for (const line of fs.readFileSync(ROLES_FILE, 'utf8').split(/\r?\n/)) {
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue
    if (!inRoles) {
      if (/^roles:\s*$/.test(line)) inRoles = true
      continue
    }
    const role = /^ {2}([a-z0-9][a-z0-9-]*):\s*$/.exec(line)
    if (role) {
      current = { id: role[1], card: '' }
      roles.push(current)
      continue
    }
    const field = /^ {4}card:\s*(.+)$/.exec(line)
    if (field && current) current.card = field[1].trim()
  }
  return roles.filter((role) => role.card)
}

function normalize(text) {
  return text
    .replace(/[\u200b\u00a0]/g, '')
    .replace(/`/g, '')
    .replace(/[*_~]/g, '')
    .replace(/\s+/g, '')
}

/** 去掉 markdown 的行首记号（标题 / 引用 / 列表），页面渲染后这些记号不出现 */
function stripLineMarkers(line) {
  return line
    .replace(/^\s*#{1,6}\s+/, '')
    .replace(/^\s*>\s?/, '')
    .replace(/^\s*[-*+]\s+/, '')
    .replace(/^\s*\d+\.\s+/, '')
}

function htmlText(file) {
  const raw = fs.readFileSync(file, 'utf8')
  return normalize(
    raw
      .replace(/<script[\s\S]*?<\/script>/g, '')
      .replace(/<style[\s\S]*?<\/style>/g, '')
      .replace(/<[^>]+>/g, '')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'"),
  )
}

const roles = readRoles()
if (!roles.length) {
  console.error(`✗ 未读到角色清单：${ROLES_FILE}`)
  process.exit(1)
}

let checked = 0
let failed = 0

for (const role of roles) {
  const cardPath = path.join(PROMPTS_DIR, role.card)
  const pagePath = path.join(DIST, 'roles', `${role.id}.html`)

  checked += 1
  if (!fs.existsSync(cardPath) || !fs.existsSync(pagePath)) {
    console.error(`✗ 缺文件：${role.id}（卡 ${cardPath} / 页 ${pagePath}；dist 缺失先 npm run docs:build）`)
    failed += 1
    continue
  }

  const page = htmlText(pagePath)
  const raw = fs.readFileSync(cardPath, 'utf8').replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '')

  // 段落 = 连续非空行；代码围栏整体跳过（页面里会被 highlight 改写，逐字比对无意义）
  const blocks = []
  let buffer = []
  let inFence = false
  for (const line of raw.split(/\r?\n/)) {
    if (line.startsWith('```')) {
      inFence = !inFence
      if (buffer.length) blocks.push(buffer.join(' '))
      buffer = []
      continue
    }
    if (inFence) continue
    // 表格行不逐字比对（HTML 表格会拆成单元格，文本拼接顺序与源不同）
    if (/^\s*\|/.test(line)) {
      if (buffer.length) blocks.push(buffer.join(' '))
      buffer = []
      continue
    }
    if (!line.trim()) {
      if (buffer.length) blocks.push(buffer.join(' '))
      buffer = []
      continue
    }
    buffer.push(stripLineMarkers(line))
  }
  if (buffer.length) blocks.push(buffer.join(' '))

  const missing = blocks
    .map((block) => normalize(block.replace(/^[-*>\s]+/, '')))
    .filter((block) => block.length > 24)
    .filter((block) => !page.includes(block))

  if (missing.length) {
    failed += 1
    console.error(`✗ ${role.id} 有 ${missing.length} 段与卡原文不一致`)
    for (const block of missing.slice(0, 3)) console.error(`   · ${block.slice(0, 80)}…`)
  }
}

if (failed) {
  console.error(`✗ AC3 未过：${failed}/${checked} 个角色页不一致`)
  process.exit(1)
}

console.log(`✓ AC3 通过：${checked} 个角色页正文与 .agents/prompts 逐段一致`)
