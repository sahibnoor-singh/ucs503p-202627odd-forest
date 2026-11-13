import 'package:shared_preferences/shared_preferences.dart';

/// The last few things this person searched for, kept on the phone only (never sent anywhere). Newest first, no repeats
/// (ignoring capitals). Reading or writing can fail (private storage, a full disk): then there are simply no recent searches.
class RecentSearches {
  RecentSearches({this.max = 8});

  static const _key = 'discover_recent_searches';
  final int max;

  Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } on Object {
      return const [];
    }
  }

  Future<List<String>> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return load();
    final list = [q, ...(await load()).where((r) => r.toLowerCase() != q.toLowerCase())].take(max).toList();
    return _save(list);
  }

  Future<List<String>> remove(String query) async => _save((await load()).where((r) => r != query).toList());

  Future<List<String>> clear() => _save(const []);

  Future<List<String>> _save(List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, list);
    } on Object {
      // not kept this time
    }
    return list;
  }
}
