import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_service.dart';
import '../../models/hermes_models.dart';

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
  String _currentPath = '';
  String? _fileContent;
  String? _fileContentError;
  String? _viewingFile;

  @override
  void initState() {
    super.initState();
    _loadDirectory('');
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPath = path;
      _fileContent = null;
      _viewingFile = null;
    });

    try {
      final client = context.read<HermesService>();
      final listing = await client.listFiles(path: path);

      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _readFile(String fileName) async {
    final path = _currentPath.isEmpty ? fileName : '$_currentPath/$fileName';
    setState(() {
      _loadingFile = true;
      _fileContent = null;
      _fileContentError = null;
      _viewingFile = fileName;
    });

    try {
      final client = context.read<HermesService>();
      final content = await client.readFile(path);

      if (!mounted) return;
      setState(() {
        _fileContent = content;
        _loadingFile = false;
        if (content == null) {
          _fileContentError = 'File is empty or could not be read';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fileContentError = e.toString();
        _loadingFile = false;
      });
    }
  }

  void _navigateToDir(String dir) {
    final path = _currentPath.isEmpty ? dir : '$_currentPath/$dir';
    _loadDirectory(path);
  }

  void _navigateBreadcrumb(int index) {
    if (index == 0) {
      _loadDirectory('');
    } else {
      final parts = _currentPath.split('/');
      final path = parts.take(index).join('/');
      _loadDirectory(path);
    }
  }

  List<String> get _breadcrumbs {
    if (_currentPath.isEmpty) return [];
    return _currentPath.split('/');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Scaffold(
      backgroundColor: scheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: scheme.textDim),
            onPressed: _viewingFile != null
                ? () => _readFile(_viewingFile!)
                : () => _loadDirectory(_currentPath),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(AppColorScheme scheme) {
    return Column(
      children: [
        // Breadcrumb navigation
        _buildBreadcrumbBar(scheme),

        // Back button (when viewing file)
        if (_viewingFile != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      _fileContent = null;
                      _viewingFile = null;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Back to directory',
                          style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Content area
        Expanded(child: _buildContent(scheme)),
      ],
    );
  }

  Widget _buildBreadcrumbBar(AppColorScheme scheme) {
    final crumbs = _breadcrumbs;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: scheme.borderDim, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Root
            GestureDetector(
              onTap: () => _loadDirectory(''),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_outlined, size: 12, color: _currentPath.isEmpty ? scheme.primary : scheme.textDim),
                    const SizedBox(width: 3),
                    Text(
                      '~/.hermes',
                      style: TextStyle(
                        color: _currentPath.isEmpty ? scheme.primary : scheme.textDim,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: _currentPath.isEmpty ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Path segments
            for (int i = 0; i < crumbs.length; i++) ...[
              Icon(Icons.chevron_right, size: 12, color: scheme.textMuted),
              GestureDetector(
                onTap: () => _navigateBreadcrumb(i + 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    crumbs[i],
                    style: TextStyle(
                      color: i == crumbs.length - 1 ? scheme.primary : scheme.textDim,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppColorScheme scheme) {
    // File viewer
    if (_viewingFile != null) {
      if (_loadingFile) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_fileContentError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description_outlined, size: 40, color: scheme.error.withValues(alpha: 0.6)),
                const SizedBox(height: 12),
                Text('Could not read file', style: TextStyle(color: scheme.textDim, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  _fileContentError!,
                  style: TextStyle(color: scheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.borderDim, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: 14, color: scheme.textDim),
                  const SizedBox(width: 6),
                  Text(
                    _viewingFile!,
                    style: TextStyle(color: scheme.text, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  if (_fileContent != null)
                    Text(
                      '${_fileContent!.split('\n').length} lines',
                      style: TextStyle(color: scheme.textMuted, fontSize: 10, fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // File content
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.borderDim, width: 0.5),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _fileContent ?? '(empty file)',
                      style: TextStyle(
                        color: scheme.text,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.6,
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

    // Directory listing
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_off_outlined, size: 48, color: scheme.error.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text('Could not load directory', style: TextStyle(color: scheme.textDim, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.textMuted, fontSize: 12, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              MaterialButton(
                color: scheme.primary.withValues(alpha: 0.15),
                onPressed: () => _loadDirectory(_currentPath),
                child: Text('Retry', style: TextStyle(color: scheme.primary)),
              ),
            ],
          ),
        ),
      );
    }

    if (_listing.directories.isEmpty && _listing.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 40, color: scheme.textMuted),
            const SizedBox(height: 12),
            Text(
              'This directory is empty',
              style: TextStyle(color: scheme.textDim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 12, color: scheme.textDim),
                const SizedBox(width: 6),
                Text(
                  '${_listing.directories.length} directories',
                  style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 12),
                Icon(Icons.insert_drive_file_outlined, size: 12, color: scheme.textDim),
                const SizedBox(width: 6),
                Text(
                  '${_listing.files.length} files',
                  style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          // Directory entries
          Expanded(
            child: ListView(
              children: [
                // Directories
                ..._listing.directories.map((dir) => _FileEntry(
                  scheme: scheme,
                  name: dir,
                  isDirectory: true,
                  onTap: () => _navigateToDir(dir),
                )),
                // Files
                ..._listing.files.map((file) => _FileEntry(
                  scheme: scheme,
                  name: file,
                  isDirectory: false,
                  onTap: () => _readFile(file),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileEntry extends StatelessWidget {
  final AppColorScheme scheme;
  final String name;
  final bool isDirectory;
  final VoidCallback onTap;

  const _FileEntry({
    required this.scheme,
    required this.name,
    required this.isDirectory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isDirectory ? scheme.warning : scheme.textDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: scheme.text,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Icon(
                  isDirectory ? Icons.chevron_right : Icons.open_in_new,
                  size: 14,
                  color: scheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}