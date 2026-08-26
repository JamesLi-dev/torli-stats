# Codex 多账号使用情况：实现方案

## 状态

规划阶段，尚未实现。

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

1. **默认账号**：显示默认账号的指标；
2. **最低剩余量**（建议默认）：显示所有参与汇总账号中的最低剩余额度；
3. **逐账号显示**：以简短前缀分别显示各账号指标，仅适合不超过 2 至 3 个账号。

菜单栏颜色按参与展示账号中最低的剩余额度决定，以便额度紧张时及时提示。

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
