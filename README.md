# 相册解锁（AlbumUnlock for iOS）

一个 iOS WebView 浏览器 App，打开"沙钢移动门户"及业务子应用页面时，
**自动注入脚本，把"只能调摄像头拍照"的上传框解锁为可以选择相册照片**。

> 说明：iOS 微信本身没有插件/扩展机制，不越狱无法向微信内置 WebView 注入代码。
> 因此本工具是"自带浏览器"方案：在自己 App 里打开同样的页面（登录态走网页表单），
> 上传体验与微信内一致，且可以选相册。

## 解锁原理（见 Sources/AlbumUnlock.js）

1. 移除页面所有 `input[type=file]` 上的 `capture` 属性 → 系统恢复"拍照 / 照片图库"选择菜单
2. `MutationObserver` 监听 DOM，动态创建的上传框也会被即时解锁
3. 劫持 `Element.setAttribute` 与 `HTMLInputElement.capture` 属性赋值，React/Vue 写入 `capture` 时直接丢弃
4. 补丁 `wx.chooseImage`：`sourceType: ['camera']` 强制放开为 `['album', 'camera']`
5. 脚本注入所有 frame（`forMainFrameOnly: false`），门户 iframe 里的跨域子应用同样生效
6. UA 追加 `MicroMessenger/8.0.49`，绕过页面对微信环境的检测

## 模拟定位（v1.1 新增）

门户还依赖 `wx.getLocation`（考勤/打卡类功能），本工具内置定位模拟：

- **App 内「📍 模拟定位」设置**：开关 + 经纬度输入（GCJ-02 火星坐标系），内置苏州/上海/南京等常用预设，设置持久化保存
- **补丁 `wx.getLocation`**：返回你设置的坐标（`errMsg: getLocation:ok`），门户 iframe 的 `locate-open` postMessage 链路同样生效
- **补丁 `navigator.geolocation`**：`getCurrentPosition` / `watchPosition` 也返回模拟坐标
- **模拟 `wx.config / wx.ready / wx.error`**：非微信容器里页面调用 `wx.config` 会失败走 error 分支禁用功能；脚本模拟 config 成功、ready 立即执行，保证页面定位逻辑照常运行
- 通过 `Object.defineProperty(window, 'wx', ...)` 捕获 wx 赋值，页面动态加载 jweixin 时立即补丁
- 修改定位后整页刷新，主页面与 iframe 子应用同步拿到新坐标

> 坐标注意：请填 GCJ-02 火星坐标（高德/腾讯地图拾取器获取）。若填 WGS-84（GPS 原始坐标），页面地图展示会偏移约 500 米。

## 构建

1. Mac 安装 Xcode 与 XcodeGen：
   ```
   brew install xcodegen
   ```
2. 在本目录生成 Xcode 工程：
   ```
   xcodegen generate
   open AlbumUnlock.xcodeproj
   ```
3. 选择你的 iPhone（真机），Xcode → Signing & Capabilities 用个人 Apple ID 登录自动签名
4. 运行（⌘R）。首次真机安装需在 iPhone「设置 → 通用 → VPN与设备管理」信任开发者证书

> 免费 Apple ID 签名 7 天过期，过期后重新 ⌘R 即可；付费开发者账号则无此限制。

## 使用

- 打开 App 默认加载 `http://qypt.shasteel.cn/mobile-apps/open`，登录后像在微信里一样使用
- 页面出现拍照上传框时，会弹出系统菜单：**拍照 / 照片图库 / 选取文件**，选相册即可
- 顶部「🔓 解锁相册」：对动态页面手动再执行一次解锁；「扫描文件框」：列出当前页面所有上传框的解锁状态
- 顶部「📍 模拟定位」：设置模拟经纬度并应用，`wx.getLocation` 与浏览器定位均返回该坐标

## 限制

- 微信 JS-SDK 专属能力中，扫码（scanQRCode）在非微信容器中不可用；定位已通过模拟定位功能替代
- 页面若检测 UA 强制跳转微信授权，可关闭 UA 伪装（App 内可自行调整代码开关）
