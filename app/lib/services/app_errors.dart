import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

/// What happens when something unexpected goes wrong, so a person never meets a red error screen or a silent freeze.
///
///  * a widget that fails to build is replaced by [FriendlyError] in a release build (debug keeps Flutter's detailed screen);
///  * an error nobody caught is written to the log and swallowed, instead of ending the app.
///
/// There is no crash-reporting service yet: add one (for example Sentry or Firebase Crashlytics) in [reportError] when there is one.
void installErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return true;
  };
  if (kReleaseMode) ErrorWidget.builder = (details) => const FriendlyError();
}

/// The one place errors are sent. For now: the log.
void reportError(Object error, StackTrace? stack) {
  debugPrint('Unhandled error: $error');
  if (stack != null && kDebugMode) debugPrintStack(stackTrace: stack, maxFrames: 8);
}

/// Shown in place of a part of the screen that failed to draw.
class FriendlyError extends StatelessWidget {
  const FriendlyError({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: dark ? const Color(0xFF16201A) : const Color(0xFFF2F5F3),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Something went wrong here. Go back and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: dark ? const Color(0xFFE5EEE8) : const Color(0xFF15211B), fontSize: 14, height: 1.4, decoration: TextDecoration.none),
            ),
          ),
        ),
      ),
    );
  }
}

/// The words to show a person for a failed action: the server's own message when there is one (it is written to be shown),
/// otherwise [fallback]. Never `$e`: that prints things like "Exception: SocketException: ..." on screen.
String friendlyError(Object? error, String fallback) => error is ApiException ? error.message : fallback;

/// True when this build cannot work because it still points at the emulator's address. A release build must be given the real
/// server with `--dart-define=API_BASE_URL=https://...` (docs/RELEASE.md).
bool get releaseBuildIsMisconfigured => kReleaseMode && ApiClient.defaultBaseUrl.contains('10.0.2.2');

/// What a misconfigured release build shows instead of an app that can never reach its server.
class MisconfiguredApp extends StatelessWidget {
  const MisconfiguredApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'This build was made without a server address.\nRebuild it with --dart-define=API_BASE_URL=https://your-server (see docs/RELEASE.md).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
