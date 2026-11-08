import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'story_catalog.dart';

/// 완료 기록이 권리의 근거이며, 수집 저장이 끊겨도 대조하여 복구한다.
class CollectionRepository {
  CollectionRepository._(this._preferences, this.catalog, this.writer);
  static const storageKey = 'bloriq.collection.v1';
  static const backupKey = 'bloriq.collection.corrupt-backup.v1';
  final SharedPreferences? _preferences;
  final StoryCatalog catalog;
  final Future<bool> Function(String, String)? writer;
  final Set<String> _owned = {}, _memories = {}, _seen = {};
  final Set<String> _pending = {};
  Map<String, dynamic> _extra = {};
  String? _equipped, _raw;
  bool saveFailed = false,
      backfillPending = false,
      corrupt = false,
      futureSchema = false;
  bool _writable = true;
  Future<void> _queue = Future.value();

  Set<String> get ownedIds => Set.unmodifiable(_owned);
  Set<String> get memoryIds => Set.unmodifiable(_memories);
  Set<String> get pendingIds => Set.unmodifiable(_pending);
  bool owns(String id) => _owned.contains(id);
  bool hasSeen(String id) => _seen.contains(id);
  List<SpiritDefinition> get owned =>
      catalog.released.where((s) => owns(s.id)).toList(growable: false);
  List<SpiritDefinition> inChapter(int number) =>
      owned.where((s) => s.chapter == number).toList(growable: false);
  bool chapterComplete(int number) =>
      catalog.inChapter(number).isNotEmpty &&
      inChapter(number).length == catalog.inChapter(number).length;
  SpiritDefinition? get companion {
    final selected = catalog.byId(_equipped);
    return selected != null && selected.released && owns(selected.id)
        ? selected
        : owned.firstOrNull;
  }

  static Future<CollectionRepository> load(
    StoryCatalog catalog, {
    Future<bool> Function(String, String)? writer,
  }) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {}
    final repo = CollectionRepository._(preferences, catalog, writer);
    try {
      final raw = preferences?.getString(storageKey);
      repo._raw = raw;
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] is! int) {
          throw const FormatException('Collection schema');
        }
        if (data['version'] != 1) {
          repo.futureSchema = true;
          repo._writable = false;
        } else {
          Set<String> strings(Object? value) {
            if (value is! List || value.any((e) => e is! String)) {
              throw const FormatException('Collection IDs');
            }
            return value.cast<String>().toSet();
          }

          repo._owned.addAll(strings(data['owned']));
          repo._memories.addAll(strings(data['memories']));
          repo._seen.addAll(strings(data['seen']));
          repo._pending.addAll(strings(data['pending']));
          if (data['equipped'] != null && data['equipped'] is! String) {
            throw const FormatException('Companion ID');
          }
          repo._equipped = data['equipped'];
          repo.backfillPending = data['backfillPending'] == true;
          repo._extra = Map<String, dynamic>.from(data);
        }
      }
    } catch (_) {
      repo._writable = false;
      repo.corrupt = true;
      repo._owned.clear();
      repo._memories.clear();
      repo._seen.clear();
      repo._pending.clear();
      repo._equipped = null;
    }
    repo.saveFailed = !repo._writable || preferences == null;
    return repo;
  }

  Future<List<SpiritDefinition>> reconcile(
    Set<int> completedLevels, {
    bool backfill = false,
  }) async {
    if (!_writable) return [];
    final added = <SpiritDefinition>[];
    var changed = false;
    for (final spirit in catalog.released) {
      if (!completedLevels.contains(spirit.levelId)) continue;
      changed = _memories.add(spirit.memoryId) || changed;
      if (_owned.add(spirit.id)) {
        added.add(spirit);
        changed = true;
        if (backfill) {
          backfillPending = true;
        } else {
          _pending.add(spirit.id);
        }
        _equipped ??= spirit.id;
      }
    }
    if (changed || saveFailed) await retrySave();
    return added;
  }

  Future<bool> equip(String id) async {
    if (!_writable || !owns(id) || catalog.byId(id)?.released != true) {
      return false;
    }
    _equipped = id;
    return retrySave();
  }

  Future<bool> acknowledge(String id) async {
    if (!_writable || !owns(id)) return false;
    _pending.remove(id);
    _seen.add(id);
    return retrySave();
  }

  Future<bool> acknowledgeBackfill() async {
    if (!_writable) return false;
    backfillPending = false;
    return retrySave();
  }

  Future<bool> retrySave() async {
    final snapshot = jsonEncode({
      ..._extra,
      'version': 1,
      'owned': _owned.toList()..sort(),
      'memories': _memories.toList()..sort(),
      'seen': _seen.toList()..sort(),
      'pending': _pending.toList()..sort(),
      'equipped': _equipped,
      'backfillPending': backfillPending,
    });
    var saved = false;
    final task = _queue.then((_) async {
      if (!_writable || _preferences == null) return;
      try {
        saved =
            await (writer?.call(storageKey, snapshot) ??
                _preferences.setString(storageKey, snapshot));
      } catch (_) {}
    });
    _queue = task;
    await task;
    saveFailed = !saved;
    return saved;
  }

  /// 손상된 원문 백업이 성공한 경우에만 사용자가 요청한 복구를 수행한다.
  Future<bool> recover(Set<int> completedLevels) async {
    if (!corrupt || futureSchema || _preferences == null || _raw == null) {
      return false;
    }
    try {
      final backup =
          await (writer?.call(backupKey, _raw!) ??
              _preferences.setString(backupKey, _raw!));
      if (!backup) return false;
    } catch (_) {
      return false;
    }
    _extra = {};
    _writable = true;
    corrupt = false;
    await reconcile(completedLevels, backfill: true);
    return !saveFailed;
  }

  Future<void> flush() => _queue;
}
