import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/feed_item.dart';
import '../../screens/upload_screen.dart';
import '../../services/analytics.dart';
import '../../theme/forest_theme.dart';
import '../../ui/chips.dart';
import '../../ui/forest_avatar.dart';
import '../editor/post_attachment.dart';
import '../reply/reply_sheet.dart';
import 'prompt_screen.dart';
import 'today_controller.dart';

/// The top of Home: the question of the day, and the opinions that are still waiting for a first reply. It is why a new person who follows
/// nobody still has something to do, and why a returning person has a reason to open the app. It draws nothing until the server has
/// answered, and nothing at all if it cannot.
class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TodayController?>();
    final prompt = c?.prompt;
    if (c == null || prompt == null) return const SizedBox.shrink();
    return Column(
      key: const Key('today-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptCard(controller: c),
        if (c.waiting.isNotEmpty) _WaitingStrip(controller: c),
      ],
    );
  }
}

/// Answers the question: records or picks a video, tagged with the day so it joins everyone else's answers.
Future<void> answerTodaysQuestion(BuildContext context, TodayController c) async {
  final prompt = c.prompt;
  if (prompt == null) return;
  context.read<Analytics?>()?.track('prompt_opened', {'from': 'answer'});
  final sent = await openUploadFor(context, PostAttachment(promptDay: prompt.day, label: 'Answer today\'s question'));
  if (sent == true) c.markAnswered();
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.controller});

  final TodayController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final p = controller.prompt!;
    final answers = p.answerCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The label on the left, how many have answered on the right.
          Row(children: [
            Icon(Icons.bolt_rounded, size: 15, color: t.accent),
            const SizedBox(width: 3),
            Text('QUESTION OF THE DAY', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                key: const Key('prompt-see-answers'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  context.read<Analytics?>()?.track('prompt_opened', {'from': 'answers'});
                  Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => PromptScreen(controller: controller)));
                },
                // Shrinks to fit a narrow phone instead of cutting the words off.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    answers == 0 ? 'No answers yet. Be the first.' : '$answers ${answers == 1 ? 'answer' : 'answers'} · see them',
                    maxLines: 1,
                    style: TextStyle(color: t.fg2, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // The whole question, with the video button beside it.
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Tapping the question itself opens its page too (not only the small "answers" line).
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  context.read<Analytics?>()?.track('prompt_opened', {'from': 'question'});
                  Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => PromptScreen(controller: controller)));
                },
                child: Text(p.text, key: const Key('prompt-text'), style: TextStyle(color: t.fg, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
              ),
            ),
            const SizedBox(width: 10),
            if (p.answered)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 18, color: t.forStance),
                const SizedBox(width: 4),
                Text('You answered', style: TextStyle(color: t.forStance, fontWeight: FontWeight.w700, fontSize: 13)),
              ])
            else
              FilledButton.icon(
                key: const Key('prompt-answer'),
                onPressed: () => answerTodaysQuestion(context, controller),
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: const Text('Answer'),
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

class _WaitingStrip extends StatelessWidget {
  const _WaitingStrip({required this.controller});

  final TodayController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text('Waiting for an answer', style: TextStyle(color: t.fg, fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height < 700 ? 130 : 148, // lower on a short phone so a video still shows below
            child: ListView.separated(
              key: const Key('waiting-strip'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: controller.waiting.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _WaitingTile(key: ValueKey('waiting-${controller.waiting[i].post.id}'), item: controller.waiting[i], controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile({super.key, required this.item, required this.controller});

  final FeedItem item;
  final TodayController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final post = item.post;
    final replies = post.replyCount;
    return Container(
      width: 236,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ForestAvatar(user: item.actor, size: 26),
            const SizedBox(width: 8),
            Flexible(child: Text(item.actor.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.fg, fontWeight: FontWeight.w700, fontSize: 13.5))),
            if (item.actor.isBot) ...[const SizedBox(width: 6), const BotTag()],
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              post.title ?? post.summary ?? 'Video opinion',
              maxLines: MediaQuery.sizeOf(context).height < 700 ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.fg, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600),
            ),
          ),
          Row(children: [
            Expanded(child: Text(replies == 0 ? 'No replies yet' : '$replies ${replies == 1 ? 'reply' : 'replies'}', style: TextStyle(color: t.fg2, fontSize: 12.5))),
            SizedBox(
              height: 32,
              child: FilledButton(
                key: Key('waiting-reply-${post.id}'),
                onPressed: () async {
                  context.read<Analytics?>()?.track('reply_wanted_opened');
                  final posted = await showReplySheet(context, parent: post, author: item.actor);
                  if (posted == true) controller.markReplied(post.id);
                },
                style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Reply'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
