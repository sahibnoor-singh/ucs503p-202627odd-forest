import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';
import 'personality_editor.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Full screen for editing own profile.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final ProfileRepository _repo = ProfileRepository(context.read<ApiClient>());

  late final TextEditingController _nameCtrl = TextEditingController(text: widget.profile.user.fullName);
  late final TextEditingController _bioCtrl = TextEditingController(text: widget.profile.bio ?? '');

  late List<String> _keywords = List.from(widget.profile.personality.keywords);
  late String? _summary = widget.profile.personality.summary;
  late bool _summaryApproved = widget.profile.personality.summaryApproved;
  late List<String> _interests = List.from(widget.profile.personality.interests);

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Display name cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.updateProfile(
        fullName: name,
        bio: _bioCtrl.text.trim(),
        personalityKeywords: _keywords,
        personalitySummary: _summary,
        personalitySummaryApproved: _summaryApproved,
        interests: _interests,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _saving = false; });
    } on Object {
      if (mounted) setState(() { _error = 'Could not update profile. Try again.'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.againstStance.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.againstStance),
                ),
                child: Text(_error!, style: TextStyle(color: t.againstStance, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],

            // Basic Info
            Text('BASIC INFORMATION', style: TextStyle(color: t.fg2, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle: TextStyle(color: t.fg2, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bioCtrl,
              maxLines: 2,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: 'Short Bio',
                hintText: 'What topics do you engage in?',
                labelStyle: TextStyle(color: t.fg2, fontSize: 13),
                hintStyle: TextStyle(color: t.fg2, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              ),
            ),
            const SizedBox(height: 24),
            Divider(height: 1, color: t.border),
            const SizedBox(height: 24),

            // Personality Section
            PersonalityEditor(
              initialKeywords: _keywords,
              initialSummary: _summary,
              initialSummaryApproved: _summaryApproved,
              initialInterests: _interests,
              repo: _repo,
              onChanged: ({
                required List<String> keywords,
                required String? summary,
                required bool summaryApproved,
                required List<String> interests,
              }) {
                _keywords = keywords;
                _summary = summary;
                _summaryApproved = summaryApproved;
                _interests = interests;
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
