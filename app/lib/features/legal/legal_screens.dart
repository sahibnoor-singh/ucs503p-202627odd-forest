import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../theme/forest_theme.dart';

/// The terms of use and the privacy notice, in plain words, shown inside the app (the sign-up and Account link here).
/// Draft for the closed alpha: a lawyer must review both before a public launch (docs/RELEASE.md).
enum LegalDoc { terms, privacy }

const _updated = 'Last updated 22 October 2026';

class _Section {
  const _Section(this.heading, this.body);
  final String heading;
  final List<String> body;
}

const _terms = <_Section>[
  _Section('Who can use FOREST', [
    'You must be 18 or older. You use one account, and you verify it with your e-mail address.',
  ]),
  _Section('What you post', [
    'You post videos and short text replies. Post only things you made or have the right to share, including any music or clips in them.',
    'You keep ownership of what you post. You allow FOREST to store it, process it (including with automatic analysis), and show it to other people in the app so that it works as described here.',
    'You can delete a post, or your whole account, whenever you like.',
  ]),
  _Section('Rules of the room', [
    'Argue with the claim, not the person. Do not post harassment, hate, threats, content that glorifies violence, sexual content, anything that targets or endangers a child, impersonation, spam, or anything illegal.',
    'Do not post other people\'s videos or music that you have no right to use.',
    'Do not try to mislead people on purpose. Claims in videos are checked automatically and shown with a credibility percentage.',
  ]),
  _Section('Automatic labels can be wrong', [
    'FOR, AGAINST, UNRESOLVED and the credibility percentage are estimates made by software. They can be mistaken. If a label about you or your video is wrong, contact us (details below) and a person will look at it.',
  ]),
  _Section('Reports and moderation', [
    'Anyone can report a post, and reports are reviewed by a person. We may hide a post, give a warning, or suspend an account that breaks these rules. Nothing is removed only because a report was made.',
    'Automated accounts are always marked BOT.',
  ]),
  _Section('Videos and reactions between friends', [
    'You can send a video to a friend only if you follow each other. Friends reply with an emoji reaction. There is no free text and no messages from strangers. You can block anyone at any time.',
  ]),
  _Section('Ending your use', [
    'You can delete your account in Account. We may suspend an account that breaks these terms.',
  ]),
  _Section('Changes and questions', [
    'We will tell you in the app before we make important changes to these terms. Questions and complaints go to the contact below.',
  ]),
];

const _privacy = <_Section>[
  _Section('What we collect', [
    'Your e-mail address (to check it is you and to sign you in), your name, username and date of birth (to check your age), and your password (stored only as a one-way hash).',
    'What you post: videos, text, and the title, description, subtitles and labels made from them.',
    'What you do: likes, follows, blocks, reports, the videos you watch and for how long. We use this to rank what you see.',
    'We also keep simple counts of actions such as opening the app, answering the daily question or joining a room, so we can learn what works. They hold no video, text or search words.',
    'Your camera and microphone are used only while you record. Nothing is recorded in the background.',
  ]),
  _Section('How we use it', [
    'To run FOREST, to rank Discover, to keep the room safe, and to explain videos: the audio of a video you post is sent to Google\'s Gemini service to be transcribed, labelled and checked.',
    'Discover can include a few posts that a friend who keeps sending you videos you like would pick. You can switch this off in Account.',
    'If you ask for a personality summary on your profile, the keywords you chose are sent to Google\'s Gemini service to write it. You read and approve it before anyone else sees it.',
    'If you sign up with a friend\'s invite code, you and that friend follow each other. Posts you make in a debate room are public like any other post, and the room\'s members can see who joined.',
  ]),
  _Section('Who sees what', [
    'Your posts, name and username are visible to other people in the app. Your e-mail address and date of birth are never shown to others.',
    'If you choose "Continue with Google", Google tells us your e-mail address and name. The mail service that delivers your sign-up code receives your e-mail address. Google\'s Gemini service receives the audio of videos you post. We do not sell your data.',
  ]),
  _Section('Keeping and deleting it', [
    'You can delete your account in Account. That removes your personal details, your videos and your likes, follows, blocks and messages. Replies other people wrote to your posts stay, under a deleted account.',
    'Reports and moderation records may be kept for a limited time where the law or safety needs it.',
  ]),
  _Section('Your choices', [
    'You can block people, turn off friends\' taste in Discover, delete posts, and delete your account.',
    'To ask for a copy of your data or a correction, contact us below.',
  ]),
  _Section('Children', [
    'FOREST is for people 18 and over. We do not knowingly collect data from anyone younger.',
  ]),
];

/// One of the two documents, with the grievance contact at the bottom (loaded from the server; the text still reads without it).
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.doc, this.api});

  final LegalDoc doc;

  /// For tests; the app uses the shared client.
  final ApiClient? api;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  String? _contact;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final api = widget.api ?? context.read<ApiClient?>();
    if (api == null) return;
    try {
      final json = await api.getJson('/api/legal/contact');
      if (json is! Map<String, dynamic>) return;
      final name = json['name'] as String?;
      final email = json['email'] as String?;
      final parts = [if (name != null && name.isNotEmpty) name, if (email != null && email.isNotEmpty) email];
      if (parts.isNotEmpty && mounted) setState(() => _contact = parts.join(' · '));
    } on Object {
      // the documents are complete without it
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final terms = widget.doc == LegalDoc.terms;
    final sections = terms ? _terms : _privacy;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(terms ? 'Terms of use' : 'Privacy notice', style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.border)),
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(_updated, style: TextStyle(color: t.fg2, fontSize: 12.5)),
            for (final s in sections) ...[
              const SizedBox(height: 20),
              Text(s.heading, style: TextStyle(color: t.fg, fontSize: 16.5, fontWeight: FontWeight.w800)),
              for (final p in s.body) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p, style: TextStyle(color: t.fg, fontSize: 14.5, height: 1.45))),
            ],
            const SizedBox(height: 24),
            Text('Contact', style: TextStyle(color: t.fg, fontSize: 16.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              _contact == null ? 'Complaints and questions go to our grievance contact, shown at the bottom of this page when it is set.' : 'Complaints and questions: $_contact',
              key: const Key('legal-contact'),
              style: TextStyle(color: t.fg, fontSize: 14.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openLegal(BuildContext context, LegalDoc doc) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc)));

/// "By creating an account you confirm you are 18 or older and agree to the Terms of use and the Privacy notice." with both as links.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({super.key});

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()..onTap = () => openLegal(context, LegalDoc.terms);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()..onTap = () => openLegal(context, LegalDoc.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final base = TextStyle(color: t.fg2, fontSize: 12.5, height: 1.4);
    final link = base.copyWith(color: t.accent, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text.rich(
        key: const Key('legal-consent'),
        TextSpan(style: base, children: [
          const TextSpan(text: 'By creating an account you confirm you are 18 or older and agree to the '),
          TextSpan(text: 'Terms of use', style: link, recognizer: _terms),
          const TextSpan(text: ' and the '),
          TextSpan(text: 'Privacy notice', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ]),
      ),
    );
  }
}

/// Two rows for Account.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(key: const Key('open-terms'), leading: const Icon(Icons.description_outlined), title: const Text('Terms of use'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => openLegal(context, LegalDoc.terms)),
          ListTile(key: const Key('open-privacy'), leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy notice'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => openLegal(context, LegalDoc.privacy)),
        ],
      );
}
