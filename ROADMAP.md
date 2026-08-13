# LiveKit 路线图

当前发布版本：`v0.2.0`

LiveKit 的长期目标是做一个安全、轻量、面向 Android Live Photo / Motion Photo 的本地管理工具。

核心原则：

```text
安全性 > 正确性 > 支持数量
```

未知格式宁可跳过，也不冒险处理用户照片。

## v0.1：vivo 双文件 Live Photo 管理

状态：已发布。

目标：稳定支持 vivo 传统 Live Photo 双文件结构，并提供接近系统相册的浏览和管理体验。

已完成：

- MediaStore 扫描
- vivo JPG/JPEG + 同名 MP4 配对
- 全部 / Live / 回收站 Tab
- 首页时间线分组
- 合集页面
- 详情页左右滑动、缩放、播放
- 删除 Live 动态部分
- 应用内回收站
- 分享和 EXIF 操作
- 缩略图懒加载缓存

## v0.2：Motion Photo 检测链和 JPEG Motion Photo 支持

状态：已发布。

目标：从 vivo 专用配对逻辑升级为可扩展检测链，并开始支持标准 JPEG Motion Photo。

已完成：

- `LivePhotoDetector` 检测链
- `VivoLegacyPairDetector`
- `GoogleMotionPhotoDetector`
- Motion Photo XMP 元数据解析
- 内嵌 MP4 尾部数据校验
- Motion Photo 动态视频提取播放
- Motion Photo 动态部分清理
- 合成测试样本和测试工具
- 首页和详情页加载体验优化

## v0.2.x：稳定性和兼容性修复

目标：围绕 v0.2.0 做低风险修复，不大幅扩展功能范围。

候选任务：

- 收集更多 vivo 新机型 Motion Photo 样本
- 修复具体机型上的 Motion Photo 检测差异
- 优化首页缩略图加载队列
- 优化详情页大图预加载
- 优化 EXIF 写入后的时间显示问题
- 改进批量授权和批量清理体验
- 补充回归测试

## v0.3：更多厂商 Motion Photo 适配

目标：在安全验证前提下扩展更多 Android 厂商格式。

计划支持：

- Google / Pixel Motion Photo 更多变体
- OPPO / OnePlus Motion Photo
- 小米 Motion Photo
- Samsung Motion Photo
- Huawei / Honor Live Photo
- HEIC / HEIF 动态照片识别

计划能力：

- 开发者检测页 / Live Photo Inspector
- 手动选择文件分析协议
- 显示 MIME、文件大小、协议、置信度、offset、video size、错误原因
- 弱匹配只展示，不进入清理流程

## 长期方向

- 收集真实 OEM Live Photo 样本
- 按文件结构和 metadata 判断协议，不按品牌猜测
- 提高批量处理能力
- 增强回收站和恢复能力
- 持续优化大图库滚动性能
- 保持应用本地运行和隐私友好
