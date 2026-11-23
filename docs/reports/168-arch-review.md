# 评审报告 · herdr desktop app 第二后端（T562 · #168）

- 状态：定稿 · 2026-11-24 · Owner：arch-designer
- 指针：ADR `docs/adr/2026-11-24-herdr-app-backend.md` · PRD `docs/prds/2026-11-24-herdr-app-backend.md` · 证据 `docs/research/2026-11-22-herdr-desktop-app.md`

## 一、结论

**可行（有条件）**，ADR 已签。条件三条：① app 窗口不在跑 ⇒ 放置永不成，ensure 必须先置 exit 3；② 放置以 `doc.get` 结构验证，`where` 只作辅助；③ 测试按 **③ 部分隔离**（详见 §三）。

## 二、实测证据（2026-11-24 本机 `hc 0.1.22` / `herdr-app 0.1.16`）

- **核心隔离**：`XDG_RUNTIME_DIR=/tmp/aprun XDG_STATE_HOME=/tmp/apstate HC_SESSION=nao-t4-x hc server status|run|ls` ⇒ 新 core（pid / holder / socket 全在私有 runtime + state），默认 `hc ls` 逐字不变。
- **收养属 app，不属 core**：默认 core 上 `hc run --bg --keep --label herdr.space=<已存> --label herdr.tab=<已存> -- sleep 45`，**app 窗口未开** ⇒ 10×0.5s 轮询 `where` 恒 `None`、`doc.get` 不含该终端；kill+rm 后零残留（`hc ls --all` 前后一致）。
- **doc 结构**：`printf '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}\n' | hc connect` ⇒ `{value:{spaces:[{id,folder,name,tabs:[{id,root:{…content:{terminal:"t2"}}}]}]},version:10}`。app 关了仍返回**上次持久化** doc ⇒ doc 存在 ≠ 窗口在跑。
- **身份 env（app 终端内）**：`HC_SCOPE=<不透明>` / `HC_TERMINAL_ID=tN` / `HC_TERMINAL_SOCKET=<runtime>/herdr-core/<session>.sock`；**并继承**宿主 `HERDR_*`（从 TUI pane 起时两套同时存在）。
- **连接路由**：`HC_SOCKET` 决定连哪个 core（指错 ⇒ rc=5 `kind:unavailable`，stderr）；`HC_TERMINAL_SOCKET` **不参与路由**；`HC_SESSION=<不存在>` 会**静默新建**空 core（⇒ app 臂用 `HC_SOCKET=$HC_TERMINAL_SOCKET`，不靠 `HC_SESSION`）。
- **OSC 7501 可脚本驱动**：`printf '\033]7501;state=working:app=probe\007'` ⇒ `hc get` 读到 `status:{app:"probe",state:"working",msg}`；`done` 使 `turn` 0→1；进程退出 ⇒ `state:finished` + `status:null`（core 不保留 done）+ labels 保留。
- **生命周期/错误面**：`--no-parent` 才不挂父终端（默认挂；kill 父 ⇒ 子同死，`--no-parent` 子存活）；`hc rm` 未 kill ⇒ rc=1 `kind:live`；`kill` 已结束终端 ⇒ rc=0 幂等；`get/kill` 不存在 ⇒ rc=3 `not_found`；重名 ⇒ rc=1 `name_taken`。
- **keep 语义**：`--keep` 不保 pane —— 程序退出 pane 关、终端转 `finished`（`hc ls` 隐藏、`--all` 可见）；keep 真实语义 = core 丢失/重启后原地换 shell（labels 保留）。

## 三、R1 测试隔离定论（③ 部分隔离）

