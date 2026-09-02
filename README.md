# iPhone Scroll Control

一个轻量级原生 macOS 工具，用 Logitech 鼠标侧键和键盘快捷键控制「iPhone Mirroring / iPhone 镜像」中的抖音视频。

当前版本：**1.1.4**
系统要求：macOS 15 或更高版本
架构：Apple Silicon（arm64）与 Intel（x86_64）

## 功能

| 输入 | 功能 | 生效条件 |
| --- | --- | --- |
| Logitech G309 后侧键 | 下一条视频 | iPhone Mirroring 前台、同时看到“首页”和“推荐” |
| Logitech G309 前侧键 | 上一条视频 | iPhone Mirroring 前台、同时看到“首页”和“推荐” |
| `↓` / `↑` | 下一条 / 上一条 | 同时识别到“首页”和“推荐” |
| `Space` | 播放或暂停 | 同时识别到“首页”和“推荐” |
| `←` | 双击点赞 | 同时识别到“首页”和“推荐” |
| `→` | 打开分享面板 | 同时识别到“首页”和“推荐” |
| `1`–`5` | 选择前五位联系人，可多选 | 已识别到“分享给”弹窗 |
| `Enter` | 点击发送 | 已选择至少一位联系人 |
| `Command + M` | 先暂停，再最小化 | 已识别为视频页 |
| `Command + H` | 先暂停，再隐藏 | 已识别为视频页 |

程序还会通过 ScreenCaptureKit 创建无焦点的实时悬浮预览：

- 其他应用位于前台时，iPhone 镜像画面仍可保持可见。
- 点击悬浮画面可激活真实的 iPhone Mirroring。
- 真实窗口最小化、隐藏或离开当前桌面时，预览同步消失。
- 隐藏或最小化后，工具立即暂停全部镜像交互；点击原窗口区域不会重新唤出镜像。
- 隐藏、最小化或离开当前桌面后会停止 ScreenCaptureKit 采集，菜单栏 sharing 状态随之结束；恢复窗口后自动重新采集。
- 上下独立圆角遮罩用于清除镜像画面四角黑边。

## 安全与输入保护

- 视频快捷键只在真实 iPhone Mirroring 位于前台、且 Vision 同时识别到“首页”和“推荐”时生效。
- 聊天页、搜索页以及识别不明确的页面会放行普通键盘输入。
- 离开 iPhone Mirroring 后，鼠标侧键保留浏览器前进、后退等原有功能。
- 分享数字键与 Enter 只有识别到“分享给”弹窗时才会被拦截；手动点击打开分享也支持。
- 屏幕捕获仅针对 iPhone Mirroring 单个窗口，不捕获系统音频。

## 安装发布版

从 GitHub Releases 下载 `iPhone-Scroll-Control-1.1.4-macOS.dmg`：

1. 打开 DMG。
2. 按住 Control 点击“安装.command”，选择“打开”。
3. 在“系统设置 > 隐私与安全性”中，为 `~/Applications/iPhone Scroll Control.app` 开启：
   - 辅助功能
   - 输入监控
   - 屏幕与系统音频录制
4. 运行 DMG 中的“重新启动.command”。

分享版本使用本地临时签名，没有 Apple Developer ID 公证。首次运行时 macOS 可能显示“无法验证开发者”；请仅从你信任的仓库或发布者下载。

完整图文教程见 [Docs/iPhone-Scroll-Control-安装与使用教程.pdf](Docs/iPhone-Scroll-Control-安装与使用教程.pdf)。

## 从源码构建

不需要 Homebrew、cliclick、Python 第三方库或其他自动化软件。只需要 macOS 自带框架与 Xcode Command Line Tools。

```bash
git clone https://github.com/hsha845-maker/iphone-scroll-control.git
cd iphone-scroll-control
./Scripts/build.sh
```

构建结果：

```text
build/iPhone Scroll Control.app
```

生成 DMG：

```bash
./Scripts/package.sh
```

输出位置：

```text
dist/iPhone-Scroll-Control-1.1.4-macOS.dmg
```

运行静态检查：

```bash
./Scripts/check.sh
```

## 配置

主要配置位于 [Sources/main.swift](Sources/main.swift) 顶部的 `Config`：

```swift
var nextButton: Int64 = 3
var previousButton: Int64 = 4
var debounceInterval: TimeInterval = 0.60
var floatingPreviewTopCornerRadius: CGFloat = 24
var floatingPreviewBottomCornerRadius: CGFloat = 82
```

当前 Logitech G309 实测映射为：后侧键 Button 3、前侧键 Button 4。不同鼠标或驱动可能报告不同编号，可从日志确认后修改配置。

## 日志

```text
~/Library/Logs/iPhoneScrollControl.log
~/Library/Logs/iPhoneScrollControl.error.log
```

## 项目结构

```text
App/           App Bundle 的 Info.plist
Docs/          安装教程、使用说明和版本说明
Installer/     安装、重启脚本与 LaunchAgent 模板
Scripts/       构建、检查和 DMG 打包脚本
Sources/       Swift 源码
```

## 已知限制

- 抖音界面文字或分享面板布局大幅改版后，页面识别关键词和点击比例可能需要调整。
- 分享联系人快捷键按第一行从左到右的前五个位置计算。
- 临时签名版本每次升级后，macOS 可能要求重新添加隐私权限。
- 工具依赖 Apple iPhone Mirroring，仅支持 macOS 15 及更高版本。

## 版本记录

参见 [CHANGELOG.md](CHANGELOG.md)。
