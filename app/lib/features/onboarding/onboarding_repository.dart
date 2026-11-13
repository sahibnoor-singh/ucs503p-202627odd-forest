import '../../services/api_client.dart';

class OnboardingTopic {
  const OnboardingTopic({required this.id, required this.label});
  final String id;
  final String label;
}

/// What the first-run page offers: the topics and how many to ask for (`GET /api/onboarding/topics`).
class OnboardingTopics {
  const OnboardingTopics({required this.topics, required this.min, required this.max});
  final List<OnboardingTopic> topics;
  final int min;
  final int max;
}

/// The first-run calls of `docs/api.md` ("Onboarding").
class OnboardingRepository {
  OnboardingRepository(this._api);

  final ApiClient _api;

  Future<OnboardingTopics> topics() async {
    final json = await _api.getJson('/api/onboarding/topics');
    if (json is! Map<String, dynamic>) {
      throw const ApiException('The server sent an answer the app does not understand.');
    }
    return OnboardingTopics(
      topics: [
        for (final t in (json['topics'] as List<dynamic>? ?? const []))
          if (t is Map<String, dynamic> && t['id'] is String && t['label'] is String)
            OnboardingTopic(id: t['id'] as String, label: t['label'] as String),
      ],
      min: (json['min'] as num?)?.toInt() ?? 3,
      max: (json['max'] as num?)?.toInt() ?? 8,
    );
  }

  /// Saves the chosen topics (an empty list is "skip"). The server also marks the first-run pages as done.
  Future<void> save(List<String> topicIds) async {
    await _api.sendJson('POST', '/api/me/onboarding', body: {'topics': topicIds});
  }
}
