import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/post.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../home/feed_controller.dart';
import 'editor_pickers.dart';
import 'post_attachment.dart';
import 'recipe.dart';

/// Everything the editor screen is showing and editing: the files picked, the recipe being built, the heading and caption,
/// and whether a post is on its way. The screen only draws this and calls its methods, so the rules live here (and in
/// [Recipe]) where they can be tested without a screen.
class EditorController extends ChangeNotifier {
  EditorController({
    required EditorMode mode,
    this.parent,
    this.parentAuthor,
    String? videoPath,
    double? videoSeconds,
    EditorPickers? pickers,
    this.attach,
  })  : pickers = pickers ?? PlatformPickers(),
        _recipe = Recipe(mode: mode) {
    if (videoPath != null && videoSeconds != null) setVideo(videoPath, videoSeconds);
  }

  /// Where files come from (the system pickers; a fake in tests).
  final EditorPickers pickers;

  /// The post being replied to, or null for a new opinion.
  final Post? parent;
  final User? parentAuthor;

  /// The question or room this new opinion belongs to, if any.
  final PostAttachment? attach;

  Recipe _recipe;
  Recipe get recipe => _recipe;
  EditorMode get mode => _recipe.mode;
  bool get isReply => parent != null;

  String? videoPath;

  /// Length of the whole picked video.
  double? videoSeconds;
  final List<String> photos = [];
  String? musicPath;
  String? musicName;

  String title = '';
  String caption = '';

  bool posting = false;
  String? error;

  /// A short message about something that happened while picking files ("2 photos were too big"). The screen shows it once and
  /// then calls [clearNotice].
  String? notice;
  bool _disposed = false;

  /// How long the finished post will be.
  double get length => _recipe.lengthSeconds(videoSeconds: videoSeconds);

  /// True once there is something a person would be sorry to lose by closing the editor.
  bool get hasContent {
    switch (mode) {
      case EditorMode.text:
        return _recipe.text.content.trim().isNotEmpty;
      case EditorMode.photos:
        return photos.isNotEmpty;
      case EditorMode.video:
        return videoPath != null;
    }
  }

  /// The first thing that stops the post from being sent, in words for the person; null when it can go.
  String? get problem {
    switch (mode) {
      case EditorMode.video:
        if (videoPath == null) return 'Choose or record a video first.';
        final size = _sizeOf(videoPath!);
        if (size != null && size > EditorLimits.maxVideoBytes) return 'That video is ${_mb(size)} MB. The limit is 50 MB.';
      case EditorMode.photos:
        if (photos.isEmpty) return 'Pick at least one photo.';
      case EditorMode.text:
        break;
    }
    final fromRecipe = _recipe.problem(videoSeconds: videoSeconds);
    if (fromRecipe != null) return fromRecipe;
    if (!isReply && title.trim().length > EditorLimits.maxTitleChars) return 'The question can be at most ${EditorLimits.maxTitleChars} characters.';
    if (caption.trim().length > EditorLimits.maxCaptionChars) return 'The caption can be at most ${EditorLimits.maxCaptionChars} characters.';
    if (musicPath != null) {
      final size = _sizeOf(musicPath!);
      if (size != null && size > EditorLimits.maxMusicBytes) return 'That music file is ${_mb(size)} MB. The limit is 15 MB.';
    }
    return null;
  }

  bool get canPost => !posting && problem == null;

  static int? _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on Object {
      return null;
    }
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  // ---- changing things ----

  void update(Recipe Function(Recipe r) change) {
    _recipe = change(_recipe);
    _changed();
  }

  void setTitle(String v) {
    title = v;
    _changed();
  }

  void setCaption(String v) {
    caption = v;
    _changed();
  }

  /// A video was picked or recorded: keep its first minute by default, and forget a crop meant for another picture.
  void setVideo(String path, double seconds) {
    videoPath = path;
    videoSeconds = seconds;
    _recipe = _recipe.copyWith(trim: Trim(0, math.min(seconds, EditorLimits.maxSeconds.toDouble())), clearCrop: true, clearCover: true);
    _changed();
  }

