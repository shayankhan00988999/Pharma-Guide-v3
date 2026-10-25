import 'package:flutter/material.dart';
import '../models/drive_node.dart';
import '../services/drive_service.dart';
import '../services/auth_service.dart';
import '../services/reading_history_service.dart';
import '../services/search_index_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_shimmer.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/file_tile.dart';
import '../widgets/folder_card.dart';
import '../widgets/folder_result_tile.dart';
import '../widgets/recent_pdf_card.dart';
import 'document_viewer_screen.dart';
import 'folder_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _driveService = DriveService();
  late Future<DriveNode> _treeFuture;
  final _searchController = TextEditingController();

  String get _query => _searchController.text;

  @override
  void initState() {
    super.initState();
    _treeFuture = _driveService.fetchNode();
    ReadingHistoryService.instance.load();
    SearchIndexService.instance.ensureFresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = _driveService.fetchNode(forceRefresh: true);
    // Pulling to refresh also refreshes what search knows about.
    SearchIndexService.instance.rebuild();
    setState(() => _treeFuture = future);
    await future;
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<DriveNode>(
          future: _treeFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CustomScrollView(
                slivers: [
                  _buildHeaderSliver(itemsLabel: 'Loading your notes…'),
                  const SliverToBoxAdapter(child: DashboardShimmer()),
                ],
              );
            }

            if (snapshot.hasError) {
              return CustomScrollView(
                slivers: [
                  _buildHeaderSliver(itemsLabel: 'Something went wrong'),
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('${snapshot.error}', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final root = snapshot.data!;
            final subfolders = root.children.where((c) => c.isFolder).toList();
            final files = root.children.where((c) => !c.isFolder).toList();

            if (root.children.isEmpty) {
              return CustomScrollView(
                slivers: [
                  _buildHeaderSliver(itemsLabel: 'No notes uploaded yet'),
                  const SliverFillRemaining(
                    child: Center(child: Text('No notes uploaded yet.')),
                  ),
                ],
              );
            }

            final searching = _query.trim().isNotEmpty;

            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                _buildHeaderSliver(
                  itemsLabel:
                      '${subfolders.length} folders · ${files.length} files',
                ),
                _buildSearchFieldSliver(),
                if (searching)
                  ..._buildSearchResultSlivers()
                else ...[
                _buildRecentSliver(),
                if (subfolders.isNotEmpty) ...[
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text('Folders',
                          style:
                              TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.15,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final folder = subfolders[index];
                          return FadeSlideIn(
                            delay: Duration(milliseconds: 40 * index),
                            child: FolderCard(
                              node: folder,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FolderScreen(node: folder),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: subfolders.length,
                      ),
                    ),
                  ),
                ],
                if (files.isNotEmpty) ...[
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: Text('Files',
                          style:
                              TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => FileTile(node: files[index]),
                        childCount: files.length,
                      ),
                    ),
                  ),
                ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchFieldSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search notes, slides, textbooks…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchResultSlivers() {
    final service = SearchIndexService.instance;
    return [
      ValueListenableBuilder<bool>(
        valueListenable: service.indexing,
        builder: (context, indexing, _) {
          if (!indexing) return const SliverToBoxAdapter(child: SizedBox.shrink());
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Still indexing your library — more results may appear',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      ValueListenableBuilder<int>(
        valueListenable: service.revision,
        builder: (context, _, __) {
          final results = service.search(_query);
          if (results.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No results for “${_query.trim()}”',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = results[index];
                  final node = entry.toNode();
                  if (entry.isFolder) {
                    return FolderResultTile(
                      node: node,
                      location: entry.path,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FolderScreen(node: node),
                        ),
                      ),
                    );
                  }
                  return FileTile(node: node, location: entry.path);
                },
                childCount: results.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildRecentSliver() {
    return ValueListenableBuilder<List<ReadingEntry>>(
      valueListenable: ReadingHistoryService.instance.entries,
      builder: (context, list, _) {
        if (list.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('Recently opened',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final entry = list[index];
                    return RecentPdfCard(
                      entry: entry,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DocumentViewerScreen(node: entry.toNode()),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderSliver({required String itemsLabel}) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      backgroundColor: AppColors.teal,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          tooltip: 'Log out',
          onPressed: _logout,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.teal, AppColors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.local_pharmacy_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Shayan Pharma Guide',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    itemsLabel,
                    style: TextStyle(color: Colors.white.withOpacity(0.85)),
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
