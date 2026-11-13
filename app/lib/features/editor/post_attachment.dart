/// What a new opinion is part of, besides being an opinion: an answer to the day's question, or a post in a motion room.
/// It travels from the screen that offers it (the question card, the room page) to the post call, and shows in the editor's top bar.
class PostAttachment {
  const PostAttachment({this.promptDay, this.roomId, required this.label}) : assert((promptDay == null) != (roomId == null));

  /// The question's day (`YYYY-MM-DD`).
  final String? promptDay;

  /// The room's id.
  final String? roomId;

  /// Words for the editor's top bar, e.g. "Answer today's question".
  final String label;
}