  /// Moves the start or end of the trim, keeping at least half a second and at most a minute between them.
  void setTrim({double? start, double? end}) {
    final total = videoSeconds ?? EditorLimits.maxSeconds.toDouble();
    final current = _recipe.trim ?? Trim(0, math.min(total, EditorLimits.maxSeconds.toDouble()));
    var s = (start ?? current.startSec).clamp(0.0, total).toDouble();
    var e = (end ?? current.endSec).clamp(0.0, total).toDouble();
    const minLen = EditorLimits.minVideoSeconds;
    const maxLen = 60.0;
    if (start != null) {
      if (e - s < minLen) s = math.max(0, e - minLen);
      if (e - s > maxLen) e = s + maxLen;
    } else {
      if (e - s < minLen) e = math.min(total, s + minLen);
      if (e - s > maxLen) s = e - maxLen;
    }
    _recipe = _recipe.copyWith(trim: Trim(s, e));
    final cover = _recipe.coverSec;
    if (cover != null && cover > e - s - 0.1) _recipe = _recipe.copyWith(coverSec: math.max(0, e - s - 0.1)); // the cover must stay inside what is kept
    _changed();
  }

  /// Picks the moment (seconds into the kept part) whose picture is shown before the video plays; null lets the server pick.
  void setCover(double? seconds) {
    if (seconds == null) {
      _recipe = _recipe.copyWith(clearCover: true);
    } else {
      final room = math.max(0.0, length - 0.1);
      _recipe = _recipe.copyWith(coverSec: seconds.clamp(0.0, room).toDouble());
    }
    _changed();
  }

  /// The shape the crop box keeps while it is resized (width / height as seen on screen), or null for free. Used only while the
  /// Crop tool is open.
  double? cropRatio;

  void setCropRatio(double? ratio) {
    cropRatio = ratio;
    _changed();
  }

  /// Keeps this part of the picture (every photo, for a photo post); a crop that cuts nothing off clears it.
  void setCrop(Crop? crop) {
    _recipe = (crop == null || crop.isFull) ? _recipe.copyWith(clearCrop: true) : _recipe.copyWith(crop: crop);
    _changed();
  }

  /// Back to the whole picture.
  void resetCrop() {
    cropRatio = null;
    _recipe = _recipe.copyWith(clearCrop: true);
    _changed();
  }

  void clearNotice() => notice = null;

  /// Shows [text] once on the editor screen.
  void say(String text) {
    notice = text;
    _changed();
  }

  /// Asks for more photos and keeps the ones the server will take. Says in [notice] what was left out and why.
  Future<void> pickMorePhotos() async {
    final room = EditorLimits.maxPhotos - photos.length;
    if (room <= 0) {
      notice = 'You can use up to ${EditorLimits.maxPhotos} photos.';
      _changed();
      return;
    }
    final picked = await _picking(() => pickers.photos(limit: room), 'your photos');
    if (picked == null) return;
    final good = <String>[];
    final skipped = <String>[];
    for (final path in picked) {
      final why = _photoProblem(path);
      why == null ? good.add(path) : skipped.add(why);
    }
    if (good.isNotEmpty) addPhotos(good);
    if (skipped.isNotEmpty) notice = skipped.length == 1 ? skipped.single : '${skipped.length} photos were left out. ${skipped.first}';
    _changed();
  }

  /// Runs a system picker. When it cannot open (the app is not allowed to read the files, the picker crashed) says so in
  /// [notice] and gives null, the same as when the person backs out.
  Future<T?> _picking<T>(Future<T> Function() ask, String what) async {
    try {
      return await ask();
    } on Object {
      notice = 'Could not open $what. Check that FOREST is allowed to read them, then try again.';
      _changed();
      return null;
    }
  }

  String? _photoProblem(String path) {
    if (!photoExtensions.contains(extensionOf(path))) return '"${fileNameOf(path)}" is not a JPG, PNG or WebP photo.';
    final size = _sizeOf(path);
    if (size != null && size > EditorLimits.maxPhotoBytes) return '"${fileNameOf(path)}" is ${_mb(size)} MB. The limit is 10 MB a photo.';
    return null;
  }

  /// Asks for a video from the gallery and keeps it if the server will take it.
  Future<void> pickGalleryVideo() async {
    final v = await _picking(pickers.galleryVideo, 'your videos');
    if (v != null) useVideo(v.path, v.seconds);
  }

