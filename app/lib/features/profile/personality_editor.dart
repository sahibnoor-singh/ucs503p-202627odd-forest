import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import 'profile_repository.dart';

/// Interactive personality editor widget used inside ProfileEditScreen.
class PersonalityEditor extends StatefulWidget {
  const PersonalityEditor({
    super.key,
    required this.initialKeywords,
    required this.initialSummary,
    required this.initialSummaryApproved,
    required this.initialInterests,
    required this.repo,
    required this.onChanged,
  });

  final List<String> initialKeywords;
  final String? initialSummary;
  final bool initialSummaryApproved;
  final List<String> initialInterests;
  final ProfileRepository repo;
  final void Function({
    required List<String> keywords,
    required String? summary,
    required bool summaryApproved,
    required List<String> interests,
  }) onChanged;

  @override
  State<PersonalityEditor> createState() => _PersonalityEditorState();
}

class _PersonalityEditorState extends State<PersonalityEditor> {
  late final List<String> _keywords = List.from(widget.initialKeywords);
  late final TextEditingController _summaryCtrl = TextEditingController(text: widget.initialSummary ?? '');
  late final TextEditingController _keywordInputCtrl = TextEditingController();
  late bool _summaryApproved = widget.initialSummaryApproved;
  late final List<String> _interests = List.from(widget.initialInterests);

  bool _generating = false;
  String? _generateError;

  static const _availableTopics = [
    'Politics',
    'Economy',
    'Technology and AI',
    'Education',
    'Environment',
    'Health',
    'Law and rights',
    'Society and culture',
    'Sports',
    'Entertainment',
    'Ethics and religion',
    'Startups',
    'Foreign affairs',
    'Farming',
  ];

  @override
  void initState() {
    super.initState();
    _summaryCtrl.addListener(_notify);
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _keywordInputCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(
      keywords: _keywords,
      summary: _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim(),
      summaryApproved: _summaryApproved,
      interests: _interests,
    );
  }

  void _addKeyword() {
    final text = _keywordInputCtrl.text.trim();
    if (text.isEmpty) return;
    if (_keywords.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 8 keywords allowed.')));
      return;
    }
    if (text.length > 30) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keyword must be 30 characters or less.')));
      return;
    }
    if (_keywords.any((k) => k.toLowerCase() == text.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keyword already added.')));
      return;
    }
    setState(() {
      _keywords.add(text);
      _keywordInputCtrl.clear();
    });
    _notify();
  }

  void _removeKeyword(String kw) {
    setState(() {
      _keywords.remove(kw);
    });
    _notify();
  }

  Future<void> _generateSummary() async {
    if (_keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one keyword first.')));
      return;
    }
    setState(() {
      _generating = true;
      _generateError = null;
    });
    try {
      final summary = await widget.repo.generatePersonalitySummary(_keywords);
      if (mounted) {
        setState(() {
          _summaryCtrl.text = summary;
          _summaryApproved = false; // Must be reviewed & approved by user
          _generating = false;
        });
        _notify();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _generateError = e is ApiException ? e.message : 'Could not generate this. Try again.';
          _generating = false;
        });
      }
    }
  }

  void _toggleInterest(String topic) {
    setState(() {
      if (_interests.contains(topic)) {
        _interests.remove(topic);
      } else {
        if (_interests.length >= 10) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 10 topics.')));
          return;
        }
        _interests.add(topic);
      }
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. KEYWORDS
        Text('PERSONALITY KEYWORDS', style: TextStyle(color: t.fg2, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text('Add words that describe your debate and thought style (e.g. Analytical, Curious, Skeptical).', style: TextStyle(color: t.fg2, fontSize: 12.5)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _keywordInputCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addKeyword(),
                decoration: InputDecoration(
                  hintText: 'Enter keyword...',
                  hintStyle: TextStyle(color: t.fg2, fontSize: 13),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _addKeyword,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        if (_keywords.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kw in _keywords)
                Chip(
                  label: Text(kw, style: TextStyle(color: t.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: t.accent.withValues(alpha: 0.10),
                  side: BorderSide.none,
                  deleteIcon: Icon(Icons.close, size: 14, color: t.accent),
                  onDeleted: () => _removeKeyword(kw),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // 2. AI SUMMARY
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PERSONALITY SUMMARY', style: TextStyle(color: t.fg2, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            if (_generating)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('Suggest with AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: _keywords.isEmpty ? null : _generateSummary,
              ),
          ],
        ),
        if (_generateError != null) ...[
          const SizedBox(height: 4),
          Text(_generateError!, style: TextStyle(color: t.againstStance, fontSize: 12)),
        ],
        const SizedBox(height: 6),
        TextField(
          controller: _summaryCtrl,
          maxLines: 3,
          maxLength: 300,
          style: TextStyle(color: t.fg, fontSize: 13.5, height: 1.4),
          decoration: InputDecoration(
            hintText: 'A concise summary describing how you think and engage...',
            hintStyle: TextStyle(color: t.fg2, fontSize: 13),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
          ),
        ),
        CheckboxListTile(
          value: _summaryApproved,
          onChanged: (v) {
            setState(() => _summaryApproved = v ?? false);
            _notify();
          },
          title: Text('Publish this summary on my public profile', style: TextStyle(color: t.fg, fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Text('Unapproved summaries stay private as drafts.', style: TextStyle(color: t.fg2, fontSize: 11.5)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 20),

        // 3. INTERESTS & FAVORITE TOPICS
        Text('FAVORITE TOPICS', style: TextStyle(color: t.fg2, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text('Select topics you frequently debate or follow (up to 10).', style: TextStyle(color: t.fg2, fontSize: 12.5)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final topic in _availableTopics)
              FilterChip(
                selected: _interests.contains(topic),
                label: Text(topic, style: TextStyle(fontSize: 12, color: _interests.contains(topic) ? Colors.white : t.fg)),
                selectedColor: t.accent,
                backgroundColor: t.surface,
                side: BorderSide(color: _interests.contains(topic) ? t.accent : t.border),
                showCheckmark: false,
                onSelected: (_) => _toggleInterest(topic),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
          ],
        ),
      ],
    );
  }
}
