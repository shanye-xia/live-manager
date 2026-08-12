# Live Manager 路线图

当前发布版本：`v0.1.0`

## v0.1：vivo Live Photo 管理器

状态：发布准备完成。

目标：稳定支持 vivo 传统 Live Photo 双文件结构，并提供接近系统相册的浏览与管理体验。

### 已完成

- Flutter + Kotlin 原生桥接
- Android 媒体权限处理
- MediaStore 扫描
- vivo JPG + MP4 同名同目录配对
- 全部 / Live / 回收站 Tab
- 时间线分组：今天 / 昨天 / 一周内 / 月份
- 首页缩略图懒加载缓存
- 缩略图磁盘缓存上限 100MB
- 启动读取扫描快照，后台继续扫描
- 合集页面
- 合集内全部 / Live 分类
- 详情页左右滑动、缩放、预加载相邻图片
- 长按播放 Live 视频
- 单张分享、多选分享
- 删除整张照片
- 删除 Live 动态部分
- 应用回收站、恢复、永久删除
- EXIF 查看
- EXIF 编辑
- 敏感 EXIF 清除
- GPS 地名和数字坐标展示
- 路径展示与文件管理器跳转尝试

### v0.1 限制

- Live Photo 格式主要支持 vivo 双文件结构
- Google / Pixel / 小米 / OPPO / 三星等单文件 Motion Photo 尚未完整支持
- HEIC / HEIF Motion Photo 暂不清理
- 文件管理器跳转只能尽量打开目录，无法保证所有系统都定位到具体文件

## v0.1.x：稳定性修复

目标：只做低风险修复，不扩大功能范围。

候选项：

- 继续优化首页缩略图加载稳定性
- 修复具体机型上的文件管理器跳转兼容问题
- 优化 EXIF 编辑输入体验
- 修复回收站和批量操作边界问题
- 清理已废弃代码和文案
- 补充回归测试

## v0.2：通用 Live Photo 检测架构

目标：把检测逻辑从 vivo 专用配对升级为协议检测链。

计划架构：

```text
LivePhotoDetectorChain
├── VivoLegacyPairDetector
├── GoogleMotionPhotoV2Detector
├── GoogleMicroVideoV1Detector
├── OppoOnePlusMotionPhotoDetector
├── HeicMotionPhotoDetector
└── EmbeddedMp4FallbackDetector
```

设计原则：

- 不按手机品牌硬编码
- 优先按文件结构和 metadata 判断协议
- 只有强校验通过才允许处理
- 弱匹配只在检测页展示，不进入清理流程
- 未知格式安全跳过

### v0.2 重点任务

1. 抽象统一模型

```kotlin
LivePhotoProtocol
LivePhotoDetection
LivePhotoDetector
```

2. 将当前 vivo 配对逻辑迁移为：

```text
VivoLegacyPairDetector
```

3. 增加 Developer / Live Photo Inspector 页面

用于手动选择文件并查看：

- MIME
- 文件大小
- 协议
- 置信度
- motion offset
- motion size
- 是否可提取
- 是否可安全清理
- 错误原因

4. 支持标准 JPEG Motion Photo 检测

优先支持：

- Google Motion Photo V2
- Google MicroVideo V1

5. 建立测试样本体系

```text
testdata/
├── synthetic/
├── vivo/
├── pixel/
├── xiaomi/
├── oppo/
├── samsung/
├── huawei/
└── honor/
```

## v0.3：Motion Photo 提取与静态副本

目标：在不破坏原图的前提下处理单文件 Motion Photo。

计划能力：

- 提取 Motion Photo 内嵌视频
- 生成静态副本
- 校验副本：
  - 图片可打开
  - 分辨率一致
  - Orientation 一致
  - 文件大小变小
  - 不再识别为 Live
  - 不重新压缩 JPEG
  - 尽量保留 EXIF / HDR 等重要信息

安全策略：

```text
原图不动
先生成静态副本
验证成功后再提示用户
```

## 长期方向

- 收集真实 OEM Live Photo 样本
- 按协议逐步扩展，不按品牌猜测
- 支持更多 Android Motion Photo 变体
- 增强批量处理能力
- 增强回收站和恢复能力
- 持续优化大图库性能

## 核心原则

```text
安全性 > 正确性 > 支持数量
```

宁可不处理未知格式，也不能误删或破坏用户照片。