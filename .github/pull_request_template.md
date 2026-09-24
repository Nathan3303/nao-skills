<!-- 本仓库自用的 PR 模板。规范源：.agents/templates/github/pull_request_template.md.example（装到用户项目的那份）
     改动本文件时请同步规范源，避免漂移。流程见 .agents/skills/github-flow.md -->
## 需求

- Issue：Closes #<id>
- 设计与决策：`docs/ARCHITECTURE.md#<section>` / `docs/prds/<file>.md#<section>`
- 验收标准：AC1 / AC2 / …

## 用户可见变化

<!-- 一句话，用户可读；将作为 squash 提交的标题主体 -->

## 变更点

- <行为变化 1>
- <行为变化 2>

## 门禁（全量精确数字）

- `bash .agents/scripts/nao-fleet.sh check` → exit=<n> · roles=<n> · files=<n>
- <其他门禁命令> → exit=<n> · 文件数/例数/红数：<n>/<n>/<n>

## 验收 / 预览

- 预览环境：<URL 或「无」>
- PM 验收：<待验收 / 通过（日期）>

## 风险 / 回滚

- <风险 + 应对；无则写「无」>
