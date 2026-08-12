# Live Manager 产品说明

当前版本：`v0.1.0`

## 1. 产品定位

Live Manager 是一个面向 Android Live Photo 的本地相册管理工具。

v0.1 的核心目标是稳定支持 vivo 传统 Live Photo 双文件格式：

```text
IMG_xxx.jpg
IMG_xxx.mp4
```

应用把 JPG 和对应 MP4 作为一张 Live Photo 展示和管理，避免第三方相册把照片和动态视频拆开显示。

## 2. 不做什么

Live Manager 当前不是：

- 完整相册替代品
- 云相册
- 图片编辑器
- 视频编辑器
- 在线同步工具

v0.1 的重点是：

```text
正确识别 Live Photo
提供流畅浏览体验
安全管理动态部分
保护用户原始照片
```

## 3. v0.1 支持范围

### 3.1 支持的 Live 格式

vivo 双文件格式：

```text
同目录
同基础文件名
JPG/JPEG + MP4
MP4 时长小于 Live 阈值
```

示例：

```text
DCIM/Camera/IMG_001.jpg
DCIM/Camera/IMG_001.mp4
```

### 3.2 暂不支持的格式

v0.1 暂不完整支持：

- Google / Pixel Motion Photo 单文件
- 小米 Motion Photo
- OPPO / OnePlus Motion Photo
- Samsung Motion Photo
- Huawei / Honor Live Photo
- HEIC / HEIF 单文件动态照片清理

这些会进入二期协议检测架构。

## 4. v0.1 核心功能

### 4.1 首页时间线

- 全部照片浏览
- Live 照片筛选
- 回收站入口
- 今天 / 昨天 / 一周内 / 月份分组
- 滚动时显示当前时间位置
- 自定义右侧滚动条
- 缩略图懒加载缓存

### 4.2 合集

- 按相册目录分类
- 同名合集合并
- 合集封面
- 合集内全部 / Live 分类
- 当前合集数量和大小统计

### 4.3 详情页

- 高清图片查看
- 左右滑动切换
- 相邻图片预加载
- 双击缩放
- 双指缩放
- 放大后边界切页
- 长按播放 Live 视频
- 点击隐藏 / 显示 UI

### 4.4 信息与 EXIF

- 显示文件名、日期、大小、路径
- 显示图片大小、动态视频大小、总大小
- 显示常见 EXIF
- GPS 支持地名和数字坐标
- 路径可尝试跳转文件管理器
- 支持编辑 EXIF 常见字段
- 高级 EXIF 字段折叠显示
- 支持清除敏感 EXIF 信息

### 4.5 分享与删除

- 单张分享
- 多选批量分享
- 删除整张照片
- 删除 Live 动态部分
- 应用内回收站
- 回收站恢复
- 回收站永久删除

## 5. 安全要求

所有危险操作必须遵守：

- 用户未确认，不删除任何真实手机数据
- 删除整张照片或永久删除必须二次确认
- 删除 Live 动态部分时，vivo 双文件只处理 MP4，保留 JPG
- 后续单文件 Motion Photo 不直接覆盖原图，优先生成静态副本
- 未知格式不执行清理

## 6. 性能要求

v0.1 以真实滑动体验为优先：

- 首页缩略图懒生成
- 缩略图磁盘缓存上限 100MB
- 大图和视频优先直读系统路径
- 启动优先显示上次扫描快照
- 后台扫描更新数据
- 避免全库启动预热

## 7. APK 版本

v0.1 发布包使用：

```text
versionName: 0.1.0
versionCode: 1
```

对应 Flutter：

```text
version: 0.1.0+1
```

## 8. 二期产品目标

二期目标是从 vivo 专用工具升级为通用 Android Live Photo 管理器。

核心不是“按品牌判断”，而是“按协议判断”：

```text
文件结构
+ metadata
+ offset/size 合法性
+ 视频结构校验
```

计划支持：

- vivo 双文件协议
- Google Motion Photo V2
- Google MicroVideo V1
- OPPO / OnePlus 扩展协议
- HEIC Motion Photo 识别
- 未知嵌入式 MP4 安全检测

二期仍然坚持：

```text
安全性 > 正确性 > 支持数量
```