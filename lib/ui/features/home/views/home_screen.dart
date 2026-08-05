import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/live_photo.dart';
import '../../../core/formatters.dart';
import '../../detail/views/detail_screen.dart';
import '../view_models/home_view_model.dart';

/// 首页：Live 图片网格（Phase 3 首版）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final LivePhotoRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Manager'),
        centerTitle: false,
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
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
        },
      ),
    );
  }

  Widget _buildGrid() {
    return Column(
      children: [
        _SummaryBar(
          count: _viewModel.items.length,
          totalBytes: _viewModel.totalBytes,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _viewModel.load,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 自适应列数：可用宽度越大，单格越大
                final maxExtent = constraints.maxWidth < 400 ? 120.0 : 160.0;
                return Stack(
                  children: [
                    GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(2),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: _viewModel.items.length,
                      itemBuilder: (context, index) {
                        final item = _viewModel.items[index];
                        return _LivePhotoTile(
                          item: item,
                          thumbnailFuture: _viewModel.thumbnailPathFor(item),
                          onTap: () => _openDetail(item),
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
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDetail(LivePhoto item) async {
    // 进详情前先确保缩略图就绪（预生成后几乎瞬时），保证第一帧有图
    String? thumbnailPath;
    try {
      thumbnailPath = await _viewModel.thumbnailPathFor(item);
    } catch (_) {
      // 缩略图失败不阻塞进入详情
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          item: item,
          repository: widget.repository,
          thumbnailPath: thumbnailPath,
          thumbnailFuture: _viewModel.thumbnailPathFor(item),
        ),
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
            // 半透明轨道
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
            // 可拖动滑块
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

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.count, required this.totalBytes});

  final int count;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('共 $count 张 Live 图片', style: textTheme.titleSmall),
          const Spacer(),
          Text(
            '占用 ${formatBytes(totalBytes)}',
            style: textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _LivePhotoTile extends StatelessWidget {
  const _LivePhotoTile({
    required this.item,
    required this.thumbnailFuture,
    required this.onTap,
  });

  final LivePhoto item;
  final Future<String> thumbnailFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
          const Positioned(
            top: 6,
            left: 6,
            child: _LiveBadge(),
          ),
        ],
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
            Text('无法扫描 Live 图片',
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
          Text('未发现 Live 图片', style: Theme.of(context).textTheme.titleMedium),
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
