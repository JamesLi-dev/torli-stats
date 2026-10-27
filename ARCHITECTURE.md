# 社区版核心与扩展构建

社区版保留系统监控、Dashboard、状态栏、Codex、WakaTime、便签和通用设置。此仓库独立构建，不需要任何私有仓库权限。

## Swift Package 边界

- `TorliStatsCore` 是公开的 library product，Swift module 名为 `TorliStats`，源文件仍位于 `Sources/TorliStats`，避免无意义地搬动公共代码。
- `TorliStatsCommunity` 是社区版入口；调用 `TorliApplication.run()`，不注册额外功能。可执行产品仍叫 `TorliStats`。
- `TorliStatsShared` 与 `TorliStatsHelper` 保留现有传感器协议和 Helper。
- 商业版在独立私有仓库通过固定 commit 引用 `TorliStatsCore`，不复制公共 App 实现。

扩展实现 `TorliFeature`：提供设置页面、面板卡片、可用与启用状态、变化通知、预估高度及重置/退出回调。应用入口必须在启动前注册扩展。核心仅暴露必要的入口和公共卡片/图标样式；业务 Store、账号和解析逻辑不进入接口。

面板排序使用稳定字符串 ID。内置模块 ID 保持不变；扩展写成 `feature:<id>`，可以识别已注册扩展的旧裸 ID。没有注册的扩展不显示在社区版设置或面板中。

## 本地验证与构建

```sh
python3 scripts/check-community-boundary.py
swift test
SKIP_INSTALL=1 ./build-app.sh
```

产物为 `TorliStats.app`。不设置 `SKIP_INSTALL=1` 会替换 `/Applications/TorliStats.app` 并重启，请在需要安装时再执行。

打包脚本可由另一个应用入口复用：`TORLI_PACKAGE_ROOT` 指向该入口所在 Package；`TORLI_PRODUCT`、`TORLI_APP_NAME` 指定产品和产物名称。图片、公共资源、第三方声明与 Helper 始终从本核心取用，应用 Info.plist、VERSION 和 build number 来自入口仓库。

## 自动发布

现有 main push / 手动触发流程保留。先检查公共边界并运行测试，再检查 VERSION：已有同名 Release 则跳过打包和发布；新版本则打包、上传 artifact、创建 tag 和 GitHub Release。仍为 arm64、ad-hoc 签名，未新增公证流程。

公共核心修改先合并在此仓库。使用者随后在自己的仓库更新固定的核心 SHA，并单独测试、升级自身 VERSION、发布自己的产品；社区版发布不触发其他产品自动升级。

## 授权与范围

继续保留 `THIRD_PARTY_NOTICES.md` 及 LICENSES 中的第三方授权文本。当前根目录尚无项目主许可证；此次拆分不代替维护者选择许可证，也不改变第三方授权。

边界检查用于拦截已知私有实现误放回社区包，不是完整的机密或 Git 历史审计。发布前仍需检查待提交 diff。

## 基础统计与扩展接口

社区版保留今日输入次数、活跃时长、KPM、今日 WakaTime 时长，以及账号配置和权限管理。Codex 额度、多账号和 Token 活动继续完整公开。

公共核心通过 `TorliStatisticsProvider` 提供可选的统计视图扩展接口，保留数据模型、采集与缓存服务，以及共用图表组件。未注册提供者时仅展示基础统计、请求 WakaTime 今日数据；注册提供者后可启用历史查询。

切换应用入口不主动清空已有本地统计和缓存。扩展的业务实现、产品规划及私有仓库内部结构由对应仓库维护。
