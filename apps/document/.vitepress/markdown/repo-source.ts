/**
 * 仓库侧单一事实读取：`.agents/roles.yaml` 与 `.agents/prompts/*.md`。
 *
 * 约束（ADR 2026-11-16-docs-site-pipeline D2/D3）：
 *   - 只在构建期现读，零中间产物、零网络；
 *   - roles.yaml 用与 `.agents/scripts/nao-fleet.sh` `load_manifest` 同一严格子集
 *     （顶层 `roles:` / 2 空格角色条目 / 4 空格字段，禁 Tab），不引入 YAML 库；
 *   - 角色卡 frontmatter 只取 `version`（来源徽标用），正文整体原样交给渲染层。
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))

/** apps/document */
export const DOCS_ROOT = path.resolve(HERE, '..', '..')
/** 仓库根（nao 机制包根） */
export const REPO_ROOT = path.resolve(DOCS_ROOT, '..', '..')
export const PROMPTS_DIR = path.join(REPO_ROOT, '.agents', 'prompts')
export const ROLES_FILE = path.join(REPO_ROOT, '.agents', 'roles.yaml')

/** 由 build.mjs 在检测到卡源缺失时置位；仅作配置侧兜底，不作为对外口径。 */
export const CARDS_MISSING_ENV = 'NAO_CARDS_MISSING'

export interface RoleEntry {
  id: string
  card: string
}

export interface CardSource {
  /** `.agents/prompts` 是否存在（AC5 的判据） */
  available: boolean
  /** 声明顺序 = roles.yaml 声明顺序 */
  roles: RoleEntry[]
  /** 缺失原因（available=false 时有值） */
  reason: string
}

/** 严格子集解析 roles.yaml；文件缺失或格式非法时返回空表（构建不崩，严格模式由 build.mjs 兜）。 */
export function readRoles(): RoleEntry[] {
  let raw: string
  try {
    raw = fs.readFileSync(ROLES_FILE, 'utf8')
  } catch {
    return []
  }

  const roles: RoleEntry[] = []
  let inRoles = false
  let current: RoleEntry | null = null

  for (const line of raw.split(/\r?\n/)) {
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue
    if (!inRoles) {
      if (/^roles:\s*$/.test(line)) inRoles = true
      continue
    }
    const roleMatch = /^ {2}([a-z0-9][a-z0-9-]*):\s*$/.exec(line)
    if (roleMatch) {
      current = { id: roleMatch[1], card: '' }
      roles.push(current)
      continue
    }
    const fieldMatch = /^ {4}([a-z_]+):\s*(.*)$/.exec(line)
    if (fieldMatch && current && fieldMatch[1] === 'card') {
      current.card = fieldMatch[2].trim()
    }
  }

  return roles.filter((role) => role.card !== '')
}

/** 卡源状态（每次调用现读，dev 下改 roles.yaml 后重载即可生效）。 */
export function readCardSource(): CardSource {
  const roles = readRoles()
  const available = fs.existsSync(PROMPTS_DIR)
  return {
    available,
    roles,
    reason: available ? '' : '未找到 .agents/prompts',
  }
}

export interface CardFile {
  /** `.agents/prompts/<card>.md` 的仓库内相对路径，徽标展示用 */
  relPath: string
  /** frontmatter 的 version（缺失时为 null） */
  version: string | null
  /** 剥掉 frontmatter 后的正文 */
  body: string
}

const FRONTMATTER = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/

/** 读取一张角色卡；文件不存在返回 null。 */
export function readCard(role: RoleEntry): CardFile | null {
  const abs = path.join(PROMPTS_DIR, role.card)
  let raw: string
  try {
    raw = fs.readFileSync(abs, 'utf8')
  } catch {
    return null
  }

  const match = FRONTMATTER.exec(raw)
  let body = raw
  let version: string | null = null
  if (match) {
    const versionMatch = /^version:\s*(.+)$/m.exec(match[1])
    version = versionMatch ? versionMatch[1].trim() : null
    body = raw.slice(match[0].length)
  }

  return {
    relPath: `.agents/prompts/${role.card}`,
    version,
    body,
  }
}
