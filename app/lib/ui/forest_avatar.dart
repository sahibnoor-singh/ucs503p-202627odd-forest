import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/feed_repository.dart';
import '../models/user.dart';
import '../theme/forest_theme.dart';
import 'forest_icon.dart';

/// Round avatar (`.av`: 26px, 1px border, `raised` fill). Shows the
/// prototype's person silhouette (84% of the circle, sitting on the bottom,
/// 85% opaque) when there is no picture or it fails to load.
class ForestAvatar extends StatelessWidget {
  const ForestAvatar({super.key, required this.user, this.size = 26});

  final User user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final silhouette = ForestIcon(
      Icn.avatar,
      size: size * 0.84,
      color: t.fg2.withValues(alpha: 0.85),
    );
    final url = user.avatarUrl;
    Widget child = silhouette;
    if (url != null) {
      final resolved = Provider.of<FeedRepository?>(context, listen: false)?.mediaUrl(url) ?? url;
      child = Image.network(
        resolved,
        width: size,
        height: size,
        // decode at the size it is drawn, not the 256 px of the picture
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => silhouette,
      );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.raised,
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}
