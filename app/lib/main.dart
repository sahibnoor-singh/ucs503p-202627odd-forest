import 'dart:async';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/api_feed_repository.dart';
import 'data/auth_repository.dart';
import 'data/feed_repository.dart';
import 'features/auth/auth_gate.dart';
import 'features/home/feed_controller.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/notifications/notifications_repository.dart';
import 'features/messages/messages_repository.dart';
import 'features/rooms/rooms_repository.dart';
import 'features/today/today_controller.dart';
import 'features/today/today_repository.dart';
import 'features/onboarding/onboarding_repository.dart';
import 'features/messages/unread_controller.dart';
import 'features/reels/reels_repository.dart';
import 'features/safety/safety_repository.dart';
import 'features/share/share_repository.dart';
import 'screens/account_screen.dart';
import 'screens/discovery_feed_screen.dart';
import 'screens/home_feed_screen.dart';
import 'screens/upload_screen.dart';
import 'services/analytics.dart';
import 'services/api_client.dart';
import 'services/app_errors.dart';
import 'services/caption_service.dart';
import 'services/google_identity.dart';
import 'services/public_links.dart';
import 'services/session.dart';
import 'services/video_cache.dart';
import 'services/video_pool.dart';
import 'theme/forest_theme.dart';
import 'ui/forest_icon.dart';
import 'ui/forest_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling();
  if (releaseBuildIsMisconfigured) {
    runApp(const MisconfiguredApp());
    return;
  }
  // Compile the icons now so cards draw them the moment they scroll into view.
  unawaited(ForestIcon.precacheIcons());
  runApp(const ForestApp());
}

/// The app's wiring, top to bottom:
///
///   Session (who is logged in) ─ ApiClient (adds their token to every request)
///     └ AuthRepository (login / sign-up calls)
///     └ per-person objects (feed, reels), keyed by the login token
///         └ MaterialApp ─ AuthGate ── logged out → LoginScreen
///                                  └─ logged in  → RootShell
///
/// Everything that holds one person's data (the Home feed, the reels list) is
/// keyed by the login token, so logging out and in as someone else throws it away
/// and can never show the previous person's posts. It must sit ABOVE the
/// MaterialApp: the full-screen viewer, the thread/reply/report sheets and every other
/// screen opened on top of Home are pushed onto the app's Navigator, which is above
/// anything inside `home:`, so providers placed there are invisible to them (a red
/// "Could not find the correct `Provider<FeedController>`" screen).
class ForestApp extends StatelessWidget {
  /// The optional arguments are for tests; the app passes none.
  /// [repository] replaces the Home API, [session] replaces the saved login,
  /// [apiClient] replaces the network client.
  const ForestApp({super.key, this.repository, this.session, this.apiClient, this.googleIdentity});

  final FeedRepository? repository;
  final Session? session;
  final ApiClient? apiClient;

  /// Replaces the real "Continue with Google" window (tests).
  final GoogleIdentity? googleIdentity;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // The DEV_USER shortcut (debug builds only) skips the login screen.
        ChangeNotifierProvider<Session>(
          create: (_) {
            final s = session ??
                Session(devBypass: ApiClient.defaultDevUser.isNotEmpty);
            if (session == null) unawaited(s.restore());
            return s;
          },
        ),
        Provider<ApiClient>(
          create: (context) {
            final s = context.read<Session>();
            return apiClient ??
                ApiClient(tokenProvider: () => s.token, onUnauthorized: () => unawaited(s.expire()));
          },
        ),
        ProxyProvider<ApiClient, AuthRepository>(update: (_, api, _) => AuthRepository(api)),
        ProxyProvider<ApiClient, Analytics>(update: (_, api, _) => Analytics(api)),
        Provider<GoogleIdentity>(create: (_) => googleIdentity ?? RealGoogleIdentity()),
        ProxyProvider<ApiClient, OnboardingRepository>(update: (_, api, _) => OnboardingRepository(api)),
        // Subtitles: the on/off switch and the subtitle lines of each video.
        ChangeNotifierProvider<CaptionService>(create: (context) => CaptionService(context.read<ApiClient>())),
        // Videos already loaded this session open from disk (wiped at every
        // start), and the last few players stay ready (see VideoPool).
        Provider<VideoCache>(
          create: (_) {
            final cache = VideoCache();
            unawaited(cache.reset());
            return cache;
          },
        ),
        Provider<VideoPool>(
          create: (context) => VideoPool(context.read<VideoCache>()),
          dispose: (_, pool) => pool.dispose(),
        ),
      ],
      child: _PerPersonScope(
        repository: repository,
        child: MaterialApp(
          title: 'FOREST',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          scrollBehavior: const _AnyDeviceScrollBehavior(),
          theme: ForestTheme.light,
          darkTheme: ForestTheme.dark,
          home: const AuthGate(app: RootShell()),
        ),
      ),
    );
  }
}

