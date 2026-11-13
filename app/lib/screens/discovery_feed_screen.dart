import 'package:flutter/material.dart';

import '../features/discover/discover_screen.dart';

/// Discover tab: a grid of posts ranked for this person. Tapping one opens the full-screen reels feed (swipe left/right between
/// FOR and AGAINST replies, up/down through what you watched and what is next).
class DiscoveryFeedScreen extends StatelessWidget {
  const DiscoveryFeedScreen({super.key});

  @override
  Widget build(BuildContext context) => const DiscoverScreen();
}
