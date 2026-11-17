/** 文案里的行内代码：`...` → <code>（其余全部转义，不接受任意 HTML）。 */
const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

export function inlineHtml(text: string): string {
  return text
    .replace(/[&<>"']/g, (char) => ESCAPES[char] ?? char)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
}