  /// Keeps a picked or recorded video if the server will take it; otherwise says why in [notice].
  void useVideo(String path, double seconds) {
    if (!videoExtensions.contains(extensionOf(path))) {
      notice = 'That file type is not supported. Use an MP4, MOV, WebM or MKV video.';
    } else {
      final size = _sizeOf(path);
      if (size != null && size > EditorLimits.maxVideoBytes) {
        notice = 'That video is ${_mb(size)} MB. The limit is 50 MB.';
      } else {
        setVideo(path, seconds);
        return;
      }
    }
    _changed();
  }

  /// Asks for a music file and keeps it if the server will take it.
  Future<void> pickMusic() async {
    final m = await _picking(pickers.music, 'your files');
    if (m == null) return;
    if (!musicExtensions.contains(extensionOf(m.path))) {
      notice = 'Music has to be an MP3, M4A, AAC, WAV or OGG file.';
    } else {
      final size = _sizeOf(m.path);
      if (size != null && size > EditorLimits.maxMusicBytes) {
        notice = 'That music file is ${_mb(size)} MB. The limit is 15 MB.';
      } else {
        setMusic(m.path, m.name);
        return;
      }
    }
    _changed();
  }

  void addPhotos(List<String> paths) {
    final room = EditorLimits.maxPhotos - photos.length;
    photos.addAll(paths.take(room));
    _syncPhotos();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    photos.removeAt(index);
    _syncPhotos();
  }

  void movePhoto(int from, int to) {
    if (from < 0 || from >= photos.length) return;
    final target = to.clamp(0, photos.length - 1);
    photos.insert(target, photos.removeAt(from));
    _syncPhotos();
  }

  void _syncPhotos() {
    _recipe = _recipe.copyWith(photoCount: photos.length);
    _changed();
  }

  void setMusic(String path, String name) {
    musicPath = path;
    musicName = name;
    _recipe = _recipe.copyWith(music: _recipe.music ?? const MusicSpec());
    _changed();
  }

  void clearMusic() {
    musicPath = null;
    musicName = null;
    _recipe = _recipe.copyWith(clearMusic: true);
    _changed();
  }

  /// The piece of text on the picture that is being edited (its index), or null.
  int? selectedOverlay;

  void selectOverlay(int? index) {
    selectedOverlay = index;
    _changed();
  }

  void addOverlay(TextOverlay overlay) {
    if (_recipe.overlays.length >= EditorLimits.maxOverlays) return;
    _recipe = _recipe.copyWith(overlays: [..._recipe.overlays, overlay]);
    selectedOverlay = _recipe.overlays.length - 1;
    _changed();
  }

  void changeOverlay(int index, TextOverlay overlay) {
    if (index < 0 || index >= _recipe.overlays.length) return;
    final list = [..._recipe.overlays];
    list[index] = overlay;
    _recipe = _recipe.copyWith(overlays: list);
    _changed();
  }

  void removeOverlay(int index) {
    if (index < 0 || index >= _recipe.overlays.length) return;
    _recipe = _recipe.copyWith(overlays: [..._recipe.overlays]..removeAt(index));
    final sel = selectedOverlay;
    if (sel != null) selectedOverlay = sel == index ? null : (sel > index ? sel - 1 : sel);
    _changed();
  }

  // ---- sending ----

  /// Sends the post. Resolves true when the server took it (it is then being made; [FeedController] keeps polling it);
  /// false when it could not be sent, with [error] saying why.
  Future<bool> submit(FeedController feed) async {
    final p = problem;
    if (p != null) {
      error = p;
      _changed();
      return false;
    }
    if (posting) return false;
    posting = true;
    error = null;
    _changed();
    try {
      await feed.compose(
        parent: parent,
        recipe: _recipe,
        videoSeconds: videoSeconds,
        title: isReply ? null : title,
        body: caption,
        videoPath: mode == EditorMode.video ? videoPath : null,
        photoPaths: mode == EditorMode.photos ? List.of(photos) : const [],
        musicPath: musicPath,
        attach: isReply ? null : attach,
      );
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } on Object {
      error = 'Could not post. Check your connection and try again.';
      return false;
    } finally {
      posting = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
