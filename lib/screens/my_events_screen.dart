import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_actions.dart';
import 'guest_notice.dart';

const _danger = Color(0xFFB42318);

String occasionEmoji(String occasion) => switch (occasion) {
      'Birthday' => '🎂',
      'Housewarming' => '🏡',
      'Baby shower' => '🍼',
      'Pooja' => '🪔',
      'Anniversary' => '💍',
      _ => '🎉',
    };

/// My events: what's coming up, what's been celebrated, and what was cancelled.
class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  int tab = 0;

  void _open(AppState state, EventDetails e) {
    state.switchTo(e.id);
    Navigator.of(context).pop();
  }

  Future<void> _deleteForever(AppState state, EventDetails e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${e.title}"?'),
        content: const Text('This removes the event, its plan and lists for good. It can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: _danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await state.deleteEvent(e.id);
  }

  Future<void> _restore(AppState state, EventDetails e) async {
    if (!state.canAddEvent) {
      toast(context, 'Guests keep one event. Sign in free (Account) or cancel the current one to restore this.');
      return;
    }
    await state.restoreEvent(e.id);
    if (!mounted) return;
    toast(context, '"${e.title}" is back in Upcoming.');
    await offerGuestNotice(context, e, 'back');
  }

  Future<void> _planAgain(AppState state, EventDetails e) async {
    if (!state.canAddEvent) {
      toast(context, 'Sign in free (Account) to plan more than one event.');
      return;
    }
    final copy = await state.planAgain(e);
    if (!mounted) return;
    toast(context, 'New plan for ${DateFormat('MMM d, y').format(copy.date)}. Change the date with ✏️.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final upcoming = state.upcomingEvents;
    final past = state.pastEvents;
    final cancelled = state.cancelledEvents;
    final next = upcoming.isEmpty ? null : upcoming.first;
    final lists = [upcoming, past, cancelled];
    final list = lists[tab];

    return Scaffold(
      appBar: AppBar(title: const Text('My events')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: HC.violet,
        foregroundColor: Colors.white,
        onPressed: () => startNewEvent(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New event'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              // ---- counts
              Row(
                children: [
                  Expanded(child: _Count(value: upcoming.length, label: 'Upcoming', color: HC.lime, selected: tab == 0, onTap: () => setState(() => tab = 0))),
                  const SizedBox(width: 8),
                  Expanded(child: _Count(value: past.length, label: 'Celebrated', color: const Color(0xFFDDEBFF), selected: tab == 1, onTap: () => setState(() => tab = 1))),
                  const SizedBox(width: 8),
                  Expanded(child: _Count(value: cancelled.length, label: 'Cancelled', color: const Color(0xFFFFE3E0), selected: tab == 2, onTap: () => setState(() => tab = 2))),
                ],
              ),

              // ---- next up
              if (next != null && tab == 0) ...[
                const SizedBox(height: 16),
                _NextUp(event: next, onOpen: () => _open(state, next)),
              ],

              const SizedBox(height: 18),
              Text(
                ['Coming up', 'Celebrated', 'Cancelled'][tab],
                style: display(20),
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      Text(['🎈', '📸', '🗂️'][tab], style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 6),
                      Text(
                        [
                          'Nothing planned yet. Tap New event to start.',
                          'Parties you\'ve thrown show up here after the day.',
                          'No cancelled events.',
                        ][tab],
                        textAlign: TextAlign.center,
                        style: body(14, color: HC.muted),
                      ),
                    ],
                  ),
                ),
              for (final e in list)
                _EventCard(
                  event: e,
                  current: e.id == state.event?.id && tab != 2,
                  kind: tab,
                  onOpen: tab == 2 ? null : () => _open(state, e),
                  onCancel: tab == 0 ? () => confirmCancelEvent(context, e) : null,
                  onRestore: tab == 2 ? () => _restore(state, e) : null,
                  onPlanAgain: tab == 1 ? () => _planAgain(state, e) : null,
                  onDelete: tab == 0 ? null : () => _deleteForever(state, e),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.color, required this.selected, required this.onTap});
  final int value;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : HC.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? HC.ink : HC.line, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: display(28)),
              Text(label, style: body(12, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.event, required this.onOpen});
  final EventDetails event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final days = DateUtils.dateOnly(e.date).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final tasks = PlanGenerator.build(e).tasks;
    final done = tasks.where((t) => e.doneTasks.contains(t.id)).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [HC.ink, Color(0xFF3B2C8F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('NEXT UP', style: overline(color: HC.lime)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: HC.lime, borderRadius: BorderRadius.circular(20)),
                child: Text(days == 0 ? 'Today! 🎉' : (days == 1 ? 'Tomorrow' : '$days days to go'), style: body(12, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${occasionEmoji(e.occasion)} ${e.title}', style: display(24, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('EEE, MMM d').format(e.date)} · ${clockAmPm(e.startMinutes)} · ${e.guests} guests'
            '${e.venue == null ? '' : ' · ${e.venue!.label}'}',
            style: body(13, color: HC.nightMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: tasks.isEmpty ? 0 : done / tasks.length,
                    minHeight: 8,
                    backgroundColor: const Color(0x33FFFFFF),
                    color: HC.lime,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$done of ${tasks.length} done', style: body(12, color: Colors.white, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.lime, foregroundColor: HC.ink),
            onPressed: onOpen,
            child: const Text('Open plan'),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.current,
    required this.kind,
    this.onOpen,
    this.onCancel,
    this.onRestore,
    this.onPlanAgain,
    this.onDelete,
  });

  final EventDetails event;
  final bool current;

  /// 0 upcoming, 1 celebrated, 2 cancelled.
  final int kind;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;
  final VoidCallback? onRestore;
  final VoidCallback? onPlanAgain;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final days = DateUtils.dateOnly(e.date).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final when = switch (kind) {
      0 => days == 0 ? 'Today' : (days == 1 ? 'Tomorrow' : 'In $days days'),
      1 => 'Celebrated ${DateFormat('MMM d, y').format(e.date)}',
      _ => 'Was ${DateFormat('MMM d, y').format(e.date)}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: HC.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: current ? HC.violet : HC.line, width: current ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kind == 2 ? HC.track : HC.ground, borderRadius: BorderRadius.circular(14)),
                  child: Text(occasionEmoji(e.occasion), style: TextStyle(fontSize: 24, color: kind == 2 ? HC.muted : null)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: body(15, weight: FontWeight.w700, color: kind == 2 ? HC.muted : HC.ink),
                            ),
                          ),
                          if (current) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: HC.violet, borderRadius: BorderRadius.circular(6)),
                              child: Text('OPEN', style: body(10, color: Colors.white, weight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      Text('${e.occasion} · ${DateFormat('EEE, MMM d').format(e.date)} · ${e.guests} guests',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12, color: HC.muted)),
                      Text(when, style: body(12, weight: FontWeight.w600, color: kind == 0 ? HC.violet : HC.muted)),
                    ],
                  ),
                ),
                if (onRestore != null) TextButton(onPressed: onRestore, child: const Text('Restore')),
                if (onPlanAgain != null) TextButton(onPressed: onPlanAgain, child: const Text('Plan again')),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: HC.muted, size: 20),
                  onSelected: (v) => switch (v) {
                    'open' => onOpen?.call(),
                    'cancel' => onCancel?.call(),
                    'again' => onPlanAgain?.call(),
                    'restore' => onRestore?.call(),
                    _ => onDelete?.call(),
                  },
                  itemBuilder: (_) => [
                    if (onOpen != null) const PopupMenuItem(value: 'open', child: Text('Open plan')),
                    if (onPlanAgain != null) const PopupMenuItem(value: 'again', child: Text('Plan it again')),
                    if (onRestore != null) const PopupMenuItem(value: 'restore', child: Text('Restore')),
                    if (onCancel != null) const PopupMenuItem(value: 'cancel', child: Text('Cancel event')),
                    if (onDelete != null) PopupMenuItem(value: 'delete', child: Text('Delete for good', style: body(14, color: _danger))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
