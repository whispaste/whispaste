/// Manages recent search queries for the history smart search panel.
///
/// Persists the last 5 unique queries via [SharedPreferences].
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefKey = 'recent_searches';
const _kMaxEntries = 5;

/// Notifier that tracks and persists recent search queries.
class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      state = list.take(_kMaxEntries).toList();
    } catch (_) {
      // Corrupted data — reset silently.
    }
  }

  /// Adds [query] to the front. De-duplicates and caps at 5 entries.
  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      trimmed,
      ...state.where((s) => s != trimmed),
    ].take(_kMaxEntries).toList();
    state = updated;
    await _persist(updated);
  }

  /// Removes a single entry by value.
  Future<void> removeSearch(String query) async {
    final updated = state.where((s) => s != query).toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> _persist(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, jsonEncode(list));
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );
