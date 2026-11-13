import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../utils/stance.dart';

/// Card displayed at the bottom of a reel after the viewer takes a side.
class OpinionResultCard extends StatelessWidget {
  const OpinionResultCard({
    super.key,
    required this.side,
    this.strongestReply,
    required this.onWatchReply,
    required this.onUndo,
    required this.onOpenReplySheet,
  });

  final String side;
  final Video? strongestReply;
  final ValueChanged<Video> onWatchReply;
  final VoidCallback onUndo;
  final VoidCallback onOpenReplySheet;

  @override
  Widget build(BuildContext context) {
    final isFor = side.toUpperCase() == 'FOR';
    final pillBg = isFor ? StanceColors.forBg : StanceColors.againstBg;
    final pillText = isFor ? StanceColors.forText : StanceColors.againstText;
    final pillBorder = isFor ? StanceColors.forBorder : StanceColors.againstBorder;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pillBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFor ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: pillText,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Your side: $side',
                      style: TextStyle(
                        color: pillText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Undo',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (strongestReply != null) ...[
            const Text(
              'Strongest reply on your side:',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strongestReply!.title?.isNotEmpty == true
                              ? strongestReply!.title!
                              : strongestReply!.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Credibility: ${strongestReply!.credibility}% · by @${strongestReply!.userName}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => onWatchReply(strongestReply!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Watch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'No replies yet on your side.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onOpenReplySheet,
              icon: const Icon(Icons.reply_outlined, size: 16),
              label: const Text('Be the first to reply'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF16A34A),
                side: const BorderSide(color: Color(0xFF16A34A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
