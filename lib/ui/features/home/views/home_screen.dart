import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../domain/models/photo_item.dart';
import '../../../core/exif_clear_options.dart';
import '../../../core/formatters.dart';
import '../../detail/views/detail_screen.dart';
import '../view_models/home_view_model.dart';

/// 首页：全部照片网格（Live 图带 LIVE 角标）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.viewModel,
    this.liveOnly = false,
    this.title,
    this.itemFilter,
  });

  final HomeViewModel viewModel;
  final bool liveOnly;
  final String? title;
  final List<PhotoItem> Function(HomeViewModel viewModel)? itemFilter;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _showTopButton = false;
  double _lastScrollPixels = 0;
  Timer? _topButtonTimer;
  Timer? _scrollDateTimer;
  Timer? _thumbnailResumeTimer;
  double _summaryHeight = 56.0;
  Timer? _summaryTimer;
  bool _animatingToTop = false;
  bool _showScrollDate = false;
  bool _deferThumbnailLoading = false;
  DateTime? _scrollDate;

  // ---- 滑动多选：选择模式下横向滑动选择，纵向滑动翻页 ----
  double? _sweepRow0Top;
  double? _sweepGridLeft;
  double _sweepExtent = 0;
  int _sweepCols = 1;
  int _sweepStartRow = -1;
  int _sweepStartCol = -1;
  Set<int> _sweepRange = {};
  bool _sweepSelectState = false;
  final GlobalKey _sweepViewportKey = GlobalKey();
  final GlobalKey _summaryKey = GlobalKey();
  double _sweepStartScroll = 0;
  Offset _sweepLastPosition = Offset.zero;
  Timer? _sweepTimer;
  int _sweepEdgeZone = 0;
  double _sweepEdgeStrength = 0;
  int _sweepPointer = -1;
  int _lastPointerDown = -1;
  Set<int> _sweepPreSelected = {};

  /// Visible items for this tab (all photos, or cached live-only view).
  List<PhotoItem> get _visibleItems {
    final filter = widget.itemFilter;
    if (filter != null) {
      final filtered = filter(widget.viewModel);
      return widget.liveOnly
          ? filtered.where((item) => item.isLive).toList()
          : filtered;
    }
    return widget.liveOnly
        ? widget.viewModel.liveItems
        : widget.viewModel.items;
  }

  List<_TimelineGroup> get _timelineGroups {
    final todayItems = <PhotoItem>[];
    final yesterdayItems = <PhotoItem>[];
    final weekItems = <PhotoItem>[];
    final monthItems = <String, List<PhotoItem>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(const Duration(days: 6));

    for (final item in _visibleItems) {
      final day = DateTime(
        item.createTime.year,
        item.createTime.month,
        item.createTime.day,
      );
      if (day == today) {
        todayItems.add(item);
      } else if (day == yesterday) {
        yesterdayItems.add(item);
      } else if (!day.isBefore(weekStart)) {
        weekItems.add(item);
      } else {
        final month = _monthTitle(item.createTime);
        monthItems.putIfAbsent(month, () => <PhotoItem>[]).add(item);
      }
    }

    final groups = <_TimelineGroup>[];
    var start = 0;
    void add(String title, List<PhotoItem> items) {
      if (items.isEmpty) return;
      groups.add(_TimelineGroup(title: title, items: items, startIndex: start));
      start += items.length;
    }

    add('今天', todayItems);
    add('昨天', yesterdayItems);
    add('一周内', weekItems);
    for (final entry in monthItems.entries) {
      add(entry.key, entry.value);
    }
    return groups;
  }

  String _monthTitle(DateTime time) => '${time.year}年${time.month}月';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onGridScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSummary());
  }

  void _measureSummary() {
    if (!mounted) return;
    final size = _summaryKey.currentContext?.size;
    if (size == null) return;
    if ((size.height - _summaryHeight).abs() < 0.5) return;
    setState(() => _summaryHeight = size.height);
  }

  @override
  void dispose() {
    _stopSweepTimer();
    _topButtonTimer?.cancel();
    _scrollDateTimer?.cancel();
    _thumbnailResumeTimer?.cancel();
    _summaryTimer?.cancel();
    _scrollController.removeListener(_onGridScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onGridScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollPixels;
    _lastScrollPixels = offset;
    if (delta.abs() > 0.5 && _visibleItems.isNotEmpty) {
      _showScrollDateTemporarily(_currentScrollItem()?.createTime);
    }
    if (_animatingToTop) return;
    if (widget.viewModel.selectionMode || offset < 400) {
      _setTopButtonVisible(false);
      return;
    }
    // 下滑（内容向顶部滚动）时显示；向上浏览深处时不打扰。
    if (delta > -8) return;
    _setTopButtonVisible(true);
    _topButtonTimer?.cancel();
    _topButtonTimer = Timer(
      const Duration(seconds: 2),
      () => _setTopButtonVisible(false),
    );
  }

  void _setTopButtonVisible(bool value) {
    if (_showTopButton == value) return;
    setState(() => _showTopButton = value);
  }

  void _showScrollDateTemporarily(DateTime? date) {
    _scrollDateTimer?.cancel();
    final normalized = date == null
        ? null
        : DateTime(date.year, date.month, date.day);
    final changed =
        _scrollDate?.year != normalized?.year ||
        _scrollDate?.month != normalized?.month ||
        _scrollDate?.day != normalized?.day;
    if (!_showScrollDate || changed) {
      setState(() {
        _showScrollDate = true;
        _scrollDate = normalized;
      });
    }
    _scrollDateTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _showScrollDate = false);
    });
  }

  void _setScrollbarDragging(bool dragging) {
    _thumbnailResumeTimer?.cancel();
    if (dragging) {
      if (!_deferThumbnailLoading) {
        setState(() => _deferThumbnailLoading = true);
      }
      return;
    }
    _thumbnailResumeTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_deferThumbnailLoading) return;
      setState(() => _deferThumbnailLoading = false);
    });
  }

  void _scrollToTop() {
    _topButtonTimer?.cancel();
    _setTopButtonVisible(false);
    if (!_scrollController.hasClients) return;
    _animatingToTop = true;
    _scrollController
        .animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _animatingToTop = false);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final selectionMode = widget.viewModel.selectionMode;
        // 多选模式下拦截系统返回：先退出选择模式，再按一次才退出应用。
        return PopScope(
          canPop: !selectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && selectionMode) {
              widget.viewModel.exitSelectionMode();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: selectionMode
                  ? TextButton(
                      onPressed: () => widget.viewModel.toggleSelectAllVisible(
                        _visibleItems,
                      ),
                      child: Text(
                        widget.viewModel.allVisibleSelected(_visibleItems)
                            ? '取消全选'
                            : '全选',
                      ),
                    )
                  : null,
              title: selectionMode
                  ? _SelectionSummary(viewModel: widget.viewModel)
                  : Text(
                      widget.title ?? (widget.liveOnly ? 'Live 动态' : 'LiveKit'),
                    ),
              centerTitle: selectionMode,
              actions: selectionMode
                  ? [
                      TextButton(
                        onPressed: widget.viewModel.exitSelectionMode,
                        child: const Text('取消'),
                      ),
                    ]
                  : null,
            ),
            body: _buildBody(),
            bottomNavigationBar: selectionMode
                ? _SelectionActionBar(
                    showDeleteLive: widget.viewModel.selectedLiveCount > 0,
                    onDeleteLive: _confirmDeleteLiveParts,
                    onShare: _shareSelected,
                    onClearExif: _confirmClearSelectedExif,
                    onDelete: _confirmBatchDelete,
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (widget.viewModel.status) {
      case HomeStatus.initial:
      case HomeStatus.loading:
        if (_visibleItems.isNotEmpty) {
          return _buildGrid();
        }
        return const _StartupGridSkeleton();
      case HomeStatus.error:
        return _ErrorView(
          message: widget.viewModel.error ?? '未知错误',
          onRetry: widget.viewModel.load,
        );
      case HomeStatus.ready:
        if (_visibleItems.isEmpty) {
          return _EmptyView(onRefresh: widget.viewModel.load);
        }
        return _buildGrid();
    }
  }

  Widget _buildGrid() {
    // 信息栏收起时的高度：轨道起点与图片区顶部对齐。
    final summaryHeight = _summaryHeight;
    final groups = _timelineGroups;
    final summary = _VisibleSummary.from(_visibleItems);
    return RefreshIndicator(
      onRefresh: widget.viewModel.load,
      child: SizedBox.expand(
        child: Stack(
          key: _sweepViewportKey,
          children: [
            Listener(
              onPointerDown: (e) => _lastPointerDown = e.pointer,
              onPointerMove: (e) => _onSweepPointerMove(e.pointer, e.position),
              onPointerUp: (e) => _onSweepPointerEnd(e.pointer),
              onPointerCancel: (e) => _onSweepPointerEnd(e.pointer),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = constraints.maxWidth < 400 ? 120.0 : 160.0;
                  return CustomScrollView(
                    controller: _scrollController,
                    cacheExtent: 0,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _SummaryBar(
                          key: _summaryKey,
                          onExpandedChanged: _onSummaryExpandedChanged,
                          liveOnly: widget.liveOnly,
                          count: summary.count,
                          liveCount: summary.liveCount,
                          totalBytes: summary.totalBytes,
                          liveImageBytes: summary.liveImageBytes,
                          liveVideoBytes: summary.liveVideoBytes,
                        ),
                      ),
                      for (final group in groups) ...[
                        SliverToBoxAdapter(
                          child: _TimelineHeader(
                            title: group.title,
                            count: group.items.length,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: maxExtent,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final item = group.items[index];
                              final globalIndex = group.startIndex + index;
                              return _PhotoTile(
                                index: globalIndex,
                                item: item,
                                thumbnailFuture: _deferThumbnailLoading
                                    ? null
                                    : widget.viewModel.thumbnailPathFor(item),
                                onThumbnailError: () =>
                                    widget.viewModel.evictThumbnail(item),
                                selectionMode: widget.viewModel.selectionMode,
                                selected: widget.viewModel.selectedIds.contains(
                                  item.imageId,
                                ),
                                onTap: () => widget.viewModel.selectionMode
                                    ? widget.viewModel.toggleSelection(item)
                                    : _openDetail(item),
                                onLongPress: () =>
                                    widget.viewModel.enterSelectionMode(item),
                                onSweepStart: _startSweep,
                              );
                            }, childCount: group.items.length),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (context, railConstraints) {
                  final available = (railConstraints.maxHeight - summaryHeight)
                      .clamp(0.0, railConstraints.maxHeight);
                  final trackHeight = available;
                  return Padding(
                    padding: EdgeInsets.only(top: summaryHeight),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SizedBox(
                        width: _GridScrollRail.railWidth,
                        height: trackHeight,
                        child: _GridScrollRail(
                          controller: _scrollController,
                          trackHeight: trackHeight,
                          currentLabel: _scrollTimeLabel,
                          onDragStateChanged: _setScrollbarDragging,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _TopScrollDateIndicator(
                visible: _showScrollDate,
                date: _scrollDate,
              ),
            ),
            Positioned(
              right: 56,
              bottom: 18,
              child: IgnorePointer(
                ignoring: !_showTopButton,
                child: AnimatedOpacity(
                  opacity: _showTopButton ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: _showTopButton ? 1 : 0.6,
                    duration: const Duration(milliseconds: 180),
                    child: FloatingActionButton.small(
                      heroTag: 'backToTop-${widget.liveOnly}',
                      onPressed: _scrollToTop,
                      tooltip: '回到顶部',
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _scrollTimeLabel() {
    if (!_scrollController.hasClients || _visibleItems.isEmpty) return null;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    final index = (fraction * (_visibleItems.length - 1)).round().clamp(
      0,
      _visibleItems.length - 1,
    );
    return formatDateTime(_visibleItems[index].createTime);
  }

  PhotoItem? _currentScrollItem() {
    if (!_scrollController.hasClients || _visibleItems.isEmpty) return null;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    final index = (fraction * (_visibleItems.length - 1)).round().clamp(
      0,
      _visibleItems.length - 1,
    );
    return _visibleItems[index];
  }

  Future<void> _openDetail(PhotoItem item) async {
    String? thumbnailPath;
    try {
      thumbnailPath = await widget.viewModel.thumbnailPathFor(item);
    } catch (_) {
      // 缩略图失败不阻塞进入详情
    }
    if (!mounted) return;
    final index = _visibleItems.indexWhere((e) => e.imageId == item.imageId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          items: _visibleItems,
          initialIndex: index < 0 ? 0 : index,
          repository: widget.viewModel.repository,
          thumbnailLoader: widget.viewModel.thumbnailPathFor,
          thumbnailPath: thumbnailPath,
          onDelete: (imageId, videoOnly) {
            if (mounted) {
              widget.viewModel.applyDelete(imageId, videoOnly: videoOnly);
            }
          },
        ),
      ),
    );
  }

  Future<void> _confirmBatchDelete() async {
    final count = widget.viewModel.selectedCount;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 $count 项？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${formatBytes(widget.viewModel.selectedTotalBytes)}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (widget.viewModel.selectedLiveVideoBytes > 0) ...[
              const SizedBox(height: 4),
              Text(
                '含 Live 动态 ${formatBytes(widget.viewModel.selectedLiveVideoBytes)}'
                '（${widget.viewModel.selectedLiveCount} 张）',
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '删除后可在回收站恢复。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

    final result = await _withProgress(
      '正在删除 $count 项…',
      widget.viewModel.deleteSelected,
    );
    if (!mounted) return;
    final parts = <String>[
      if (result.deleted > 0) '已删除 ${result.deleted} 项',
      if (result.videoOnly > 0) '${result.videoOnly} 项仅删动态',
      if (result.failed > 0) '${result.failed} 项失败',
    ];
    _showSnack(parts.isEmpty ? '删除失败' : parts.join('，'));
  }

  /// Starts the sweep selection from an anchor tile: from an unselected
  /// tile selects, from a selected tile deselects.
  void _onSummaryExpandedChanged(bool expanded) {
    setState(() {});
    _summaryTimer?.cancel();
    _summaryTimer = Timer(const Duration(milliseconds: 260), _measureSummary);
  }

  void _startSweep(
    int index,
    Offset tileTopLeft,
    double tileSize,
    bool currentlySelected,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final extent = tileSize + 2; // 单元格宽/高 + 2px 间距
    final cols = ((width - 2) / extent).round().clamp(1, 1000);
    _sweepRow0Top = tileTopLeft.dy - (index ~/ cols) * extent;
    _sweepGridLeft = tileTopLeft.dx - (index % cols) * extent;
    _sweepExtent = extent;
    _sweepCols = cols;
    _sweepStartRow = index ~/ cols;
    _sweepStartCol = index % cols;
    _sweepPreSelected = Set.of(widget.viewModel.selectedIds);
    _sweepSelectState = !currentlySelected;
    _sweepPointer = _lastPointerDown;
    _sweepStartScroll = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
    _sweepRange = {index};
    if (currentlySelected != _sweepSelectState) {
      widget.viewModel.setSelection(
        _visibleItems[index],
        selected: _sweepSelectState,
      );
    }
  }

  void _onSweepPointerMove(int pointer, Offset position) {
    if (pointer != _sweepPointer) return;
    _onSweepMove(position);
  }

  void _onSweepPointerEnd(int pointer) {
    if (pointer != _sweepPointer) return;
    _endSweep();
  }

  void _onSweepMove(Offset globalPosition) {
    _sweepLastPosition = globalPosition;
    _updateEdgeAutoScroll(globalPosition);
    final row0Top = _sweepRow0Top;
    final gridLeft = _sweepGridLeft;
    if (row0Top == null || gridLeft == null || _sweepExtent <= 0) return;
    if (_sweepStartRow < 0) return;
    final scrollDelta = _scrollController.hasClients
        ? _scrollController.offset - _sweepStartScroll
        : 0.0;
    final row =
        ((globalPosition.dy - row0Top + scrollDelta + 0.5) / _sweepExtent)
            .floor();
    if (row < 0) return;
    final col = ((globalPosition.dx - gridLeft + 0.5) / _sweepExtent).floor();
    _applyRange(row, col);
  }

  /// Recomputes the anchor-to-finger band and applies only the delta:
  /// cells entering the band are toggled to the sweep state, cells
  /// leaving it are restored to their pre-sweep state.
  void _applyRange(int row, int col) {
    final next = <int>{};
    final cols = _sweepCols;
    if (row == _sweepStartRow) {
      final lo = col < _sweepStartCol ? col : _sweepStartCol;
      final hi = col > _sweepStartCol ? col : _sweepStartCol;
      for (var c = lo; c <= hi; c++) {
        final index = _sweepStartRow * cols + c;
        if (index >= 0 && index < _visibleItems.length) next.add(index);
      }
    } else {
      final movingDown = row > _sweepStartRow;
      final topRow = movingDown ? _sweepStartRow : row;
      final bottomRow = movingDown ? row : _sweepStartRow;
      for (var r = topRow; r <= bottomRow; r++) {
        int c0;
        int c1;
        if (r == _sweepStartRow) {
          // Anchor row: from the anchor column toward the movement.
          c0 = movingDown ? _sweepStartCol : 0;
          c1 = movingDown ? cols - 1 : _sweepStartCol;
        } else if (r == row) {
          // Current row: from the row edge up to the current column.
          c0 = movingDown ? 0 : col;
          c1 = movingDown ? col : cols - 1;
        } else {
          c0 = 0;
          c1 = cols - 1;
        }
        for (var c = c0; c <= c1; c++) {
          final index = r * cols + c;
          if (index >= 0 && index < _visibleItems.length) next.add(index);
        }
      }
    }
    if (next.length == _sweepRange.length && next.containsAll(_sweepRange)) {
      return;
    }
    final toEnter = next.difference(_sweepRange);
    final toLeave = _sweepRange.difference(next);
    final changes = <(PhotoItem, bool)>[
      for (final i in toEnter) (_visibleItems[i], _sweepSelectState),
      for (final i in toLeave)
        (
          _visibleItems[i],
          _sweepPreSelected.contains(_visibleItems[i].imageId),
        ),
    ];
    _sweepRange = next;
    widget.viewModel.applySelectionDelta(changes);
  }

  /// Edge auto-scroll: hold near the top/bottom edge to keep scrolling.
  void _updateEdgeAutoScroll(Offset globalPosition) {
    final box = _sweepViewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      _stopSweepTimer();
      return;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = 72.0;
    final dy = globalPosition.dy;
    int zone = 0;
    double strength = 0;
    if (dy <= top + edge) {
      zone = -1;
      strength = ((top + edge - dy) / edge).clamp(0.0, 1.0).toDouble();
    } else if (dy >= bottom - edge) {
      zone = 1;
      strength = ((dy - (bottom - edge)) / edge).clamp(0.0, 1.0).toDouble();
    }
    _sweepEdgeZone = zone;
    _sweepEdgeStrength = strength;
    if (zone == 0) {
      _stopSweepTimer();
    } else {
      _sweepTimer ??= Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => _tickSweepAutoScroll(),
      );
    }
  }

  void _tickSweepAutoScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_sweepPointer < 0) {
      _stopSweepTimer();
      return;
    }
    final zone = _sweepEdgeZone;
    if (zone == 0) {
      _stopSweepTimer();
      return;
    }
    final position = _scrollController.position;
    final delta = 18.0 * _sweepEdgeStrength * zone;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) {
      _stopSweepTimer();
      return;
    }
    position.jumpTo(target);
    _applySweepAt(_sweepLastPosition);
  }

  /// Applies the band under the stationary finger while auto-scrolling.
  void _applySweepAt(Offset globalPosition) {
    final row0Top = _sweepRow0Top;
    final gridLeft = _sweepGridLeft;
    if (row0Top == null || gridLeft == null || _sweepExtent <= 0) return;
    if (_sweepStartRow < 0) return;
    if (!_scrollController.hasClients) return;
    final scrollDelta = _scrollController.offset - _sweepStartScroll;
    final row =
        ((globalPosition.dy - row0Top + scrollDelta + 0.5) / _sweepExtent)
            .floor();
    if (row < 0) return;
    final col = ((globalPosition.dx - gridLeft + 0.5) / _sweepExtent).floor();
    _applyRange(row, col);
  }

  void _stopSweepTimer() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  void _endSweep() {
    _stopSweepTimer();
    _sweepPointer = -1;
    _lastPointerDown = -1;
    _sweepPreSelected = {};
    _sweepRange = {};
    _sweepRow0Top = null;
    _sweepGridLeft = null;
    _sweepStartRow = -1;
    _sweepStartCol = -1;
    _sweepStartScroll = 0;
    _sweepLastPosition = Offset.zero;
    _sweepEdgeZone = 0;
    _sweepEdgeStrength = 0;
  }

  Future<void> _confirmDeleteLiveParts() async {
    final liveCount = widget.viewModel.selectedLiveCount;
    if (liveCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Live 动态视频？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${formatBytes(widget.viewModel.selectedLiveVideoBytes)}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('将删除 $liveCount 张 Live 图的动态视频，照片保留。'),
            const SizedBox(height: 12),
            Text(
              '普通照片不受影响。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

    final result = await _withProgress(
      '正在删除动态视频…',
      widget.viewModel.deleteLiveParts,
    );
    if (!mounted) return;
    _showSnack(
      result.failed > 0
          ? '已删除 ${result.videoOnly} 张 Live 动态，${result.failed} 张失败'
          : '已删除 ${result.videoOnly} 张 Live 动态',
    );
  }

  Future<void> _confirmClearSelectedExif() async {
    final count = widget.viewModel.selectedCount;
    if (count == 0) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => ExifClearDialog(
        title: '清除敏感 EXIF？',
        description: '将清除 $count 张照片中勾选的元数据。默认不清除拍摄时间；元数据修改后可能无法恢复。',
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    ExifClearSelectionMemory.remember(selected);

    final result = await _withProgress(
      '正在清除敏感 EXIF…',
      () => widget.viewModel.clearSelectedSensitiveExif(selected.toList()),
    );
    if (!mounted) return;
    _showSnack(
      result.failed > 0
          ? '已清除 ${result.success} 张，${result.failed} 张失败'
          : '已清除 ${result.success} 张',
    );
  }

  Future<void> _shareSelected() async {
    try {
      await widget.viewModel.shareSelected();
    } catch (_) {
      if (mounted) _showSnack('分享失败');
    }
  }

  Future<T> _withProgress<T>(
    String message,
    Future<T> Function() action,
  ) async {
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
      return await action();
    } finally {
      if (mounted) navigator.pop();
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(message),
      ),
    );
  }
}

class _StartupGridSkeleton extends StatelessWidget {
  const _StartupGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            height: 92,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            alignment: Alignment.centerLeft,
            child: Text(
              '正在读取照片',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              childCount: 36,
            ),
          ),
        ),
      ],
    );
  }
}

/// 竖向滚动条：直接拖动跳转，单击不跳转（避免误触）。
class _TimelineGroup {
  const _TimelineGroup({
    required this.title,
    required this.items,
    required this.startIndex,
  });

  final String title;
  final List<PhotoItem> items;
  final int startIndex;
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '$count 张',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibleSummary {
  const _VisibleSummary({
    required this.count,
    required this.liveCount,
    required this.totalBytes,
    required this.liveImageBytes,
    required this.liveVideoBytes,
  });

  factory _VisibleSummary.from(List<PhotoItem> items) {
    var liveCount = 0;
    var totalBytes = 0;
    var liveImageBytes = 0;
    var liveVideoBytes = 0;
    for (final item in items) {
      totalBytes += item.totalSize;
      if (!item.isLive) continue;
      liveCount++;
      liveImageBytes += item.imageSize;
      liveVideoBytes += item.videoSize ?? 0;
    }
    return _VisibleSummary(
      count: items.length,
      liveCount: liveCount,
      totalBytes: totalBytes,
      liveImageBytes: liveImageBytes,
      liveVideoBytes: liveVideoBytes,
    );
  }

  final int count;
  final int liveCount;
  final int totalBytes;
  final int liveImageBytes;
  final int liveVideoBytes;
}

class _TopScrollDateIndicator extends StatelessWidget {
  const _TopScrollDateIndicator({required this.visible, required this.date});

  final bool visible;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible && date != null ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 11, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  date?.day.toString().padLeft(2, '0') ?? '--',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  date == null ? '' : '${date.month}月\n${date.year}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridScrollRail extends StatefulWidget {
  const _GridScrollRail({
    required this.controller,
    required this.trackHeight,
    required this.currentLabel,
    required this.onDragStateChanged,
  });

  /// 轨道触控区宽度。
  static const double railWidth = 48;

  final ScrollController controller;
  final double trackHeight;
  final String? Function() currentLabel;
  final ValueChanged<bool> onDragStateChanged;

  @override
  State<_GridScrollRail> createState() => _GridScrollRailState();
}

class _GridScrollRailState extends State<_GridScrollRail> {
  static const double _thumbMinHeight = 48;
  static const double _thumbHitWidth = 28;
  static const double _thumbVisualWidth = 5;

  double _maxExtent = 0;
  double _thumbHeight = _thumbMinHeight;
  double _thumbTop = 0;
  bool _dragging = false;
  bool _dragFrameScheduled = false;
  double? _pendingDragTarget;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    if (_dragging) {
      widget.onDragStateChanged(false);
    }
    widget.controller.removeListener(_update);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _GridScrollRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackHeight != widget.trackHeight ||
        oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
  }

  void _update() {
    final controller = widget.controller;
    if (!mounted || !controller.hasClients) return;
    final position = controller.position;
    final max = position.maxScrollExtent;
    final height = widget.trackHeight;
    final thumbHeight = max <= 0
        ? _thumbMinHeight
        : (height * height / (max + height)).clamp(_thumbMinHeight, height);
    final thumbTop = max <= 0
        ? 0.0
        : (position.pixels / max) * (height - thumbHeight);
    if ((_maxExtent - max).abs() < 0.5 &&
        (_thumbHeight - thumbHeight).abs() < 0.5 &&
        (_thumbTop - thumbTop).abs() < 0.5) {
      return;
    }
    setState(() {
      _maxExtent = max;
      _thumbHeight = thumbHeight;
      _thumbTop = thumbTop;
    });
  }

  void _dragBy(double deltaY) {
    final controller = widget.controller;
    if (!controller.hasClients || _maxExtent <= 0) return;
    final travel = widget.trackHeight - _thumbHeight;
    if (travel <= 0) return;
    final delta = deltaY / travel * _maxExtent;
    final base = _pendingDragTarget ?? controller.position.pixels;
    _pendingDragTarget = (base + delta).clamp(0.0, _maxExtent).toDouble();
    if (_dragFrameScheduled) return;
    _dragFrameScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _dragFrameScheduled = false;
      final target = _pendingDragTarget;
      _pendingDragTarget = null;
      if (!mounted || target == null || !controller.hasClients) return;
      controller.jumpTo(
        target.clamp(0.0, controller.position.maxScrollExtent).toDouble(),
      );
    });
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    widget.onDragStateChanged(value);
    setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_maxExtent <= 0) return const SizedBox.shrink();

    final label = widget.currentLabel();
    final bubbleTop = widget.trackHeight <= 36
        ? 0.0
        : (_thumbTop + _thumbHeight / 2 - 18)
              .clamp(0.0, widget.trackHeight - 36)
              .toDouble();
    return SizedBox(
      width: _GridScrollRail.railWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: bubbleTop,
            right: 40,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragging && label != null ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      label ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: _thumbTop,
            right: 4,
            width: _thumbHitWidth,
            height: _thumbHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _setDragging(true),
              onVerticalDragUpdate: (details) => _dragBy(details.delta.dy),
              onVerticalDragEnd: (_) => _setDragging(false),
              onVerticalDragCancel: () => _setDragging(false),
              child: Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_thumbVisualWidth / 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.32),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: _thumbVisualWidth,
                    height: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(
                          _thumbVisualWidth / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatefulWidget {
  const _SummaryBar({
    super.key,
    this.liveOnly = false,
    this.onExpandedChanged,
    required this.count,
    required this.liveCount,
    required this.totalBytes,
    required this.liveImageBytes,
    required this.liveVideoBytes,
  });

  final bool liveOnly;
  final ValueChanged<bool>? onExpandedChanged;
  final int count;
  final int liveCount;
  final int totalBytes;
  final int liveImageBytes;
  final int liveVideoBytes;

  @override
  State<_SummaryBar> createState() => _SummaryBarState();
}

class _SummaryBarState extends State<_SummaryBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            widget.onExpandedChanged?.call(_expanded);
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: _expanded ? 12 : 8,
              ),
              child: Row(
                children: [
                  if (!widget.liveOnly) ...[
                    Expanded(
                      child: _buildColumn(
                        scheme,
                        icon: Icons.photo_library_outlined,
                        label: '全部照片',
                        color: scheme.primary,
                        countText: '${widget.count} 张',
                        detailTexts: [formatBytes(widget.totalBytes)],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: _expanded ? 56 : 32,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ],
                  Expanded(
                    child: _buildColumn(
                      scheme,
                      icon: Icons.motion_photos_on_outlined,
                      label: 'Live',
                      color: Colors.redAccent,
                      countText: '${widget.liveCount} 张',
                      detailTexts: [
                        '图片 ${formatBytes(widget.liveImageBytes)}',
                        '视频 ${formatBytes(widget.liveVideoBytes)}',
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColumn(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required Color color,
    required String countText,
    required List<String> detailTexts,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(countText, style: textTheme.titleSmall),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _expanded
              ? Column(
                  children: [
                    for (final text in detailTexts) ...[
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: textTheme.bodySmall?.copyWith(
                          color: color.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.index,
    required this.item,
    required this.thumbnailFuture,
    required this.onThumbnailError,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSweepStart,
  });

  final int index;
  final PhotoItem item;
  final Future<String>? thumbnailFuture;
  final VoidCallback onThumbnailError;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(
    int index,
    Offset tileTopLeft,
    double tileSize,
    bool currentlySelected,
  )
  onSweepStart;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  Future<String>? _thumbnailFuture;
  String? _lastThumbnailPath;
  bool _thumbnailRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.thumbnailFuture;
  }

  @override
  void didUpdateWidget(_PhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thumbnailFuture != null &&
        oldWidget.thumbnailFuture != widget.thumbnailFuture) {
      _thumbnailFuture = widget.thumbnailFuture;
    }
  }

  void _startSweepFromContext(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox) {
      widget.onSweepStart(
        widget.index,
        box.localToGlobal(Offset.zero),
        box.size.shortestSide,
        widget.selected,
      );
    }
  }

  void _scheduleThumbnailRetry() {
    if (_thumbnailRetryScheduled) {
      return;
    }
    _thumbnailRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onThumbnailError();
      _thumbnailRetryScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) {
        widget.onLongPress();
        _startSweepFromContext(context);
      },
      onHorizontalDragStart: widget.selectionMode
          ? (_) => _startSweepFromContext(context)
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnail(),
          if (widget.item.isLive)
            const Positioned(top: 6, left: 6, child: _LiveBadge()),
          if (widget.item.isLive)
            Positioned(
              bottom: 6,
              right: 6,
              child: _VideoSizeBadge(size: widget.item.videoSize ?? 0),
            ),
          if (widget.selectionMode) ...[
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: widget.selected ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _SelectionBadge(selected: widget.selected),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (widget.thumbnailFuture == null) {
      final path = _lastThumbnailPath;
      if (path == null || path.isEmpty) {
        return const _TilePlaceholder();
      }
      return _ThumbnailImage(path: path, onError: _scheduleThumbnailRetry);
    }
    final future = _thumbnailFuture;
    if (future == null) {
      return const _TilePlaceholder();
    }
    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          _lastThumbnailPath = snapshot.data;
          return _ThumbnailImage(
            path: snapshot.data!,
            onError: _scheduleThumbnailRetry,
          );
        }
        if (snapshot.hasError) {
          _scheduleThumbnailRetry();
        }
        return const _TilePlaceholder();
      },
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.path, required this.onError});

  final String path;
  final VoidCallback onError;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 512,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) {
        onError();
        return const _TilePlaceholder();
      },
    );
  }
}

/// 多选模式右上角圆圈 / 对勾。
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Theme.of(context).colorScheme.primary : null,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

/// 选择模式顶部信息：选中数量 + 总大小 + Live 动态大小。
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = viewModel.selectedTotalBytes;
    final liveVideo = viewModel.selectedLiveVideoBytes;
    final sizeText = liveVideo > 0
        ? '共 ${formatBytes(total)} · Live 动态 ${formatBytes(liveVideo)}'
        : '共 ${formatBytes(total)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          viewModel.selectedLiveCount > 0
              ? '已选 ${viewModel.selectedCount} 项 · Live ${viewModel.selectedLiveCount}'
              : '已选 ${viewModel.selectedCount} 项',
        ),
        Text(
          sizeText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 底部批量操作栏（全选 / 删除）。
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.showDeleteLive,
    required this.onDeleteLive,
    required this.onShare,
    required this.onClearExif,
    required this.onDelete,
  });

  final bool showDeleteLive;
  final VoidCallback onDeleteLive;
  final VoidCallback onShare;
  final VoidCallback onClearExif;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              if (showDeleteLive)
                _ActionButton(
                  icon: Icons.movie_outlined,
                  label: '删除Live部分',
                  onTap: onDeleteLive,
                ),
              _ActionButton(
                icon: Icons.ios_share_rounded,
                label: '分享',
                onTap: onShare,
              ),
              _ActionButton(
                icon: Icons.privacy_tip_outlined,
                label: '清EXIF',
                onTap: onClearExif,
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                label: '删除',
                destructive: true,
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = destructive
        ? Colors.redAccent
        : scheme.secondaryContainer;
    final foreground = destructive ? Colors.white : scheme.onSecondaryContainer;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground, size: 22),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoSizeBadge extends StatelessWidget {
  const _VideoSizeBadge({required this.size});

  final int size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '动态 ${formatBytes(size)}',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TilePlaceholder extends StatelessWidget {
  const _TilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.perm_media_outlined,
              size: 56,
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: 16),
            Text('无法扫描照片', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新授权并扫描'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          Text('未发现照片', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }
}
