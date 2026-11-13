/// Prototype-style relative age: `5m`, `3h`, `2d` (never less than `1m`).
String relativeTime(DateTime time, {DateTime? now}) {
  final minutes = ((now ?? DateTime.now()).difference(time).inSeconds / 60).round();
  final m = minutes < 1 ? 1 : minutes;
  if (m < 60) return '${m}m';
  if (m < 1440) return '${(m / 60).round()}h';
  return '${(m / 1440).round()}d';
}

/// `m:ss`.
String durationLabel(Duration d) {
  final total = d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
