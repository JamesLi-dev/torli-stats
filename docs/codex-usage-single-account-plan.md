# Codex 账号使用情况显示：单账号第一版方案

## 1. 文档信息

- 状态：方案确认稿
- 目标分支：`feature/codex-usage-single-account`
- 适用版本：Torli Stats 当前 macOS 13+ 版本
- 实施范围：只读取本机默认 `codex_home` 中的 Codex 账号
- 本阶段不实现：多账号、账号切换、应用内登录、历史用量统计

---

## 2. 背景与目标

Torli Stats 当前已经具备状态栏展示和监控面板能力。本阶段增加一个 Codex 使用情况模块，用于显示当前本机 Codex CLI 登录账号的远程额度状态。

第一版刻意保持简单：

1. 只支持一个本地 Codex Home。
2. 默认使用 `CODEX_HOME` 环境变量指定的目录；未设置时使用 `~/.codex`。
3. 不在 Torli Stats 内完成 OAuth 登录。
4. 不直接保存、解析或上传 access token / refresh token。
5. 不读取本地会话日志来估算额度。
6. 只显示当前服务端返回的额度窗口和重置时间。
7. 展开面板中提供一个 Codex 使用情况卡片，显示当前账号的使用进度。
8. 菜单栏在现有 CPU/MEM/网络状态栏中追加 Codex 两行进度块：上行显示账号前缀，下行显示百分比，默认显示剩余量。
9. 设置面板可以分别控制 Codex 卡片和菜单栏中的 Codex 进度是否显示，并切换菜单栏显示用量还是剩余量。

完成并稳定后，再扩展为多个独立 Codex Home、多账号管理和账号切换。

---

## 3. 当前项目结构与接入点

当前主要代码位于：

```text
Sources/TorliStats/App.swift
```

相关现有组件：

- `AppDelegate`
  - 创建状态栏项目
  - 创建 Dashboard popover
  - 打开设置窗口
- `MetricsStore`
  - 系统指标采集
  - 通过高频和低频 Dispatch Queue 执行采样
  - 通过 `objectWillChange` 通知 SwiftUI 更新
- `AppSettings`
  - 使用 `UserDefaults` 保存应用偏好
  - 管理面板模块显示开关
- `DashboardView`
  - 使用滚动容器展示监控面板
  - 当前固定宽度约为 360，支持多个监控卡片
- `SettingsView`
  - 管理状态栏项目、监控间隔、面板模块等设置

Codex 数据不应阻塞现有系统指标采集，因此建议作为独立的低频异步模块接入，而不是直接塞入 `MetricsStore.collectHighFrequency()` 或 `collectLowFrequency()`。

---

## 4. 数据来源选择

### 4.1 采用 Codex CLI app-server

第一版通过 Codex CLI 的 app-server 查询额度：

```text
codex app-server --stdio
```

