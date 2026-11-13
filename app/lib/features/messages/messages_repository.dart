import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/user.dart';
import '../../models/video.dart';
import '../../services/api_client.dart';

/// The reactions a message can get, in the order the picker shows them (the server accepts exactly these).
const messageReactions = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

/// One row of the inbox.
class Conversation {
  const Conversation({required this.id, required this.person, required this.preview, required this.lastAt, required this.lastFromMe, required this.unread});

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final last = json['last'] as Map<String, dynamic>;
    return Conversation(
      id: json['id'] as String,
      person: User.fromJson(json['with'] as Map<String, dynamic>),
      preview: last['preview'] as String? ?? '',
      lastAt: DateTime.tryParse(last['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastFromMe: last['fromMe'] == true,
      unread: (json['unread'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final User person;
  final String preview;
  final DateTime lastAt;
  final bool lastFromMe;
  final int unread;

  Conversation read() => Conversation(id: id, person: person, preview: preview, lastAt: lastAt, lastFromMe: lastFromMe, unread: 0);
}

/// Both people's reaction to one message: mine and theirs (each an emoji or null).
class Reactions {
  const Reactions({this.mine, this.theirs});

  factory Reactions.fromJson(Object? json) =>
      json is Map ? Reactions(mine: json['mine'] as String?, theirs: json['theirs'] as String?) : const Reactions();

  final String? mine;
  final String? theirs;

  bool get isEmpty => mine == null && theirs == null;
}

/// A video that was sent in a conversation (there is no text).
class Message {
  const Message({required this.id, required this.fromMe, required this.video, required this.createdAt, required this.reactions});

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawVideo = json['video'];
    Video? video;
    if (rawVideo is Map<String, dynamic>) {
      try {
        video = Video.fromJson(rawVideo);
        if (video.id.isEmpty || video.filename.isEmpty) video = null;
      } on Object catch (error) {
        debugPrint('A sent video the app could not read: $error');
      }
    }
    return Message(
      id: json['id'] as String,
      fromMe: json['fromMe'] == true,
      video: video,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      reactions: Reactions.fromJson(json['reactions']),
    );
  }

  final String id;
  final bool fromMe;

  /// The sent video, or null when it is no longer available.
  final Video? video;
  final DateTime createdAt;
  final Reactions reactions;

  Message withReactions(Reactions r) => Message(id: id, fromMe: fromMe, video: video, createdAt: createdAt, reactions: r);
}

class ChatPage {
  const ChatPage({required this.person, required this.messages, required this.hasMore});

  final User person;
  final List<Message> messages;
  final bool hasMore;
}

/// Direct messages: videos that friends sent, and emoji reactions to them (docs/api.md "Direct messages").
class MessagesRepository {
  MessagesRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  Future<List<Conversation>> conversations() async {
    final json = _map(await _api.getJson('/api/messages/conversations'));
    final out = <Conversation>[];
    for (final raw in (json['conversations'] as List? ?? const [])) {
      try {
        out.add(Conversation.fromJson(_map(raw)));
      } on Object catch (error) {
        debugPrint('Skipping a conversation the app could not read: $error');
      }
    }
    return out;
  }

  /// How many conversations have something new (for the badge on Home).
  Future<int> unread() async => (_map(await _api.getJson('/api/messages/unread'))['unread'] as num?)?.toInt() ?? 0;

  /// The newest messages of the conversation with [userId], oldest first; [before] (a message id) asks for older ones.
  Future<ChatPage> thread(String userId, {String? before, int limit = 40}) async {
    final json = _map(await _api.getJson('/api/messages/with/$userId', query: {'limit': '$limit', 'before': ?before}));
    final messages = <Message>[];
    for (final raw in (json['messages'] as List? ?? const [])) {
      try {
        messages.add(Message.fromJson(_map(raw)));
      } on Object catch (error) {
        debugPrint('Skipping a message the app could not read: $error');
      }
    }
    return ChatPage(
      person: User.fromJson(_map(json['with'])),
      messages: messages,
      hasMore: json['hasMore'] == true,
    );
  }

  /// Fire and forget: reading is never worth an error.
  Future<void> markRead(String userId) async {
    try {
      await _api.sendJson('POST', '/api/messages/with/$userId/read');
    } on Object catch (error) {
      debugPrint('Could not mark a conversation read: $error');
    }
  }

  /// The person opened a video that was sent to them.
  Future<void> markOpened(String messageId) async {
    try {
      await _api.sendJson('POST', '/api/messages/$messageId/open');
    } on Object catch (error) {
      debugPrint('Could not mark a video opened: $error');
    }
  }

  Future<Reactions> react(String messageId, String emoji) async =>
      Reactions.fromJson(_map(await _api.sendJson('PUT', '/api/messages/$messageId/reaction', body: {'emoji': emoji}))['reactions']);

  Future<Reactions> unreact(String messageId) async =>
      Reactions.fromJson(_map(await _api.sendJson('DELETE', '/api/messages/$messageId/reaction'))['reactions']);

  /// Where to load a video's still picture from, or null.
  String? coverUrl(Video video) => video.coverUrl == null ? null : _api.resolveUrl(video.coverUrl!);
}
