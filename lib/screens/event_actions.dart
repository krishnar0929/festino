import 'package:flutter/material.dart';

import '../models/event_details.dart';
import '../state/app_state.dart';
import 'guest_notice.dart';
import 'my_events_screen.dart';
import 'setup_screen.dart';
import 'sign_in_screen.dart';

const _danger = Color(0xFFB42318);

/// "Start new event". Guests keep one event, so offer to replace it or sign in free.
Future<void> startNewEvent(BuildContext context) async {
  final state = AppScope.of(context);
  final nav = Navigator.of(context);
  if (state.canAddEvent) {
    await nav.push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
    return;
  }
  final current = state.event;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Plan more than one event?'),
      content: Text(
        'Sign in free to plan as many events as you like, or replace "${current?.title ?? 'your event'}". '
        'It moves to My events → Cancelled and you can bring it back later.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace it')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'upgrade'), child: const Text('Sign in free')),
      ],
    ),
  );
  if (choice == 'upgrade') {
    final ok = await nav.push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen(reason: 'It\'s free. Plan as many events as you like.')));
    if (ok == true && state.canAddEvent) await nav.push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
  } else if (choice == 'replace') {
    await nav.push(MaterialPageRoute<void>(builder: (_) => SetupScreen(replaceId: current?.id)));
  }
}

/// Asks first, then moves the event to Cancelled.
Future<void> confirmCancelEvent(BuildContext context, EventDetails e) async {
  final state = AppScope.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Cancel "${e.title}"?'),
      content: const Text('It moves to My events → Cancelled. You can restore it anytime.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Cancel event'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await state.cancelEvent(e.id);
  if (context.mounted) await offerGuestNotice(context, e, 'cancelled');
}

/// My events: upcoming, celebrated and cancelled events.
void showMyEvents(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyEventsScreen()));
}
