import 'package:flutter/foundation.dart';
import '../models/drive_node.dart';
import 'drive_service.dart';
import 'local_json_store.dart';

/// One folder or file in the searchable library index.
class IndexEntry {
  final String id;
  final String name;
  final bool isFolder;

  /// Folders it sits inside, e.g. "Pharmacology › Lecture Slides".
  /// Empty for items directly in the root folder.
  final String path;
  final String? mimeType;
  final int? sizeBytes;
  final String? modifiedAt;
  final String? viewUrl;
  final String? downloadUrl;
  final int? itemCount;

  final String nameKey;
  final String pathKey;

  IndexEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    required this.path,
    this.mimeType,
    this.sizeBytes,
    this.modifiedAt,
    this.viewUrl,
    this.downloadUrl,
    this.itemCount,
  })  : nameKey = SearchIndexService.normalize(name),
        pathKey = SearchIndexService.normalize(path);

  factory IndexEntry.fromNode(DriveNode n, String path) => IndexEntry(
        id: n.id,
        name: n.name,
        isFolder: n.isFolder,
        path: path,
        mimeType: n.mimeType,
        sizeBytes: n.sizeBytes,
        modifiedAt: n.modifiedAt,
        viewUrl: n.viewUrl,
        downloadUrl: n.downloadUrl,
        itemCount: n.isFolder ? n.displayItemCount : null,
      );

  DriveNode toNode() => DriveNode(
        type: isFolder ? 'folder' : 'file',
        id: id,
        name: name,
        itemCount: itemCount,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        modifiedAt: modifiedAt,
        viewUrl: viewUrl,
        downloadUrl: downloadUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folder': isFolder,
        'path': path,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt,
        'viewUrl': viewUrl,
        'downloadUrl': downloadUrl,
        'itemCount': itemCount,
      };

  factory IndexEntry.fromJson(Map<String, dynamic> j) => IndexEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        isFolder: j['folder'] as bool? ?? false,
        path: j['path'] as String? ?? '',
        mimeType: j['mimeType'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
        modifiedAt: j['modifiedAt'] as String?,
        viewUrl: j['viewUrl'] as String?,
        downloadUrl: j['downloadUrl'] as String?,
        itemCount: (j['itemCount'] as num?)?.toInt(),
      );
}

class _Pending {
  final String? id;
  final String path;
  const _Pending(this.id, this.path);
}

/// Builds and searches a local index of the whole library.
///
/// The Drive script only returns one folder at a time, so the app walks
/// the folder tree itself in the background (a few folders in parallel),
/// saves the result on the phone, and searches that saved list as the
/// student types. No change to the Apps Script is needed.
///
/// - The index is rebuilt automatically when it is older than 12 hours,
///   and whenever the student pulls to refresh on the home screen.
/// - Search works while the first build is still running; results simply
///   keep growing until it finishes.
class SearchIndexService {
  SearchIndexService._();
  static final SearchIndexService instance = SearchIndexService._();

  static const _fileName = 'search_index';
  static const _maxAge = Duration(hours: 12);
  static const _workerCount = 4;
  static const _maxResults = 80;

  final DriveService _drive = DriveService();

  /// Bumps every time the index changes, so the UI can refresh results.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// True while the library is being (re)indexed.
  final ValueNotifier<bool> indexing = ValueNotifier<bool>(false);

  List<IndexEntry> _entries = [];
  int _builtAtMs = 0;
  Future<void>? _loading;

  /// Lower-case, letters and digits only (any language), single spaces.
  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
  }

  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    final raw = await LocalJsonStore.read(_fileName);
    if (raw is Map) {
      _builtAtMs = (raw['builtAt'] as num?)?.toInt() ?? 0;
      final list = raw['entries'];
      if (list is List) {
        final parsed = <IndexEntry>[];
        for (final item in list) {
          try {
            parsed.add(IndexEntry.fromJson(Map<String, dynamic>.from(item as Map)));
          } catch (_) {
            // Skip a damaged entry.
          }
        }
        _entries = parsed;
        revision.value++;
      }
    }
  }

  /// Loads the saved index and rebuilds it if missing or out of date.
  Future<void> ensureFresh() async {
    await load();
    final age = DateTime.now().millisecondsSinceEpoch - _builtAtMs;
    if (_entries.isEmpty || age > _maxAge.inMilliseconds) {
      await rebuild();
    }
  }

  /// Walks the whole folder tree and replaces the saved index.
  Future<void> rebuild() async {
    if (indexing.value) return;
    await load();
    indexing.value = true;
    try {
      final found = <IndexEntry>[];
      final queue = <_Pending>[const _Pending(null, '')];
      var active = 0;
      var failed = false;
      // With no previous index, show results as they are discovered.
      final progressive = _entries.isEmpty;
      var lastPublish = DateTime.fromMillisecondsSinceEpoch(0);

      Future<void> worker() async {
        while (true) {
          if (queue.isEmpty) {
            if (active == 0) return;
            await Future.delayed(const Duration(milliseconds: 120));
            continue;
          }
          final item = queue.removeAt(0);
          active++;
          try {
            final node =
                await _drive.fetchNode(folderId: item.id, forceRefresh: true);
            for (final child in node.children) {
              found.add(IndexEntry.fromNode(child, item.path));
              if (child.isFolder) {
                queue.add(_Pending(
                  child.id,
                  item.path.isEmpty ? child.name : '${item.path} › ${child.name}',
                ));
              }
            }
          } catch (_) {
            failed = true;
          } finally {
            active--;
          }
          if (progressive &&
              DateTime.now().difference(lastPublish) >
                  const Duration(milliseconds: 700)) {
            lastPublish = DateTime.now();
            _entries = List.of(found);
            revision.value++;
          }
        }
      }

      await Future.wait(List.generate(_workerCount, (_) => worker()));

      // If some folders couldn't be read (e.g. network dropped), never
      // replace a fuller saved index with a smaller partial one.
      final keepOld = failed && _entries.length >= found.length;
      if (!keepOld) _entries = found;
      // A failed run is retried the next time the app opens.
      _builtAtMs = failed ? 0 : DateTime.now().millisecondsSinceEpoch;
      await LocalJsonStore.write(_fileName, {
        'builtAt': _builtAtMs,
        'entries': _entries.map((e) => e.toJson()).toList(),
      });
      revision.value++;
    } catch (_) {
      // Indexing is best-effort; search keeps using what it already has.
    } finally {
      indexing.value = false;
    }
  }

  /// Every word typed must appear in the item's name or the names of the
  /// folders it sits in. Name matches rank above folder-path matches, and
  /// folders (subjects/topics) rank slightly above files.
  List<IndexEntry> search(String query) {
    final terms =
        normalize(query).split(' ').where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return const [];

    final scored = <MapEntry<IndexEntry, int>>[];
    for (final e in _entries) {
      var inName = 0;
      var inPath = 0;
      var matchesAll = true;
      for (final t in terms) {
        if (e.nameKey.contains(t)) {
          inName++;
        } else if (e.pathKey.contains(t)) {
          inPath++;
        } else {
          matchesAll = false;
          break;
        }
      }
      if (!matchesAll) continue;
      var score = inName * 3 + inPath;
      if (e.nameKey.startsWith(terms.first)) score += 2;
      if (e.isFolder) score += 1;
      scored.add(MapEntry(e, score));
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return a.key.name.toLowerCase().compareTo(b.key.name.toLowerCase());
    });
    return scored.take(_maxResults).map((e) => e.key).toList();
  }
}
