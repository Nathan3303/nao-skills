/** 首页文案的数据形状 —— 与 content/index.md 的 frontmatter.home 一一对应（文案单一源在 content 侧）。 */

export interface HomeLink {
  text: string
  /** 站内路径（以 / 开头）或外链 */
  href: string
  external?: boolean
  style?: 'solid' | 'text'
}

export interface TerminalLine {
  kind: 'cmd' | 'ok' | 'muted'
  text: string
  /** 与上一行之间留一个空隙 */
  gap?: boolean
  /** 窄屏（<1080）隐藏 */
  more?: boolean
  /** 行尾光标 */
  cursor?: boolean
}

export interface HomeProblem {
  index: string
  title: string
  body: string
}

export interface HomeRole {
  id: string
  name: string
  duty: string
}

export interface HomeStep {
  num: string
  title: string
  body: string
  /** 每行一条命令，按行渲染为同一个命令块 */
  code: string[]
}

export interface HomeFaqItem {
  q: string
  a: string
}

export interface HomeFooter {
  title: string
  lead: string
  cta: HomeLink[]
  legal: string
}

export interface HomeFlowStep {
  num: string
  title: string
  body: string
  /** 这一步需要用户参与（标出「你在这里」） */
  yours?: boolean
  you?: string
  /** 按需启用（不是每个需求都要走） */
  optional?: boolean
  /** 按需步骤的徽标文字，如「按需」 */
  optionalNote?: string
}

export interface HomeFlowMessage {
  /** 时间戳，如 09:30（让流程有「多快」的体感） */
  time?: string
  from: string
  to: string
  text: string
  /** 任务号，如 T1 */
  tag?: string
}

export interface HomeFlow {
  kicker: string
  title: string
  lead: string
  steps: HomeFlowStep[]
  messagesTitle: string
  /** 日志下方的一句总结，如「一个小需求走完一轮」 */
  messagesNote?: string
  /** 紧跟 note 的免责说明（时长只是示意，不是承诺） */
  messagesDisclaimer?: string
  messages: HomeFlowMessage[]
}

export interface HomeResultLine {
  /** body 普通行 / ok 通过 / warn 打回 / gap 空隙 */
  kind: 'body' | 'ok' | 'warn' | 'gap'
  text: string
}

export interface HomeResultBlock {
  /** 面板标题，如「主干上的一条提交」 */
  label: string
  head: string
  lines: HomeResultLine[]
}

export interface HomeCompareItem {
  title: string
  body: string
}

export interface HomeBanner {
  /** 图片解码失败时给读屏的一句降级文案（正常路径不渲染，屏上永远无文字） */
  fallback: string
}

export interface HomeData {
  kicker: string
  title: string[]
  lead: string[]
  command: string
  commandNote: string
  commandNoteHref: string
  commandNoteLinkText: string
  cta: HomeLink[]
  trust: string
  terminal: TerminalLine[]
  banner: HomeBanner
  jumpNav: { text: string; href: string }[]
  problems: HomeProblem[]
  flow: HomeFlow
  compareKicker: string
  compareTitle: string
  compareLead: string
  compare: HomeCompareItem[]
  resultKicker: string
  resultTitle: string
  resultLead: string
  result: HomeResultBlock[]
  problemsKicker: string
  problemsTitle: string
  problemsLead: string
  rolesKicker: string
  rolesTitle: string
  rolesLead: string
  roles: HomeRole[]
  stepsKicker: string
  stepsTitle: string
  steps: HomeStep[]
  faqKicker: string
  faqTitle: string
  faq: HomeFaqItem[]
  footer: HomeFooter
}
