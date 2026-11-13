import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// File types the server accepts (docs/api.md → "Editor posts").
const photoExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
const videoExtensions = {'.mp4', '.mov', '.webm', '.mkv'};
const musicExtensions = {'.mp3', '.m4a', '.aac', '.wav', '.ogg'};

String extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[\\/]'));
  return dot <= slash ? '' : path.substring(dot).toLowerCase();
}

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

class PickedVideo {
  const PickedVideo(this.path, this.seconds);
  final String path;
  final double seconds;
}

class PickedMusic {
  const PickedMusic(this.path, this.name);
  final String path;
  final String name;
}

/// Where the editor gets its files from. The editor only talks to this, so tests can hand it files without a phone.
abstract class EditorPickers {
  /// Up to [limit] photos from the gallery. Empty when the person backs out.
  Future<List<String>> photos({required int limit});

  /// One video from the gallery, with its length. Null when the person backs out or the file cannot be read.
  Future<PickedVideo?> galleryVideo();

  /// One audio file from the phone. Null when the person backs out.
  Future<PickedMusic?> music();
}

/// The real thing: the system pickers.
class PlatformPickers implements EditorPickers {
  PlatformPickers({ImagePicker? imagePicker}) : _images = imagePicker ?? ImagePicker();

  final ImagePicker _images;

  @override
  Future<List<String>> photos({required int limit}) async {
    if (limit <= 0) return const [];
    if (limit == 1) {
      final one = await _images.pickImage(source: ImageSource.gallery);
      return one == null ? const [] : [one.path];
    }
    final many = await _images.pickMultiImage(limit: limit);
    return [for (final f in many) f.path];
  }

  @override
  Future<PickedVideo?> galleryVideo() async {
    final file = await _images.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    final seconds = await videoLength(file.path);
    return seconds == null ? null : PickedVideo(file.path, seconds);
  }

  @override
  Future<PickedMusic?> music() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    return file == null || path == null ? null : PickedMusic(path, file.name);
  }
}

/// How long the video in [path] is, in seconds; null when it cannot be opened.
Future<double?> videoLength(String path) async {
  final probe = VideoPlayerController.file(File(path));
  try {
    await probe.initialize();
    final ms = probe.value.duration.inMilliseconds;
    return ms > 0 ? ms / 1000 : null;
  } on Object {
    return null;
  } finally {
    await probe.dispose();
  }
}
