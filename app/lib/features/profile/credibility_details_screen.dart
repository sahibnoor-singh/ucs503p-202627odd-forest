import 'package:flutter/material.dart';

import '../../theme/forest_theme.dart';
import 'profile_models.dart';

/// Screen opened when tapping on the Credibility Score card.
class CredibilityDetailsScreen extends StatelessWidget {
  const CredibilityDetailsScreen({super.key, required this.credibility});

  final UserCredibility credibility;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final score = credibility.scorePercent;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Credibility Assessment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Big Score Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _BigScoreDisplay(score: score, sufficient: credibility.sufficient, tokens: t),
                  const SizedBox(height: 16),
                  Text(
                    credibility.sufficient
                        ? _scoreTier(score)
                        : 'Insufficient Data',
                    style: TextStyle(color: t.fg, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    credibility.sufficient
                        ? 'Based on rigorous AI claim verification and evidence retrieval.'
                        : 'At least 3 verifiable claims must be assessed to compute a reliable credibility score.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.fg2, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Statistics Row
            Text('ASSESSMENT METRICS', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricBox(
                    label: 'Analyzed Videos',
                    value: '${credibility.analyzedVideos}',
                    icon: Icons.videocam_outlined,
                    tokens: t,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricBox(
                    label: 'Assessed Claims',
                    value: '${credibility.totalClaims}',
                    icon: Icons.fact_check_outlined,
                    tokens: t,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Verdict Distribution
            if (credibility.verdictDistribution.isNotEmpty) ...[
              Text('VERDICT BREAKDOWN', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final entry in credibility.verdictDistribution.entries) ...[
                      _VerdictRow(
                        verdict: entry.key,
                        count: entry.value,
                        total: credibility.totalClaims,
                        tokens: t,
                      ),
                      if (entry.key != credibility.verdictDistribution.keys.last)
                        Divider(height: 16, color: t.border.withValues(alpha: 0.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Method Explanation
            Text('HOW CREDIBILITY IS CALCULATED', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 18, color: t.accent),
                      const SizedBox(width: 8),
                      Text('Evidence-backed Scoring', style: TextStyle(color: t.fg, fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'FOREST extracts factual assertions from each video using Google Gemini and verifies them against authoritative citations. Each claim is mathematically scored:',
                    style: TextStyle(color: t.fg, fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: t.raised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.border),
                    ),
                    child: Text(
                      'S_Cᵢ = w(Vᵢ) × Eᵢ',
                      style: TextStyle(color: t.fg, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• w(Vᵢ) = Verdict weight (True, Mostly True, Inconclusive, Misleading, False)\n'
                    '• Eᵢ = External evidence confidence score\n'
                    '• User Credibility = Normalized average of all assessed claims',
                    style: TextStyle(color: t.fg2, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: t.border),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: t.forStance),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No Popularity Bias: Followers, likes, and view counts NEVER factor into credibility. Only evidence-backed statements move this score.',
                          style: TextStyle(color: t.fg2, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _scoreTier(int? score) {
    if (score == null) return 'Unrated';
    if (score >= 80) return 'High Credibility';
    if (score >= 60) return 'Moderate Credibility';
    if (score >= 40) return 'Mixed Credibility';
    return 'Low Evidence Ratio';
  }
}

class _BigScoreDisplay extends StatelessWidget {
  const _BigScoreDisplay({required this.score, required this.sufficient, required this.tokens});

  final int? score;
  final bool sufficient;
  final ForestTokens tokens;

  Color get _color {
    if (!sufficient || score == null) return tokens.fg2;
    if (score! >= 75) return tokens.forStance;
    if (score! >= 50) return const Color(0xFFEAB308);
    return tokens.againstStance;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: (sufficient && score != null) ? score! / 100.0 : 0.05,
              strokeWidth: 7,
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation(_color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sufficient && score != null ? '$score%' : '—',
                style: TextStyle(color: tokens.fg, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              if (sufficient)
                Text('/100', style: TextStyle(color: tokens.fg2, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value, required this.icon, required this.tokens});

  final String label;
  final String value;
  final IconData icon;
  final ForestTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tokens.fg2),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: TextStyle(color: tokens.fg2, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: tokens.fg, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.verdict, required this.count, required this.total, required this.tokens});

  final String verdict;
  final int count;
  final int total;
  final ForestTokens tokens;

  Color get _verdictColor {
    final v = verdict.toLowerCase();
    if (v.contains('true') && !v.contains('mostly')) return tokens.forStance;
    if (v.contains('mostly true')) return const Color(0xFF3E9E74);
    if (v.contains('misleading')) return const Color(0xFFEAB308);
    if (v.contains('false')) return tokens.againstStance;
    return tokens.fg2;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _verdictColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(verdict, style: TextStyle(color: tokens.fg, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            Text('$count (${(ratio * 100).round()}%)', style: TextStyle(color: tokens.fg2, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: tokens.raised,
            valueColor: AlwaysStoppedAnimation(_verdictColor),
          ),
        ),
      ],
    );
  }
}
