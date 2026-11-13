// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/caption_cue.dart';
import 'api_client.dart';

/// Subtitles: whether they are on and in which language (one setting for the whole app, remembered between launches),
/// and the subtitle lines of each post, fetched once per language and kept for the session.
///
/// [language] is `original` (what is spoken in the video), or a code such as `en` or `hi`. English is the default.
class CaptionService extends ChangeNotifier {
  CaptionService(this._api, {bool enabled = true, String language = 'en', bool restore = true})
      : _enabled = enabled,
        _language = language {
    if (restore) unawaited(_restore());
  }

  static const _onKey = 'forest.captions.on';
  static const _languageKey = 'forest.captions.lang';

  final ApiClient _api;
  final Map<String, Future<CaptionTrack?>> _cache = {};
  final Map<String, String> _spoken = {};
  bool _enabled;
  String _language;

  bool get enabled => _enabled;
  String get language => _language;

  /// The language spoken in a post's video, once its subtitles have been loaded (null before that, or when unknown).
  String? spokenLanguage(String postId) => _spoken[postId];

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(_onKey);
      final lang = prefs.getString(_languageKey);
      if ((on != null && on != _enabled) || (lang != null && lang != _language)) {
        _enabled = on ?? _enabled;
        _language = lang ?? _language;
        notifyListeners();
      }
    } catch (_) {
      // no stored setting: keep the defaults
    }
  }

  /// Switches subtitles off (null) or on in [language] (`original`, `en`, `hi`, ...).
  Future<void> select(String? language) async {
    _enabled = language != null;
    if (language != null) _language = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onKey, _enabled);
      await prefs.setString(_languageKey, _language);
    } catch (_) {
      // the setting just does not survive a restart
    }
  }

  /// Subtitle lines of [postId] in [language] (default: the chosen one). Resolves to null when they could not be
  /// loaded, which is not remembered, so the next call tries again.
  Future<CaptionTrack?> trackFor(String postId, {String? language}) {
    final lang = language ?? _language;
    final key = '$postId:$lang';
    return _cache.putIfAbsent(key, () async {
      try {
        final body = await _api.getJson(
          '/api/posts/${Uri.encodeComponent(postId)}/captions',
          query: {'lang': lang},
        );
        final track = CaptionTrack.fromJson(body);
        if (track.language != null) _spoken[postId] = track.language!;
        return track;
      } catch (_) {
        _cache.remove(key);
        return null;
      }
    });
  }
}
