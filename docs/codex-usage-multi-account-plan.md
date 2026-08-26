# Codex 多账号使用情况：实现方案

## 状态

第一阶段已实现：菜单栏指标组排序、系统 CPU / 内存样式、受 Torli Stats 管理的额外账号目录、独立终端登录、账号级 Dashboard 展示与菜单栏 Codex 展示模式。后续仍需补齐账号导入、受限并发刷新和更完整的异常场景验证。

## 目标

在现有单账号 Codex 用量展示的基础上，支持多个本地 Codex CLI 账号；每个账号拥有独立的 `CODEX_HOME`、独立登录态和独立刷新状态。

本阶段只管理本机 Codex CLI 已登录账号，不实现 OAuth，不读取或保存 `access_token`、`refresh_token`，也不尝试访问 Pi Agent 的内部凭据。

## 已确定的账号目录约定

```text
~/.codex/                              # 用户已有的默认 Codex 账号，不修改
~/.torli-stats-codex/                  # Torli Stats 管理的额外账号根目录
├── personal/                          # 一个独立的 CODEX_HOME
│   ├── auth.json
│   ├── config.toml
│   └── ...
├── work/                              # 另一个独立的 CODEX_HOME
│   ├── auth.json
│   └── ...
└── ...
```

- `~/.torli-stats-codex` 是账号根目录，**不能**直接作为一个账号的 `CODEX_HOME`。
- 每个一级子目录是一个独立账号的 `CODEX_HOME`。
- 默认账号继续使用已有的 `CODEX_HOME` 或 `~/.codex`，无需重新登录。
- 后续由 Torli Stats 添加的账号都必须位于 `~/.torli-stats-codex/<目录名>`，并分别执行一次 `codex login`。
- 建议对根目录及新建账号目录设置 `0700` 权限。

示例：

```bash
CODEX_HOME="$HOME/.torli-stats-codex/personal" codex login
CODEX_HOME="$HOME/.torli-stats-codex/work" codex login
```

查询时同样为每个子进程明确指定其 `CODEX_HOME`：

```bash
CODEX_HOME="$HOME/.torli-stats-codex/personal" codex app-server --stdio
```

## 账号模型

每个账号配置仅保存非敏感元数据：

```swift
struct CodexAccountConfiguration: Codable, Identifiable {
    let id: UUID
    var displayName: String
    var homePath: String
    var isDefaultAccount: Bool
    var isDashboardVisible: Bool
    var isStatusBarVisible: Bool
    var sortOrder: Int
}
```

运行时快照独立保存账号身份和额度状态：

```swift
struct CodexAccountSnapshot {
    let configurationID: UUID
    let email: String?
    let accountID: String?
    let planType: CodexPlanType?
    let usage: CodexUsageSnapshot?
    let updatedAt: Date?
    let error: CodexUsageError?
}
```

禁止持久化、记录或展示：

- `auth.json` 原文；
- access token、refresh token 或任何认证头；
- app-server 的原始认证数据；
- Pi Agent 或其他应用的内部凭据。

## 添加账号流程

1. 用户在设置页点击“添加账号”。
2. 输入显示名称，例如“个人账号”或“工作账号”。
3. 应用将名称转换为安全目录名；冲突时追加序号，例如 `personal-2`。
4. 在 `~/.torli-stats-codex/<目录名>` 创建账号目录。
5. 用户点击“登录账号”，应用打开终端执行带该 `CODEX_HOME` 的 `codex login`。
6. 用户在浏览器完成 Codex 授权。
7. 返回应用后点击“验证并刷新”；应用通过 `codex app-server --stdio` 获取邮箱、套餐和额度。
8. 仅在验证成功后将账号标记为可用并进入 Dashboard / 菜单栏选择范围。

登录取消、登录过期、CLI 缺失或网络失败只影响该账号，不应阻塞其他账号。

## 管理规则

- 默认账号显示为“默认账号”，路径为配置的 `codexHomePath`、进程环境中的 `CODEX_HOME` 或 `~/.codex`。
- Torli Stats 管理的账号显示在单独列表中，路径固定在 `~/.torli-stats-codex/` 下。
- 显示名称可以修改；修改名称不自动重命名账号目录。
- 删除账号仅删除 Torli Stats 的账号配置，绝不删除账号目录、`auth.json` 或 Codex CLI 生成的其他文件。
- 路径必须去重；若不同路径解析出相同邮箱或 account ID，提示用户可能重复添加。
- 后续可提供“导入已有账号目录”，但仅接受一个具体的账号子目录，不能选择 `~/.torli-stats-codex` 根目录。

## 刷新与并发

- 每个账号拥有独立的最近成功快照、加载状态、错误状态和最后更新时间。
- “刷新全部”使用后台队列，建议最多并发 2 个 `codex app-server` 进程。
- 单账号手动刷新仅刷新目标账号。
- 失败时保留该账号的旧快照；初次失败显示账号级错误说明。
- 每次启动 app-server 都显式传入对应账号的 `CODEX_HOME`，不修改 Torli Stats 进程全局环境，也不影响默认账号或 Pi Agent。

## UI 方案

### 设置页

```text
Codex 账号

默认账号
默认账号 · ~/.codex                         自动发现

Torli Stats 管理的账号
个人账号 · ~/.torli-stats-codex/personal    已验证 · Plus
工作账号 · ~/.torli-stats-codex/work        已验证 · Team

[添加账号]  [导入已有账号目录]  [刷新全部]
```

