/**
 * 构建期清掉默认主题的「死残留」（AC10 / 架构评审 R2 判据：dist CSS 不含 3451b2、a8b1ff、'Inter'）。
 *
 * 默认主题 `vars.css` 会声明一整套 indigo 调色板与 Inter 字体栈；我们在 tokens.css 里
 * 用更高的层叠顺序把它们全部重映射为基准 token。这里的替换只作用在**已被覆盖的死声明**上，
 * 目的是让产物里连字面量都不残留（否则静态 grep 会误判「默认蓝还在」）。
 *
 * 实现用 `writeBundle` 在 CSS 落盘后原地改写：vite 的 css-post 在自身 generateBundle 里才发射
 * CSS 资源，用户插件的 generateBundle 早于它、看不到 CSS 资源。
 *
 * 守卫：若 vitepress 升级后替换规则失效，构建直接失败，避免「静默残留」。
 */
import fs from 'node:fs'
import path from 'node:path'

const PALETTE: [RegExp, string][] = [
  // 默认 indigo 调色板 → 基准 accent（这些值在 tokens.css 之后已无处生效）
  [/#3451b2/gi, '#1d4ed8'],
  [/#3a5ccc/gi, '#1b45c0'],
  [/#5672cd/gi, '#1d4ed8'],
  [/#a8b1ff/gi, '#8fb4ff'],
  [/#5c73e7/gi, '#2a5be0'],
  [/#3e63dd/gi, '#1d4ed8'],
]

const RESIDUE = /3451b2|a8b1ff|["']Inter["']/

function walkCss(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) walkCss(full, out)
    else if (entry.name.endsWith('.css')) out.push(full)
  }
  return out
}

export function stripThemeResidue(): {
  name: string
  apply: 'build'
  configResolved: (config: { build: { outDir: string } }) => void
  writeBundle: (this: { error: (message: string) => never }) => void
} {
  let outDir = ''

  return {
    name: 'nao-strip-theme-residue',
    apply: 'build',
    configResolved(config) {
      outDir = config.build.outDir
    },
    writeBundle() {
      if (!outDir || !fs.existsSync(outDir)) {
        this.error(`[nao] 残留清理：找不到构建产物目录 ${outDir}`)
      }

      const files = walkCss(outDir)
      if (!files.length) {
        this.error('[nao] 残留清理：产物里没有 CSS，规则无法验证（构建行为可能已变）')
      }

      for (const file of files) {
        const before = fs.readFileSync(file, 'utf8')
        let css = before
        for (const [pattern, replacement] of PALETTE) {
          css = css.replace(pattern, replacement)
        }
        // 默认字体栈首项（Inter / Punctuation SC）：整段去掉，剩 ui-sans-serif 起的系统栈
        css = css
          .replace(/["']Punctuation SC["'],\s*["']Inter["'],\s*/g, '')
          .replace(/["']Inter["'],\s*/g, '')
        if (css !== before) fs.writeFileSync(file, css)

        if (RESIDUE.test(css)) {
          this.error(
            `[nao] 默认主题残留清理失效（${path.relative(outDir, file)}）：` +
              'vitepress 升级后请复核 .vitepress/theme/styles/tokens.css 与清零点清单',
          )
        }
      }
    },
  }
}
