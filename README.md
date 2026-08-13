# LiveKit

LiveKit 是一个本地运行的 Android Live Photo / Motion Photo 管理工具。

它的重点不是替代系统相册，而是帮你找出 Live Photo 里占空间的“动态视频部分”，看清占用，并在你确认后清理不需要的动态部分，尽量保留静态照片。

## 适用范围

当前版本：`v0.2.0`

APK 版本：`versionName 0.2.0`，`versionCode 2014`

v0.2.0 主要适合：

- vivo 传统双文件 Live Photo：同目录、同名的 `.jpg/.jpeg + .mp4`
- 标准 JPEG Motion Photo：单个 `.jpg/.jpeg` 文件内嵌动态视频，当前已支持识别、播放和清理动态部分

仍在继续适配：

- vivo 新机型中的更多 Motion Photo 变体，例如 X300 系列及以上、S50 系列及以上，以及发布时间晚于 X300 系列的机型
- Pixel / Google Photos、OPPO / OnePlus、小米、三星、华为 / 荣耀等不同厂商的 Live Photo / Motion Photo 变体
- HEIC / HEIF 动态照片

LiveKit 对未知格式会优先跳过，不会为了“猜测支持”去冒险处理用户照片。

## 为什么需要 LiveKit

很多人旅行、拍孩子、拍宠物、聚会时会打开 Live Photo，因为它能记录按下快门前后的一小段动态。

但真实使用里经常会出现另一种情况：

- 只是忘记关闭 Live 模式
- 连续拍了很多普通照片，但每张都带了一段动态视频
- 这些动态片段以后基本不会再看
- 真正需要保留的只是那张静态照片
- 时间久了，手机空间被这些隐藏视频慢慢占满

系统相册通常不会提供一个足够直接的方式，让你批量检查并清理 Live Photo 的动态部分。LiveKit 就是为这个场景做的。

```text
找到 Live Photo
看清静态照片和动态视频分别占多少空间
保留静态照片
清理不需要的动态视频部分
释放手机存储空间
```

## 核心功能

### 清理 Live 动态部分

对于 vivo 双文件 Live Photo：

```text
IMG_xxx.jpg
IMG_xxx.mp4
```

LiveKit 会把它们识别为同一张 Live Photo。清理动态部分时，会保留 JPG/JPEG，处理对应 MP4。

对于标准 JPEG Motion Photo：

```text
motion_photo.jpg
```

LiveKit 会读取文件内的 Motion Photo 元数据，校验内嵌视频的位置和大小。只有验证通过时，才允许清理动态部分。

### 像相册一样浏览

- 全部 / Live / 回收站 Tab
- 首页时间线：今天、昨天、一周内、按月分组
- 合集页面：按相册目录分类
- 合集内部支持全部 / Live 分类
- 右侧自定义滚动条
- 滚动时显示当前日期位置
- 首页缩略图懒加载和小体积缓存

### 详情页查看和播放

- 点击照片进入详情页
- 左右滑动切换照片
- 相邻照片预加载，减少滑动转圈
- 双击 / 双指缩放
- 放大后的边界切页手势
- 长按或点击播放按钮播放 Live 动态视频
- 查看日期、大小、路径、EXIF、GPS 信息

### 分享、EXIF 和回收站

- 单张分享
- 多选批量分享
- 查看和编辑 EXIF
- 快捷清除敏感 EXIF 信息
- GPS 同时显示地名和数字坐标
- 应用内回收站、恢复、永久删除

## 如何安装

普通用户建议直接从 GitHub Releases 下载发布版 APK：

```text
https://github.com/shanye-xia/live-manager/releases
```

v0.2.0 发布包：

```text
LiveKit-v0.2.0-arm64-v8a.apk
LiveKit-v0.2.0-universal.apk
```

优先下载小包：

```text
LiveKit-v0.2.0-arm64-v8a.apk
```

它适合绝大多数近几年的 Android 手机，体积更小。

如果小包无法安装，再下载通用包：

```text
LiveKit-v0.2.0-universal.apk
```

通用包体积更大，但兼容更多 CPU 架构。

安装步骤：

1. 在手机上打开 Releases 页面，或先在电脑下载 APK 再发送到手机。
2. 点击 APK 安装。
3. 如果系统提示禁止安装未知来源应用，按系统提示允许当前浏览器或文件管理器安装 APK。
4. 打开 LiveKit，授予照片和视频读取权限。

如果只是使用软件，不需要安装 Flutter，也不需要使用 ADB。

## 如何使用

### 1. 首次打开

首次打开会请求照片和视频读取权限。请允许权限，否则应用无法扫描相册。

授权后应用会开始扫描照片。以后再次打开时，会优先显示上次扫描快照，再在后台刷新最新数据。

### 2. 浏览 Live Photo

首页包含：

- `全部`：显示普通照片和 Live Photo
- `Live`：只显示识别出的 Live Photo / Motion Photo
- `合集`：按相册目录分类浏览
- `回收站`：查看应用内删除的内容

带 `LIVE` 标识的照片表示检测到了动态部分。

### 3. 播放 Live

进入详情页后：

```text
长按图片或点击播放按钮 -> 播放动态视频
松手或再次点击 -> 回到静态照片
```

### 4. 清理动态部分

在详情页或多选操作中选择删除 Live 动态部分。

LiveKit 会根据格式执行不同策略：

- vivo 双文件：保留 JPG/JPEG，处理同名 MP4
- JPEG Motion Photo：验证通过后移除内嵌动态视频标记和视频尾部数据

清理后照片仍保留，只是不再具有动态效果。

## 安全和隐私

LiveKit 全程本地运行：

- 不上传照片
- 不需要账号
- 不依赖服务器
- 不做云同步
- 不主动删除任何数据

删除、清理、永久删除都需要用户主动操作。未知格式默认跳过，不冒险处理。

## 缓存说明

为了保证浏览流畅，应用会使用少量缓存：

- 首页缩略图会落盘缓存
- 缩略图缓存上限 100MB
- 超过上限后按最近使用时间淘汰
- 详情页大图优先直读系统相册真实路径
- Live 视频优先直读系统相册真实路径
- 大图和视频不做长期副本缓存

缓存只用于加速显示，不是用户原始照片。

## 当前限制

v0.2.0 已经开始支持标准 JPEG Motion Photo，但 Android 厂商实现差异很大，仍可能存在不支持的机型和格式。

暂不完整支持：

- HEIC / HEIF Motion Photo 清理
- 部分厂商私有 Motion Photo 变体
- 所有系统文件管理器的精确定位跳转

## 开发者命令

检查：

```powershell
flutter analyze
flutter test
```

构建小包和通用包：

```powershell
flutter build apk --release --split-per-abi
flutter build apk --release
```

构建产物对应关系：

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk -> LiveKit-v0.2.0-arm64-v8a.apk
build/app/outputs/flutter-apk/app-release.apk           -> LiveKit-v0.2.0-universal.apk
```

## 文档

- [project.md](project.md)：产品定位与当前范围
- [ROADMAP.md](ROADMAP.md)：版本路线
- [docs/v0.2-motion-photo-plan.md](docs/v0.2-motion-photo-plan.md)：Motion Photo 兼容设计
- [CHANGELOG.md](CHANGELOG.md)：版本变更记录

## License

[MIT License](LICENSE)
