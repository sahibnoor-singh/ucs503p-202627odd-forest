import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/forest_theme.dart';
import '../../ui/forest_mark.dart';

/// Shared look of the login and sign-up screens. They follow the phone's light or dark setting through the theme colours; the blue
/// accent is for the main button and links, red only for errors.
///
/// [brand] shows the FOREST mark and name at the top (the login screen). [steps] and [step] show the progress dots of the sign-up pages.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
    this.brand = false,
    this.step,
    this.steps = 3,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool brand;

  /// 0-based position in the sign-up pages; null hides the dots.
  final int? step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, (height * 0.04).clamp(12.0, 40.0), 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(t),
                  SizedBox(height: brand ? 36 : 24),
                  Text(title, style: TextStyle(color: t.fg, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!, style: TextStyle(color: t.fg2, fontSize: 15, height: 1.4)),
                  ],
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ForestTokens t) {
    if (brand) {
      return Row(children: [
        const ForestMark(size: 44),
        const SizedBox(width: 12),
        Text('FOREST', style: TextStyle(color: t.fg, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
      ]);
    }
    return SizedBox(
      height: 44,
      child: Row(children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded, color: t.fg),
            style: IconButton.styleFrom(backgroundColor: t.raised, minimumSize: const Size(44, 44)),
          ),
        const Spacer(),
        if (step != null)
          Row(children: [
            for (var i = 0; i < steps; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(left: 6),
                width: i == step ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: i <= step! ? t.accent : t.border, borderRadius: BorderRadius.circular(4)),
              ),
          ]),
      ]),
    );
  }
}

/// A labelled text box with its server/validation message underneath. [code] makes it the big, centred box for a 6-digit code.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.error,
    this.helper,
    this.obscure = false,
    this.keyboard,
    this.onChanged,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
    this.suffix,
    this.fieldKey,
    this.code = false,
  });

  final String label;
  final TextEditingController controller;
  final String? error;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final Widget? suffix;
  final Key? fieldKey;
  final bool code;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: fieldKey,
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        onChanged: onChanged,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        maxLength: maxLength,
        textAlign: code ? TextAlign.center : TextAlign.start,
        cursorColor: t.accent,
        style: code
            ? TextStyle(color: t.fg, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 10)
            : TextStyle(color: t.fg, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          errorText: error,
          helperText: helper,
          helperMaxLines: 2,
          errorMaxLines: 3,
          suffixIcon: suffix,
          filled: true,
          fillColor: t.raised,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: code ? 20 : 18),
          labelStyle: TextStyle(color: t.fg2),
          floatingLabelStyle: TextStyle(color: t.fg2, fontWeight: FontWeight.w600),
          helperStyle: TextStyle(color: t.fg2),
          border: _border(t.border),
          enabledBorder: _border(t.border),
          focusedBorder: _border(t.accent, width: 1.6),
          errorBorder: _border(t.like),
          focusedErrorBorder: _border(t.like, width: 1.6),
        ),
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: color, width: width));
}

class AuthButton extends StatelessWidget {
  const AuthButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: t.accent.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
    );
  }
}

/// "or" between the main form and the Google button.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(children: [
        Expanded(child: Divider(color: t.border)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('or', style: TextStyle(color: t.fg2, fontSize: 13))),
        Expanded(child: Divider(color: t.border)),
      ]),
    );
  }
}

const _googleG = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

/// "Continue with Google", with Google's own four-colour G. Shown only when the server has Google sign-in on.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed, this.busy = false, this.label = 'Continue with Google'});

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        key: const Key('google-button'),
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.fg,
          backgroundColor: t.raised,
          side: BorderSide(color: t.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(_googleG, width: 20, height: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

/// A line of red text for problems that belong to no single input.
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(message!, style: TextStyle(color: context.forest.like, fontSize: 13.5, height: 1.3)),
    );
  }
}
