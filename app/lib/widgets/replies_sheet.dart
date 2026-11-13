import 'package:flutter/material.dart';

import '../models/video.dart';
import '../utils/stance.dart';

/// Bottom sheet listing replies grouped with stance badges.
Future<void> showRepliesSheet(
  BuildContext context, {
  required Video parent,
  required List<Video> replies,
  required ValueChanged<Video> onSelect,
  VoidCallback? onRecordReply,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text(
                      '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    if (onRecordReply != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onRecordReply();
                        },
                        icon: const Icon(Icons.reply_outlined, size: 16),
                        label: const Text('Add Reply'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF16A34A)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: replies.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.forum_outlined, size: 40, color: Color(0xFF9CA3AF)),
                              const SizedBox(height: 10),
                              const Text(
                                'No replies yet.',
                                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Be the first to record a video taking a stance.',
                                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                              ),
                              if (onRecordReply != null) ...[
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onRecordReply();
                                  },
                                  icon: const Icon(Icons.reply_outlined),
                                  label: const Text('Record reply'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: replies.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64, color: Color(0xFFF3F4F6)),
                        itemBuilder: (context, i) {
                          final reply = replies[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            onTap: () {
                              Navigator.of(context).pop();
                              onSelect(reply);
                            },
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFF3F4F6),
                              child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF111827), size: 24),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  '@${reply.userName}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111827)),
                                ),
                                const SizedBox(width: 8),
                                StanceBadge(stance: reply.stance, role: reply.role),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                reply.title?.isNotEmpty == true ? reply.title! : reply.id,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}