每个账号支持：

- 显示名称；
- 路径展示与“在 Finder 中显示”；
- 登录 / 重新登录；
- 验证 / 单独刷新；
- 是否显示在 Dashboard；
- 是否参与菜单栏汇总；
- 从 Torli Stats 配置移除。

### Dashboard

将当前单一 Codex 卡片扩展为一个 Codex 账号组。每个账号条目显示：

- 显示名称、邮箱和 Team / Plus / Pro 标签；
- 用量与剩余量；
- 进度条、重置时间、Credits、更新时间；
- 单账号刷新及该账号的错误状态。

建议默认展示前 2 至 3 个账号，其余账号通过“显示更多”展开，避免状态面板无限增长。

### 菜单栏

提供三个可选模式：

1. **默认账号**（当前默认）：显示默认账号的指标；
2. **最低剩余量**：显示所有参与汇总账号中的最低剩余额度；
3. **逐账号显示**：以简短前缀分别显示各账号指标，仅适合不超过 2 至 3 个账号。

菜单栏颜色按参与展示账号中最低的剩余额度决定，以便额度紧张时及时提示。

### 菜单栏指标排序

设置页的“外观与状态栏”增加“菜单栏指标顺序”设置，支持拖拽调整三个**指标组**的位置：

```text
菜单栏指标顺序
≡ 系统：CPU / 内存
≡ 网络：下载 / 上传
≡ Codex 使用情况
```

- CPU 和内存始终属于“系统”这一组：两项保留现有内部展示方式，不能拆分为独立可排序项目。
- 下载和上传始终属于“网络”这一组，同样不可拆分。
- Codex 是第三个可排序组；其内部继续遵循所选菜单栏模式（默认账号、最低剩余量或逐账号展示）。
- 默认顺序保持当前行为：**系统（CPU / 内存）→ 网络（下载 / 上传）→ Codex**。
- 用户可将三个组排序为任意顺序，例如 Codex → 系统 → 网络。
- 各组原有显示开关继续生效：隐藏的组不显示，但其排序仍被保留；重新开启时恢复到原来的相对位置。
- 排序只影响菜单栏标题的组顺序，不改变 Dashboard 卡片或设置页中模块的位置。

建议持久化为稳定枚举数组，而非显示文本：

```swift
enum StatusBarMetricGroup: String, Codable, CaseIterable {
    case system       // CPU + memory
    case network      // download + upload
    case codex
}

var statusBarMetricOrder: [StatusBarMetricGroup]
```

读取配置时应补齐未来新增的组，并过滤重复值；配置缺失或损坏时回退到 `[.system, .network, .codex]`。UI 可使用 SwiftUI 的 `List` / `ForEach` `onMove` 提供拖拽排序，也应提供“恢复默认顺序”操作。

### 系统指标样式

“系统（CPU / 内存）”仍是一个可排序模块，但增加独立的显示样式设置：

```text
系统指标样式
○ 紧凑：CPU 13%
        MEM 39%
○ 分栏：CPU   MEM
        13%   39%
```

- **紧凑**为默认值，保持当前 CPU / 内存上下排列的菜单栏样式。
- **分栏**将 CPU 与内存渲染为两个小型上下结构：第一行是 `CPU` / `MEM`，第二行是相应百分比；两个小块仍共同构成“系统”模块。
- 此选项只影响系统模块的内部排版，不影响系统、网络、Codex 三个模块之间的排序、显示开关或 Dashboard。
- 网络模块继续维持下载 / 上传的既有成组样式；后续如有需求，可用同样模式扩展网络样式，但本阶段不增加额外选项。

建议持久化为：

```swift
enum SystemStatusBarStyle: String, Codable {
    case compact
    case stacked
}

var systemStatusBarStyle: SystemStatusBarStyle
```

第一阶段继续只使用一个 `NSStatusItem`，由其双行 attributed title 按 `statusBarMetricOrder` 组合系统、网络和 Codex 三个组；系统组在 `stacked` 模式下渲染为两个上下子块。若以后需要独立点击区域、更多组内样式或更严格的跨组基线控制，再迁移为自定义 AppKit 状态栏视图。

## 迁移与兼容

- 现有 `codexHomePath` 迁移为“默认账号”的路径来源，不复制 `auth.json`。
- 现有 `showCodexCard`、`showCodexStatusItem`、`codexStatusMetric` 作为全局初始默认值；后续可逐步迁移为账号级可见性配置。
- 新安装仍自动探测 `CODEX_HOME` / `~/.codex` 作为默认账号。
- 旧版配置读取失败时回退为单默认账号模式。

## 验收标准

- 默认 `~/.codex` 账号继续正常查询，无需重新登录。
- 新增账号创建在 `~/.torli-stats-codex/<目录名>` 下，并必须通过独立 `codex login` 完成授权。
- 不同账号的 app-server 查询使用正确的 `CODEX_HOME`，数据互不串扰。
- 任一账号刷新失败不影响其他账号展示；旧快照保留。
- 应用不写入、不打印、不持久化 token 或 `auth.json` 内容。
- 移除账号配置不会删除本地 Codex Home 目录或登录态。
- Dashboard 和菜单栏可按照配置展示、汇总多个账号。
