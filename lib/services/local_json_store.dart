import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Tiny best-effort JSON file store used for the reading history and the
/// search index. Reads and writes never throw: if storage is unavailable
/// the app simply behaves as if nothing was saved.
class LocalJsonStore {
  LocalJsonStore._();

  static Future<File> _file(String name) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/app_data');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$name.json');
  }

  static Future<dynamic> read(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, Object data) async {
    try {
      final file = await _file(name);
      // Write to a temp file first so a crash mid-write can't corrupt
      // the saved copy.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Ignore — saving is best-effort.
    }
  }
}
