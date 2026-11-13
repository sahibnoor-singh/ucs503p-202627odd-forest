import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/app_errors.dart';
import '../../models/video.dart';
import '../../services/api_client.dart';
import '../../utils/stance.dart';
import 'reels_repository.dart';

/// Modal bottom sheet to record or upload a video reply to a parent opinion.
class ReplySheet extends StatefulWidget {
  const ReplySheet({
    super.key,
    required this.parentVideo,
    required this.repository,
    required this.onReplyPosted,
  });

  final Video parentVideo;
  final ReelsRepository repository;
  final ValueChanged<Video> onReplyPosted;

  @override
  State<ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<ReplySheet> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  int _processingStep = 0; // 0: Uploading, 1: Extracting Audio, 2: Transcribing, 3: Classifying, 4: Ready
  String? _errorMessage;
  Timer? _pollTimer;

  static const _steps = [
    'Uploading video file...',
    'Extracting audio track...',
    'Transcribing with Whisper/Gemini...',
    'Classifying stance relative to parent...',
    'Ready!',
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = 'No camera found on this device.');
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = friendlyError(e, 'The camera could not start. Check that FOREST may use it, then try again.'));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (_isRecording) {
      try {
        final xFile = await controller.stopVideoRecording();
        if (!mounted) return;
        setState(() => _isRecording = false);
        await _processUpload(File(xFile.path));
      } catch (e) {
        if (mounted) setState(() => _errorMessage = friendlyError(e, 'The recording could not be saved. Try again.'));
      }
    } else {
      try {
        await controller.startVideoRecording();
        if (mounted) setState(() => _isRecording = true);
      } catch (e) {
        if (mounted) setState(() => _errorMessage = friendlyError(e, 'Recording could not start. Try again.'));
      }
    }
  }

  Future<void> _processUpload(File file) async {
    setState(() {
      _isProcessing = true;
      _processingStep = 0;
      _errorMessage = null;
    });

    try {
      final uploadedVideo = await widget.repository.uploadVideo(
        file,
        parentVideoId: widget.parentVideo.id,
      );

      if (!mounted) return; // the sheet was closed while uploading; the server still has the video
      _pollStatus(uploadedVideo);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = friendlyError(e, 'The upload failed. Check your connection and try again.');
        });
      }
    }
  }

  /// 1.5 s apart: about 90 s for the server to transcribe and classify the reply.
  static const _maxPolls = 60;

  bool _pollInFlight = false;
  bool _pollFinished = false;

  /// Asks the server how the new reply is doing until it is ready, failed, or we give up.
  /// One request at a time (a slow answer must not let two ticks both finish and close the sheet twice).
  void _pollStatus(Video video) {
    int attempts = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_pollInFlight || _pollFinished) return;
      _pollInFlight = true;
      attempts++;
      try {
        if (!mounted) return timer.cancel();
        if (attempts <= 3 && _processingStep < 3) setState(() => _processingStep = attempts);

        Map<String, dynamic>? status;
        try {
          status = await widget.repository.getStatus(video.id);
        } on ApiException catch (e) {
          // Rate limited or server trouble: wait it out instead of hammering. Anything else (e.g. not found,
          // signed out) will not fix itself, so stop and say so.
          if (!e.shouldBackOff && e.statusCode != null && e.statusCode! < 500) {
            _stopPolling(timer);
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _errorMessage = e.message;
              });
            }
            return;
          }
        }
        if (!mounted) return timer.cancel();

        final state = (status?['status'] as String? ?? '').toLowerCase();
        if (state == 'failed') {
          _stopPolling(timer);
          setState(() {
            _isProcessing = false;
            _errorMessage = 'Processing failed on the server. Please record your reply again.';
          });
        } else if (state == 'ready' || attempts >= _maxPolls) {
          _stopPolling(timer);
          setState(() => _processingStep = 4);
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (!mounted) return; // swiped away meanwhile
          // Hand back what the server decided (the stance), or the unfinished upload if it is still processing.
          widget.onReplyPosted(state == 'ready'
              ? video.copyWith(
                  status: 'ready',
                  stance: (status?['stance'] as String? ?? video.stance).toUpperCase(),
                )
              : video);
          Navigator.pop(context);
        }
      } finally {
        _pollInFlight = false;
      }
    });
  }

  void _stopPolling(Timer timer) {
    _pollFinished = true;
    timer.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Parent video context
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  StanceBadge(stance: widget.parentVideo.stance, role: widget.parentVideo.role),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to @${widget.parentVideo.userName}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        Text(
                          widget.parentVideo.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Camera Preview or Multi-Step Processing View
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  child: _isProcessing
                      ? Container(
                          color: const Color(0xFFF9FAFB),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(color: Color(0xFF16A34A)),
                              const SizedBox(height: 24),
                              const Text(
                                'AI Debate Pipeline Active',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...List.generate(_steps.length, (i) {
                                final isDone = i < _processingStep;
                                final isCurrent = i == _processingStep;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isDone
                                            ? Icons.check_circle_rounded
                                            : isCurrent
                                                ? Icons.pending_rounded
                                                : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: isDone
                                            ? const Color(0xFF16A34A)
                                            : isCurrent
                                                ? const Color(0xFF2563EB)
                                                : const Color(0xFFD1D5DB),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _steps[i],
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                                            color: isCurrent
                                                ? const Color(0xFF111827)
                                                : isDone
                                                    ? const Color(0xFF4B5563)
                                                    : const Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        )
                      : _cameraController != null && _isCameraReady
                          ? CameraPreview(_cameraController!)
                          : Center(
                              child: Text(
                                _errorMessage ?? 'Starting camera...',
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bottom Record Button
          if (!_isProcessing)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF111827), width: 4),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: _isRecording ? 32 : 56,
                    height: _isRecording ? 32 : 56,
                    decoration: BoxDecoration(
                      color: _isRecording ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(_isRecording ? 6 : 999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