启动后按 JSON Lines 发送 JSON-RPC 请求：

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"torli-stats","version":"0.1.0"}}}
{"jsonrpc":"2.0","method":"initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"account/read","params":{}}
{"jsonrpc":"2.0","id":3,"method":"account/rateLimits/read","params":{}}
```

读取 `id = 2` 的账号信息和 `id = 3` 的额度信息。Dashboard 卡片展示完整账号邮箱；菜单栏只使用邮箱账号部分开头最多 3 个字符作为简短标识。

当前 Codex CLI 的 app-server 返回的核心字段包括：

```text
result.rateLimits.primary.usedPercent
result.rateLimits.primary.windowDurationMins
result.rateLimits.primary.resetsAt
result.rateLimits.secondary
result.rateLimits.credits
result.rateLimits.individualLimit
result.rateLimits.planType
result.rateLimits.rateLimitReachedType
account.email
account.planType
```

其中：

- `usedPercent` 是已使用百分比，不是剩余百分比。
- `resetsAt` 是 Unix 时间戳。
- `secondary` 可能为空。
- `credits` 可能为空或没有余额信息。
- `rateLimitReachedType` 可能为空，表示当前没有达到限制。
- `account/read` 用于取得当前账号的邮箱和计划类型，Dashboard 展示完整邮箱。
- 菜单栏账号标识取邮箱账号部分开头最多 3 个可见字符并转换为大写。例如 `torli@example.com` 显示为 `TOR`。
- 如果服务端没有返回邮箱，则使用 `C` 作为 Codex 的默认标识。

### 4.2 不采用直接 HTTP 请求

不建议第一版直接读取 `auth.json` 中的 token 后请求 ChatGPT/Codex 内部接口，原因如下：

- 相关接口不是稳定的公开 API。
- token 刷新流程容易和 Codex CLI 脱节。
- 需要在应用中处理 refresh token 的持久化和安全问题。
- 私有接口和响应字段可能随 Codex 版本变化。

使用 app-server 的好处是由 Codex CLI 负责现有认证和 token 刷新，Torli Stats 只处理协议响应。

### 4.3 不采用本地日志估算

本地 Codex session、history 或 usage archive 只能用于统计历史 token 消耗，不能可靠反映服务端限额。第一版只显示服务端额度状态。

### 4.4 进度显示语义

Dashboard 统一显示用量和剩余量：

```text
Dashboard：用量 90%，剩余 10%
```

菜单栏默认显示剩余量，并可在设置中切换为用量。菜单栏上行显示账号前缀、下行显示百分比：

```text
TOR
10%
```

原始百分比来自 `rateLimits.primary.usedPercent`；设置为剩余量时使用 `100 - usedPercent`。如果该字段缺失，则不显示伪造的百分比，而显示 Dashboard 错误状态；已有旧快照时继续显示旧值。

---

## 5. `codex_home` 解析规则

第一版只允许一个 Codex Home，解析顺序如下：

1. 读取进程环境中的 `CODEX_HOME`。
2. 如果未设置，使用：

   ```text
   ~/\.codex
   ```

3. 将路径标准化为绝对路径。
4. 检查目录是否存在。
5. 检查目录中是否存在 `auth.json`。
6. 不读取 `auth.json` 的 token 内容；只把它作为登录状态存在性的判断依据。

需要注意：从 Finder 启动 App 时，GUI 进程的环境变量通常不完整。因此默认路径必须明确支持 `~/.codex`，不能只依赖进程的 `CODEX_HOME`。

如果用户使用自定义 Codex Home，而当前 App 启动时没有继承 `CODEX_HOME`，第一版可以增加一个只读的路径设置项；但不做多账号列表。若希望进一步保持简单，也可以第一版只支持 `~/.codex`，并把自定义 `CODEX_HOME` 作为后续增强项。

建议最终采用：

- 自动识别 `CODEX_HOME` / `~/.codex`。
- 设置页提供“Codex Home 路径”单值配置。
- 该路径只保存目录路径，不保存 token。

---

## 6. Codex CLI 可执行文件查找

由于 macOS App 从 Finder 启动时通常不会继承完整 shell `PATH`，不能只执行 `codex` 作为命令名。

建议查找顺序：

1. 当前进程 `PATH` 中的 `codex`。
2. `/opt/homebrew/bin/codex`。
3. `/usr/local/bin/codex`。
4. `/usr/bin/codex`。
5. 如果都不存在，返回“未找到 Codex CLI”。

建议将查找逻辑封装为：

```swift
struct CodexExecutableResolver {
    func resolve() -> URL?
}
```

第一版不需要在设置页配置 Codex 可执行文件路径。后续如果支持更多安装方式，再增加手动选择路径。

---

## 7. 推荐代码结构

为了避免继续扩大 `App.swift`，实际实现新增以下文件：

```text
Sources/TorliStats/CodexUsageModels.swift
Sources/TorliStats/CodexUsageClient.swift
Sources/TorliStats/CodexUsageStore.swift
Sources/TorliStats/CodexUsageView.swift
```

Swift Package 会自动包含 `Sources/TorliStats` 下的新增 Swift 文件，因此暂不额外修改 `Package.swift`。

### 7.1 `CodexUsageModels.swift`

定义协议响应和 UI 状态模型。

建议模型：

```swift
struct CodexUsageWindow {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?
}

struct CodexCredits {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct CodexAccountIdentity {
    let email: String?
    let displayPrefix: String
    let planType: String?
}

struct CodexUsageSnapshot {
    let account: CodexAccountIdentity
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
    let credits: CodexCredits?
    let rateLimitReachedType: String?
    let fetchedAt: Date
}

enum CodexUsageState {
    case idle
    case loading(CodexUsageSnapshot?)
    case available(CodexUsageSnapshot)
    case unavailable(CodexUsageError, CodexUsageSnapshot?)
}
```

JSON 解码模型和 UI 模型可以分开，避免把 Codex app-server 的字段命名直接暴露给 SwiftUI。

### 7.2 `CodexUsageClient.swift`

职责：

- 解析 Codex Home。
- 查找 Codex 可执行文件。
- 启动 app-server 子进程。
- 写入 JSON-RPC 请求。
- 读取 stdout 中的 JSON Lines。
- 按 request id 匹配响应。
- 解码账号身份和额度字段。
- 由账号邮箱生成菜单栏使用的单字符标识。
- 处理超时、进程退出和协议错误。

建议接口：

```swift
final class CodexUsageClient {
    func fetch(completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void)
}
```

实际实现使用后台 Dispatch Queue 和完成回调，避免阻塞主线程。

### 7.3 `CodexUsageStore.swift`

职责：

- 管理当前 UI 状态。
- 管理刷新定时器。
- 防止重复请求。
- 保留上一次成功结果。
- 发布状态变化给 SwiftUI。

它不应修改系统指标的采样队列。

### 7.4 `CodexUsageView.swift`

职责：

- 展示 Codex 卡片。
- 展示加载状态、成功状态和错误状态。
- 格式化百分比和重置时间。
- 不负责发起请求，也不读取文件或 token。

---

## 8. 子进程生命周期

第一版建议采用“每次查询启动一个短生命周期 app-server”的方式，而不是常驻一个 app-server。

理由：

- 实现简单。
- 不需要处理长时间连接断开和重连。
- Codex 使用情况刷新频率很低，启动开销可以接受。
- 每次查询结束后立即释放子进程和管道。

建议流程：

```text
开始刷新
  ↓
检查是否已有请求
  ↓
解析 Codex Home
  ↓
查找 codex 可执行文件
  ↓
启动 codex app-server --stdio
  ↓
发送 initialize
  ↓
发送 initialized 通知
  ↓
发送 account/read 和 account/rateLimits/read
  ↓
等待两个请求对应 id 的响应
  ↓
解码结果
  ↓
结束并清理子进程
  ↓
回到主线程更新 UI
```

### 8.1 超时

单次请求建议超时 15 秒：

- 超时后终止子进程。
- 返回 `.timeout`。
- 不清空上一次成功数据显示。
- 在 UI 中显示“本次刷新超时”。

### 8.2 stdout 和 stderr

- stdout 只用于 JSON-RPC 协议。
- stderr 不应混入 stdout。
- stderr 可以读取后丢弃，或仅保留通用错误类型。
- 不把 stderr 原文直接显示给用户，因为其中可能包含路径或诊断信息。

### 8.3 并发控制

同一时间最多允许一个 Codex 查询：

```text
isRefreshing == true 时，跳过新的定时刷新
```

手动刷新也不能制造并发请求。请求完成后再允许下一次刷新。

---

## 9. 刷新周期

Codex 额度不需要跟随 CPU 采样频率刷新。

每次成功获得新快照后，需要同时更新两个展示位置：

1. Dashboard 中的 Codex 卡片。
2. 现有菜单栏状态栏中的 Codex 进度文本。

两个位置使用同一个 `CodexUsageSnapshot`，避免出现面板和菜单栏显示不同进度的情况。

建议：

- App 启动后异步刷新一次。
- 默认每 5 分钟刷新一次。
- 提供 Dashboard 内的手动刷新按钮。
- 后续可以把 5 分钟加入设置项，但第一版可以先固定。

系统监控的 1/3/5/10/30 秒刷新间隔不影响 Codex 查询频率。

如果 App 进入休眠、网络不可用或连续失败，不需要高频重试。连续失败时可以使用 1 分钟的最小重试间隔，避免每次系统指标刷新都启动 Codex。

---

## 10. 错误状态定义

建议定义以下错误：

```swift
enum CodexUsageError: Error {
    case codexHomeNotFound
    case authFileNotFound
    case executableNotFound
    case processLaunchFailed
    case initializeFailed
    case unauthorized
    case protocolError
    case invalidResponse
    case timeout
    case networkUnavailable
    case unsupportedAuthMode
    case unknown
}
```

UI 文案建议：

| 内部错误 | UI 文案 |
|---|---|
| `codexHomeNotFound` | 未找到 Codex Home |
| `authFileNotFound` | Codex 尚未登录 |
| `executableNotFound` | 未找到 Codex CLI |
| `unauthorized` | Codex 登录已失效 |
| `timeout` | 刷新超时 |
| `networkUnavailable` | 网络不可用 |
| `invalidResponse` | Codex 返回数据无法识别 |
| `unsupportedAuthMode` | 当前认证方式暂不支持 |

失败时应保留以下信息：

- 上一次成功的额度数据。
- 上一次成功更新时间。
- 当前错误状态。

如果从未成功过，才显示空状态卡片。

---

## 11. Dashboard UI 方案

在 `DashboardView` 中增加一个全宽 `CodexUsageView`，放在电源模块（`PowerStatusView`）之后、进程模块之前。这样 Codex 使用情况和电源状态归为同一组低频状态信息。展开面板使用更大的固定高度并隐藏滚动条，尽量一次展示全部模块；六个 CPU/GPU/内存/磁盘/网络/风扇方块使用更小的间距和高度，百分比、转速、网速等主数值使用较小字号。

该卡片由 `AppSettings.showCodexCard` 控制。默认开启；关闭后只隐藏 Dashboard 卡片，不影响菜单栏中的 Codex 进度。

示例：

```text
┌────────────────────────────────────┐
│ Codex 使用情况                 刷新 │
│ torli@example.com  用量 4% 剩余 96% │
│ ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ 重置 6 天后  Credits：可用  更新 14:32 │
└────────────────────────────────────┘
```

### 11.1 正常状态

显示：

- Codex 图标和标题。
- 完整账号邮箱，邮箱后显示 `Team`、`Plus` 或 `Pro` 计划类型标签。
- 同一行显示用量百分比和剩余百分比。
- 主额度进度条。
- 同一行显示重置时间、Credits 状态和最后更新时间。

### 11.2 次级窗口

如果 `secondary` 不为空，增加一行：

```text
短窗口：已使用 32%，2 小时后重置
```

### 11.3 Credits

如果响应中存在可用 credits：

```text
Credits：可用
```

如果是 unlimited：

```text
Credits：无限制
```

第一版不对 credits 做金额计算，原样保留为可选字段。

### 11.4 颜色规则

以剩余百分比为准：

- 剩余大于 50%：绿色
- 剩余 20%～50%：橙色
- 剩余小于 20%：红色
- 已达到限制：红色并显示“已达到限制”
- 无数据：次要灰色

### 11.5 菜单栏现有状态栏中的 Codex 进度

Codex 使用率不创建第二个 `NSStatusItem`，而是追加到现有 CPU、内存和网络状态栏文本中，项目之间使用两个空格分隔。

正常状态示例：

```text
CPU 19%  ↑ 0 KB/s  TOR
MEM 49%  ↓ 0 KB/s  91%
```

含义：

- `TOR`：当前 Codex 账号邮箱账号部分开头最多 3 个字符，使用和 CPU/MEM 相同的白色字体。
- `91%`：默认显示主额度窗口剩余 91%；切换为“用量”后显示已使用百分比。
- Codex 上行和下行在同一列左对齐，百分比只改变颜色，不改变字号。

实现要求：

- 复用现有 `updateStatusTitle(_:)`，不新增状态栏项目。
- 账号前缀使用和 CPU/MEM 相同的等宽字体、字号和白色。
- Codex 百分比沿用相同字号，按额度剩余比例显示绿色、橙色或红色。
- 成功刷新后同时更新 Dashboard 卡片和现有状态栏标题。
- 暂无成功数据时不追加 Codex 文本；Dashboard 显示具体错误。
- 刷新失败但已有旧数据时，保留上一次的 Codex 进度。
- 是否追加 Codex 文本由 `AppSettings.showCodexStatusItem` 控制。

后续多账号阶段再考虑显示“剩余最低账号”的摘要。

---

## 12. 设置页方案

为了保持第一版简单，设置页只增加一个单值 Codex 配置区域，不做账号列表。

显示控制拆成两个独立开关：

- `showCodexCard`：是否在展开面板显示 Codex 使用情况卡片。
- `showCodexStatusItem`：是否在现有菜单栏状态栏中追加 Codex 两行进度块。
- `codexStatusMetric`：菜单栏显示“剩余量”或“用量”，默认是“剩余量”。

两个开关默认均为开启，互不影响。用户可以只保留 Dashboard 卡片，或只保留菜单栏进度。

建议内容：

```text
Codex

Codex Home
[ /Users/xxx/.codex                 ] [选择]

[✓] 在展开面板显示 Codex 使用情况
[✓] 在菜单栏显示 Codex 使用进度（默认剩余量）
[剩余量 ▾]

状态：已登录 / 未登录 / 不可用
[立即刷新]
```

配置保存：

- 使用 `UserDefaults` 保存 Codex Home 路径。
- 使用 `UserDefaults` 保存 `showCodexCard` 和 `showCodexStatusItem`。
- 不保存 token。
- “恢复默认设置”时删除该路径，让程序回到 `CODEX_HOME` 或 `~/.codex` 自动解析。
- “恢复默认设置”时将两个展示开关恢复为开启。

如果当前 App 没有沙盒权限，保存普通路径即可。未来开启 App Sandbox 时，需要迁移到 security-scoped bookmark。

设置窗口使用与 Dashboard 一致的隐藏/overlay 小号滚动条，Codex Home 单独放在 Codex 设置卡片中。外观与状态栏合并为一组，面板模块与外观状态栏同排，监控区域移到下一排并使用两列布局，系统中的传感器和恢复默认按钮并排，窗口高度收紧以去除底部空白。

第一版不增加：

- 账号邮箱编辑。
- 多账号列表。
- 登录/退出按钮。
- 账号删除。
- 账号切换。

### 12.1 `AppSettings` 接入

在现有 `AppSettings` 中新增两个持久化属性：

```swift
@Published var showCodexCard: Bool
@Published var showCodexStatusItem: Bool
@Published var codexStatusMetric: CodexStatusMetric
```

读取和保存规则：

```swift
showCodexCard = defaults.object(forKey: "showCodexCard") as? Bool ?? true
showCodexStatusItem = defaults.object(forKey: "showCodexStatusItem") as? Bool ?? true
codexStatusMetric = CodexStatusMetric(rawValue: defaults.string(forKey: "codexStatusMetric") ?? "") ?? .remaining
```

两个属性的 `didSet` 写回 `UserDefaults`。`resetToDefaults()` 同时删除对应 key，并恢复为 `true`。

### 12.2 `AppDelegate` 接入现有状态栏

复用现有状态栏项目：

```swift
private var statusItem: NSStatusItem!
```

初始化时不创建第二个 `NSStatusItem`。`updateStatusTitle(_:)` 同时构造系统指标和 Codex 进度的富文本标题：

```text
showCodexStatusItem == false
    → 不追加 Codex 文本

showCodexStatusItem == true 且没有成功快照
    → 不追加 Codex 文本

showCodexStatusItem == true 且有成功快照
    → 在现有 CPU/MEM/网络文本后追加两个空格
    → 上行追加账号前缀 "TOR"
    → 下行追加设置选择的百分比 "91%"
```

标题分段：

```swift
let prefix = snapshot.account.displayPrefix
let used = Int(snapshot.primary?.usedPercent.rounded() ?? 0)
let remaining = 100 - used
let displayed = settings.codexStatusMetric == .used ? used : remaining
// prefix 使用 labelColor；displayed 使用额度状态颜色
```

状态栏更新必须在主线程执行。`CodexUsageStore` 在后台完成请求后，通过主线程发布新状态；`AppDelegate` 订阅该状态并再次调用现有 `updateStatusTitle(_:)`。

推荐的对象关系：

```text
AppDelegate
 ├── statusItem                 // CPU/MEM/网络/Codex
 ├── MetricsStore
 │    └── CodexUsageStore
 └── AppSettings
```

点击现有状态栏项目继续打开 Dashboard popover，右键菜单行为保持不变。

### 12.3 Dashboard 接入

`DashboardView` 增加：

```swift
if settings.showCodexCard {
    CodexUsageView(store: codexUsageStore)
}
```

`CodexUsageView` 只读取 Store 的状态：

- `.loading`：显示“正在读取 Codex 使用情况…”和进度指示器。
- `.available`：显示完整账号邮箱及 `Team`/`Plus`/`Pro` 计划标签、同一行的用量和剩余百分比、ProgressView，以及重置时间、Credits 状态和更新时间。
- `.unavailable`：显示错误文案和“重试”按钮；如果有旧快照，继续显示旧进度并标注更新时间。

ProgressView 的 value 使用：

```swift
(snapshot.primary?.usedPercent ?? 0) / 100
```

实际代码需要先将百分比转换为 `Double` 的 0～1 区间，且应对 0～100 之外的异常值做 clamp。

### 12.4 设置变化时的行为

当用户切换 `showCodexCard`：

- 只触发 Dashboard 重新布局。
- 不停止 Codex 刷新。
- 不影响菜单栏中的 Codex 进度。

当用户切换 `showCodexStatusItem`：

- 立即更新现有状态栏标题，追加或移除 Codex 进度。
- 不停止 Codex 刷新。
- 不改变 Dashboard 卡片显示状态。

当用户切换 `codexStatusMetric`：

- 立即更新现有状态栏下行百分比。
- 不重新请求 Codex。
- 默认值为“剩余量”。

当 `AppSettings.objectWillChange` 触发时，`AppDelegate` 应同时刷新：

1. 系统指标和 Codex 共用的状态栏标题。
2. Dashboard 卡片的显示状态。
3. 设置窗口的主题。

---

## 13. 安全与隐私要求

必须遵守以下规则：

1. 不读取 token 字符串到日志。
2. 不把 `auth.json` 内容复制到应用配置目录。
3. 不把 access token 或 refresh token 放入 `UserDefaults`。
4. 不通过网络把认证信息发送到 Torli Stats 自有服务器。
5. 子进程只继承必要环境变量，避免把不相关的 API key 写入日志。
6. 错误信息只显示归类后的状态，不直接显示命令输出。
7. 调试日志中禁止打印完整命令环境和 JSON-RPC 原始响应。

Codex CLI 负责读取和刷新本地认证文件，Torli Stats 只通过 app-server 取得额度结果。

---

## 14. 测试计划

### 14.1 单元测试

建议新增测试 Target 或可测试模块，覆盖：

- 成功响应解码。
- `primary` 存在。
- `secondary` 为空。
- `credits` 为空。
- `rateLimitReachedType` 存在。
- `usedPercent` 到剩余百分比的转换。
- Unix 时间戳转本地时间。
- 非法 JSON。
- 缺失关键字段。
- 错误状态映射。

### 14.2 集成测试

在真实本机环境执行：

1. Codex 已登录。
2. Codex 未登录。
3. Codex CLI 不在 PATH 中。
4. `CODEX_HOME` 指向不存在目录。
5. 网络断开。
6. token 过期并由 Codex CLI 刷新。
7. Codex CLI 返回非零退出码。
8. App 从 Finder 启动而不是终端启动。

测试过程中不能把真实 `auth.json`、token 或完整响应提交到仓库。

### 14.3 UI 验收

确认：

- Codex 卡片不会遮挡现有监控模块。
- 刷新过程中界面仍然响应。
- 网络失败时不会清空上一次成功结果。
- 没有 Codex 时有明确提示。
- Dashboard 可以正常滚动。
- 深色、浅色和跟随系统主题下颜色都可读。
- 重置时间显示符合用户本地时区。

---

## 15. 验收标准

第一版完成的判断标准：

- [ ] 能自动找到 `CODEX_HOME` 或 `~/.codex`。
- [ ] 能发现本地 `auth.json` 是否存在。
- [ ] 能找到并启动 Codex CLI。
- [ ] 能完成 app-server JSON-RPC 初始化。
- [ ] 能读取 `account/rateLimits/read`。
- [ ] 能展示主额度使用率。
- [ ] 能展示剩余百分比。
- [ ] 能展示重置时间。
- [ ] 能展示计划类型。
- [ ] 能展示完整账号邮箱、用量百分比和剩余百分比。
- [ ] 能在现有菜单栏状态栏中显示账号前缀和百分比上下两行的 Codex 进度。
- [ ] 能通过设置分别隐藏 Dashboard 卡片和菜单栏中的 Codex 进度。
- [ ] 能处理 secondary 为空。
- [ ] 能处理未登录、超时、网络错误和 CLI 不存在。
- [ ] 网络请求不会阻塞 Dashboard 和系统指标采集。
- [ ] Dashboard 和菜单栏使用同一个最新快照。
- [ ] 刷新失败时可以保留旧进度。
- [ ] 不输出或保存任何 token。
- [ ] `swift build -c release` 通过。
- [ ] 打包后的 App 从 Finder 启动时也能正常工作。

---

## 16. 后续多账号扩展预留

第一版虽然只做单账号，但接口设计应避免把路径和状态写死为全局单例。

后续可以自然扩展为：

```swift
struct CodexAccountConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var codexHomePath: String
    var enabled: Bool
}

struct CodexAccountState: Identifiable {
    let account: CodexAccountConfig
    let usage: CodexUsageState
}
```

第一版的 `CodexUsageClient.fetchUsage()` 后续可以扩展为：

```swift
func fetchUsage(codexHome: URL) async -> Result<CodexUsageSnapshot, CodexUsageError>
```

这样多账号阶段只需要：

- 将单一路径改成账号数组。
- 并行查询多个 Codex Home。
- Dashboard 从单卡片变成多账号列表。
- 在设置页增加账号管理。

不需要重写协议解析和 UI 状态模型。

---

## 17. 推荐实施顺序

### 阶段 A：协议和命令行客户端

- 新增 Codex 数据模型。
- 实现可执行文件查找。
- 实现 Codex Home 解析。
- 实现 app-server 启动和 JSON-RPC 请求。
- 加入超时和错误映射。

### 阶段 B：Store 接入

- 新增 `CodexUsageStore`。
- App 启动后异步首次刷新。
- 每 5 分钟定时刷新。
- Dashboard 和设置页支持手动刷新。
- 不阻塞 MetricsStore。

### 阶段 C：Dashboard 展示

- 新增 Codex 使用情况卡片。
- 展示正常、加载和错误状态。
- 加入剩余百分比和重置时间格式化。
- 在现有菜单栏状态栏中追加 `TOR 90%` Codex 进度。
- 由 `showCodexCard` 和 `showCodexStatusItem` 分别控制两处展示。

### 阶段 D：单路径设置

- 增加 Codex Home 路径设置。
- 增加状态提示。
- 增加恢复默认行为。

### 阶段 E：验证和文档

- 增加解码和格式化测试。
- 执行 Release 构建。
- 从 Finder 启动打包 App 验证。
- 更新 README 和 CHANGELOG。

---

## 18. 本阶段明确不做的内容

以下内容留到后续版本：

- 多个 Codex 账号。
- 多个 Codex Home 自动扫描。
- 账号邮箱和账号 ID 展示。
- 应用内 OAuth 登录。
- 应用内 Codex logout。
- Codex 历史用量曲线。
- 按模型统计 token。
- 额度告警通知。
- 状态栏显示多个账号额度。
- 直接调用私有 HTTP API 的 fallback。

## 结论

第一版采用“本地单一 Codex Home + Codex CLI app-server + 异步低频刷新”的实现方式。展开面板显示完整账号邮箱、用量/剩余和紧凑的额度卡片，菜单栏复用现有状态栏追加类似 `TOR 90%` 的已使用进度，并由设置面板分别控制两处展示。它可以复用现有 Codex 登录状态，不在 Torli Stats 中处理敏感 token，同时为后续多账号扩展保留清晰的接口边界。
