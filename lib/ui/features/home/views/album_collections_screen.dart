import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../domain/models/photo_item.dart';
import '../view_models/home_view_model.dart';
import 'home_screen.dart';

class AlbumCollectionsScreen extends StatefulWidget {
  const AlbumCollectionsScreen({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<AlbumCollectionsScreen> createState() => _AlbumCollectionsScreenState();
}

class _AlbumCollectionsScreenState extends State<AlbumCollectionsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('合集')),
          body: switch (widget.viewModel.status) {
            HomeStatus.initial || HomeStatus.loading =>
              widget.viewModel.items.isNotEmpty
                  ? _buildReady(context)
                  : const _AlbumStartupPlaceholder(),
            HomeStatus.error => _AlbumErrorView(
              message: widget.viewModel.error ?? '未知错误',
              onRetry: widget.viewModel.load,
            ),
            HomeStatus.ready => _buildReady(context),
          },
        );
      },
    );
  }

  Widget _buildReady(BuildContext context) {
    final albums = _buildAlbums(widget.viewModel.items);
    if (albums.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.viewModel.refresh,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(child: Text('暂无相册')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.viewModel.refresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.88,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return _AlbumCard(
            album: album,
            thumbnailFuture: widget.viewModel.thumbnailPathFor(album.cover),
            onThumbnailError: () =>
                widget.viewModel.evictThumbnail(album.cover),
            onTap: () => _openAlbum(album),
          );
        },
      ),
    );
  }

  void _openAlbum(_AlbumGroup album) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _AlbumDetailShell(viewModel: widget.viewModel, album: album),
      ),
    );
  }

  List<_AlbumGroup> _buildAlbums(List<PhotoItem> items) {
    final grouped = <String, List<PhotoItem>>{};
    for (final item in items) {
      final key = _AlbumGroup.albumTitle(item.relativePath);
      grouped.putIfAbsent(key, () => <PhotoItem>[]).add(item);
    }
    final albums = <_AlbumGroup>[
      for (final entry in grouped.entries)
        if (entry.value.isNotEmpty) _AlbumGroup.from(entry.key, entry.value),
    ];
    albums.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      if (rank != 0) return rank;
      final count = b.items.length.compareTo(a.items.length);
      if (count != 0) return count;
      return b.latest.compareTo(a.latest);
    });
    return albums;
  }
}

class _AlbumDetailShell extends StatefulWidget {
  const _AlbumDetailShell({required this.viewModel, required this.album});

  final HomeViewModel viewModel;
  final _AlbumGroup album;

  @override
  State<_AlbumDetailShell> createState() => _AlbumDetailShellState();
}

class _AlbumDetailShellState extends State<_AlbumDetailShell> {
  late final PageController _pageController;
  final ValueNotifier<int> _indexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _indexNotifier.dispose();
    super.dispose();
  }

  List<PhotoItem> _albumItems(HomeViewModel viewModel) {
    return viewModel.items
        .where((item) => widget.album.relativePaths.contains(item.relativePath))
        .toList();
  }

  void _selectTab(int index) {
    if (index == _indexNotifier.value) return;
    _indexNotifier.value = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    if (index != _indexNotifier.value) {
      _indexNotifier.value = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: [
              HomeScreen(
                viewModel: widget.viewModel,
                title: widget.album.title,
                itemFilter: _albumItems,
              ),
              HomeScreen(
                viewModel: widget.viewModel,
                liveOnly: true,
                title: '${widget.album.title} · Live',
                itemFilter: _albumItems,
              ),
            ],
          ),
          bottomNavigationBar: widget.viewModel.selectionMode
              ? null
              : ValueListenableBuilder<int>(
                  valueListenable: _indexNotifier,
                  builder: (context, index, _) => NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: _selectTab,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.photo_library_outlined),
                        selectedIcon: Icon(Icons.photo_library),
                        label: '全部',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.motion_photos_on_outlined),
                        selectedIcon: Icon(Icons.motion_photos_on),
                        label: 'Live',
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _AlbumGroup {
  _AlbumGroup({
    required this.relativePaths,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.cover,
    required this.latest,
    required this.rank,
  });

  factory _AlbumGroup.from(String title, List<PhotoItem> source) {
    final items = [...source]
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    final paths = items.map((item) => item.relativePath).toSet();
    return _AlbumGroup(
      relativePaths: paths,
      title: title,
      subtitle: _subtitle(paths, items.length),
      items: items,
      cover: items.first,
      latest: items.first.createTime,
      rank: _rank(paths, title),
    );
  }

  final Set<String> relativePaths;
  final String title;
  final String subtitle;
  final List<PhotoItem> items;
  final PhotoItem cover;
  final DateTime latest;
  final int rank;

  static String albumTitle(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final leaf = parts.isEmpty ? '未知相册' : parts.last;
    final lower = normalized.toLowerCase();
    if (lower.contains('dcim/camera')) return '相机';
    if (lower.contains('screenshot')) return '截图';
    if (lower.contains('weixin') || lower.contains('wechat')) return '微信';
    if (lower.contains('download')) return '下载';
    return leaf;
  }

  static String _subtitle(Set<String> relativePaths, int count) {
    if (relativePaths.length > 1) return '多个位置 · $count 张';
    final text = relativePaths.isEmpty ? '' : relativePaths.first.trim();
    if (text.isEmpty) return '未知路径';
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }

  static int _rank(Set<String> relativePaths, String title) {
    final lower = relativePaths.join('|').toLowerCase();
    if (title == '相机' || lower.contains('dcim/camera')) return 0;
    if (title == '截图' || lower.contains('screenshot')) return 1;
    if (title == '微信' || lower.contains('weixin') || lower.contains('wechat')) {
      return 2;
    }
    if (title == '下载' || lower.contains('download')) return 3;
    return 10;
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.thumbnailFuture,
    required this.onThumbnailError,
    required this.onTap,
  });

  final _AlbumGroup album;
  final Future<String> thumbnailFuture;
  final VoidCallback onThumbnailError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                          cacheWidth: 512,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              onThumbnailError();
                            });
                            return const _AlbumPlaceholder();
                          },
                        );
                      }
                      if (snapshot.hasError) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onThumbnailError();
                        });
                      }
                      return const _AlbumPlaceholder();
                    },
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          '${album.items.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                album.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.photo_album_outlined,
        color: scheme.onSurfaceVariant,
        size: 42,
      ),
    );
  }
}

class _AlbumStartupPlaceholder extends StatelessWidget {
  const _AlbumStartupPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemCount: 8,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 80,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumErrorView extends StatelessWidget {
  const _AlbumErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
