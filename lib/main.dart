import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'screens/provider_home_screen.dart';
import 'screens/provider_setup_screen.dart';
import 'screens/setup_screen.dart';
import 'services/account_service.dart';
import 'services/event_store.dart';
import 'services/invite_service.dart';
import 'services/referrals.dart';
import 'services/reminders.dart';
import 'services/shared_reels.dart';
import 'services/search_log.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/launch_intro.dart';
import 'screens/rsvp_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use Firebase when it's set up (run `flutterfire configure`);
  // otherwise keep events on this device so the app still works.
  EventStore store;
  var cloud = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    store = FirestoreEventStore();
    cloud = true;
    SearchLog.instance.enabled = true;
  } catch (e) {
    debugPrint('Firebase not available, saving on this device. If Firebase is set up, check that '
        'Authentication → Sign-in method → Anonymous is enabled. ($e)');
    store = LocalEventStore();
  }

  await Reminders.init();

  final state = AppState(
    store,
    usingCloud: cloud,
    accounts: cloud ? AccountService() : null,
    referrals: cloud ? ReferralService() : null,
  );
  state.themeColor = await AppState.loadThemeColor();
  applyAppColor(state.themeColor);
  await state.load();

  // Invite links: https://festino.web.app/?ref=CODE
  if (kIsWeb) {
    final code = codeFromUri(Uri.base);
    if (code != null && state.referral.usedCode == null) await state.setPendingRefCode(code);
  }
  // Party invites: https://festino.web.app/?invite=<hostUid>_<eventId>
  // or the short form https://festino.web.app/i/<hostUid>_<eventId>
  final (invite, guest) = kIsWeb ? inviteFromUri(Uri.base) : (null, '');
  runApp(FestinoApp(state: state, inviteId: invite, guestKey: guest));
}

class FestinoApp extends StatefulWidget {
  const FestinoApp({super.key, required this.state, this.inviteId, this.guestKey = ''});
  final AppState state;

  /// From a personal invite link: who this guest is on the host's list.
  final String guestKey;

  /// Opened from a party invite link: show the RSVP page first.
  final String? inviteId;

  @override
  State<FestinoApp> createState() => _FestinoAppState();
}

class _FestinoAppState extends State<FestinoApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  AppState get state => widget.state;
  late String? _inviteId = widget.inviteId;

  /// The branded opening screen: shown, then fading out, then gone.
  bool _intro = true;
  bool _introGone = false;

  void _endIntro() {
    if (mounted && _intro) setState(() => _intro = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectSharedReels());
    Future<void>.delayed(const Duration(milliseconds: 1400), _endIntro);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _collectSharedReels();
  }

  /// Picks up reels shared to Festino from Instagram (or TikTok, YouTube) while the app was closed.
  Future<void> _collectSharedReels() async {
    final reels = await SharedReels.take();
    final added = await state.addReels(reels);
    if (added == 0) return;
    _messenger.currentState?.showSnackBar(SnackBar(
      content: Text(added == 1 ? 'Saved "${reels.first.title}". Find it in Games.' : 'Saved $added reels. Find them in Games.'),
    ));
  }

  /// Providers see their listing; everyone else plans events.
  static Widget _home(AppState s) {
    if (s.isProvider) {
      return s.provider == null ? const ProviderSetupScreen() : const ProviderHomeScreen();
    }
    return s.event == null ? const SetupScreen() : const HomeShell();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          scaffoldMessengerKey: _messenger,
          title: 'Festino',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (!_introGone)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_intro,
                    child: AnimatedOpacity(
                      opacity: _intro ? 1 : 0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      onEnd: () {
                        if (!_intro && mounted) setState(() => _introGone = true);
                      },
                      child: LaunchIntro(onTap: _endIntro),
                    ),
                  ),
                ),
            ],
          ),
          home: _inviteId != null
              ? RsvpScreen(inviteId: _inviteId!, guestKey: widget.guestKey, onPlanOwn: () => setState(() => _inviteId = null))
              : _home(state),
        ),
      ),
    );
  }
}
