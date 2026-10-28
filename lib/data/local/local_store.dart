import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/catalog.dart';

/// Small on-device store (IndexedDB on web). Holds preferences and the last
/// downloaded catalog so the shop opens instantly, even without internet.
class LocalStore {
  LocalStore._(this._prefs, this._cache);

  final _KeyValue _prefs;
  final _KeyValue _cache;

  static Future<LocalStore> open() async {
    await Hive.initFlutter('chhabra_store');
    final prefs = await Hive.openBox<dynamic>('prefs');
    final cache = await Hive.openBox<dynamic>('cache');
    return LocalStore._(_HiveKeyValue(prefs), _HiveKeyValue(cache));
  }

  /// Widget tests: everything in memory, nothing touches the disk.
  factory LocalStore.memory() => LocalStore._(_MemoryKeyValue(), _MemoryKeyValue());

  T? pref<T>(String key) {
    final v = _prefs.get(key);
    return v is T ? v : null;
  }

  Future<void> setPref(String key, Object? value) => value == null ? _prefs.delete(key) : _prefs.put(key, value);

  Catalog? readCatalog(String key) {
    final raw = _cache.get('catalog:$key');
    if (raw is! String) return null;
    try {
      return Catalog.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null; // old/corrupt cache → just download again
    }
  }

  Future<void> writeCatalog(String key, Catalog catalog) => _cache.put('catalog:$key', jsonEncode(catalog.toJson()));

  Future<void> clearCatalogs() async {
    for (final k in _cache.keys.where((k) => k.startsWith('catalog:')).toList()) {
      await _cache.delete(k);
    }
  }
}

abstract class _KeyValue {
  Object? get(String key);
  Future<void> put(String key, Object value);
  Future<void> delete(String key);
  Iterable<String> get keys;
}

class _HiveKeyValue implements _KeyValue {
  _HiveKeyValue(this._box);
  final Box<dynamic> _box;
  @override
  Object? get(String key) => _box.get(key);
  @override
  Future<void> put(String key, Object value) => _box.put(key, value);
  @override
  Future<void> delete(String key) => _box.delete(key);
  @override
  Iterable<String> get keys => _box.keys.map((k) => k.toString());
}

class _MemoryKeyValue implements _KeyValue {
  final _map = <String, Object>{};
  @override
  Object? get(String key) => _map[key];
  @override
  Future<void> put(String key, Object value) async => _map[key] = value;
  @override
  Future<void> delete(String key) async => _map.remove(key);
  @override
  Iterable<String> get keys => _map.keys;
}
