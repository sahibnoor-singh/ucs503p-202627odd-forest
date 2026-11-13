import '../../models/feed_item.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';

enum RoomStatus { upcoming, open, closed }

/// A motion room (`docs/api.md`, "Motion rooms"): a society debating one motion for a few days.
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.motion,
    required this.status,
    required this.memberCount,
    required this.posts,
    required this.forCount,
    required this.againstCount,
    required this.undecided,
    this.code,
    this.description,
    this.startsAt,
    this.endsAt,
    this.isOwner = false,
    this.owner,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as String,
        name: json['name'] as String,
        motion: json['motion'] as String,
        status: switch (json['status']) {
          'UPCOMING' => RoomStatus.upcoming,
          'CLOSED' => RoomStatus.closed,
          _ => RoomStatus.open,
        },
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
        posts: (json['posts'] as num?)?.toInt() ?? 0,
        forCount: (json['forCount'] as num?)?.toInt() ?? 0,
        againstCount: (json['againstCount'] as num?)?.toInt() ?? 0,
        undecided: (json['undecided'] as num?)?.toInt() ?? 0,
        code: json['code'] as String?,
        description: json['description'] as String?,
        startsAt: json['startsAt'] is String ? DateTime.tryParse(json['startsAt'] as String) : null,
        endsAt: json['endsAt'] is String ? DateTime.tryParse(json['endsAt'] as String) : null,
        isOwner: json['role'] == 'OWNER',
        owner: json['owner'] is Map<String, dynamic> ? User.fromJson(json['owner'] as Map<String, dynamic>) : null,
      );

  final String id;
  final String name;
  final String motion;
  final RoomStatus status;
  final int memberCount;
  final int posts;
  final int forCount;
  final int againstCount;

  /// Opinions the AI could not place on either side of the motion (yet).
  final int undecided;

  /// What to hand to a friend so they can join. Only members see it.
  final String? code;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isOwner;
  final User? owner;

  bool get canPost => status == RoomStatus.open;
}

class RoomDetail {
  const RoomDetail({required this.room, required this.members});

  final Room room;
  final List<User> members;
}

/// The room calls of `docs/api.md`.
class RoomsRepository {
  RoomsRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  Future<List<Room>> mine() async {
    final json = _map(await _api.getJson('/api/rooms/mine'));
    return [
      for (final r in (json['rooms'] as List<dynamic>? ?? const []))
        if (r is Map<String, dynamic>) Room.fromJson(r),
    ];
  }

  Future<Room> create({required String name, required String motion, String? description, DateTime? endsAt}) async {
    final json = _map(await _api.sendJson('POST', '/api/rooms', body: {
      'name': name,
      'motion': motion,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (endsAt != null) 'endsAt': endsAt.toUtc().toIso8601String(),
    }));
    return Room.fromJson(_map(json['room']));
  }

  Future<Room> join(String code) async {
    final json = _map(await _api.sendJson('POST', '/api/rooms/join', body: {'code': code}));
    return Room.fromJson(_map(json['room']));
  }

  Future<RoomDetail> detail(String id) async {
    final json = _map(await _api.getJson('/api/rooms/$id'));
    return RoomDetail(
      room: Room.fromJson(_map(json['room'])),
      members: [
        for (final m in (json['members'] as List<dynamic>? ?? const []))
          if (m is Map<String, dynamic>) User.fromJson(m),
      ],
    );
  }

  Future<List<FeedItem>> posts(String id, {int limit = 20}) async {
    final json = _map(await _api.getJson('/api/rooms/$id/posts', query: {'limit': '$limit'}));
    return [
      for (final raw in (json['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) FeedItem.fromJson(raw),
    ];
  }

  Future<void> leave(String id) async {
    await _api.sendJson('POST', '/api/rooms/$id/leave');
  }

  Future<Room> close(String id) async {
    final json = _map(await _api.sendJson('POST', '/api/rooms/$id/close'));
    return Room.fromJson(_map(json['room']));
  }
}
