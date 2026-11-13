import 'package:flutter/material.dart';

/// A page that slides in from the right and slides back out the same way (like Instagram's messages), on every platform.
Route<T> slideFromRight<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved), child: child);
    },
  );
}
