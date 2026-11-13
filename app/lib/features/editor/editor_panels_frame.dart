import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/forest_theme.dart';
import 'editor_controller.dart';
import 'editor_widgets.dart';
import 'recipe.dart';

/// What shape the crop box keeps. "Free" lets every side move on its own.
enum CropShape {
  free('Free', null),
  square('1:1', 1),
  portrait('4:5', 4 / 5),
  story('9:16', 9 / 16),
  wide('16:9', 16 / 9);

  const CropShape(this.label, this.ratio);
  final String label;

  /// Width / height as seen on screen; null for free.
  final double? ratio;

  static CropShape of(double? ratio) => values.firstWhere(
        (s) => s.ratio == null ? ratio == null : (ratio != null && (s.ratio! - ratio).abs() < 1e-6),
        orElse: () => free,
      );
}

/// Crop tool: the box itself is dragged on the picture; this chooses its shape and puts everything back.
class CropPanel extends StatelessWidget {
  const CropPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final cropped = c.recipe.crop != null;
    final hasPicture = c.mode == EditorMode.video ? c.videoPath != null : c.photos.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel('Crop', trailing: cropped ? 'Cut' : null),
        if (!hasPicture)
          Text(c.mode == EditorMode.video ? 'Choose a video first.' : 'Add a photo first.', style: TextStyle(fontSize: 13, color: t.fg2))
        else ...[
          ChoicePills<CropShape>(values: CropShape.values, selected: CropShape.of(c.cropRatio), label: (s) => s.label, onPick: (s) => c.setCropRatio(s.ratio)),
          const SizedBox(height: 8),
          Text(
            c.mode == EditorMode.photos
                ? 'Drag the box on the first photo. Everything outside it is cut off, in every photo.'
                : 'Drag the box on the picture. Everything outside it is cut off.',
            style: TextStyle(fontSize: 13, color: t.fg2),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: cropped || c.cropRatio != null ? c.resetCrop : null,
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            label: const Text('Use the whole picture'),
          ),
        ],
      ],
    );
  }
}

/// Cover tool (video): which moment's picture people see before the video plays.
class CoverPanel extends StatelessWidget {
  const CoverPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();
    final t = context.forest;
    final length = c.length;
    final at = (c.recipe.coverSec ?? 0).clamp(0.0, length).toDouble();
    final max = length > 0.2 ? length - 0.1 : 0.1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel('Cover', trailing: c.videoPath == null ? null : clockText(at)),
        if (c.videoPath == null)
          Text('Choose a video first.', style: TextStyle(fontSize: 13, color: t.fg2))
        else ...[
          LabeledSlider(label: 'Moment', value: at.clamp(0.0, max).toDouble(), min: 0, max: max, display: clockText, onChanged: c.setCover),
          Text('This is the picture people see before the video plays. Drag to pick it; the picture above shows it.', style: TextStyle(fontSize: 13, color: t.fg2)),
        ],
      ],
    );
  }
}
