import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/feedback_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Contact us: what it's about, a message and the person's email (to reply).
/// Saved to the `feedback` collection with their location and the time.
Future<void> showFeedbackSheet(BuildContext context, {int rating = 0, FeedbackType? type}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HC.ground,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _FeedbackSheet(rating: rating, type: type),
  );
}

/// "Rate Festino": 4–5 stars go to the App Store, 1–3 stars open the feedback form
/// so we can fix what's wrong.
Future<void> showRateSheet(BuildContext context) async {
  final stars = await showDialog<int>(context: context, builder: (_) => const _RateDialog());
  if (stars == null || stars == 0 || !context.mounted) return;
  if (stars >= 4) {
    await openStoreReview(context);
  } else {
    await showFeedbackSheet(context, rating: stars, type: FeedbackType.problem);
  }
}

/// Apple's review pop-up when it's allowed, otherwise the App Store page.
Future<void> openStoreReview(BuildContext context) async {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.android)) {
    await openLink(context, Uri.parse(appStoreUrl));
    return;
  }
  try {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing(appStoreId: appStoreId);
    }
  } catch (_) {
    if (context.mounted) await openLink(context, Uri.parse(appStoreUrl));
  }
}

/// Asks "Enjoying Festino?" once, right after a fun moment (a party game finishing).
class RatePrompt {
  static const _askedKey = 'hoopla.ratePrompted';
  static const _momentsKey = 'hoopla.happyMoments';

  /// How many fun moments before asking.
  static const momentsBeforeAsking = 2;

  static Future<void> afterHappyMoment(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) == true) return;
      final moments = (prefs.getInt(_momentsKey) ?? 0) + 1;
      await prefs.setInt(_momentsKey, moments);
      if (moments < momentsBeforeAsking) return;
      await prefs.setBool(_askedKey, true);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    final happy = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enjoying Festino? 🎉'),
        content: const Text('A quick rating helps other party planners find us.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not really')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.violet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Love it!'),
          ),
        ],
      ),
    );
    if (happy == null || !context.mounted) return;
    if (happy) {
      await openStoreReview(context);
    } else {
      await showFeedbackSheet(context, type: FeedbackType.problem);
    }
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged, this.size = 36});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i star${i == 1 ? '' : 's'}',
            iconSize: size,
            onPressed: () => onChanged(i),
            icon: Icon(
              i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i <= value ? const Color(0xFFF5B400) : HC.muted,
            ),
          ),
      ],
    );
  }
}

class _RateDialog extends StatefulWidget {
  const _RateDialog();

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int stars = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rate Festino', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('How are we doing?', style: body(14, color: HC.muted)),
          const SizedBox(height: 8),
          _Stars(value: stars, onChanged: (v) => setState(() => stars = v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HC.violet),
          onPressed: stars == 0 ? null : () => Navigator.pop(context, stars),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.rating, this.type});
  final int rating;
  final FeedbackType? type;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late FeedbackType type = widget.type ?? FeedbackType.question;
  late int rating = widget.rating;
  final messageCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  bool busy = false;
  String? error;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    emailCtrl.text = AppScope.of(context).email ?? '';
  }

  @override
  void dispose() {
    messageCtrl.dispose();
    emailCtrl.dispose();
    super.dispose();
  }

  String get _hint => switch (type) {
        FeedbackType.question => 'What would you like to know?',
        FeedbackType.problem => 'What went wrong? What were you trying to do?',
        FeedbackType.idea => 'What would make Festino better for your party?',
        FeedbackType.account => 'What\'s happening with your account or sign-in?',
        FeedbackType.helpers => 'Tell us about the helper or your listing',
        FeedbackType.deals => 'Which deal or payment is this about?',
        FeedbackType.praise => 'What did you love?',
        FeedbackType.other => 'Tell us anything',
      };

  static final _emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _send() async {
    final state = AppScope.of(context);
    final message = messageCtrl.text.trim();
    final email = emailCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => error = 'Write a few words first.');
      return;
    }
    if (!_emailOk.hasMatch(email)) {
      setState(() => error = 'Add your email so we can reply.');
      return;
    }
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!state.usingCloud) throw StateError('offline');
      final venue = state.event?.venue;
      await FeedbackService.send(
        type: type,
        rating: rating,
        message: message.length > 2000 ? message.substring(0, 2000) : message,
        email: email,
        plan: state.tier.name,
        location: venue?.label ?? '',
        country: venue?.countryCode ?? '',
      );
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Thanks! We got your message and will reply by email. 💜')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Couldn\'t send right now. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Contact us', style: display(22)),
              const SizedBox(height: 4),
              Text('A real person reads every message, usually within a day.', style: body(13, color: HC.muted)),
              const SizedBox(height: 16),
              DropdownButtonFormField<FeedbackType>(
                value: type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'What is it about?'),
                items: [for (final t in FeedbackType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (t) => setState(() => type = t ?? type),
              ),
              if (widget.rating > 0) ...[
                const SizedBox(height: 12),
                Text('Your rating', textAlign: TextAlign.center, style: body(13, color: HC.muted)),
                _Stars(value: rating, size: 32, onChanged: (v) => setState(() => rating = v == rating ? 0 : v)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: messageCtrl,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _hint),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Your email (so we can reply)'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: body(13, color: const Color(0xFFB42318), weight: FontWeight.w500)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: HC.violet,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: busy ? null : _send,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text('Send', style: display(17, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