- **可自动化（真 `hc` + 私有 core）**：三件套闸门 + 自证（`hc get $HC_TERMINAL_ID` 回读 address）、`run/kill/rm/label` 往返、`status` 状态机（用 OSC 7501 小脚本，不必真 pi 与模型调用）、`live/finished` 判定、契约探测（`hc schema` 方法/字段、`doc.version`、错误 `kind`）、确定性 id 派生、`doc` 解析（离线夹具）。
- **桩 + 断言（`hc` 桩记录 argv）**：`--label herdr.space/tab`、`--no-parent`、`--keep`、`--name`、`HC_SOCKET` 注入；放置流程 = 写标签 → 读 doc → 不符 ⇒ kill+rm + 非零 + 一行指路（AC4）；能力缺失 ⇒ fail loud（AC8）。
- **`[SKIP]` + 理由（转人工验收）**：真实收养与 `where`（必须 app 窗口在跑 ⇒ 必写用户布局）；`ensure`/`close` 的 UI 可见效果（tab 出现/消失）；「app 关闭期间起的终端，开窗后是否补收养」（未验证）。
- **隔离护栏**：优先私有 `XDG_RUNTIME_DIR` + `XDG_STATE_HOME`（结构性，实测默认 core 碰不到），仅在无私有 runtime 时才用 `HC_SESSION`；用例名 `nao-t4-*`；teardown 必须**带同一私有 env** `hc server stop`（否则停不掉，实测漏过）+ 删 state 目录；禁拼错 `HC_SESSION`（会新建 core）。
- 已知代价：私有 runtime 下新建 core 约 0.1–0.3s，用例可不复用 server；每轮多一个 core/holder 进程，teardown 不干净会堆积。

## 四、风险与未决

- **R-a 契约非版本化**：`doc version:10` / labels / `where` 无公开文档 ⇒ 探测 + fail loud；app 升级后先跑桩。
- **R-b 收养时机未验证**：app 关闭期间起的终端在开窗后是否补收养（影响「先起后开窗」的用户路径），需 PM 真机看一眼。
- **R-c `turn` ≠ `state_change_seq`**：`turn` 只在回合完成（`done`）时 +1；就绪门改 `status.app=pi ∧ state=idle`（+ `status_ms` 非空），强度不降（`status.app` 本身即「agent 已上报」）。
- **R-d 幽灵 pane**：keep 恢复成 shell 但 labels 在 ⇒ 身份必须 `foreground`/`status.app` 交叉校验（对标 TUI case 30/31）。
- **R-e 子进程 env 污染**：app 终端继承宿主 `HERDR_*` ⇒ 启动时须 `env -u HERDR_*`，否则 pi 的 herdr 集成可能指向 TUI socket。

## 五、要 PM 拍板 / 改 PRD 的点

1. **BR2 / AC2 / AC4**：把「`where` 断言」改为「`doc` 结构断言（`where` 辅助）」（`where` 是 app 写的展示 label，会陈旧）。
2. **新增 AC**：app 窗口不可达（`herdr-app status` rc≠0）⇒ exit 3 + 一行指路（实测无窗口时放置永不成，否则必然触发回滚）。
3. **M5 / BR4 keep 表述订正**：`keep:true` 并不保 pane；`close` 顺序 = kill → rm，未 kill 的 rm 是 rc=1。
4. **M4 / AC2 就绪门**：`state_change_seq` 无等价物，改 `status.app=pi ∧ state=idle` 并登记语义差异。
5. **§六 R1 定格为 ③**；M7 `cases/44` 按 §三形态（含 `[SKIP]` 清单）。

## 六、给 rd-infra 的实施护栏（非设计决策）

- 唯一入口 `_term_app_exec`：注入 `HC_SOCKET`，**失败判据 = JSON `error` 字段非空**（rc 只作辅助：内容面错误可能 rc=0），app 臂禁裸调 `hc`（AC7）。
- 忙闲表：`live`+`working|blocked` ⇒ 忙；`live`+`idle|done` ⇒ 可投递；`live`+`error` ⇒ 不可投递 + warn；`status` 缺失/null ⇒ unknown（不可投递）；`finished` 一律不在线（先判 `state`）。
- preflight（`check` app 节）：`command -v hc` + `hc schema` 必备方法/字段 + `herdr-app status` rc=0 + `doc.get` `version ≥ 10`。
