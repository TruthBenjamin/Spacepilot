import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/storage_history_entry.dart';

final class StorageHistoryService {
  StorageHistoryService({this._maxEntries = 30});

  final int _maxEntries;
  static final List<StorageHistoryEntry> _memoryHistory =
      <StorageHistoryEntry>[];

  Future<Directory?> _storageDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Storage history is not supported on the web.');
    }

    try {
      final directory = await getApplicationSupportDirectory();
      final storageDirectory = Directory(
        path.join(directory.path, 'spacepilot_history'),
      );
      await storageDirectory.create(recursive: true);
      return storageDirectory;
    } on MissingPluginException {
      return null;
    }
  }

  Future<File?> get _historyFile async {
    final directory = await _storageDirectory();
    if (directory == null) return null;
    return File(path.join(directory.path, 'storage_history.json'));
  }

  Future<List<StorageHistoryEntry>> loadHistory() async {
    if (kIsWeb) return const [];

    final file = await _historyFile;
    if (file == null) {
      return List<StorageHistoryEntry>.unmodifiable(_memoryHistory);
    }
    if (!await file.exists()) {
      return List<StorageHistoryEntry>.unmodifiable(_memoryHistory);
    }

    final contents = await file.readAsString();
    final raw = jsonDecode(contents);
    if (raw is! List<Object?>) {
      return List<StorageHistoryEntry>.unmodifiable(_memoryHistory);
    }

    return raw
        .whereType<Map<String, Object?>>()
        .map(StorageHistoryEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> appendEntry(StorageHistoryEntry entry) async {
    if (kIsWeb) return;

    final file = await _historyFile;
    if (file == null) {
      _memoryHistory.add(entry);
      if (_memoryHistory.length > _maxEntries) {
        _memoryHistory.removeRange(0, _memoryHistory.length - _maxEntries);
      }
      return;
    }

    final existing = await loadHistory();
    final history = [...existing, entry];

    if (history.length > _maxEntries) {
      history.removeRange(0, history.length - _maxEntries);
    }

    await file.writeAsString(
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    if (kIsWeb) return;

    final file = await _historyFile;
    if (file == null) {
      _memoryHistory.clear();
      return;
    }

    if (await file.exists()) {
      await file.delete();
    }
  }
}
