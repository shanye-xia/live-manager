# Live Manager 实现路线

> 依据 `project.md`（Vivo Live Photo 管理工具 MVP）与当前开发环境制定。

## 1. 环境检查结论

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Flutter | ✅ 3.44.8 stable | `D:\develop\flutterSDK\flutter`，Dart 3.12.2 |
| Android SDK | ✅ 37.0.0 | platform android-37.0，build-tools 36/37，licenses 已接受 |
| Java | ✅ JDK 25（Android Studio JBR） | 同时存在系统 JDK 17 |
| 真机 | ✅ vivo V2419A，Android 16（API 36），arm64 | 已连接：`10AF6G27JE007SC` |
| VS Code / VS2022 | ✅ | 桌面/Web 通道可选 |
| Gradle | ⚠️ 未单独安装 | 使用 Flutter 项目自带 Gradle Wrapper，无需全局安装 |
| 网络 | ⚠️ 已设 `HTTP_PROXY` 但无 `NO_PROXY`；GitHub 握手告警 | 若 `pub get` / Gradle 下载失败，先处理代理再继续 |

## 2. 总体架构

```
Flutter UI（网格 / 长按播放 / 详情 / 删除）
        │
        │  MethodChannel（live_manager）
        ▼
Kotlin 原生层
  ├─ 权限（READ_MEDIA_IMAGES / READ_MEDIA_VIDEO）
  ├─ MediaStore 扫描 + Live Photo 配对
  ├─ 缩略图生成与缓存
  ├─ EXIF 读取（ExifInterface）
  └─ 删除（MediaStore.createDeleteRequest → 系统回收站）
```

## 3. 分阶段实施计划

### Phase 0：脚手架与真机联调

- [x] `flutter create` 初始化项目（package `live_manager`，applicationId `com.livemanager.live_manager`）
- [x] SDK 版本沿用 Flutter 3.44.8 模板默认值（minSdk/targetSdk/compileSdk 随模板）；应用名改为 `Live Manager`
- [x] `pub get` 与首次 Gradle 构建成功（Debug APK `build/app/outputs/flutter-apk/app-debug.apk`）
- [x] 在真机 V2419A 上安装并启动成功（截图归档于 `build/phase0_bridge_check.png`）
- [x] MethodChannel 骨架 + 冒烟测试：`ping` 返回机型/系统/SDK 信息，真机 UI 显示“原生桥接已连通”

> Phase 0 完成于 2026-08-05。备注：项目目录尚未初始化 git 仓库（建议 `git init` 后提交基线）。

### Phase 1：原生层核心能力（Kotlin）

- [x] 权限申请：API 33+ 用 `READ_MEDIA_IMAGES` + `READ_MEDIA_VIDEO`；API ≤ 32 用 `READ_EXTERNAL_STORAGE`
- [x] MediaStore 扫描全部媒体，按“目录 + 去扩展名文件名”建立索引
- [x] Live Photo 配对规则：
  - 同名 `.jpg` + `.mp4`（仅扩展名不同）
  - 同一目录
  - MP4 时长 < 5 秒（阈值做成常量）
  - 输出 `LivePhoto{ imageUri, videoUri, createTime, imageSize, videoSize }`
- [x] 缩略图：原生 `loadThumbnail` → 缓存到应用缓存目录（API 24-28 有解码降级）
- [x] EXIF 读取：相机型号、焦距、ISO、快门、曝光补偿、GPS 坐标
- [x] 删除：`MediaStore.createDeleteRequest`（API 30+）→ 系统回收站，保留 JPG
  - ⚠️ 代码完成但**未在真机触发**；低版本直接删除路径已移除（返回 unsupported）
  - 验证删除前必须经用户明确确认（用户要求：不删除手机任何数据）
- [ ] 目录变更监听（ContentObserver）→ 后续版本

### Phase 2：Flutter 数据层

- [x] `LivePhoto` 模型（fromJson/toJson + 序列化单元测试）+ `LivePhotoPlatformService` 通道封装
- [x] 状态管理：`HomeViewModel extends ChangeNotifier`（MVVM 分层，无重依赖）
- [x] 数据仓库：`MediaStoreLivePhotoRepository`（权限 → 扫描 → 模型映射；缩略图 Future 记忆化）
- [x] 权限与空状态处理（拒绝权限引导、空列表提示、下拉刷新）

### Phase 3：UI / 交互（MVP 全部页面）

- [x] 首页：照片网格（自适应列数、LIVE 角标、不显示 MP4、单条目展示）
- [x] 顶部汇总：共 N 张 Live 图片、总占用空间
- [ ] 长按预览：默认静态图 → `video_player` 播放 content:// 视频 → 松手停止并回静态图；无控制栏、不跳播放器
- [ ] 详情页：大图 + 文件名 / 拍摄时间 / 图片大小 / 视频大小 / 总计 + EXIF 信息
- [ ] 删除流程：入口 → 系统确认（回收站）→ 成功提示 → 列表刷新；错误/取消状态处理

> Phase 1/Phase 2 完成于 2026-08-05；真机验证：2166 张 Live 图片、21.97 GB，网格渲染正常
> （截图归档于 `build/phase2_grid.png`）。

### Phase 4：性能、边界与验收

- [ ] 性能：几千张照片滚动流畅（GridView `cacheExtent`、缩略图缓存、异步加载）；长按播放预加载优化
- [ ] 边界用例：
  - 同名但不同目录（不应配对）
  - 只有 JPG / 只有 MP4（不展示为 Live，可后续提示）
  - MP4 时长 ≥ 5 秒（不配对）
  - 拍摄时间缺失 / EXIF 缺失（容错显示）
  - 删除时用户取消 / 系统拒绝
- [ ] 按 `project.md` 第 12 节验收标准逐条测试（识别 → 浏览 → 长按播放 → 删除进回收站 → EXIF）
- [ ] 打包 Debug / Release APK，安装到 V2419A 实机回归

## 4. 关键决策记录

- **长按播放**：用 `video_player` 播放 `content://` URI，避免引入重型原生视频组件；若真机卡顿再改原生 PlatformView。
- **删除进回收站**：`createDeleteRequest` 带系统确认框，天然满足“恢复/永久删除”，且不误删 JPG。
- **不引入相册类三方库**（如 photo_manager）：配对逻辑是核心价值，原生实现更可控，依赖更少。
- **EXIF GPS 反查地名**（“上海”）属增强项：MVP 先显示原始坐标，避免依赖网络定位服务。

## 5. 风险与预案

| 风险 | 预案 |
| --- | --- |
| 代理导致 `pub get` / Gradle 下载失败 | 设置 `NO_PROXY` 覆盖本地/内网地址；必要时手动配置 Gradle 镜像 |
| GitHub 握手异常 | 排查代理证书/环境变量，优先使用 Flutter 官方镜像源 |
| vivo 机型对 `createDeleteRequest` 的兼容性 | 在 V2419A 实测；异常时降级为 `contentResolver.delete`（直删，标注不可恢复） |
| 几千张照片扫描慢 | MediaStore 投影只取必要列；扫描异步 + 首次进度提示 |
