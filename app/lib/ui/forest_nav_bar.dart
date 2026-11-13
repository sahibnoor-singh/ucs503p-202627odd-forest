import 'package:flutter/material.dart';

import '../theme/forest_theme.dart';
import 'forest_icon.dart';

/// The prototype's bottom nav (`#nav`): four equal buttons, 1px top border,
/// 18px icon, 2px gap, 10.5px / weight 600 label, padding 8 top and 9 bottom
/// (52px with the border). The selected tab is `fg` with a heavier icon stroke
/// (2.5, drawn as the `_active` icon files); the others are `fg2`.
class ForestNavBar extends StatelessWidget {
  const ForestNavBar({super.key, required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _labels = ['Home', 'Discover', 'Upload', 'Account'];
  static const _icons = [Icn.navHome, Icn.navDiscover, Icn.navUpload, Icn.navAccount];

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Material(
      color: t.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selectedIndex,
                    label: _labels[i],
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => onSelected(i),
                      containedInkWell: true,
                      highlightShape: BoxShape.rectangle,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 9),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ForestIcon(
                              i == selectedIndex ? '${_icons[i]}_active' : _icons[i],
                              size: 18,
                              color: i == selectedIndex ? t.fg : t.fg2,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _labels[i],
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: i == selectedIndex ? t.fg : t.fg2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
