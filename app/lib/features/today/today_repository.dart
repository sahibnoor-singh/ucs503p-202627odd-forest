import '../../models/feed_item.dart';
import '../../services/api_client.dart';

/// The question of the day (`GET /api/prompts/today`).
class DailyPrompt {
  const DailyPrompt({required this.day, required this.text, required this.topic, required this.answerCount, required this.answered});

  factory DailyPrompt.fromJson(Map<String, dynamic> json) => DailyPrompt(
        day: json['day'] as String,
        text: json['text'] as String,
        topic: json['topic'] as String? ?? '',
        answerCount: (json['answerCount'] as num?)?.toInt() ?? 0,
        answered: json['answered'] == true,
      );

  /// `YYYY-MM-DD`; what an answer is tagged with.
  final String day;
  final String text;
  final String topic;
  final int answerCount;

  /// This person has already answered it.
  final bool answered;

  DailyPrompt copyWith({int? answerCount, bool? answered}) =>
      DailyPrompt(day: day, text: text, topic: topic, answerCount: answerCount ?? this.answerCount, answered: answered ?? this.answered);
}

/// The "what to do today" calls of `docs/api.md`.
class TodayRepository {
  TodayRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  static List<FeedItem> _items(Map<String, dynamic> json) => [
        for (final raw in (json['items'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) FeedItem.fromJson(raw),
      ];

  Future<DailyPrompt> prompt() async => DailyPrompt.fromJson(_map(await _api.getJson('/api/prompts/today')));

  /// People's video answers to today's question, newest first.
  Future<List<FeedItem>> answers({int limit = 20}) async =>
      _items(_map(await _api.getJson('/api/prompts/today/answers', query: {'limit': '$limit'})));

  /// Recent opinions nobody has answered (or only once or twice), that this person has not answered.
  Future<List<FeedItem>> replyWanted({int limit = 5}) async =>
      _items(_map(await _api.getJson('/api/reply-wanted', query: {'limit': '$limit'})));
}
