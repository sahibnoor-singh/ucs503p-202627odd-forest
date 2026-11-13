import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recipe.dart';

/// Records a video with the camera, full screen: up to 60 seconds, then back to the editor with the file. Resolves to the
/// recorded file's path, or null when the person backs out.
Future<String?> recordVideo(BuildContext context) {
  return Navigator.of(context).push<String>(MaterialPageRoute<String>(fullscreenDialog: true, builder: (_) => const RecordPage()));
}

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _lens = 0;
  Timer? _timer;
  String? _error;
  bool _recording = false;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      _lens = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_lens < 0) _lens = 0;
      await _open();
    } on CameraException {
      if (mounted) setState(() => _error = 'The camera or microphone is not allowed. You can pick a video from your gallery instead.');
    } on Object {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  Future<void> _open() async {
    final old = _camera;
    final next = CameraController(_cameras[_lens], ResolutionPreset.high, enableAudio: true);
    await next.initialize();
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() => _camera = next);
    await old?.dispose();
  }

  Future<void> _flip() async {
    if (_recording || _cameras.length < 2) return;
    _lens = (_lens + 1) % _cameras.length;
    try {
      await _open();
    } on Object {
      if (mounted) setState(() => _error = 'Could not switch the camera.');
    }
  }

  Future<void> _toggle() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      if (_recording) {
        await _stop();
        return;
      }
      await camera.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= EditorLimits.maxSeconds) _stop();
      });
    } on Object {
      if (mounted) setState(() => _error = 'Recording failed. Try again.');
    }
  }

  Future<void> _stop() async {
    final camera = _camera;
    if (camera == null || !_recording) return;
    _timer?.cancel();
    try {
      final file = await camera.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      Navigator.of(context).pop(file.path);
    } on Object {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'The recording could not be saved. Try again, or pick a video from your gallery.';
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final camera = _camera;
    if (camera != null && camera.value.isRecordingVideo) {
      () async {
        try {
          await camera.stopVideoRecording();
        } on Object {
          // the screen is gone; nothing useful to do
        }
      }();
    }
    camera?.dispose();
    super.dispose();
  }

  String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_error != null)
                Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15))))
              else if (camera != null && camera.value.isInitialized)
                Center(child: AspectRatio(aspectRatio: 1 / camera.value.aspectRatio, child: CameraPreview(camera)))
              else
                const Center(child: CircularProgressIndicator(color: Colors.white54)),
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
              ),
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: _recording ? const Color(0xCCE5484D) : const Color(0x80000000), borderRadius: BorderRadius.circular(99)),
                    child: Text('${_clock(_seconds)} / ${_clock(EditorLimits.maxSeconds)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
              if (_error == null)
                Positioned(
                  bottom: 28,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 56),
                      const SizedBox(width: 36),
                      Semantics(
                        button: true,
                        label: _recording ? 'Stop recording' : 'Start recording',
                        child: GestureDetector(
                          onTap: camera == null ? null : _toggle,
                          child: Container(
                            width: 76,
                            height: 76,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: _recording ? 28 : 56,
                              height: _recording ? 28 : 56,
                              decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(_recording ? 7 : 28)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 36),
                      SizedBox(
                        width: 56,
                        child: _cameras.length > 1 && !_recording
                            ? IconButton(tooltip: 'Switch camera', onPressed: _flip, icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 28))
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