/// Creates the objects that belong to one person. It is rebuilt (so they are thrown away,
/// and the app returns to the login gate) whenever the login token changes. The objects are
/// created lazily, so while nobody is logged in nothing here touches the network.
class _PerPersonScope extends StatelessWidget {
  const _PerPersonScope({this.repository, required this.child});

  final FeedRepository? repository;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final token = context.select<Session, String?>((s) => s.token);
    return MultiProvider(
      key: ValueKey(token),
      providers: [
        Provider<FeedRepository>(
          create: (context) => repository ?? ApiFeedRepository(context.read<ApiClient>()),
        ),
        Provider<ReelsRepository>(create: (context) => ReelsRepository(context.read<ApiClient>())),
        Provider<ShareRepository>(create: (context) => ShareRepository(context.read<ApiClient>())),
        Provider<MessagesRepository>(create: (context) => MessagesRepository(context.read<ApiClient>())),
        Provider<NotificationsRepository>(create: (context) => NotificationsRepository(context.read<ApiClient>())),
        Provider<SafetyRepository>(create: (context) => SafetyRepository(context.read<ApiClient>())),
        Provider<TodayRepository>(create: (context) => TodayRepository(context.read<ApiClient>())),
        Provider<RoomsRepository>(create: (context) => RoomsRepository(context.read<ApiClient>())),
        ChangeNotifierProvider<TodayController>(create: (context) => TodayController(context.read<TodayRepository>())),
        ChangeNotifierProvider<BlocklistController>(create: (_) => BlocklistController()),
        ChangeNotifierProvider<UnreadController>(create: (context) => UnreadController(context.read<MessagesRepository>())),
        ChangeNotifierProvider<NotificationsController>(create: (context) => NotificationsController(context.read<NotificationsRepository>())),
        ChangeNotifierProvider<FeedController>(
          create: (context) => FeedController(context.read<FeedRepository>()),
        ),
      ],
      child: child,
    );
  }
}

/// Phase-1 scope: 4 screens, swipe-navigated — Home (following feed) →
/// Feed corner (discovery) → Upload (camera/record) → Manage Account.
/// See README.md / CLAUDE.md.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _pageController = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Once per time the app is opened signed in: one measured event, and the server's public address for share links.
    context.read<Analytics?>()?.track('app_open');
    if (!PublicLinks.known) unawaited(context.read<AuthRepository>().config());
  }

  static const _screens = [
    HomeFeedScreen(),
    DiscoveryFeedScreen(),
    UploadScreen(),
    AccountScreen(),
  ];

  void _onTapNav(int i) {
    // Far jumps would slide through (and build) every tab in between, e.g.
    // the camera on the way from Home to Account. Jump instead.
    final current = _pageController.hasClients
        ? (_pageController.page ?? _index.toDouble()).round()
        : _index;
    if ((i - current).abs() > 1) {
      _pageController.jumpToPage(i);
      return;
    }
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DefaultTabNavigator(
        goTo: _onTapNav,
        child: PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _index = i),
          children: _screens,
        ),
      ),
      bottomNavigationBar: ForestNavBar(selectedIndex: _index, onSelected: _onTapNav),
    );
  }
}

/// Lets a mouse (or a pen) drag lists and pages, not only a finger. Flutter leaves the mouse out by default, which made the tabs and the
/// feed impossible to swipe on a laptop, in a browser or on an emulator whose cursor acts as a mouse.
class _AnyDeviceScrollBehavior extends MaterialScrollBehavior {
  const _AnyDeviceScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };
}
