# LiveKit

LiveKit 是一个本地运行的 Android Live Photo 管理工具。

它解决的问题很直接：很多 Android 手机的 Live Photo 实际由“静态照片 + 动态视频”组成，但第三方相册经常把它们拆成一张 JPG 和一个 MP4，浏览和清理都不方便。LiveKit 会把它们重新识别成一张 Live Photo，让你像在系统相册里一样查看、播放、分享和管理动态部分。

当前版本：`v0.1.0`

APK 版本：`versionName 0.1.0`，`versionCode 1`

## 适合谁使用

v0.1 主要适合 vivo 用户，尤其是照片目录里存在这种结构的 Live Photo：

```text
IMG_xxx.jpg
IMG_xxx.mp4
```

也就是：同一个目录下，静态 JPG/JPEG 和动态 MP4 文件名相同，只是扩展名不同。

示例：

```text
DCIM/Camera/IMG_20260813_120000.jpg
DCIM/Camera/IMG_20260813_120000.mp4
```

LiveKit 会把它们显示成一张 Live Photo，而不是两个独立文件。

## 现在能做什么

### 浏览照片

- 按时间线浏览照片
- 支持全部 / Live / 回收站三个页面
- 支持今天、昨天、一周内、月份分组
- 支持合集页面，类似传统相册分类
- 支持右侧滚动条快速跳转
- 滚动时显示当前日期，方便定位照片

### 查看 Live Photo

- 点击照片进入详情页
- 左右滑动切换照片
- 双击或双指缩放大图
- 长按播放 Live 动态视频
- 松手后回到静态照片
- 相邻照片会预加载，减少切换等待

### 查看照片信息

详情页可以查看：

- 日期时间
- 文件大小
- 图片大小
- Live 动态视频大小
- 文件路径
- EXIF 信息
- GPS 地名
- GPS 数字坐标

### 分享

- 分享单张照片
- 多选后批量分享
- 调用 Android 系统分享面板

### 管理 Live 动态部分

对于 vivo 双文件 Live Photo：

```text
删除 Live 动态部分 = 处理对应 MP4
静态 JPG 会保留
```

也就是说，你可以把 Live Photo 变成普通静态照片，用来释放动态视频占用的空间。

### 回收站

应用内提供回收站能力：

- 删除后可以在应用回收站里查看
- 可以恢复
- 可以永久删除

永久删除不可恢复，操作前需要再次确认。

### EXIF

支持：

- 查看 EXIF
- 编辑常见 EXIF 字段
- 展开高级 EXIF 字段
- 清除敏感 EXIF 信息
- 多选批量清除敏感信息

## 如何安装

普通用户建议直接从 GitHub Releases 下载发布版 APK。

发布页：

```text
https://github.com/shanye-xia/live-manager/releases
```

v0.1.0 会提供两个安装包：

```text
livekit-v0.1.0-arm64-v8a.apk
livekit-v0.1.0-universal.apk
```

优先下载小包：

```text
livekit-v0.1.0-arm64-v8a.apk
```

它适合绝大多数近几年的 Android 手机，体积更小。

如果小包无法安装，再下载通用包：

```text
livekit-v0.1.0-universal.apk
```

通用包体积更大，但兼容更多 CPU 架构。

安装步骤：

1. 在手机上打开 Releases 页面，或先在电脑下载 APK 再发送到手机。
2. 点击 APK 安装。
3. 如果系统提示“禁止安装未知来源应用”，按系统提示允许当前浏览器或文件管理器安装 APK。
4. 安装完成后打开 LiveKit，并授予照片和视频读取权限。

如果你只是使用软件，不需要自己运行 Flutter，也不需要使用 ADB。

## 如何使用

### 1. 首次打开

首次打开会请求照片和视频读取权限。

请允许权限，否则应用无法扫描相册。授权后应用会开始扫描照片；以后再次打开时，会优先显示上次扫描快照，再后台刷新最新数据。

### 2. 浏览 Live Photo

进入首页后：

- `全部`：显示普通照片和 Live Photo
- `Live`：只显示识别出的 Live Photo
- `合集`：按相册目录分类浏览
- `回收站`：查看应用内删除的内容

有 `LIVE` 标识的照片表示检测到了动态部分。

### 3. 播放 Live

点击照片进入详情页后：

```text
长按图片 → 播放动态视频
松手 → 回到静态照片
```

### 4. 清理 Live 动态部分

在详情页或多选操作中选择删除 Live 动态部分。

v0.1 对 vivo 双文件 Live Photo 的处理方式是：

```text
保留 JPG
处理同名 MP4
```

这样照片仍然保留，只是不再有动态效果。

### 5. 恢复或永久删除

如果内容进入应用回收站，可以在回收站中：

- 恢复
- 永久删除

永久删除后无法恢复。

## 安全和隐私

LiveKit 全程本地运行：

- 不上传照片
- 不需要账号
- 不依赖服务器
- 不做云同步
- 不主动删除任何数据

删除、清理、永久删除都需要用户主动操作。

v0.1 不会直接修改单文件 Motion Photo，也不会尝试破解未知格式。未知格式宁可跳过，也不冒险处理。

## 缓存说明

为了保证浏览流畅，应用会使用缓存：

- 首页缩略图会落盘缓存
- 缩略图缓存上限 100MB
- 超过上限后按最近使用时间淘汰
- 详情页大图优先直接读取系统相册真实路径
- Live 视频优先直接读取系统相册真实路径
- 大图和视频不会额外复制一份长期缓存

缓存只用于加速显示，不是用户原始照片。

## 当前限制

v0.1 主要支持 vivo 双文件 Live Photo。

暂不完整支持：

- Google / Pixel 单文件 Motion Photo
- 小米 Motion Photo
- OPPO / OnePlus Motion Photo
- Samsung Motion Photo
- Huawei / Honor Live Photo
- HEIC / HEIF 动态照片清理

后续版本会升级为通用协议检测链，不按品牌硬编码，而是按文件结构和 metadata 判断 Live Photo 格式。

## 后续计划

二期目标是支持更多 Android Live Photo / Motion Photo 格式。

计划检测链：

```text
LivePhotoDetectorChain
├── VivoLegacyPairDetector
├── GoogleMotionPhotoV2Detector
├── GoogleMicroVideoV1Detector
├── OppoOnePlusMotionPhotoDetector
├── HeicMotionPhotoDetector
└── EmbeddedMp4FallbackDetector
```

原则：

```text
安全性 > 正确性 > 支持数量
```

只有当 metadata、offset、video size 和视频结构都验证通过时，才允许进入可处理流程。未知格式只检测，不清理。

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
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  -> livekit-v0.1.0-arm64-v8a.apk
build/app/outputs/flutter-apk/app-release.apk            -> livekit-v0.1.0-universal.apk
```

调试包只用于开发，不建议发布：

```powershell
flutter build apk --debug
```

## 文档

- [project.md](project.md)：产品定位与 v0.1 范围
- [ROADMAP.md](ROADMAP.md)：版本路线
- [todo](todo)：二期 Live Photo 兼容方案
- [CHANGELOG.md](CHANGELOG.md)：版本变更记录

## License

[MIT License](LICENSE)
