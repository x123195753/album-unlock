# 无 Mac 安装指南（Windows 全流程）

> 原理：GitHub Actions 提供免费的 macOS 云构建机 → 自动编译出**未签名 ipa** →
> Windows 上用 Sideloadly 用你自己的 Apple ID 重签名后装进 iPhone。
> 全程不需要 Mac，也不需要付费开发者账号。

## 第一步：云构建（约 5 分钟）

1. 注册/登录 [GitHub](https://github.com)（免费账号即可）
2. 新建一个仓库（可以选 Private 私有仓库，免费账号也支持）
3. 把 `AlbumUnlock` 文件夹里的**全部内容**上传到仓库根目录（网页端拖拽上传即可，注意包含 `.github` 文件夹）
4. 打开仓库的 **Actions** 标签页 → 左侧选 **Build IPA** → 点 **Run workflow**（或推送后自动触发）
5. 等 3~5 分钟，构建完成后在该次运行页面底部的 **Artifacts** 下载 `AlbumUnlock-ipa`，解压得到 **AlbumUnlock.ipa**

## 第二步：Windows 签名安装（Sideloadly）

1. 下载并安装 [Sideloadly](https://sideloadly.io)（Windows 版）
2. 按提示安装 Apple 设备驱动（Sideloadly 会引导，通常需要 iTunes 官网的 iCloud + Apple Devices 组件）
3. 数据线连接 iPhone，打开 Sideloadly：
   - 拖入 `AlbumUnlock.ipa`
   - Apple ID 填你的普通 Apple ID
   - 点 Start，输入 Apple ID 密码（该密码仅用于苹果签名服务）
4. iPhone 上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID 开发者证书

## 注意事项

- **免费 Apple ID 签名 7 天有效**，到期 App 打不开，重新用 Sideloadly 签一次即可
- 免费 Apple ID 同时最多 3 个自签 App
- 想免续签：花 ¥688/年 注册 Apple Developer 个人开发者账号，Sideloadly 同样用它签名，有效期 1 年
- 若 Sideloadly 签名报错，可改用 [AltStore](https://altstore.io)（Windows 版 + 同一网络下自动续签，体验更好）

## 也可以让我代办

如果你把 GitHub 的 Personal Access Token（勾选 repo 权限）发给我，
我可以直接帮你创建仓库、推送代码、触发构建并把 ipa 下载到本地。
（注意：Token 等同于账号写权限，用完请到 GitHub 设置里删除）
