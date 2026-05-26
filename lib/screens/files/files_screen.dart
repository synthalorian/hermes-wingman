import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../services/hermes_api_client.dart' show BackendService;
import '../../models/hermes_models.dart';

/// File explorer with system-wide browsing and right-click context menus.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  FileListing _listing = FileListing();
  bool _loading = true;
  bool _loadingFile = false;
  String? _error;
  String _currentPath = ''; // empty = home (~)
  String? _fileContent;
  String? _fileContentError;
  String? _viewingFile;
  final TextEditingController _pathCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDirectory('');
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  String get _fullCurPath => _currentPath.isEmpty ? '~' : _currentPath;

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = path;
      _pathCtrl.text = path;
      _fileContent = null;
      _viewingFile = null;
    });
    try {
      final client = context.read<HermesService>();
      final listing = await client.listFiles(path: path);
      if (!mounted) return;
      setState(() { _listing = listing; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _readFile(String fileName) async {
    final path = _currentPath.isEmpty ? fileName : '$_currentPath/$fileName';
    setState(() { _loadingFile = true; _fileContent = null; _fileContentError = null; _viewingFile = fileName; });
    try {
      final client = context.read<HermesService>();
      final content = await client.readFile(path);
      if (!mounted) return;
      setState(() { _fileContent = content; _loadingFile = false; if (content == null) _fileContentError = 'File is empty or could not be read'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _fileContentError = e.toString(); _loadingFile = false; });
    }
  }

  void _navigateToDir(String dir) {
    _loadDirectory(_currentPath.isEmpty ? dir : '$_currentPath/$dir');
  }

  void _navigateBreadcrumb(int index) {
    if (index == 0) { _loadDirectory(''); }
    else { _loadDirectory(_currentPath.split('/').take(index).join('/')); }
  }

  String _fullPath(String name) => _currentPath.isEmpty ? name : '$_currentPath/$name';

  Future<void> _showContextMenu(String name, bool isDir, Offset pos) async {
    final scheme = context.read<ThemeManager>().currentScheme;
    final full = _fullPath(name);
    final backend = context.read<BackendService>();

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      color: scheme.surface.withAlpha(235),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: scheme.borderDim.withAlpha(40))),
      items: [
        if (isDir)
          PopupMenuItem(value: 'open', child: _menuItem(scheme, Icons.folder_open, 'Open'))
        else ...[
          PopupMenuItem(value: 'view', child: _menuItem(scheme, Icons.visibility_outlined, 'View')),
          PopupMenuItem(value: 'edit', child: _menuItem(scheme, Icons.edit_outlined, 'Open in Editor')),
        ],
        if (!isDir)
          PopupMenuItem(value: 'xdg', child: _menuItem(scheme, Icons.open_in_new, 'Open w/ Default App')),
        PopupMenuItem(value: 'copy_path', child: _menuItem(scheme, Icons.link, 'Copy Path')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'rename', child: _menuItem(scheme, Icons.edit, 'Rename', scheme.accent)),
        PopupMenuItem(value: 'duplicate', child: _menuItem(scheme, Icons.content_copy, 'Duplicate', scheme.accent)),
        PopupMenuItem(value: 'delete', child: _menuItem(scheme, Icons.delete_outline, 'Delete…', scheme.error)),
      ],
    );

    if (result == null) return;

    switch (result) {
      case 'open':
        _navigateToDir(name);
      case 'view':
        _readFile(name);
      case 'edit':
        _readFile(name);
      case 'xdg':
        try {
          await Process.run('xdg-open', [_fullPath(name)]);
        } catch (_) {}
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: _fullPath(name)));
        _showSnack('Path copied: ${_fullPath(name)}', scheme);
      case 'rename':
        _showRenameDialog(name, isDir, backend, scheme);
      case 'duplicate':
        _showDuplicateDialog(name, isDir, backend, scheme);
      case 'delete':
        _showDeleteConfirm(name, isDir, backend, scheme);
    }
  }

  Widget _menuItem(AppColorScheme s, IconData icon, String text, [Color? color]) {
    return Row(children: [
      Icon(icon, size: 14, color: color ?? s.textDim),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: color ?? s.text, fontSize: 11)),
    ]);
  }

  Future<void> _showRenameDialog(String name, bool isDir, BackendService backend, AppColorScheme scheme) async {
    final ctrl = TextEditingController(text: name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: scheme.borderDim.withAlpha(50))),
        title: Text('Rename', style: TextStyle(color: scheme.text, fontSize: 14)),
        content: TextField(controller: ctrl, autofocus: true,
          style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(filled: true, fillColor: scheme.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Rename', style: TextStyle(color: scheme.primary))),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == name) return;
    try {
      await backend.renameFile(_fullPath(name), newName);
      _loadDirectory(_currentPath);
      _showSnack('Renamed to $newName', scheme);
    } catch (e) { _showSnack('Error: $e', scheme, isError: true); }
    ctrl.dispose();
  }

  Future<void> _showDuplicateDialog(String name, bool isDir, BackendService backend, AppColorScheme scheme) async {
    // Simple approach: read the file and write to a new name
    try {
      final client = context.read<HermesService>();
      final content = await client.readFile(_fullPath(name));
      if (content != null) {
        final parts = name.split('.');
        String newName;
        if (parts.length > 1) {
          newName = '${parts.sublist(0, parts.length - 1).join('.')}_copy.${parts.last}';
        } else {
          newName = '${name}_copy';
        }
        await client.writeFile(_fullPath(newName), content);
        _loadDirectory(_currentPath);
        _showSnack('Created $newName', scheme);
      }
    } catch (e) { _showSnack('Error: $e', scheme, isError: true); }
  }

  Future<void> _showDeleteConfirm(String name, bool isDir, BackendService backend, AppColorScheme scheme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: scheme.borderDim.withAlpha(50))),
        title: Text(isDir ? 'Delete Directory' : 'Delete File', style: TextStyle(color: scheme.text, fontSize: 14)),
        content: Text('Delete "$name"?${isDir ? '\nThis will permanently delete the directory and all its contents.' : ''}',
            style: TextStyle(color: scheme.textDim, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: scheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await backend.deleteFile(_fullPath(name));
      _loadDirectory(_currentPath);
      _showSnack('Deleted $name', scheme);
    } catch (e) { _showSnack('Error: $e', scheme, isError: true); }
  }

  Future<void> _showNewFolderDialog() async {
    final scheme = context.read<ThemeManager>().currentScheme;
    final backend = context.read<BackendService>();
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: scheme.borderDim.withAlpha(50))),
        title: Text('New Folder', style: TextStyle(color: scheme.text, fontSize: 14)),
        content: TextField(controller: ctrl, autofocus: true,
          style: TextStyle(color: scheme.text, fontSize: 12),
          decoration: InputDecoration(hintText: 'folder name', filled: true, fillColor: scheme.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Create', style: TextStyle(color: scheme.primary))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await backend.createDirectory(_currentPath, name);
      _loadDirectory(_currentPath);
    } catch (e) { _showSnack('Error: $e', scheme, isError: true); }
    ctrl.dispose();
  }

  void _showSnack(String msg, AppColorScheme scheme, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: scheme.text, fontSize: 10)),
      backgroundColor: isError ? scheme.error.withAlpha(200) : scheme.surface,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: const Text('Files', style: TextStyle(fontSize: 15)),
        actions: [
          IconButton(icon: Icon(Icons.create_new_folder_outlined, size: 16, color: scheme.textMuted),
            onPressed: _showNewFolderDialog, tooltip: 'New Folder'),
          IconButton(icon: Icon(Icons.refresh, size: 16, color: scheme.textMuted),
            onPressed: _viewingFile != null ? () => _readFile(_viewingFile!) : () => _loadDirectory(_currentPath)),
        ],
      ),
      body: Column(children: [_buildBreadcrumbBar(scheme), if (_viewingFile != null) _buildBackButton(scheme), Expanded(child: _buildContent(scheme))]),
    );
  }

  Widget _buildBackButton(AppColorScheme s) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
    child: SizedBox(width: double.infinity, child: Material(
      color: s.primary.withAlpha(15), borderRadius: BorderRadius.circular(6),
      child: InkWell(borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() { _fileContent = null; _viewingFile = null; }),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back, size: 14, color: s.primary),
            const SizedBox(width: 4),
            Text('Back', style: TextStyle(color: s.primary, fontSize: 11)),
          ])),
      ),
    )),
  );

  Widget _buildBreadcrumbBar(AppColorScheme s) {
    final crumbs = _currentPath.isEmpty ? <String>[] : _currentPath.split('/');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(color: s.surfaceAlt, border: Border(bottom: BorderSide(color: s.borderDim, width: 0.5))),
      child: Row(children: [
        // Home
        GestureDetector(onTap: () => _loadDirectory(''),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.home_outlined, size: 12, color: _currentPath.isEmpty ? s.primary : s.textDim),
              const SizedBox(width: 3),
              Text('Home', style: TextStyle(color: _currentPath.isEmpty ? s.primary : s.textDim, fontSize: 11, fontFamily: 'monospace', fontWeight: _currentPath.isEmpty ? FontWeight.w600 : FontWeight.w400)),
            ])),
        ),
        // Root
        GestureDetector(onTap: () => _loadDirectory('/'),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_outlined, size: 12, color: _currentPath == '/' ? s.primary : s.textDim),
              const SizedBox(width: 3),
              Text('/', style: TextStyle(color: _currentPath == '/' ? s.primary : s.textDim, fontSize: 11, fontFamily: 'monospace', fontWeight: _currentPath == '/' ? FontWeight.w600 : FontWeight.w400)),
            ])),
        ),
        // Breadcrumbs
        Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (int i = 0; i < crumbs.length; i++) ...[
              Icon(Icons.chevron_right, size: 12, color: s.textMuted),
              GestureDetector(onTap: () => _navigateBreadcrumb(i + 1),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(crumbs[i], style: TextStyle(color: i == crumbs.length - 1 ? s.primary : s.textDim, fontSize: 11, fontFamily: 'monospace', fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400))),
              ),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _buildContent(AppColorScheme s) {
    // File viewer
    if (_viewingFile != null) {
      if (_loadingFile) return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
      if (_fileContentError != null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.description_outlined, size: 36, color: s.error.withAlpha(150)), const SizedBox(height: 12),
        Text('Could not read', style: TextStyle(color: s.textDim, fontSize: 13)),
        const SizedBox(height: 6), Text(_fileContentError!, style: TextStyle(color: s.textMuted, fontSize: 10, fontFamily: 'monospace'), textAlign: TextAlign.center),
      ]));
      return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: s.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: s.borderDim, width: 0.5)),
          child: Row(children: [
            Icon(Icons.insert_drive_file_outlined, size: 14, color: s.textDim), const SizedBox(width: 6),
            Text(_viewingFile!, style: TextStyle(color: s.text, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w500)),
            const Spacer(),
            if (_fileContent != null) Text('${_fileContent!.split('\n').length} lines', style: TextStyle(color: s.textMuted, fontSize: 10, fontFamily: 'monospace')),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: s.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: s.borderDim, width: 0.5)),
          child: SingleChildScrollView(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Text(_fileContent ?? '(empty)', style: TextStyle(color: s.text, fontSize: 11, fontFamily: 'monospace', height: 1.6))))),
        ),
      ]));
    }

    // Directory listing
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
    if (_error != null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.folder_off_outlined, size: 40, color: s.error.withAlpha(150)), const SizedBox(height: 12),
      Text('Could not load', style: TextStyle(color: s.textDim, fontSize: 14)), const SizedBox(height: 6),
      Text(_error!, style: TextStyle(color: s.textMuted, fontSize: 10, fontFamily: 'monospace'), textAlign: TextAlign.center),
    ]));
    if (_listing.directories.isEmpty && _listing.files.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.folder_open_outlined, size: 36, color: s.textMuted), const SizedBox(height: 10),
      Text('Empty directory', style: TextStyle(color: s.textDim, fontSize: 13)),
    ]));

    return Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: s.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: s.borderDim, width: 0.5)),
        child: Row(children: [
          Icon(Icons.folder_outlined, size: 12, color: s.textDim), const SizedBox(width: 6),
          Text('${_listing.directories.length} dirs', style: TextStyle(color: s.textDim, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          Icon(Icons.insert_drive_file_outlined, size: 12, color: s.textDim), const SizedBox(width: 6),
          Text('${_listing.files.length} files', style: TextStyle(color: s.textDim, fontSize: 10, fontFamily: 'monospace')),
          const Spacer(),
          Text(_fullCurPath, style: TextStyle(color: s.textMuted, fontSize: 9, fontFamily: 'monospace')),
        ]),
      ),
      Expanded(child: ListView(children: [
        for (final dir in _listing.directories) _FileEntry(
          scheme: s, name: dir, isDirectory: true,
          onTap: () => _navigateToDir(dir),
          onSecondaryTap: (pos) => _showContextMenu(dir, true, pos),
        ),
        for (final file in _listing.files) _FileEntry(
          scheme: s, name: file, isDirectory: false,
          onTap: () => _readFile(file),
          onSecondaryTap: (pos) => _showContextMenu(file, false, pos),
        ),
      ])),
    ]));
  }
}

class _FileEntry extends StatelessWidget {
  final AppColorScheme scheme;
  final String name;
  final bool isDirectory;
  final VoidCallback onTap;
  final void Function(Offset)? onSecondaryTap;

  const _FileEntry({required this.scheme, required this.name, required this.isDirectory, required this.onTap, this.onSecondaryTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: (details) => onSecondaryTap?.call(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.borderDim.withAlpha(40), width: 0.5),
          ),
          child: Row(children: [
            Icon(isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                size: 16, color: isDirectory ? scheme.warning ?? scheme.accent : scheme.textDim),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'))),
            GestureDetector(
              onTap: () => onSecondaryTap?.call((context.findRenderObject() as RenderBox).localToGlobal(Offset.zero) + const Offset(40, 0)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: scheme.textMuted.withAlpha(15), borderRadius: BorderRadius.circular(4)),
                child: Icon(Icons.more_vert, size: 12, color: scheme.textMuted.withAlpha(150)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}