import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';
import '../../../core/exif_clear_options.dart';
import '../../../core/formatters.dart';
import '../view_models/detail_view_model.dart';

/// 详情页：相册式分页浏览（左右滑动切换）+ 长按播放 + 单击隐藏 UI。
/// Live 图删除时的两个选项。
enum _LiveDeleteAction { videoOnly, fullDelete }

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.repository,
    required this.thumbnailLoader,
    required this.onDelete,
    this.thumbnailPath,
  });

  final List<PhotoItem> items;
  final int initialIndex;
  final LivePhotoRepository repository;
  final Future<String> Function(PhotoItem item) thumbnailLoader;
  final void Function(int imageId, bool videoOnly) onDelete;
  final String? thumbnailPath;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  static const int _balancedPrefetchRadius = 4;
  static const int _directionalForwardPrefetch = 8;
  static const int _directionalBackPrefetch = 1;

  late final PageController _pageController;
  late List<PhotoItem> _items;
  late int _currentIndex;
  bool _uiVisible = true;
  bool _pageDragActive = false;
  double _pageDragBase = 0;
  double _lastPageDragDx = 0;
  final Map<int, Future<void>> _prefetchJobs = {};
  Future<void> _prefetchQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAround(_currentIndex, direction: 0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            pageSnapping: false,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return _PhotoPage(
                key: ValueKey(item.imageId),
                item: item,
                repository: widget.repository,
                thumbnailPath: index == widget.initialIndex
                    ? widget.thumbnailPath
                    : null,
                thumbnailFuture: widget.thumbnailLoader(item),
                uiVisible: _uiVisible,
                positionText: '${index + 1} / ${_items.length}',
                onToggleUi: () => setState(() => _uiVisible = !_uiVisible),
                onPageDragStart: _startPageDrag,
                onPageDrag: _updatePageDrag,
                onPageDragEnd: _endPageDrag,
                onPageDragCancel: _cancelPageDrag,
                onDeleted: (videoOnly) => _handleDeleted(index, videoOnly),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 页面翻页手势：开始/跟手/取消/松手停靠。
  /// 由图片手势层驱动（PageView 自身不参与手势竞争，避免捏合被误判为翻页）。
  void _startPageDrag() {
    if (!_pageController.hasClients || _pageDragActive) return;
    final pixels = _pageController.position.pixels;
    _pageController.jumpTo(pixels);
    _pageDragActive = true;
    _pageDragBase = pixels;
    _lastPageDragDx = 0;
  }

  void _updatePageDrag(double dx) {
    if (!_pageController.hasClients) return;
    if (!_pageDragActive) _startPageDrag();
    _prefetchForDrag(dx);
    _lastPageDragDx = dx;
    final pos = _pageController.position;
    final target = (_pageDragBase - dx).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _pageController.jumpTo(target);
  }

  /// 第二根手指落下等需要放弃翻页时：页面回到手势开始的位置。
  void _cancelPageDrag() {
    if (!_pageController.hasClients || !_pageDragActive) return;
    _pageDragActive = false;
    _pageController.jumpTo(_pageDragBase);
  }

  /// 松手：速度快或滑过一半则停靠到相邻页，否则弹回当前页。
  void _endPageDrag(double velocityX) {
    if (!_pageController.hasClients) return;
    _pageDragActive = false;
    final pos = _pageController.position;
    final viewport = pos.viewportDimension;
    if (viewport <= 0) return;
    final fraction = pos.pixels / viewport;
    final lower = fraction.floor().clamp(0, _items.length - 1);
    final progress = fraction - lower;
    int target;
    if (velocityX.abs() > 500) {
      target = (lower + (velocityX < 0 ? 1 : 0)).clamp(0, _items.length - 1);
    } else if (progress > 0.5) {
      target = (lower + 1).clamp(0, _items.length - 1);
    } else {
      target = lower;
    }
    _pageController.animateToPage(
      target,
      duration: Duration(milliseconds: target == lower ? 160 : 240),
      curve: Curves.easeOutCubic,
    );
    final direction = target.compareTo(_currentIndex);
    _currentIndex = target;
    _prefetchAround(target, direction: direction);
  }

  void _handleDeleted(int index, bool videoOnly) {
    final item = _items[index];
    widget.onDelete(item.imageId, videoOnly);
    setState(() {
      if (videoOnly) {
        _items[index] = item.copyWith(
          isLive: false,
          videoId: null,
          videoUri: null,
          videoSize: null,
          videoDurationMs: null,
        );
      } else {
        _items.removeAt(index);
      }
    });
    if (!videoOnly && _items.isNotEmpty) {
      final target = index.clamp(0, _items.length - 1);
      _pageController.jumpToPage(target);
      _currentIndex = target;
      _prefetchAround(_currentIndex, direction: 0);
    }
    if (_items.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  void _prefetchForDrag(double dx) {
    if ((dx - _lastPageDragDx).abs() < 12) return;
    final direction = dx < 0 ? 1 : -1;
    _prefetchAround(_currentIndex, direction: direction);
  }

  void _prefetchAround(int index, {required int direction}) {
    if (direction == 0) {
      for (var step = 1; step <= _balancedPrefetchRadius; step++) {
        _prefetchIndex(index - step);
        _prefetchIndex(index + step);
      }
      return;
    }
    for (var step = 1; step <= _directionalForwardPrefetch; step++) {
      _prefetchIndex(index + direction * step);
    }
    for (var step = 1; step <= _directionalBackPrefetch; step++) {
      _prefetchIndex(index - direction * step);
    }
  }

  void _prefetchIndex(int index) {
    if (index < 0 ||
        index >= _items.length ||
        _prefetchJobs.containsKey(index)) {
      return;
    }
    final item = _items[index];
    final job = _prefetchQueue.then((_) => _loadPreviewIntoCache(item));
    _prefetchQueue = job.catchError((_) {});
    _prefetchJobs[index] = job;
  }

  Future<void> _loadPreviewIntoCache(PhotoItem item) async {
    try {
      await widget.thumbnailLoader(item);
    } catch (_) {
      // Thumbnail cache miss/failure should not block full preview warm-up.
    }
    if (!mounted) return;
    try {
      final path = await widget.repository.fullImagePathFor(item);
      if (!mounted || path.isEmpty) return;
      final width = MediaQuery.sizeOf(context).width;
      final targetWidth = (width * 2).round().clamp(1200, 2400);
      await precacheImage(
        ResizeImage(FileImage(File(path)), width: targetWidth),
        context,
      );
    } catch (_) {
      // Prefetch is opportunistic; the page will still load normally on demand.
    }
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    super.key,
    required this.item,
    required this.repository,
    this.thumbnailPath,
    this.thumbnailFuture,
    required this.uiVisible,
    required this.positionText,
    required this.onToggleUi,
    required this.onPageDragStart,
    required this.onPageDrag,
    required this.onPageDragEnd,
    required this.onPageDragCancel,
    required this.onDeleted,
  });

  final PhotoItem item;
  final LivePhotoRepository repository;
  final String? thumbnailPath;
  final Future<String>? thumbnailFuture;
  final bool uiVisible;
  final String positionText;
  final VoidCallback onToggleUi;
  final VoidCallback onPageDragStart;
  final ValueChanged<double> onPageDrag;
  final ValueChanged<double> onPageDragEnd;
  final VoidCallback onPageDragCancel;
  final ValueChanged<bool> onDeleted;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage>
    with SingleTickerProviderStateMixin {
  static const double _touchSlop = 18;

  /// photo_view ????????? 1.6s ???????????????????
  /// ???????????????????
  static const Duration _photoViewFlingGuard = Duration(milliseconds: 1650);

  late final DetailViewModel _viewModel;
  late final PhotoViewController _photoController;

  /// 当前按下的指针（被动监听，不参与手势竞争）。
  final Set<int> _activePointers = {};

  bool _pageDragging = false; // 1x 翻页已激活
  double _pageAccumDx = 0; // 未越过阈值时累计的横向位移
  double _pageTotalDx = 0; // 越过阈值后相对翻页起点的累计位移
  bool _edgeMode = false; // 放大后边界外推模式
  int _edgeDir = 0; // 外推方向：1=向右（上一张），-1=向左（下一张）
  double _edgeDx = 0;
  bool _pinchSession = false; // 本次触摸会话出现过双指：只缩放/平移，绝不翻页
  double _lastVx = 0; // 最近一次移动的横向速度（用于松手甩动判定）
  Duration _lastMoveStamp = Duration.zero;

  double _panSlopDx = 0; // 图片未移动时累计的手指横向位移

  bool _flingConsumed = false; // 本次手势的松手处理（切页/惯性）已执行
  bool _gestureStartLeftEdge = false; // 手势开始时是否已贴左边界（下一张侧）
  bool _gestureStartRightEdge = false; // 手势开始时是否已贴右边界（上一张侧）
  AnimationController? _inertiaController; // 放大后快速甩动的惯性动画
  double _inertiaFrom = 0;
  double _inertiaNaturalMs = 0; // ????????????????
  double _inertiaTo = 0;

  Size _viewport = Size.zero;
  Size? _imageSize;
  String? _resolvedKey;
  bool _originalReady = false; // full-res decode finished
  bool _warmingOriginal = false;

  @override
  void initState() {
    super.initState();
    _photoController = PhotoViewController();
    _viewModel = DetailViewModel(
      item: widget.item,
      repository: widget.repository,
      thumbnailPath: widget.thumbnailPath,
      thumbnailFuture: widget.thumbnailFuture,
    )..init();
  }

  @override
  void dispose() {
    _stopInertia();
    _photoController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        _maybeResolveImageSize();
        _maybeWarmOriginal();
        return Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                _viewport = Size(constraints.maxWidth, constraints.maxHeight);
                return _buildViewer();
              },
            ),
            AnimatedOpacity(
              opacity: widget.uiVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !widget.uiVisible,
                child: _buildOverlay(context),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Progressive: thumb -> screen-level preview -> original.
  /// Full-res decode of a huge photo is slow; show a 2x-screen preview first,
  /// then swap to full-res once _originalReady, so the user always sees a sharp image.
  ImageProvider _buildImageProvider() {
    final path = _viewModel.imagePath!;
    if (!_viewModel.fullImageReady || _originalReady) {
      return FileImage(File(path));
    }
    final targetWidth = (_viewport.width * 2).round().clamp(1200, 2400);
    return ResizeImage(FileImage(File(path)), width: targetWidth);
  }

  Widget _buildViewer() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: widget.item.isLive
            ? (_) => _viewModel.startPlayback()
            : null,
        onLongPressEnd: widget.item.isLive
            ? (_) => _viewModel.stopPlayback()
            : null,
        onLongPressCancel: widget.item.isLive ? _viewModel.stopPlayback : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_viewModel.loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_viewModel.imagePath == null)
              Center(
                child: Text(
                  '图片加载失败\n${_viewModel.error ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            else
              PhotoView(
                key: ValueKey(
                  'detail-photo-${widget.item.imageId}-'
                  '${_viewModel.imagePath}-$_originalReady',
                ),
                imageProvider: _buildImageProvider(),
                gaplessPlayback: true,
                controller: _photoController,
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: 5.0,
                scaleStateCycle: (state) {
                  switch (state) {
                    case PhotoViewScaleState.initial:
                      return PhotoViewScaleState.covering;
                    default:
                      return PhotoViewScaleState.initial;
                  }
                },
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                gestureDetectorBehavior: HitTestBehavior.opaque,
                onTapUp: (_, _, _) => widget.onToggleUi(),
                onScaleEnd: _onPhotoScaleEnd,
                errorBuilder: (_, _, _) => const Center(
                  child: Text(
                    '无法显示图片',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            if (_viewModel.isPlaying && _viewModel.videoReady)
              Center(
                child: AspectRatio(
                  aspectRatio: _viewModel.controller!.value.aspectRatio,
                  child: VideoPlayer(_viewModel.controller!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- 被动指针监听：1x 翻页 + 放大后边界外推 ----------

  void _onPointerDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    _lastMoveStamp = e.timeStamp;
    _lastVx = 0;
    _stopInertia();
    _flingConsumed = false;
    if (_activePointers.length == 1) {
      final range = _hRange;
      final dx = _photoController.position.dx;
      _gestureStartLeftEdge = range <= 0 || dx <= -range + 1.5;
      _gestureStartRightEdge = range <= 0 || dx >= range - 1.5;
      _panSlopDx = 0;
    }
    if (_activePointers.length >= 2) {
      // 第二根手指落下：本次触摸会话进入“捏合优先”，放弃翻页/外推，
      // 之后即使只剩一根手指也不再翻页，整段手势只缩放/平移。
      _pinchSession = true;
      _cancelPageGesture();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_activePointers.contains(e.pointer) || _pinchSession) {
      return; // 捏合会话：photo_view 处理缩放/平移，绝不动页面
    }
    if (_activePointers.length != 1) return;
    final rawDx = e.delta.dx;
    final rawDy = e.delta.dy;
    final dt = (e.timeStamp - _lastMoveStamp).inMicroseconds;
    if (dt > 0) _lastVx = rawDx / (dt / 1e6);
    _lastMoveStamp = e.timeStamp;

    final scale = _photoController.scale ?? _fitScale;

    // 1x（贴合屏幕）：单指横向拖动翻页。
    if (scale <= _fitScale * 1.02) {
      if (!_pageDragging) {
        _pageAccumDx += rawDx;
        if (_pageAccumDx.abs() <= _touchSlop) return;
        _pageDragging = true;
        if (kDebugMode) {
          debugPrint('[gesture] page-drag-start accum=$_pageAccumDx');
        }
        _pageTotalDx = _pageAccumDx > 0
            ? _pageAccumDx - _touchSlop
            : _pageAccumDx + _touchSlop;
        widget.onPageDragStart();
        widget.onPageDrag(_pageTotalDx);
      } else {
        _pageTotalDx += rawDx;
        widget.onPageDrag(_pageTotalDx);
      }
      return;
    }

    // 放大后：photo_view 负责平移图片；滑到图片边界继续外推才翻页。
    if (_edgeMode) {
      _edgeDx += rawDx;
      final backInside =
          (_edgeDir < 0 && rawDx > 0 && _edgeDx >= 0) ||
          (_edgeDir > 0 && rawDx < 0 && _edgeDx <= 0);
      if (backInside) {
        if (kDebugMode) {
          debugPrint(
            '[gesture] edge-back-inside dir=$_edgeDir rawDx=$rawDx edgeDx=$_edgeDx',
          );
        }
        _edgeMode = false;
        _edgeDir = 0;
        _edgeDx = 0;
        widget.onPageDragCancel();
      } else {
        widget.onPageDrag(_edgeDx);
      }
      return;
    }

    // 边界外推只允许“慢速/长按拖动”：推到图片真实边界继续推才切页。
    // 快速甩动不参与（松手后按惯性滑到边缘停住，再次在边缘快滑才切页），
    // 避免快速滑图片时被误判成切页。
    final posX = _photoController.position.dx;
    final range = _hRange;
    final atLeftEdge = range <= 0 || posX <= -range + 1.0;
    final atRightEdge = range <= 0 || posX >= range - 1.0;
    final horizontal = rawDx.abs() >= rawDy.abs() * 1.2;
    final fastFling = _lastVx.abs() > 900;
    final pushingOutward =
        (rawDx < 0 && atLeftEdge) || (rawDx > 0 && atRightEdge);

    if (horizontal && pushingOutward && !fastFling) {
      _panSlopDx += rawDx;
      if (_panSlopDx.abs() > 30) {
        _startEdgeMode(_panSlopDx > 0 ? 1 : -1, rawDx);
        return;
      }
    } else {
      _panSlopDx = 0;
    }
  }

  void _startEdgeMode(int dir, double rawDx) {
    if (kDebugMode) {
      debugPrint('[gesture] edge-start dir=$dir rawDx=$rawDx');
    }
    _edgeMode = true;
    _edgeDir = dir;
    _edgeDx = rawDx;
    widget.onPageDragStart();
    widget.onPageDrag(rawDx);
  }

  void _onPointerUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    if (_activePointers.isEmpty) {
      _pinchSession = false;
      // 手指停住超过 120ms 视为无速度，避免慢速拖拽被误判为甩动切页。
      if (e.timeStamp - _lastMoveStamp > const Duration(milliseconds: 120)) {
        _lastVx = 0;
      }
      _finishGesture(_lastVx);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    if (_activePointers.isEmpty) {
      _pinchSession = false;
      _finishGesture(0);
    }
  }

  void _cancelPageGesture() {
    if (_pageDragging) {
      _pageDragging = false;
      _pageAccumDx = 0;
      _pageTotalDx = 0;
      widget.onPageDragCancel();
    }
    if (_edgeMode) {
      _edgeMode = false;
      _edgeDir = 0;
      _edgeDx = 0;
      widget.onPageDragCancel();
    }
  }

  void _finishGesture(double velocityX) {
    if (_flingConsumed) return;
    if (_pageDragging) {
      _flingConsumed = true;
      _pageDragging = false;
      _pageAccumDx = 0;
      _pageTotalDx = 0;
      widget.onPageDragEnd(velocityX);
      return;
    }
    if (_edgeMode) {
      _flingConsumed = true;
      _edgeMode = false;
      _edgeDir = 0;
      _edgeDx = 0;
      widget.onPageDragEnd(velocityX);
      return;
    }
    if (_pinchSession) return;
    final scale = _photoController.scale ?? _fitScale;
    if (scale <= _fitScale * 1.02 || velocityX.abs() < 500) return;

    // 放大后的快速甩动：
    // - 手势开始时已贴边缘且结束时仍在边缘 → 切页（沿用速度停靠）；
    // - 否则只把图片按惯性滑到同方向边缘停住，不切页。
    _flingConsumed = true;
    final range = _hRange;
    final dx = _photoController.position.dx;
    final nowAtEdge =
        range <= 0 ||
        (velocityX < 0 && dx <= -range + 1.0) ||
        (velocityX > 0 && dx >= range - 1.0);
    final startAtEdge = velocityX < 0
        ? _gestureStartLeftEdge
        : _gestureStartRightEdge;
    if (startAtEdge && nowAtEdge) {
      if (kDebugMode) {
        debugPrint('[gesture] fling-edge-switch vx=$velocityX');
      }
      widget.onPageDragEnd(velocityX);
    } else {
      if (kDebugMode) {
        debugPrint('[gesture] fling-inertia vx=$velocityX');
      }
      _startInertia(velocityX);
    }
  }

  void _onPhotoScaleEnd(
    BuildContext context,
    ScaleEndDetails details,
    PhotoViewControllerValue value,
  ) {
    _finishGesture(details.velocity.pixelsPerSecond.dx);
  }

  /// 当前缩放级别下图片可横向平移的幅度（单侧）。
  double get _hRange {
    final img = _imageSize;
    if (img == null || img.isEmpty || _viewport == Size.zero) return 0;
    final scale = _photoController.scale ?? _fitScale;
    final contentW = img.width * scale;
    return math.max(0.0, (contentW - _viewport.width) / 2);
  }

  /// 放大后快速甩动：让图片沿甩动方向惯性滑到边缘停住（不切页）。
  void _startInertia(double velocityX) {
    final range = _hRange;
    if (range <= 0) return;
    final dx = _photoController.position.dx;
    final target = velocityX < 0 ? -range : range;
    final distance = (target - dx).abs();
    if (distance < 0.5) return;
    // ????? t = 2*d/v0??????????????????
    // easeOutQuad ????????????? easeOutCubic ?????
    final speed = velocityX.abs().clamp(600.0, 4500.0).toDouble();
    final ms = (2 * distance / speed * 1000)
        .round()
        .clamp(150, 1000)
        .toDouble();
    _stopInertia();
    _inertiaFrom = dx;
    _inertiaTo = target;
    _inertiaNaturalMs = ms;
    // ??? = ?????? + photo_view ?????????
    // ? ms ????????????????????? photo_view ??????
    _inertiaController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: ms.toInt() + _photoViewFlingGuard.inMilliseconds,
      ),
    );
    _inertiaController!.addListener(_onInertiaTick);
    _inertiaController!.forward();
  }

  void _onInertiaTick() {
    final totalMs = _inertiaController!.duration!.inMilliseconds;
    final progress = _inertiaController!.value * totalMs / _inertiaNaturalMs;
    final t = Curves.easeOutQuad.transform(progress.clamp(0.0, 1.0));
    final newDx = _inertiaFrom + (_inertiaTo - _inertiaFrom) * t;
    _photoController.position = Offset(newDx, _photoController.position.dy);
  }

  void _stopInertia() {
    _inertiaController?.stop();
    _inertiaController?.dispose();
    _inertiaController = null;
  }

  /// photo_view 的 scale 相对原图尺寸；贴合屏幕（contained）时的比例。
  double get _fitScale {
    final img = _imageSize;
    if (img == null || img.isEmpty || _viewport == Size.zero) return 1;
    return math.min(_viewport.width / img.width, _viewport.height / img.height);
  }

  /// 读取图片真实尺寸（复用全局图片缓存，不额外完整解码原图）。
  /// Track the size of the image that is CURRENTLY displayed (thumb/preview/original).
  /// Gesture logic uses this size so swiping while a small image is shown behaves like 1x paging.
  void _maybeResolveImageSize() {
    final path = _viewModel.imagePath;
    if (path == null || path.isEmpty) return;
    final provider = _buildImageProvider();
    final key = '$path|${provider.runtimeType}|$_originalReady';
    if (key == _resolvedKey) return;
    _resolvedKey = key;
    _imageSize = null;
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!mounted) return;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (w <= 0 || h <= 0) return;
      // This callback may fire synchronously during build; defer to end of frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _imageSize = Size(w, h));
      });
    }, onError: (_, _) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  /// Warm up full-res decode in the background; swap display to full-res once done.
  void _maybeWarmOriginal() {
    if (!_viewModel.fullImageReady || _originalReady || _warmingOriginal) {
      return;
    }
    final path = _viewModel.imagePath;
    if (path == null || path.isEmpty) return;
    _warmingOriginal = true;
    final provider = FileImage(File(path));
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _originalReady = true);
      });
    }, onError: (_, _) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  Widget _buildOverlay(BuildContext context) {
    final item = widget.item;
    return Stack(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Column(
              children: [
                _GlassPanel(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatDateTime(item.createTime),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              widget.positionText,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '详情',
                        onPressed: _showInfoSheet,
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _GlassPanel(
                  child: Text(
                    '照片 ${formatBytes(item.imageSize)}'
                    '${item.isLive ? ' · 动态 ${formatBytes(item.videoSize ?? 0)}' : ''}'
                    ' · 总计 ${formatBytes(item.totalSize)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                if (widget.item.isLive) ...[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LiveBadgeSmall(),
                  ),
                ],
                if (!_viewModel.fullImageReady &&
                    _viewModel.fullImageError == null) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LoadingOriginalChip(),
                  ),
                ],
                if (_viewModel.fullImageError != null) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _LoadOriginalFailedChip(),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.uiVisible)
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlassPanel(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BottomActionButton(
                          icon: Icons.ios_share_rounded,
                          label: '分享',
                          onTap: _shareImage,
                        ),
                        const SizedBox(width: 16),
                        _BottomActionButton(
                          icon: Icons.edit_note_rounded,
                          label: '编辑',
                          onTap: _showEditSheet,
                        ),
                        const SizedBox(width: 16),
                        _BottomActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: '删除',
                          color: Colors.redAccent,
                          onTap: _confirmDelete,
                        ),
                      ],
                    ),
                  ),
                  if (item.isLive) ...[
                    const SizedBox(height: 8),
                    _GlassPanel(
                      child: const Text(
                        '长按图片播放动态效果',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final item = widget.item;
    if (item.isLive) {
      final action = await _showLiveDeleteSheet();
      if (action == null || !mounted) return;
      final videoOnly = action == _LiveDeleteAction.videoOnly;
      final outcome = await _viewModel.startDelete(videoOnly: videoOnly);
      if (!mounted) return;
      switch (outcome) {
        case DeleteOutcome.done:
          _showSnack('已删除');
          widget.onDeleted(videoOnly);
        case DeleteOutcome.videoOnly:
          _showSnack('动态已删除，照片删除失败，已保留为普通照片');
          widget.onDeleted(true);
        case DeleteOutcome.needPermission:
          await _promptAllFilesAccess();
        case DeleteOutcome.failed:
          break;
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除照片？'),
        content: const Text('将把照片移入应用回收站。'),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final outcome = await _viewModel.startDelete(videoOnly: true);
    if (!mounted) return;
    switch (outcome) {
      case DeleteOutcome.done:
        _showSnack('已删除');
        widget.onDeleted(false);
      case DeleteOutcome.videoOnly:
        _showSnack('已删除');
        widget.onDeleted(false);
      case DeleteOutcome.needPermission:
        await _promptAllFilesAccess();
      case DeleteOutcome.failed:
        break;
    }
  }

  /// Live 图删除底部面板：仅删除动态 / 全部删除。
  Future<_LiveDeleteAction?> _showLiveDeleteSheet() {
    final item = widget.item;
    return showModalBottomSheet<_LiveDeleteAction>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Text(
                '删除动态视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'LIVE · 照片 ${formatBytes(item.imageSize)}'
                ' · 动态 ${formatBytes(item.videoSize ?? 0)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            _DeleteOptionTile(
              icon: Icons.movie_outlined,
              title: '仅删除Live动态',
              subtitle: '照片保留，动态视频移入回收站',
              onTap: () =>
                  Navigator.of(context).pop(_LiveDeleteAction.videoOnly),
            ),
            _DeleteOptionTile(
              icon: Icons.delete_outline,
              title: '全部删除',
              subtitle: '照片和动态一起移入回收站',
              destructive: true,
              onTap: () =>
                  Navigator.of(context).pop(_LiveDeleteAction.fullDelete),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptAllFilesAccess() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要文件访问权限'),
        content: const Text(
          'Android 11+ 删除文件需要“所有文件访问”权限（只需开启一次），'
          '开启后删除将不再弹出系统确认框。',
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (go == true) {
      await _viewModel.repository.openAllFilesAccessSettings();
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        ),
      ),
    );
  }

  Future<T?> _withProgress<T>(String message, Future<T> Function() task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }

  Future<void> _shareImage() async {
    try {
      await _viewModel.share();
    } catch (_) {
      _showSnack('分享失败');
    }
  }

  Future<void> _showEditSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _EditActionTile(
              icon: Icons.edit_note_rounded,
              title: '编辑 EXIF',
              subtitle: '修改品牌、型号、时间、软件、描述',
              onTap: () {
                Navigator.of(context).pop();
                _showExifEditor();
              },
            ),
            _EditActionTile(
              icon: Icons.privacy_tip_outlined,
              title: '清除敏感 EXIF',
              subtitle: 'GPS、设备、软件、拍摄时间等',
              destructive: true,
              onTap: () {
                Navigator.of(context).pop();
                _confirmClearSensitiveExif();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExifEditor() async {
    final exif = _viewModel.exif ?? const <String, dynamic>{};
    final values = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        fullscreenDialog: true,
        builder: (_) => _ExifEditorPage(exif: exif),
      ),
    );
    if (values == null || !mounted) return;
    final saved = await _withProgress(
      '正在写入 EXIF…',
      () => _viewModel.updateExif(values),
    );
    if (!mounted) return;
    _showSnack(saved == true ? 'EXIF 已保存' : 'EXIF 保存失败');
  }

  Future<void> _confirmClearSensitiveExif() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => const ExifClearDialog(
        title: '清除敏感 EXIF？',
        description: '将清除这张照片中勾选的元数据。照片内容不会删除，但元数据修改后可能无法恢复。',
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    ExifClearSelectionMemory.remember(selected);
    final ok = await _withProgress(
      '正在清除敏感 EXIF…',
      () => _viewModel.clearSensitiveExif(selected.toList()),
    );
    if (!mounted) return;
    _showSnack(ok == true ? '敏感 EXIF 已清除' : '清除失败');
  }

  Future<void> _showInfoSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InfoSheet(viewModel: _viewModel, item: widget.item),
    );
  }
}

class _ExifEditorPage extends StatefulWidget {
  const _ExifEditorPage({required this.exif});

  final Map<String, dynamic> exif;

  @override
  State<_ExifEditorPage> createState() => _ExifEditorPageState();
}

class _ExifEditorPageState extends State<_ExifEditorPage> {
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _datetime;
  late final TextEditingController _software;
  late final TextEditingController _description;
  late final TextEditingController _artist;
  late final TextEditingController _copyright;
  late final TextEditingController _userComment;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _gpsAltitude;
  late final TextEditingController _focalLength;
  late final TextEditingController _focalLength35mm;
  late final TextEditingController _iso;
  late final TextEditingController _exposureTime;
  late final TextEditingController _aperture;
  late final TextEditingController _exposureBias;
  late final TextEditingController _flash;
  late final TextEditingController _lensMake;
  late final TextEditingController _lensModel;
  late final TextEditingController _bodySerialNumber;
  late final TextEditingController _cameraOwnerName;
  late final TextEditingController _orientation;
  late final TextEditingController _whiteBalance;
  late final TextEditingController _meteringMode;
  late final TextEditingController _exposureProgram;
  late final TextEditingController _digitalZoomRatio;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final exif = widget.exif;
    _make = TextEditingController(text: '${exif['make'] ?? ''}');
    _model = TextEditingController(text: '${exif['model'] ?? ''}');
    _datetime = TextEditingController(
      text: '${exif['datetimeOriginal'] ?? exif['datetime'] ?? ''}',
    );
    _software = TextEditingController(text: '${exif['software'] ?? ''}');
    _description = TextEditingController(
      text: '${exif['imageDescription'] ?? ''}',
    );
    _artist = TextEditingController(text: '${exif['artist'] ?? ''}');
    _copyright = TextEditingController(text: '${exif['copyright'] ?? ''}');
    _userComment = TextEditingController(text: '${exif['userComment'] ?? ''}');
    _latitude = TextEditingController(text: '${exif['latitude'] ?? ''}');
    _longitude = TextEditingController(text: '${exif['longitude'] ?? ''}');
    _gpsAltitude = TextEditingController(text: '${exif['gpsAltitude'] ?? ''}');
    _focalLength = TextEditingController(text: '${exif['focalLength'] ?? ''}');
    _focalLength35mm = TextEditingController(
      text: '${exif['focalLength35mm'] ?? ''}',
    );
    _iso = TextEditingController(text: '${exif['iso'] ?? ''}');
    _exposureTime = TextEditingController(
      text: '${exif['exposureTime'] ?? ''}',
    );
    _aperture = TextEditingController(text: '${exif['aperture'] ?? ''}');
    _exposureBias = TextEditingController(
      text: '${exif['exposureBias'] ?? ''}',
    );
    _flash = TextEditingController(text: '${exif['flash'] ?? ''}');
    _lensMake = TextEditingController(text: '${exif['lensMake'] ?? ''}');
    _lensModel = TextEditingController(text: '${exif['lensModel'] ?? ''}');
    _bodySerialNumber = TextEditingController(
      text: '${exif['bodySerialNumber'] ?? ''}',
    );
    _cameraOwnerName = TextEditingController(
      text: '${exif['cameraOwnerName'] ?? ''}',
    );
    _orientation = TextEditingController(text: '${exif['orientation'] ?? ''}');
    _whiteBalance = TextEditingController(
      text: '${exif['whiteBalance'] ?? ''}',
    );
    _meteringMode = TextEditingController(
      text: '${exif['meteringMode'] ?? ''}',
    );
    _exposureProgram = TextEditingController(
      text: '${exif['exposureProgram'] ?? ''}',
    );
    _digitalZoomRatio = TextEditingController(
      text: '${exif['digitalZoomRatio'] ?? ''}',
    );
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _datetime.dispose();
    _software.dispose();
    _description.dispose();
    _artist.dispose();
    _copyright.dispose();
    _userComment.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _gpsAltitude.dispose();
    _focalLength.dispose();
    _focalLength35mm.dispose();
    _iso.dispose();
    _exposureTime.dispose();
    _aperture.dispose();
    _exposureBias.dispose();
    _flash.dispose();
    _lensMake.dispose();
    _lensModel.dispose();
    _bodySerialNumber.dispose();
    _cameraOwnerName.dispose();
    _orientation.dispose();
    _whiteBalance.dispose();
    _meteringMode.dispose();
    _exposureProgram.dispose();
    _digitalZoomRatio.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(<String, String>{
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'datetime': _datetime.text.trim(),
      'software': _software.text.trim(),
      'imageDescription': _description.text.trim(),
      'artist': _artist.text.trim(),
      'copyright': _copyright.text.trim(),
      'userComment': _userComment.text.trim(),
      'latitude': _latitude.text.trim(),
      'longitude': _longitude.text.trim(),
      if (_showAdvanced) ...{
        'gpsAltitude': _gpsAltitude.text.trim(),
        'focalLength': _focalLength.text.trim(),
        'focalLength35mm': _focalLength35mm.text.trim(),
        'iso': _iso.text.trim(),
        'exposureTime': _exposureTime.text.trim(),
        'aperture': _aperture.text.trim(),
        'exposureBias': _exposureBias.text.trim(),
        'flash': _flash.text.trim(),
        'lensMake': _lensMake.text.trim(),
        'lensModel': _lensModel.text.trim(),
        'bodySerialNumber': _bodySerialNumber.text.trim(),
        'cameraOwnerName': _cameraOwnerName.text.trim(),
        'orientation': _orientation.text.trim(),
        'whiteBalance': _whiteBalance.text.trim(),
        'meteringMode': _meteringMode.text.trim(),
        'exposureProgram': _exposureProgram.text.trim(),
        'digitalZoomRatio': _digitalZoomRatio.text.trim(),
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('编辑 EXIF'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ExifTextField(controller: _make, label: '相机品牌'),
          _ExifTextField(controller: _model, label: '相机型号'),
          _ExifTextField(
            controller: _datetime,
            label: '拍摄时间',
            hint: 'yyyy:MM:dd HH:mm:ss',
          ),
          _ExifTextField(controller: _software, label: '软件'),
          _ExifTextField(controller: _description, label: '描述'),
          _ExifTextField(controller: _artist, label: '作者'),
          _ExifTextField(controller: _copyright, label: '版权'),
          _ExifTextField(controller: _userComment, label: '备注'),
          _ExifTextField(controller: _latitude, label: 'GPS 纬度'),
          _ExifTextField(controller: _longitude, label: 'GPS 经度'),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('高级'),
            subtitle: const Text('镜头、曝光参数、机身和更多原始 EXIF'),
            trailing: Icon(
              _showAdvanced
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
          if (_showAdvanced) ...[
            _ExifTextField(controller: _gpsAltitude, label: 'GPS 海拔'),
            _ExifTextField(controller: _focalLength, label: '焦距'),
            _ExifTextField(controller: _focalLength35mm, label: '35mm 等效焦距'),
            _ExifTextField(controller: _iso, label: 'ISO'),
            _ExifTextField(controller: _exposureTime, label: '快门时间'),
            _ExifTextField(controller: _aperture, label: '光圈'),
            _ExifTextField(controller: _exposureBias, label: '曝光补偿'),
            _ExifTextField(controller: _flash, label: '闪光灯'),
            _ExifTextField(controller: _lensMake, label: '镜头品牌'),
            _ExifTextField(controller: _lensModel, label: '镜头型号'),
            _ExifTextField(controller: _bodySerialNumber, label: '机身序列号'),
            _ExifTextField(controller: _cameraOwnerName, label: '相机所有者'),
            _ExifTextField(controller: _orientation, label: '方向'),
            _ExifTextField(controller: _whiteBalance, label: '白平衡'),
            _ExifTextField(controller: _meteringMode, label: '测光模式'),
            _ExifTextField(controller: _exposureProgram, label: '曝光程序'),
            _ExifTextField(controller: _digitalZoomRatio, label: '数码变焦'),
          ],
        ],
      ),
    );
  }
}

class _EditActionTile extends StatelessWidget {
  const _EditActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExifTextField extends StatelessWidget {
  const _ExifTextField({
    required this.controller,
    required this.label,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _LiveBadgeSmall extends StatelessWidget {
  const _LiveBadgeSmall();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 半透明灰色圆角面板，保证文字在图片上清晰可读。
class _DeleteOptionTile extends StatelessWidget {
  const _DeleteOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  const _BottomActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情面板：文件信息 + EXIF（从底部弹出）。
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.viewModel, required this.item});

  final DetailViewModel viewModel;
  final PhotoItem item;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('文件名', item.displayName),
      ('路径', _displayPath(item)),
      ('拍摄时间', formatDateTime(item.createTime)),
      ('照片', formatBytes(item.imageSize)),
      if (item.isLive) ('动态', formatBytes(item.videoSize ?? 0)),
      ('总计', formatBytes(item.totalSize)),
    ];
    final exif = viewModel.exif;
    final gpsNumbers = _gpsNumbers(exif);
    var showGpsNumbers = false;
    if (exif != null) {
      rows.addAll(formatExif(exif));
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '详情',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Column(
                      children: [
                        for (final (label, value) in rows)
                          _InfoRow(
                            label: label,
                            value: value,
                            onTap: label == '路径'
                                ? () => _openFolder(context)
                                : null,
                            extraValue: label == 'GPS' ? gpsNumbers : null,
                            expanded: label == 'GPS' && showGpsNumbers,
                            onToggle: label == 'GPS' && gpsNumbers != null
                                ? () => setSheetState(
                                    () => showGpsNumbers = !showGpsNumbers,
                                  )
                                : null,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayPath(PhotoItem item) {
    final relativePath = item.relativePath.trim();
    if (relativePath.isEmpty) return item.displayName;
    return '$relativePath${item.displayName}';
  }

  Future<void> _openFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await viewModel.repository.openFolder(item);
      if (!context.mounted) return;
      final message = switch (status) {
        'folder' => '已尝试打开所在位置',
        'app' => '文件管理器未开放定位入口，已打开文件管理器首页',
        _ => '无法打开文件管理器',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('无法打开文件管理器')));
    }
  }

  String? _gpsNumbers(Map<String, dynamic>? exif) {
    if (exif == null) return null;
    final address = (exif['gpsAddress'] as String?)?.trim();
    final lat = exif['latitude'];
    final lng = exif['longitude'];
    if (address == null || address.isEmpty || lat is! num || lng is! num) {
      return null;
    }
    return '$lat, $lng';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.extraValue,
    this.expanded = false,
    this.onTap,
    this.onToggle,
  });

  final String label;
  final String value;
  final String? extraValue;
  final bool expanded;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(color: Colors.white38)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _copy(context, value),
                  child: Text(
                    value,
                    style: TextStyle(
                      color: onTap == null
                          ? Colors.white
                          : Colors.lightBlueAccent,
                    ),
                  ),
                ),
                if (expanded && extraValue != null) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => _copy(context, extraValue!),
                    child: Text(
                      extraValue!,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onToggle != null)
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: Colors.white38,
              size: 18,
            ),
        ],
      ),
    );
    if (onToggle != null || onTap != null) {
      return InkWell(onTap: onToggle ?? onTap, child: content);
    }
    return content;
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 96,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '已复制',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 900), entry.remove);
  }
}

class _LoadingOriginalChip extends StatelessWidget {
  const _LoadingOriginalChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
          SizedBox(width: 6),
          Text('加载原图…', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _LoadOriginalFailedChip extends StatelessWidget {
  const _LoadOriginalFailedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        '原图加载失败',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
