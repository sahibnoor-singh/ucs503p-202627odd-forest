/// Which sides of a debate this person has actually watched, so the app can say "you have heard both sides" (and, when they have
/// only heard one, point to the other). Kept in memory for the visit only: nothing about it is stored on the server, and it is
/// never used to rank anything. It exists to nudge people out of one-sided viewing, which is what FOREST is for.
class SidesHeard {
  final Map<String, Set<String>> _byDebate = {};

  /// Notes that a video with [stance] (`FOR` or `AGAINST`, anything else is ignored) in the debate [rootId] was watched.
  /// Returns true exactly once per debate: at the moment the second side is first heard.
  bool record(String rootId, String stance) {
    final side = stance.toUpperCase();
    if (side != 'FOR' && side != 'AGAINST') return false;
    final heard = _byDebate.putIfAbsent(rootId, () => <String>{});
    final hadBoth = heard.length == 2;
    heard.add(side);
    return !hadBoth && heard.length == 2;
  }

  Set<String> of(String rootId) => Set.unmodifiable(_byDebate[rootId] ?? const <String>{});

  bool heardBoth(String rootId) => of(rootId).length == 2;

  /// The line to show on a debate that has replies on both sides, or null when nothing needs saying.
  /// On the main video, swiping left (or tapping FOR) goes to a FOR reply and right (or tapping AGAINST) to an AGAINST reply; on a
  /// reply, right goes back to what it answers (see `VideoReel`), so there the advice is to go back first.
  SidesNote? noteFor(String rootId, {required bool onRoot}) {
    final heard = of(rootId);
    if (heard.length == 2) return const SidesNote('You have heard both sides', done: true);
    if (heard.contains('FOR')) {
      return SidesNote(onRoot ? 'You have heard FOR. Now hear AGAINST' : 'You have heard FOR. Go back to hear AGAINST');
    }
    if (heard.contains('AGAINST')) {
      return SidesNote(onRoot ? 'You have heard AGAINST. Now hear FOR' : 'You have heard AGAINST. Go back to hear FOR');
    }
    return null; // nothing heard yet: nothing to say (the counts below the title already show both sides exist)
  }
}

class SidesNote {
  const SidesNote(this.text, {this.done = false});
  final String text;
  final bool done;
}
