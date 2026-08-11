import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../trash/views/recycle_bin_screen.dart';
import '../view_models/home_view_model.dart';
import 'album_collections_screen.dart';
import 'home_screen.dart';

/// Bottom tab shell: All / Live / Trash.
/// Tabs live inside a PageView so the user can swipe left/right to
/// switch, or tap the bottom NavigationBar. Visited tabs stay alive
/// (state + scroll positions preserved) so switching never reloads
/// the grid or re-scans the photo store.
///
/// The selected index is held in a ValueNotifier and consumed only by
/// the bottom NavigationBar, so page turns never rebuild the PageView
/// subtree (which would cause a visible hitch mid-swipe).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final LivePhotoRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final HomeViewModel _viewModel;
  late final PageController _pageController;
  final ValueNotifier<int> _indexNotifier = ValueNotifier<int>(0);
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel(repository: widget.repository)..load();
    _pageController = PageController();
    _pages = [
      HomeScreen(viewModel: _viewModel, liveOnly: false),
      HomeScreen(viewModel: _viewModel, liveOnly: true),
      AlbumCollectionsScreen(viewModel: _viewModel),
      _RecycleBinGate(
        repository: widget.repository,
        onRestored: _viewModel.applyRestored,
        revisionListenable: _viewModel,
      ),
    ];
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _pageController.dispose();
    _indexNotifier.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _indexNotifier.value) return;
    _indexNotifier.value = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 240),
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
      listenable: _viewModel,
      builder: (context, _) {
        final inSelection = _viewModel.selectionMode;
        return Scaffold(
          body: PageView.builder(
            controller: _pageController,
            physics: const _SnappyPageScrollPhysics(),
            itemCount: 4,
            allowImplicitScrolling: false,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) =>
                RepaintBoundary(child: _pages[index]),
          ),
          bottomNavigationBar: inSelection
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
                      NavigationDestination(
                        icon: Icon(Icons.collections_bookmark_outlined),
                        selectedIcon: Icon(Icons.collections_bookmark),
                        label: '合集',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.restore_from_trash_outlined),
                        selectedIcon: Icon(Icons.delete_outline),
                        label: '回收站',
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// 快速定住的页面弹簧：左右滑动放手后约 300ms 停稳，无回弹。
/// 相比默认弹簧（mass 0.5 / stiffness 100 / ratio 1.1，要 700ms+
/// 且带回弹）明显更快，消除滑动到底后"飘一下"的卡顿感。
class _SnappyPageScrollPhysics extends PageScrollPhysics {
  const _SnappyPageScrollPhysics({super.parent});

  @override
  _SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    // 保留祖先物理链（Android 上为 ClampingScrollPhysics），
    // 使首尾页不能越界外滑，同时维持快速弹簧。
    return _SnappyPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.5,
        stiffness: 400,
        damping: 28.28,
      );
}

/// 回收站页面的懒加载门：首次进入时才创建并加载，
/// 之后保持活在，不重新扫描。
class _RecycleBinGate extends StatefulWidget {
  const _RecycleBinGate({
    required this.repository,
    required this.onRestored,
    this.revisionListenable,
  });

  final LivePhotoRepository repository;
  final void Function(Map<String, dynamic> info) onRestored;
  final Listenable? revisionListenable;

  @override
  State<_RecycleBinGate> createState() => _RecycleBinGateState();
}

class _RecycleBinGateState extends State<_RecycleBinGate> {
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    return _child ??= RecycleBinScreen(
      repository: widget.repository,
      onRestored: widget.onRestored,
      revisionListenable: widget.revisionListenable,
    );
  }
}
