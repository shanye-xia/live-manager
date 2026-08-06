import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';
import '../../../core/formatters.dart';
import '../../detail/views/detail_screen.dart';
import '../../trash/views/recycle_bin_screen.dart';
import '../view_models/home_view_model.dart';

/// 首页：全部照片网格（Live 图带 LIVE 角标）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final LivePhotoRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();

  // ---- 滑动多选：选择模式下横向滑动选择，纵向滑动翻页 ----
  double? _sweepRow0Top;
  double? _sweepGridLeft;
  double _sweepExtent = 0;
  int _sweepCols = 1;
  int _sweepStartRow = -1;
  int _sweepStartCol = -1;
  int _sweepLastRow = -1;
  int _sweepLastCol = -1;
  bool _sweepSelectState = false;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel(repository: widget.repository)..load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final selectionMode = _viewModel.selectionMode;
        // 多选模式下拦截系统返回：先退出选择模式，再按一次才退出应用。
        return PopScope(
          canPop: !selectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && selectionMode) {
              _viewModel.exitSelectionMode();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: selectionMode
                  ? IconButton(
                      tooltip: '取消',
                      onPressed: _viewModel.exitSelectionMode,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              title: Text(
                selectionMode
                    ? '已选 ${_viewModel.selectedCount} 项'
                    : 'Live Manager',
              ),
              centerTitle: false,
              actions: [
                if (!selectionMode)
                  IconButton(
                    tooltip: '回收站',
                    onPressed: _openRecycleBin,
                    icon: const Icon(Icons.restore_from_trash_outlined),
                  ),
              ],
            ),
            body: _buildBody(),
            bottomNavigationBar: selectionMode
                ? _SelectionActionBar(
                    allSelected: _viewModel.allVisibleSelected,
                    showDeleteLive: _viewModel.selectedLiveCount > 0,
                    onToggleSelectAll: _viewModel.toggleSelectAllVisible,
                    onDeleteLive: _confirmDeleteLiveParts,
                    onDelete: _confirmBatchDelete,
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_viewModel.status) {
      case HomeStatus.initial:
      case HomeStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case HomeStatus.error:
        return _ErrorView(
          message: _viewModel.error ?? '未知错误',
          onRetry: _viewModel.load,
        );
      case HomeStatus.ready:
        if (_viewModel.items.isEmpty) {
          return _EmptyView(onRefresh: _viewModel.load);
        }
        return _buildGrid();
    }
  }

  Widget _buildGrid() {
    return RefreshIndicator(
      onRefresh: _viewModel.load,
      child: SizedBox.expand(
        child: Stack(
          children: [
            LayoutBuilder(
                  builder: (context, constraints) {
                    final maxExtent =
                        constraints.maxWidth < 400 ? 120.0 : 160.0;
                    return CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _SummaryBar(
                            count: _viewModel.items.length,
                            liveCount: _viewModel.liveCount,
                            totalBytes: _viewModel.totalBytes,
                            liveImageBytes: _viewModel.liveImageTotalBytes,
                            liveVideoBytes: _viewModel.liveVideoTotalBytes,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.all(2),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: maxExtent,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _viewModel.items[index];
                                return _PhotoTile(
                                  index: index,
                                  item: item,
                                  thumbnailFuture:
                                      _viewModel.thumbnailPathFor(item),
                                  selectionMode: _viewModel.selectionMode,
                                  selected: _viewModel.selectedIds.contains(
                                    item.imageId,
                                  ),
                                  onTap: () => _viewModel.selectionMode
                                      ? _viewModel.toggleSelection(item)
                                      : _openDetail(item),
                                  onLongPress: () => _viewModel
                                      .enterSelectionMode(item),
                                  onSweepStart: _startSweep,
                                  onSweepMove: _onSweepMove,
                                  onSweepEnd: _endSweep,
                                );
                              },
                              childCount: _viewModel.items.length,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: LayoutBuilder(
                builder: (context, railConstraints) {
                  return _GridScrollRail(
                    controller: _scrollController,
                    trackHeight: railConstraints.maxHeight,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(PhotoItem item) async {
    String? thumbnailPath;
    try {
      thumbnailPath = await _viewModel.thumbnailPathFor(item);
    } catch (_) {
      // 缩略图失败不阻塞进入详情
    }
    if (!mounted) return;
    final index = _viewModel.items
        .indexWhere((e) => e.imageId == item.imageId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          items: _viewModel.items,
          initialIndex: index < 0 ? 0 : index,
          repository: widget.repository,
          thumbnailLoader: _viewModel.thumbnailPathFor,
          thumbnailPath: thumbnailPath,
          onDelete: (imageId, videoOnly) {
            if (mounted) {
              _viewModel.applyDelete(imageId, videoOnly: videoOnly);
            }
          },
        ),
      ),
    );
  }

  void _openRecycleBin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecycleBinScreen(
          repository: widget.repository,
          onRestored: (info) {
            if (mounted) _viewModel.applyRestored(info);
          },
        ),
      ),
    );
  }

  Future<void> _confirmBatchDelete() async {
    final count = _viewModel.selectedCount;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 $count 项？'),
        content: const Text('删除后可在回收站恢复。'),
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
      _viewModel.deleteSelected,
    );
    if (!mounted) return;
    final parts = <String>[
      if (result.deleted > 0) '已删除 ${result.deleted} 项',
      if (result.videoOnly > 0) '${result.videoOnly} 项仅删动态',
      if (result.failed > 0) '${result.failed} 项失败',
    ];
    _showSnack(parts.isEmpty ? '删除失败' : parts.join('，'));
  }

  /// 开始滑动选择：从已选中项滑出则取消，从未选中项滑出则选中。
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
    _sweepLastRow = _sweepStartRow;
    _sweepLastCol = _sweepStartCol;
    _sweepSelectState = !currentlySelected;
    if (currentlySelected != _sweepSelectState) {
      _viewModel.setSelection(
        _viewModel.items[index],
        selected: _sweepSelectState,
      );
    }
  }

  /// 滑动更新：起点行内按「起点列→当前列」段选；
  /// 跨入新行则整行选择/取消；纵向滑动由列表本身翻页。
  void _onSweepMove(Offset globalPosition) {
    final row0Top = _sweepRow0Top;
    final gridLeft = _sweepGridLeft;
    if (row0Top == null || gridLeft == null || _sweepExtent <= 0) return;
    if (_sweepStartRow < 0) return;
    final row =
        ((globalPosition.dy - row0Top + 0.5) / _sweepExtent).floor();
    if (row < 0) return;
    final col =
        ((globalPosition.dx - gridLeft + 0.5) / _sweepExtent).floor();

    if (row == _sweepStartRow) {
      if (col == _sweepLastCol) return;
      _sweepLastCol = col;
      _applySegment(_sweepStartRow, _sweepStartCol, col);
      return;
    }
    if (row == _sweepLastRow) return; // 已整行处理过的行内横向移动不再重复

    if (row > _sweepLastRow) {
      for (var r = _sweepLastRow + 1; r <= row; r++) {
        _applyWholeRow(r);
      }
    } else {
      for (var r = _sweepLastRow - 1; r >= row; r--) {
        _applyWholeRow(r);
      }
    }
    _sweepLastRow = row;
    _sweepLastCol = col;
  }

  void _applySegment(int row, int fromCol, int toCol) {
    final lo = fromCol < toCol ? fromCol : toCol;
    final hi = fromCol > toCol ? fromCol : toCol;
    for (var c = lo; c <= hi; c++) {
      final index = row * _sweepCols + c;
      if (index >= _viewModel.items.length) break;
      _viewModel.setSelection(
        _viewModel.items[index],
        selected: _sweepSelectState,
      );
    }
  }

  void _applyWholeRow(int row) {
    if (row < 0) return;
    final start = row * _sweepCols;
    if (start >= _viewModel.items.length) return;
    final end = (start + _sweepCols).clamp(0, _viewModel.items.length);
    for (var i = start; i < end; i++) {
      _viewModel.setSelection(
        _viewModel.items[i],
        selected: _sweepSelectState,
      );
    }
  }

  void _endSweep() {
    _sweepRow0Top = null;
    _sweepGridLeft = null;
    _sweepStartRow = -1;
    _sweepLastRow = -1;
    _sweepLastCol = -1;
  }

  Future<void> _confirmDeleteLiveParts() async {
    final liveCount = _viewModel.selectedLiveCount;
    if (liveCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Live 动态视频？'),
        content: Text(
          '将删除 $liveCount 张 Live 图的动态视频，'
          '照片保留；普通照片不受影响。',
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
      _viewModel.deleteLiveParts,
    );
    if (!mounted) return;
    _showSnack(
      result.failed > 0
          ? '已删除 ${result.videoOnly} 张 Live 动态，${result.failed} 张失败'
          : '已删除 ${result.videoOnly} 张 Live 动态',
    );
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

/// 系统相册式可拖动竖向滚动条：整条轨道可点按/拖动跳转。
class _GridScrollRail extends StatefulWidget {
  const _GridScrollRail({
    required this.controller,
    required this.trackHeight,
  });

  final ScrollController controller;
  final double trackHeight;

  @override
  State<_GridScrollRail> createState() => _GridScrollRailState();
}

class _GridScrollRailState extends State<_GridScrollRail> {
  static const double _railWidth = 26;
  static const double _thumbMinHeight = 40;

  double _maxExtent = 0;
  double _thumbHeight = _thumbMinHeight;
  double _thumbTop = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
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
    setState(() {
      _maxExtent = max;
      _thumbHeight = thumbHeight;
      _thumbTop = thumbTop;
    });
  }

  void _jumpTo(Offset localPosition) {
    final controller = widget.controller;
    if (!controller.hasClients || _maxExtent <= 0) return;
    final fraction =
        (localPosition.dy / widget.trackHeight).clamp(0.0, 1.0);
    controller.jumpTo(fraction * _maxExtent);
  }

  @override
  Widget build(BuildContext context) {
    _update();
    if (_maxExtent <= 0) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => _jumpTo(details.localPosition),
      onTapDown: (details) => _jumpTo(details.localPosition),
      child: SizedBox(
        width: _railWidth,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 120),
              top: _thumbTop,
              left: 0,
              right: 0,
              height: _thumbHeight,
              child: Center(
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatefulWidget {
  const _SummaryBar({
    required this.count,
    required this.liveCount,
    required this.totalBytes,
    required this.liveImageBytes,
    required this.liveVideoBytes,
  });

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
          onTap: () => setState(() => _expanded = !_expanded),
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
                  Expanded(
                    child: _buildColumn(
                      scheme,
                      icon: Icons.photo_library_outlined,
                      label: '全部照片',
                      color: scheme.primary,
                      countText: '${widget.count} 张',
                      detailTexts: [
                        formatBytes(widget.totalBytes),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: _expanded ? 56 : 32,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
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
              style: textTheme.labelSmall
                  ?.copyWith(color: scheme.outline),
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

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.index,
    required this.item,
    required this.thumbnailFuture,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSweepStart,
    required this.onSweepMove,
    required this.onSweepEnd,
  });

  final int index;
  final PhotoItem item;
  final Future<String> thumbnailFuture;
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
  final ValueChanged<Offset> onSweepMove;
  final VoidCallback onSweepEnd;

  void _startSweepFromContext(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox) {
      onSweepStart(
        index,
        box.localToGlobal(Offset.zero),
        box.size.shortestSide,
        selected,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) {
        onLongPress();
        _startSweepFromContext(context);
      },
      onLongPressMoveUpdate: (details) => onSweepMove(details.globalPosition),
      onLongPressEnd: (_) => onSweepEnd(),
      onLongPressCancel: onSweepEnd,
      onHorizontalDragStart: (_) {
        if (!selectionMode) return;
        _startSweepFromContext(context);
      },
      onHorizontalDragUpdate: (details) => onSweepMove(details.globalPosition),
      onHorizontalDragEnd: (_) => onSweepEnd(),
      onHorizontalDragCancel: onSweepEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<String>(
            future: thumbnailFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _TilePlaceholder(),
                );
              }
              return const _TilePlaceholder();
            },
          ),
          if (item.isLive)
            const Positioned(
              top: 6,
              left: 6,
              child: _LiveBadge(),
            ),
          if (item.isLive)
            Positioned(
              bottom: 6,
              right: 6,
              child: _VideoSizeBadge(size: item.videoSize ?? 0),
            ),
          if (selectionMode) ...[
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _SelectionBadge(selected: selected),
            ),
          ],
        ],
      ),
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

/// 底部批量操作栏（全选 / 删除）。
class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.allSelected,
    required this.showDeleteLive,
    required this.onToggleSelectAll,
    required this.onDeleteLive,
    required this.onDelete,
  });

  final bool allSelected;
  final bool showDeleteLive;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onDeleteLive;
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
              _ActionButton(
                icon: allSelected ? Icons.deselect : Icons.select_all,
                label: allSelected ? '取消全选' : '全选',
                onTap: onToggleSelectAll,
              ),
              if (showDeleteLive)
                _ActionButton(
                  icon: Icons.movie_outlined,
                  label: '删除Live部分',
                  onTap: onDeleteLive,
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
    final color = destructive ? Colors.redAccent : Colors.white;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
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
            const Icon(Icons.perm_media_outlined,
                size: 56, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text('无法扫描照片',
                style: Theme.of(context).textTheme.titleLarge),
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
