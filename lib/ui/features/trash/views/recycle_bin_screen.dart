import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/trash_entry.dart';
import '../../../core/formatters.dart';
import 'trash_detail_screen.dart';

/// 应用回收站：缩略图列表，点击查看大图并可恢复/彻底删除。
/// 支持长按多选批量操作、右上角全部恢复/全部删除。
/// 通过 [revisionListenable] 监听首页删除事件，删除后回收站即时刷新。
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({
    super.key,
    required this.repository,
    this.onRestored,
    this.revisionListenable,
  });

  final LivePhotoRepository repository;
  final void Function(Map<String, dynamic> info)? onRestored;

  /// 首页删除/恢复时触发，回收站监听后自动重新加载。
  final Listenable? revisionListenable;

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen>
    with AutomaticKeepAliveClientMixin {
  List<TrashEntry>? _entries;
  String? _error;
  final Map<String, Future<String>> _previews = {};

  // ---- 多选 ----
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    widget.revisionListenable?.addListener(_onRevisionChanged);
  }

  @override
  void dispose() {
    widget.revisionListenable?.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() {
    if (!mounted) return;
    // 首页删除事件：重新加载回收站，
    // 但保持当前列表不闪，用自动刷新方式同步。
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _entries = null;
        _error = null;
      });
    }
    try {
      final entries = await widget.repository.trashEntries();
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 原地更新：从列表移除该条目（不重新加载、不重置滚动）。
  void _removeEntry(String id) {
    final entries = _entries;
    if (entries == null) return;
    setState(() {
      _entries = entries.where((e) => e.id != id).toList();
      _selectedIds.remove(id);
    });
  }

  Future<String> _previewPath(TrashEntry entry) {
    return _previews.putIfAbsent(
      entry.id,
      () => widget.repository.trashPreviewPath(entry, size: 256),
    );
  }

  void _enterSelection(TrashEntry entry) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(entry.id);
    });
  }

  void _toggleSelected(TrashEntry entry) {
    setState(() {
      if (!_selectedIds.remove(entry.id)) {
        _selectedIds.add(entry.id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    setState(() {
      if (_selectedIds.length == entries.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(entries.map((e) => e.id));
      }
    });
  }

  Future<void> _openDetail(TrashEntry entry) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => TrashDetailScreen(
          entry: entry,
          repository: widget.repository,
          onRestored: widget.onRestored,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'restored') {
      _removeEntry(entry.id);
      _showSnack('已恢复：${entry.originalFileName}');
    } else if (result == 'deleted') {
      _removeEntry(entry.id);
      _showSnack('已彻底删除');
    }
  }

  Future<void> _restore(TrashEntry entry) async {
    final info = await widget.repository.restoreTrash(entry.id);
    if (!mounted) return;
    if (info != null) {
      widget.onRestored?.call(info);
      _removeEntry(entry.id);
      _showSnack('已恢复：${entry.originalFileName}');
    } else {
      _showSnack('恢复失败');
    }
  }

  Future<void> _confirmPermanentDelete(TrashEntry entry) async {
    final confirmed = await _confirmDialog(
      title: '彻底删除？',
      message: '此操作不可恢复，文件将从回收站永久删除。',
      confirmText: '彻底删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final ok = await widget.repository.permanentDeleteTrash(entry.id);
    if (!mounted) return;
    if (ok) {
      _removeEntry(entry.id);
      _showSnack('已彻底删除');
    } else {
      _showSnack('删除失败');
    }
  }

  // ---- 批量操作 ----

  List<TrashEntry> _selectedEntries() {
    final entries = _entries;
    if (entries == null) return const [];
    return entries.where((e) => _selectedIds.contains(e.id)).toList();
  }

  Future<void> _restoreAll() async {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '全部恢复？',
      message: '将恢复回收站中全部 ${entries.length} 项。',
      confirmText: '全部恢复',
    );
    if (confirmed != true || !mounted) return;
    await _runBatch(
      entries,
      action: (e) => _restore(e),
      failMessage: '恢复失败',
    );
    _showSnack('已全部恢复');
  }

  Future<void> _deleteAll() async {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '全部彻底删除？',
      message: '此操作不可恢复，将永久删除回收站中全部 ${entries.length} 项。',
      confirmText: '全部删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    var okCount = 0;
    for (final e in entries) {
      try {
        if (await widget.repository.permanentDeleteTrash(e.id)) {
          okCount++;
          if (mounted) _removeEntry(e.id);
        }
      } catch (_) {
        // 单项失败不阻断其余
      }
    }
    if (!mounted) return;
    if (okCount == entries.length) {
      _showSnack('已全部彻底删除');
    } else if (okCount > 0) {
      _showSnack('部分删除失败');
    } else {
      _showSnack('删除失败');
    }
  }

  Future<void> _restoreSelected() async {
    final targets = _selectedEntries();
    if (targets.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '恢复选中项？',
      message: '将恢复 ${targets.length} 项。',
      confirmText: '恢复',
    );
    if (confirmed != true || !mounted) return;
    var okCount = 0;
    for (final e in targets) {
      try {
        final info = await widget.repository.restoreTrash(e.id);
        if (info != null) {
          widget.onRestored?.call(info);
          okCount++;
          if (mounted) _removeEntry(e.id);
        }
      } catch (_) {
        // 单项失败不阻断其余
      }
    }
    if (!mounted) return;
    if (okCount == targets.length) {
      _showSnack('已恢复 $okCount 项');
    } else if (okCount > 0) {
      _showSnack('恢复 $okCount 项，部分失败');
    } else {
      _showSnack('恢复失败');
    }
    if (_selectedIds.isEmpty) _exitSelection();
  }

  Future<void> _deleteSelected() async {
    final targets = _selectedEntries();
    if (targets.isEmpty) return;
    final confirmed = await _confirmDialog(
      title: '彻底删除选中项？',
      message: '此操作不可恢复，将删除 ${targets.length} 项。',
      confirmText: '彻底删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    var okCount = 0;
    for (final e in targets) {
      try {
        if (await widget.repository.permanentDeleteTrash(e.id)) {
          okCount++;
          if (mounted) _removeEntry(e.id);
        }
      } catch (_) {
        // 单项失败不阻断其余
      }
    }
    if (!mounted) return;
    if (okCount == targets.length) {
      _showSnack('已彻底删除 $okCount 项');
    } else if (okCount > 0) {
      _showSnack('删除 $okCount 项，部分失败');
    } else {
      _showSnack('删除失败');
    }
    if (_selectedIds.isEmpty) _exitSelection();
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? Colors.redAccent
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _runBatch(
    List<TrashEntry> targets, {
    required Future<void> Function(TrashEntry entry) action,
    required String failMessage,
  }) async {
    for (final e in targets) {
      try {
        await action(e);
      } catch (_) {
        // 单项失败不阻断其余
      }
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                tooltip: '取消',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _selectionMode
              ? '已选 ${_selectedIds.length} 项'
              : '回收站',
        ),
        centerTitle: false,
        actions: [
          if (!_selectionMode)
            IconButton(
              tooltip: '全部恢复',
              onPressed: _entries == null || _entries!.isEmpty ? null : _restoreAll,
              icon: const Icon(Icons.restore, color: Colors.green),
            ),
          if (!_selectionMode)
            IconButton(
              tooltip: '全部删除',
              onPressed: _entries == null || _entries!.isEmpty
                  ? null
                  : _deleteAll,
              icon: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectionMode
          ? _buildSelectionBar()
          : null,
    );
  }

  Widget _buildSelectionBar() {
    final entries = _entries;
    final allSelected =
        entries != null && entries.isNotEmpty && _selectedIds.length == entries.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                allSelected
                    ? Icons.deselect_outlined
                    : Icons.select_all_outlined,
              ),
              label: Text(allSelected ? '取消全选' : '全选'),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty ? null : _restoreSelected,
              icon: const Icon(Icons.restore),
              label: const Text('恢复'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text('加载失败\n$_error', textAlign: TextAlign.center),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_selectionMode ? '没有选择项' : '回收站为空'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = _selectedIds.contains(entry.id);
          return ListTile(
            selected: selected,
            leading: _TrashThumbnail(
              future: _previewPath(entry),
              mediaType: entry.mediaType,
            ),
            title: Text(
              entry.originalFileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatDateTime(entry.trashedAt)} · ${formatBytes(entry.size)}',
            ),
            onTap: () => _selectionMode
                ? _toggleSelected(entry)
                : _openDetail(entry),
            onLongPress: () => _enterSelection(entry),
            selectedTileColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            trailing: _selectionMode
                ? Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '恢复',
                        onPressed: () => _restore(entry),
                        icon: const Icon(Icons.restore, color: Colors.green),
                      ),
                      IconButton(
                        tooltip: '彻底删除',
                        onPressed: () => _confirmPermanentDelete(entry),
                        icon: const Icon(Icons.delete_forever_outlined,
                            color: Colors.redAccent),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _TrashThumbnail extends StatelessWidget {
  const _TrashThumbnail({required this.future, required this.mediaType});

  final Future<String> future;
  final String mediaType;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Image.file(
                File(snapshot.data!),
                fit: BoxFit.cover,
                cacheWidth: 256,
                errorBuilder: (_, _, _) => _icon(context),
              );
            }
            return _icon(context);
          },
        ),
      ),
    );
  }

  Widget _icon(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        mediaType == 'video' ? Icons.movie_outlined : Icons.photo_outlined,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
