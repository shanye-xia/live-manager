# Live Manager

针对 **vivo Live Photo 双文件结构**（`IMG_xxx.jpg` + `IMG_xxx.mp4` 同名同目录）的轻量级 Android 管理工具。

正确识别 JPG + MP4 配对关系，以「一张 Live 图片」为单位浏览与管理，而不是把图片和视频当成两个独立媒体。

## 功能（当前进度）

- ✅ 自动扫描并识别 Live 图片（同名同目录配对，MP4 时长 < 5 秒）
- ✅ 首页网格浏览（自适应列数、LIVE 角标、数量与占用空间汇总、下拉刷新）
- ✅ 原生缩略图生成与缓存
- ✅ 详情页大图 + 长按播放动态效果（松手停止、无控制栏）
- ✅ EXIF 信息展示（相机、焦距、ISO、快门、曝光、GPS）
- 🚧 删除流程入口（进行中）

## 技术栈

- Flutter（UI / 状态管理 MVVM）
- Kotlin 原生层（MediaStore、EXIF、系统回收站），通过 MethodChannel/EventChannel 桥接
- 本地运行，不上传任何数据，无需账号与服务器

## 项目结构

```text
lib/
├── data/
│   ├── models/          # 领域数据模型（LivePhoto）
│   ├── repositories/    # 数据仓库（MediaStore 桥接）
│   └── services/        # MethodChannel / EventChannel 封装
├── domain/models/       # 纯领域模型
└── ui/
    ├── core/            # 共享组件与主题
    └── features/home/   # 首页（views / view_models）
```

## 构建与运行

```bash
flutter pub get
flutter run -d <device-id>
```

测试与检查：

```bash
flutter analyze
flutter test
```

## 安全说明

应用全程本地运行。删除功能仅通过系统回收站确认框执行，且不会删除 JPG 静态照片；开发调试中未经用户确认不会触发任何删除。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

## 路线图

见 [ROADMAP.md](ROADMAP.md)。产品需求见 [project.md](project.md)。
