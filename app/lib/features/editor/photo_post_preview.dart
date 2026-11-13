import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'adjust_filter.dart';
import 'crop_editor.dart';
import 'overlay_layer.dart';
import 'recipe.dart';

/// The slideshow of a PHOTOS post: each photo fitted inside a 9:16 picture on black (as the server renders it), changing every
/// [Recipe.slideSeconds] with a fade or a cut, and looping.
class PhotoPostPreview extends StatefulWidget {
  const PhotoPostPreview({
    super.key,
    required this.photos,
    required this.recipe,
    this.onAdd,
    this.onOverlayMoved,
    this.onOverlayTap,
    this.selectedOverlay,
    this.cropping = false,
    this.cropRatio,
    this.onCrop,
  });

  final List<String> photos;
  final Recipe recipe;

  /// Shown on the empty picture.
  final VoidCallback? onAdd;
  final void Function(int index, double x, double y)? onOverlayMoved;
  final void Function(int index)? onOverlayTap;
  final int? selectedOverlay;

  /// The Crop tool is open: show the first photo whole with the crop box over it. The crop is the same for every photo.
  final bool cropping;
  final double? cropRatio;
  final ValueChanged<Crop?>? onCrop;

  @override
  State<PhotoPostPreview> createState() => _PhotoPostPreviewState();
}

class _PhotoPostPreviewState extends State<PhotoPostPreview> {
  int _index = 0;
  Timer? _timer;

  /// The controller changes its list of photos in place, so the widget cannot tell from the old and new list that one was added.
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(PhotoPostPreview old) {
    super.didUpdateWidget(old);
    if (old.recipe.slideSeconds != widget.recipe.slideSeconds || _count != widget.photos.length) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _count = widget.photos.length;
    if (_index >= widget.photos.length) _index = 0;
    if (widget.photos.length < 2) return;
    _timer = Timer.periodic(Duration(milliseconds: (widget.recipe.slideSeconds * 1000).round()), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.photos.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _broken = Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40));

  ImageProvider _provider(String path) => ResizeImage(FileImage(File(path)), width: 720);

  /// One photo of the slideshow, with the crop applied: the cropped part fitted inside the frame, as the server does it.
  Widget _slide(String path) {
    final crop = widget.recipe.crop;
    final provider = _provider(path);
    if (crop == null) return Image(image: provider, fit: BoxFit.contain, errorBuilder: (_, _, _) => _broken);
    return ImageShape(
      image: provider,
      builder: (context, size) {
        if (size == null) return const SizedBox.shrink();
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: size.width * crop.w,
            height: size.height * crop.h,
            child: CropWindow(crop: crop, child: Image(image: provider, fit: BoxFit.fill, errorBuilder: (_, _, _) => _broken)),
          ),
        );
      },
    );
  }

  /// The first photo, whole, with the crop box over it.
  Widget _cropper(String path) {
    final provider = _provider(path);
    return ImageShape(
      image: provider,
      builder: (context, size) {
        if (size == null) return const SizedBox.shrink();
        final aspect = size.width / size.height;
        return AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: provider, fit: BoxFit.fill, errorBuilder: (_, _, _) => _broken),
              CropEditor(crop: widget.recipe.crop, sourceAspect: aspect, ratio: widget.cropRatio, onChanged: widget.onCrop ?? (_) {}),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final fade = widget.recipe.transition == PhotoTransition.fade;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(builder: (context, box) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (photos.isEmpty)
                Center(
                  child: TextButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white70),
                    label: const Text('Add photos', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  ),
                )
              else if (widget.cropping)
                Center(child: _cropper(photos.first))
              else
                AdjustedPicture(
                  adjust: widget.recipe.adjust,
                  pictureWidth: box.maxWidth,
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: fade ? 500 : 0),
                    child: SizedBox.expand(
                      key: ValueKey('${_index}_${photos[_index.clamp(0, photos.length - 1)]}'),
                      child: _slide(photos[_index.clamp(0, photos.length - 1)]),
                    ),
                  ),
                ),
              if (!widget.cropping)
                OverlayLayer(
                  overlays: widget.recipe.overlays,
                  size: Size(box.maxWidth, box.maxHeight),
                  selected: widget.selectedOverlay,
                  onMoved: widget.onOverlayMoved,
                  onTap: widget.onOverlayTap,
                ),
            ],
          ),
        );
      }),
    );
  }
}
