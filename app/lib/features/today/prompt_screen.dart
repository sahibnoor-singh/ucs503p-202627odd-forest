import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/feed_item.dart';
import '../../screens/home_feed_screen.dart' show cardActionsFor;
import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import '../home/feed_controller.dart';
import '../home/feed_item_card.dart';
import 'today_controller.dart';
import 'today_header.dart' show answerTodaysQuestion;

/// The question of the day on its own page: the question, the button to answer it, and everyone's answers.
class PromptScreen extends StatefulWidget {
  const PromptScreen({super.key, required this.controller});

  final TodayController controller;

  @override
  State<PromptScreen> createState() => _PromptScreenState();
}

class _PromptScreenState extends State<PromptScreen> {
  List<FeedItem>? _answers;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _load();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _load() async {
    final feed = context.read<FeedController>();
    try {
      final list = await widget.controller.repository.answers();
      feed.adopt(list);
      if (mounted) {
        setState(() {
          _answers = list;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load the answers. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final prompt = widget.controller.prompt;
    final feed = context.read<FeedController>();
    final answers = _answers;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Question of the day', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: RefreshIndicator(
        color: t.fg,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Text(prompt?.text ?? '', key: const Key('prompt-screen-text'), style: TextStyle(color: t.fg, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
            ),
            if (prompt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                child: prompt.answered
                    ? Row(children: [
                        Icon(Icons.check_circle_rounded, size: 18, color: t.forStance),
                        const SizedBox(width: 6),
                        Text('You answered this one', style: TextStyle(color: t.forStance, fontWeight: FontWeight.w700)),
                      ])
                    : SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('prompt-screen-answer'),
                          onPressed: () async {
                            await answerTodaysQuestion(context, widget.controller);
                            if (mounted) _load();
                          },
                          icon: const Icon(Icons.videocam_rounded),
                          label: const Text('Answer on video', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
              ),
            Divider(height: 1, color: t.border),
            if (answers == null && _error == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (answers == null)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.fg2))))
            else if (answers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: Text('Nobody has answered yet. Yours could be the first video here.', textAlign: TextAlign.center, style: TextStyle(color: t.fg2, fontSize: 15, height: 1.4)),
              )
            else
              for (final item in answers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                  child: FeedItemCard(key: ValueKey('answer-${item.post.id}'), item: item, actions: cardActionsFor(context, feed)),
                ),
          ],
        ),
      ),
    );
  }
}
