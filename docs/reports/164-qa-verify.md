# #164 intercom-protocol 常驻面同步 v2 · QA 只读复核

- 状态：待 PM 验收 · 更新：2026-11-23 · Owner：qa
- 指针：Issue #164 · PR #165 · 分支 `fix/164-intercom-protocol-sync` @ `5c3e1d6`（base `main`）· RD 报告 `docs/reports/164-intercom-protocol-sync.md` · 前序 `docs/reports/161-qa-verify.md`
- 结论：**done(full) · 0 P1 / 0 P2 / 3 P3（均不阻塞合并）**。复验 RD 二轮 4 处整改全部到位。复核零写入（本文件除外）。

## TL;DR

- **「legacy 仍可解析」成立但需限定**：名册内 `pm@nao-todo`（`01a1f926`）确实在；`ask` 能精确名命中；而 `send`/`handover` 对任何含 `@` 的 `to` 无条件走跨机（`index.ts:1801/1827/1879`），本机机器表为空 ⇒ 不可达。文档写「`@` 形不作准 + `send`/`handover` 跨机不可达」= 与实测一致，**未写松**。
- **判据复算**：`@<fleet>` 模板 0（常驻面/清单/技能面）；`回 PM` 0（该文件）；旧 `fleet.sh` 0；废弃 ADR 引用 0（该文件）。三处均在 `5c3e1d6` 前后复算。
- **4 处整改逐条到位**：废弃 ADR 指针改指`已接受`的 `2026-11-20-workspace-as-binding-unit`；`send`/`handover` 半句未过度收敛（未否定 `ask`）；`--card` 名形态补全；现场名 `pm@nao-todo` 已移出正文。

## 一、范围与不测

- 范围：`intercom-protocol.md` 文本与语义（v1 残留、单源纪律、寻址表述）、RD 二轮 4 处整改、判据 grep、门禁。
- 不测：`README` / `docs/INSTALL.md` / `nao-fleet.sh` 用法头仍为 v1 —— PM 已建 Issue [#166](https://github.com/Nathan3303/nao-skills/issues/166)，本批不覆盖（§四 只点名不判）。

## 二、环境与命令

- `bash .agents/scripts/nao-fleet.sh check` → rc=0 · `roles=7 · files=53`（后端 herdr · codegraph 齐备）
- `npm test` → rc=0 · 40 例 · **2513 PASS / 0 FAIL** · SKIP=0 · DEGRADE=0 · NOTE=17（白名单）· 日志 `/tmp/qa-t560-test.log`

## 三、逐条结论

1. **legacy 可解析（本批最重要语义）**：`nao-fleet.sh:4028` 注释「旧形不占 v2 槽位 —— 旧会话只读、可并存」属实；`status`/`list` 均可识别该名。可投性分面：`send`/`handover` 含 `@` ⇒ 跨机地址（`herdr machine list` = `[]`）⇒ 本机不可达、不回落；`ask` 走本地精确名 ⇒ 可达。RD 原「在线即证」论证不成立，但结论方向对，文档已按实测写明。
2. **v1 残留全文扫**：按「含 `@` 或含 `fleet`」逐行核对；9 处改动 + 2 处豁免（`:24`/`:28` 的 `@<repo>` = `ensure` 目标仓选择符）+ 6 类不动均核对成立。首轮唯一语义级残留（`:35` 以**已废弃** ADR `2026-11-17-fleet-identity-source` 作放置语义出处）已在 `5c3e1d6` 修。
3. **单源未破**：`:11` = 一句红线 + 指针（「口径单源 @.agents/skills/pm-operations.md §一」），规则细节留 `pm-operations:18-20`；该文件内 `前缀回退|E_TARGET_NOT_FOUND|完整名|解析顺序|歧义` grep = 0。
4. **`:11` 可读性**：新 worker 只读该行 ⇒「名字不含位置 / 跨仓寻址一律用会话 id / `@` 形不作准 / `send`·`handover` 跨机不可达」，不会得出「跨仓可裸名」或「`@` 还能用」。
5. **判据复算**：`grep -rn '@<fleet>' .agents` ⇒ 2 命中，均在 `nao-fleet.sh:32/37` 用法头（#166 面，见 §四）；`grep -rn '回 PM' .agents` ⇒ 4 命中，`pm-operations:19` 为规则文本、另 3 处为角色卡「打回 / 回 PM 转…」动词义（非寻址）；旧 `fleet.sh`（排除 `nao-fleet.sh`）⇒ 0；废弃 ADR 引用 `intercom-protocol.md` ⇒ 0。
6. **二轮 4 处整改**：① `:35` 现指 `2026-11-20-workspace-as-binding-unit`（状态「已接受」，且正是取代 11-17 的那篇）✓；② `:11` 半句仅限 `send`/`handover`，未写成「全都不可」✓；③ `:31` `--card` 名形态齐（`<role>(<任务>)` / `<role><N>(<任务>)` / 无 `--task` / `--as`）✓；④ 现场名 `pm@nao-todo` 已移出（grep 0）✓。

## 四、缺陷与遗留

- **P3-1（#166 面）**：`nao-fleet.sh:32/37` 用法头仍写 `<别名>-<编号>@<fleet>` /「新会话恒带 `@<fleet>`」= v1 命名契约，与 v2 相反。技术债属 #166，点名为避免遗漏。
- **P3-2（#166 面）**：`nao-fleet.sh:14` 用法头仍以已废弃 ADR `2026-11-17-fleet-identity-source` 作放置键出处，同上。
- **P3-3（非本批文件）**：ADR `2026-11-20-workspace-as-binding-unit` 状态行仍为「已接受（待落地）」，而 v2 已落地（`cases/40` 全绿）⇒ 建议 arch 收口为 `已接受（已落地 vX.Y.Z）`。
- 已知边界（沿用 #161 结论）：静态闸/判据只能覆盖 `@`、`fleet` 字面与寻址字面；行为级语义（如「fleet 决定放置」）靠人工扫，本批已扫，无残留。

## 五、未覆盖与风险

- RD 报「4 次全量 1 次 FAIL」仍不可点名（未留日志）；本轮 0 FAIL，无法归因，建议按其既有 flake 流程登记。
- legacy `@` 名在 `ask` 下仍可投：机制未封，只靠协议禁用 ⇒ 残留风险由常驻面措辞兜底（`:11` 已写死「一律用会话 id」）。
- `#166`（README/INSTALL/用法头）未覆盖，属已登记后续。

## 六、发布建议

- **可合并**：0 P1 / 0 P2，门禁全绿；3 条 P3 均不改变合并结论（P3-1/P3-2 随 #166，P3-3 随 arch 文档收口）。合并后 `main` 如需复核可再派。
