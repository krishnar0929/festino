import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/referrals.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';

/// Sign in or create an account, as a customer (planning an event)
/// or as a provider (photographer, decorator, panthulu, ...).
/// Returns true when signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.initialRole = UserRole.customer, this.reason, this.startWithSignIn = false});

  final UserRole initialRole;
  final String? reason;

  /// Open on "Sign in" instead of "Create account".
  final bool startWithSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late UserRole role = widget.initialRole;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final refCtrl = TextEditingController();
  bool _refFilled = false;
  late bool creating = !widget.startWithSignIn;
  bool busy = false;
  bool showPass = false;
  String? error;

  /// Shown under the error: a one-tap fix, like switching to Sign in.
  String? fixLabel;
  VoidCallback? fixAction;

  bool get _showApple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _showGoogle => kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    refCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_refFilled) {
      _refFilled = true;
      refCtrl.text = AppScope.of(context).pendingRefCode ?? '';
    }
  }

  bool get _askForCode => creating && role == UserRole.customer;

  Future<void> _run(Future<void> Function(AccountService a) action) async {
    final state = AppScope.of(context);
    final a = state.accounts;
    if (a == null) {
      setState(() => error = 'Sign-in needs Firebase. Run flutterfire configure first.');
      return;
    }
    final typed = refCtrl.text.trim();
    if (_askForCode && typed.isNotEmpty) {
      if (normalizeCode(typed) == null) {
        setState(() => error = 'That friend\'s code doesn\'t look right. Codes are 6 letters and numbers.');
        return;
      }
      await state.setPendingRefCode(typed);
    }
    final carry = List.of(state.events);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final overlay = Celebration.overlayOf(context);
    setState(() {
      busy = true;
      error = null;
      fixLabel = null;
      fixAction = null;
    });
    try {
      await action(a);
      await state.afterSignIn(role, carry);
      final notice = state.takeReferralNotice();
      if (notice != null && notice.startsWith('Friend')) {
        Celebration.show(overlay, title: 'Welcome to Hoopla!', message: 'Your friend\'s invite code is saved. Happy planning!', emoji: '🎁');
      } else if (notice != null) {
        messenger.showSnackBar(SnackBar(content: Text(notice)));
      }
      if (mounted) nav.pop(true);
    } on FirebaseAuthException catch (e) {
      if (mounted) _showAuthError(e);
    } catch (e) {
      if (mounted) _setError('Something went wrong. Please try again. ($e)');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _setError(String? message, {String? fix, VoidCallback? onFix}) => setState(() {
        error = message;
        fixLabel = fix;
        fixAction = onFix;
      });

  /// Switches between "Create account" and "Sign in", keeping what was typed.
  void _setMode(bool create, {bool force = false}) {
    if (busy && !force) return;
    setState(() {
      creating = create;
      error = null;
      fixLabel = null;
      fixAction = null;
    });
  }

  /// Friendly errors, and when the person picked the wrong mode, switch for them.
  void _showAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        _setMode(false, force: true);
        passCtrl.clear();
        _setError('You already have an account with this email. Enter your password to sign in.',
            fix: 'Forgot password?', onFix: _forgot);
      case 'user-not-found':
        _setError('No account with this email yet.', fix: 'Create an account instead', onFix: () => _setMode(true));
      case 'wrong-password' || 'invalid-credential' when !creating:
        _setError('Email or password is wrong. New here? Create an account instead.',
            fix: 'Create an account', onFix: () => _setMode(true));
      default:
        _setError(_message(e));
    }
  }

  void _email() {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;
    if (!email.contains('@') || !email.contains('.')) {
      _setError('Enter your email address.');
      return;
    }
    if (pass.isEmpty) {
      _setError(creating ? 'Create a password.' : 'Enter your password.');
      return;
    }
    if (creating && pass.length < 6) {
      _setError('Use a password with at least 6 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    _run((a) => a.emailSignIn(email: email, password: pass, create: creating));
  }

  Future<void> _forgot() async {
    final a = AppScope.of(context).accounts;
    final email = emailCtrl.text.trim();
    if (a == null || !email.contains('@')) {
      _setError('Type your email above, then tap "Forgot password?" again.');
      return;
    }
    try {
      await a.sendPasswordReset(email);
      if (mounted) {
        _setError(null);
        toast(context, 'Password reset link sent to $email. Check your inbox (and spam).');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _setError(_message(e));
    }
  }

  static String? _message(FirebaseAuthException e) => switch (e.code) {
        'popup-closed-by-user' || 'cancelled-popup-request' || 'canceled' || 'web-context-canceled' => null,
        'invalid-email' => 'That email doesn\'t look right.',
        'wrong-password' || 'invalid-credential' || 'user-not-found' => 'Email or password is wrong.',
        'email-already-in-use' => 'That email already has an account. Switch to Sign in.',
        'weak-password' => 'Use a password with at least 6 characters.',
        'too-many-requests' => 'Too many tries. Wait a minute and try again.',
        'network-request-failed' => 'No internet connection.',
        'operation-not-allowed' => 'This sign-in method isn\'t turned on yet (Firebase → Authentication → Sign-in method).',
        'account-exists-with-different-credential' =>
          'This email already signs in another way (email and password, or Apple). Use that instead, then you\'re in.',
        'popup-blocked' => 'Your browser blocked the pop-up. Allow pop-ups for this site and try again.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };

  @override
  Widget build(BuildContext context) {
    final provider = role == UserRole.provider;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Row(
                    children: [
                      BackArrow(onPressed: () => Navigator.of(context).pop(false)),
                      const Spacer(),
                      Text('HOOPLA', style: overline()),
                      const SizedBox(width: 12),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Segmented(
                    options: const ['Create account', 'Sign in'],
                    selected: creating ? 0 : 1,
                    height: 40,
                    onChanged: (i) => _setMode(i == 0),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    creating ? (provider ? 'List your business' : 'Create your account') : 'Welcome back',
                    style: display(30),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    creating
                        ? (widget.reason ?? 'It\'s free. Your plans stay safe on all your devices.')
                        : 'Sign in to see your events, invites and listing on this device.',
                    style: body(14, color: HC.muted),
                  ),
                  if (creating) ...[
                    const SizedBox(height: 22),
                    const SectionLabel('I am'),
                    Segmented(
                      options: const ['Planning an event', 'A service provider'],
                      selected: provider ? 1 : 0,
                      height: 42,
                      onChanged: (i) => setState(() => role = i == 0 ? UserRole.customer : UserRole.provider),
                    ),
                    if (provider) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Photographers, decorators, planners, cake makers, panthulu and more: get a free listing customers nearby can find.',
                        style: body(13, color: HC.muted),
                      ),
                    ],
                  ],
                  const SizedBox(height: 22),
                  if (_showApple)
                    _AuthButton(
                      label: 'Continue with Apple',
                      icon: const Icon(Icons.apple, color: Colors.white),
                      dark: true,
                      onTap: busy ? null : () => _run((a) => a.appleSignIn()),
                    ),
                  if (_showGoogle)
                    _AuthButton(
                      label: 'Continue with Google',
                      icon: Text('G', style: display(18, color: const Color(0xFF4285F4))),
                      onTap: busy ? null : () => _run((a) => a.googleSignIn()),
                    ),
                  if (_showApple || _showGoogle)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          const Expanded(child: Divider(color: HC.line)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('or with email', style: body(12, color: HC.muted)),
                          ),
                          const Expanded(child: Divider(color: HC.line)),
                        ],
                      ),
                    ),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: !showPass,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: _askForCode ? TextInputAction.next : TextInputAction.done,
                    autofillHints: [creating ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: creating ? 'Create a password (6+ characters)' : 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: showPass ? 'Hide password' : 'Show password',
                        onPressed: () => setState(() => showPass = !showPass),
                        icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ),
                    onSubmitted: (_) => _askForCode ? null : _email(),
                  ),
                  if (!creating)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: busy ? null : _forgot, child: const Text('Forgot password?')),
                    ),
                  if (_askForCode) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: refCtrl,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _email(),
                      decoration: const InputDecoration(
                        labelText: 'Friend\'s invite code (optional)',
                        helperText: 'If a friend invited you'
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(color: const Color(0xFFFEF3F2), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB42318)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(error!, style: body(13, color: const Color(0xFFB42318), weight: FontWeight.w500))),
                            ],
                          ),
                          if (fixLabel != null && fixAction != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: TextButton(onPressed: busy ? null : fixAction, child: Text(fixLabel!)),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: HC.violet,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: busy ? null : _email,
                      child: busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(creating ? 'Create account' : 'Sign in', style: display(17, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: busy ? null : () => _setMode(!creating),
                    child: Text(creating ? 'Already have an account? Sign in' : 'New to Hoopla? Create an account'),
                  ),
                  const SizedBox(height: 8),
                  Text('You can delete your account anytime from Account.', textAlign: TextAlign.center, style: body(12, color: HC.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, required this.icon, required this.onTap, this.dark = false});
  final String label;
  final Widget icon;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: dark ? Colors.black : HC.card,
            side: BorderSide(color: dark ? Colors.black : HC.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Text(label, style: body(15, weight: FontWeight.w600, color: dark ? Colors.white : HC.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
