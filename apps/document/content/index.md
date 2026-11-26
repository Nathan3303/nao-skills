---
layout: page
sidebar: false
pageClass: page-home
title: 给你的 pi 配一支开发小队
description: 7 个 AI 角色分工干活，各管一段：需求、方案、界面、前后端、测试、发布。你只做两件事：回答问题、点确认。一条命令装进你的项目。
home:
  kicker: 角色卡 + 协作规矩 + 小工具
  title:
    - 给你的 pi
    - 配一支开发小队
  lead:
    - 7 个 AI 角色分工干活，各管一段。
    - 你只做两件事：回答问题、点确认。
  command: pi install --local npm:@nathan33/nao-skill
  commandNote: 项目内版本 pin 见
  commandNoteHref: https://github.com/Nathan3303/nao-skills/blob/main/README.md
  commandNoteLinkText: README 安装段
  cta:
    - text: GitHub
      href: https://github.com/Nathan3303/nao-skills
      external: true
      style: solid
    - text: 快速开始
      href: /quickstart/prereq
      style: solid
    - text: npm 最新版 ↗
      href: https://www.npmjs.com/package/@nathan33/nao-skill
      external: true
      style: text
  trust: MIT 开源 · Node ≥18 · 仅支持 pi
  terminal:
    - kind: cmd
      text: nao-fleet.sh check
    - kind: ok
      text: ✓ 体检通过 · 7 个角色可开工
    - kind: cmd
      text: nao-fleet.sh ensure pm arch rd-fe
      gap: true
    - kind: ok
      text: ✓ 已拉起 3 个会话
    - kind: muted
      text: 3 个会话窗口逐个亮起（要拉满 7 个，照快速开始里的三步走）
      more: true
    - kind: muted
      text: 你：想加个「导出 CSV」功能
      more: true
      gap: true
      cursor: true
  jumpNav:
    - text: 三个毛病
      href: '#why'
    - text: 怎么用
      href: '#flow'
    - text: 七个角色
      href: '#roles'
    - text: 三步装好
      href: '#install'
    - text: 常见问题
      href: '#faq'
  flow:
    kicker: 怎么用
    title: 一句需求，五步走完
    lead: 你只在第 1 步和第 5 步出现；中间是角色之间自己在派单、回执、打回。
    steps:
      - num: '01'
        title: 你说一句话
        body: '「做个登录页，邮箱加密码，错了给提示。」不用写规格，不用拆任务。'
        yours: true
        you: 你在这里
      - num: '02'
        title: pm 拆单派活
        body: 拆成前端、后端、测试三单，分别发给对应的角色，同时发出去。
      - num: '03'
        title: 角色并行干
        body: 前端做表单，后端做校验接口，测试写用例。三边互不阻塞。
      - num: '04'
        title: QA 逐条验
        body: 过了的回一条放行；不过的当场打回，附复现步骤，改完再看。
      - num: '05'
        title: 合并到主干
        body: 全部放行后由研发合并，主干上留一条可读提交，一个需求一条。
        yours: true
        you: 你点确认
    messagesTitle: 中间实际发生的事（就是会话之间发的消息）
    messages:
      - from: pm
        to: rd-fe
        tag: T1
        text: 登录页表单 · 邮箱密码 · 错误提示放在输入框下方
      - from: pm
        to: rd-be
        tag: T2
        text: POST /api/login · 401 带错误码 · 密码不做明文比较
      - from: rd-be
        to: pm
        text: done · 3 个文件 · 200 与 401 都验过
      - from: pm
        to: qa
        tag: T3
        text: 验收 T1 与 T2 · 重点看错误提示和重复提交
      - from: qa
        to: pm
        text: 打回 1 条 · 连点提交会叠出三条提示（附复现步骤）
      - from: rd-fe
        to: pm
        text: 已修 · 300 毫秒防抖，只留一条提示
      - from: pm
        to: 你
        text: 都过了，合并？
  problemsKicker: 为什么需要
  problemsTitle: 一个人对着 AI 写代码，常见三个毛病
  problemsLead: 不是模型不够强，是缺分工与交付纪律。
  problems:
    - index: '01'
      title: 一个会话什么都干，聊到后面就糊涂了
      body: 拆成 7 个专业角色，各管一段，互不干扰。
    - index: '02'
      title: 需求没问清楚就开写，写完发现不对
      body: PM 先追问、写清 PRD（把需求写成能验收的文档）和目标，你点头才开工。
    - index: '03'
      title: 干完不知道算不算干完
      body: 每个任务必须回执（干完交的结论单）并按清单自查，PM 逐条验收才归档。
  rolesKicker: 分工
  rolesTitle: 七个角色，各管一段
  rolesLead: 不想要哪个角色，删掉对应文件即可；只留 PM + 一个研发角色也能跑。
  roles:
    - id: pm
      name: 产品经理
      duty: 拆需求、写 PRD、派活、验收，唯一的调度者
    - id: arch-designer
      name: 架构师
      duty: 技术选型与方案评审，出 ADR，评影响面
    - id: uiux-designer
      name: UI/UX 设计师
      duty: 信息架构、交互流程、视觉令牌与断点
    - id: rd-fe
      name: 前端研发
      duty: 实现界面与交互，自测通过后回执
    - id: rd-be
      name: 后端研发
      duty: 实现服务与数据，自测通过后回执
    - id: qa
      name: 测试工程师
      duty: 按验收标准出用例、跑全量检查、报缺陷
    - id: rd-infra
      name: 工程基座
      duty: CI、发布、脚本守卫与仓库治理
  stepsKicker: 三步装好
  stepsTitle: 从零到能派活，只要三步
  steps:
    - num: '01'
      title: 装前置
      body: pi ≥1.4.0、herdr ≥0.9.1（唯一终端后端）、Node ≥18、git 都齐了才装得起来。一条命令自检：
      code:
        - pi --version && node -v && git --version && herdr --version
    - num: '02'
      title: 把机制装进你的项目
      body: 项目级安装：pin 写进 `.pi/settings.json` 进仓库，团队 clone 即得同款。
      code:
        - cd 你的项目
        - pi install --local npm:@nathan33/nao-skill
        - npx @nathan33/nao-skill init
    - num: '03'
      title: 装协作插件，拉队开工
      body: 插件负责多会话派活；体检 exit 0 就能拉动 7 个常驻会话。
      code:
        - npx @nathan33/nao-skill plugins install-all
        - .agents/scripts/nao-fleet.sh check
        - .agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra uiux
  faqKicker: 常见问题
  faqTitle: 装之前你大概会问这几句
  faq:
    - q: 会改我的代码库吗？
      a: 只会新增三样东西：项目根的 AGENTS.md、.pi/settings.json，以及一个转发入口脚本。角色卡、清单、技能这些机制文件都在依赖包里，不铺进你的仓库，也不碰你原有文件；仓库里已有 AGENTS.md 时是合并追加，不会覆盖。
    - q: 除了 pi，能配别的编程 Agent 吗？
      a: 不能。nao 的多会话派活、回执、回收整套机制都建立在 pi 之上，只支持 pi，不为其他编程 Agent 做适配，也不承诺可互换。
    - q: 它会在 GitHub 上开 PR 吗？
      a: 会。每个需求一条分支、一个合并请求，草案早开、检查早跑。你确认验收后，由研发角色合并，主干上只留 1 条可读提交。没有远端或没装 gh 时降级为本地分支，流程顺序不变。
    - q: 跑完的会话要留着吗？
      a: 派生会话验收完就回收，常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留，目标在别的项目里也能回收。
    - q: 为什么需要终端后端？
      a: 舰队要把 7 个角色会话放进终端里，还要能可靠地找回与收掉。后端只有 herdr：每个角色一个 tab，身份靠结构化事实判定。旧的 tmux 后端已经删了，不会悄悄换后端。如果你的环境变量或启动脚本里还设着 `NAO_TERMINAL=tmux`，启动时会直接报错并告诉你改哪儿。把它删掉就行；不设这个变量时默认就是 herdr。
  footer:
    title: 现在就把小队拉起来
    lead: 装完只要一句话：在 PM 会话里说需求，剩下的它自己流转。
    cta:
      - text: GitHub
        href: https://github.com/Nathan3303/nao-skills
        external: true
        style: solid
      - text: 读 README ↗
        href: https://github.com/Nathan3303/nao-skills/blob/main/README.md
        external: true
        style: text
      - text: npm 最新版 ↗
        href: https://www.npmjs.com/package/@nathan33/nao-skill
        external: true
        style: text
    legal: MIT © 2026 Nathan Lee · 仅支持 pi ≥1.4.0 · 零外部依赖：不加载 CDN、不引外链字体、不做统计
---

<PortalHome />
