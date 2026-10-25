import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/drive_node.dart';
import 'local_json_store.dart';

/// One PDF the student has opened, plus where they stopped reading.
class ReadingEntry {
  final String id;
  final String name;
  final String? mimeType;
  final int? sizeBytes;
  final String? modifiedAt;
  final String? viewUrl;
  final String? downloadUrl;
  int lastPage;
  int totalPages;
  int lastOpened;

  ReadingEntry({
    required this.id,
    required this.name,
    this.mimeType,
    this.sizeBytes,
    this.modifiedAt,
    this.viewUrl,
    this.downloadUrl,
    this.lastPage = 1,
    this.totalPages = 0,
    required this.lastOpened,
  });

  DriveNode toNode() => DriveNode(
        type: 'file',
        id: id,
        name: name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        modifiedAt: modifiedAt,
        viewUrl: viewUrl,
        downloadUrl: downloadUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt,
        'viewUrl': viewUrl,
        'downloadUrl': downloadUrl,
        'lastPage': lastPage,
        'totalPages': totalPages,
        'lastOpened': lastOpened,
      };

  factory ReadingEntry.fromJson(Map<String, dynamic> json) => ReadingEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        mimeType: json['mimeType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        modifiedAt: json['modifiedAt'] as String?,
        viewUrl: json['viewUrl'] as String?,
        downloadUrl: json['downloadUrl'] as String?,
        lastPage: (json['lastPage'] as num?)?.toInt() ?? 1,
        totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
        lastOpened: (json['lastOpened'] as num?)?.toInt() ?? 0,
      );
}

/// Remembers the PDFs a student opened and the last page they reached.
/// Stored on the device only (not synced between phones).
class ReadingHistoryService {
  ReadingHistoryService._();
  static final ReadingHistoryService instance = ReadingHistoryService._();

  static const _fileName = 'reading_history';
  static const _maxEntries = 15;

  /// Most recently opened first. The home screen listens to this.
  final ValueNotifier<List<ReadingEntry>> entries =
      ValueNotifier<List<ReadingEntry>>(const []);

  List<ReadingEntry> _items = [];
  Future<void>? _loading;
  Timer? _saveTimer;

  Future<void> load() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    final raw = await LocalJsonStore.read(_fileName);
    if (raw is List) {
      final parsed = <ReadingEntry>[];
      for (final item in raw) {
        try {
          parsed.add(ReadingEntry.fromJson(Map<String, dynamic>.from(item as Map)));
        } catch (_) {
          // Skip a damaged entry rather than losing the whole history.
        }
      }
      _items = parsed;
    }
    _publish();
  }

  void _publish() => entries.value = List.unmodifiable(_items);

  void _persist() => LocalJsonStore.write(
        _fileName,
        _items.map((e) => e.toJson()).toList(),
      );

  ReadingEntry? _find(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The page to open this PDF on. Falls back to page 1 if the file was
  /// replaced in Drive since it was last read.
  int startPageFor(DriveNode node) {
    final e = _find(node.id);
    if (e == null || e.modifiedAt != node.modifiedAt) return 1;
    if (e.totalPages > 0 && e.lastPage > e.totalPages) return 1;
    return e.lastPage < 1 ? 1 : e.lastPage;
  }

  /// Call when a PDF is opened: moves it to the top of the list.
  Future<void> recordOpen(DriveNode node) async {
    await load();
    final existing = _find(node.id);
    final sameVersion = existing != null && existing.modifiedAt == node.modifiedAt;
    final entry = ReadingEntry(
      id: node.id,
      name: node.name,
      mimeType: node.mimeType,
      sizeBytes: node.sizeBytes,
      modifiedAt: node.modifiedAt,
      viewUrl: node.viewUrl,
      downloadUrl: node.downloadUrl,
      lastPage: sameVersion ? existing.lastPage : 1,
      totalPages: sameVersion ? existing.totalPages : 0,
      lastOpened: DateTime.now().millisecondsSinceEpoch,
    );
    _items.removeWhere((e) => e.id == node.id);
    _items.insert(0, entry);
    if (_items.length > _maxEntries) {
      _items.removeRange(_maxEntries, _items.length);
    }
    _persist();
    _publish();
  }

  /// Called while reading. Saved to disk shortly after the last change.
  void saveProgress(String id, {int? page, int? total}) {
    final e = _find(id);
    if (e == null) return;
    if (page != null) e.lastPage = page;
    if (total != null) e.totalPages = total;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _persist);
  }

  /// Writes immediately and refreshes the home screen's list. Called when
  /// the reader closes.
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _persist();
    // Deferred: this runs while the reader screen is being torn down, and
    // other screens must not be notified in the middle of that.
    scheduleMicrotask(_publish);
  }
}
