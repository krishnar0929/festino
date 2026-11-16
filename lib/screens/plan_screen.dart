import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/locked.dart';
import '../widgets/reminder_ui.dart';
import '../widgets/task_guide.dart';
import '../widgets/timeline_editor.dart';
import '../services/cost_estimate.dart';
import '../widgets/weather_brief.dart';
import 'cost_estimate_screen.dart';
import 'event_actions.dart';
import 'setup_screen.dart';
import 'plan_tabs.dart';
import 'weather_screen.dart';

/// The Plan tab: timeline, to-dos, budget and your own list, with weather and cost at a glance.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.onNavigate});

  /// Switch tab or open a page (see [HomeTab]).
  final ValueChanged<int> onNavigate;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final plan = state.plan;

    final open = plan.tasks.where((t) => !e.doneTasks.contains(t.id)).length;
    final cost = estimateCost(e);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Plan', style: display(28))),
            _RoundIcon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit event details',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(existing: e))),
            ),
            const SizedBox(width: 8),
            Material(
              color: HC.card,
              shape: const CircleBorder(side: BorderSide(color: HC.line)),
              child: PopupMenuButton<String>(
                tooltip: 'Event options',
                icon: const Icon(Icons.more_horiz_rounded, color: HC.ink, size: 20),
                onSelected: (v) {
                  switch (v) {
                    case 'new':
                      startNewEvent(context);
                    case 'events':
                      showMyEvents(context);
                    case 'cancel':
                      confirmCancelEvent(context, e);
                  }
                },
                itemBuilder: (_) => [
                  _menuItem('new', Icons.add_rounded, 'Start new event'),
                  _menuItem('events', Icons.event_note_outlined, 'My events · ${state.upcomingEvents.length} upcoming'),
                  _menuItem('cancel', Icons.event_busy_outlined, 'Cancel this event', danger: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Segmented(
          options: ['Timeline', open == 0 ? 'To-dos' : 'To-dos · $open', 'Budget', 'My list'],
          selected: tab,
          height: 40,
          onChanged: (i) => setState(() => tab = i),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: WeatherBriefBuilder(
                event: e,
                builder: (context, brief) => _Chip(
                  emoji: brief?.emoji ?? '🌤️',
                  label: brief == null
                      ? (e.venue == null ? 'Add venue for weather' : 'Weather')
                      : brief.worry && !e.indoor
                          ? '${brief.short} · Plan B'
                          : brief.short,
                  warn: brief?.worry ?? false,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeatherReportScreen())),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Chip(
                emoji: '💰',
                label: !e.costOn ? 'Cost estimate' : (cost.high <= 0 ? 'Cost estimate' : 'About ${cost.money(cost.mid)}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CostEstimateScreen())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${DateFormat('EEE, MMM d').format(e.date)} · ${clockAmPm(e.startMinutes)}–${clockAmPm(e.startMinutes + e.hours * 60)}'
          '${e.days > 1 ? ' · ${e.days} days' : ''} · ${e.indoor ? 'indoor' : 'outdoor'} · ${e.guests} guests'
          '${e.audienceNote.isNotEmpty ? ' · ${e.audienceNote}' : ''}',
          style: body(13, color: HC.muted),
        ),
        const SizedBox(height: 12),
        switch (tab) {
          0 => _Timeline(plan: plan, showOnly: state.limitedGuest ? 3 : null),
          1 => state.limitedGuest
              ? const LockedCard(
                  needs: Access.member,
                  title: 'Your checklist',
                  message: 'Sign in free to get a to-do list with due dates for invites, bookings and supplies.',
                )
              : _Checklist(onNavigate: widget.onNavigate),
          3 => const MyListTab(),
          _ => !state.limitedGuest
              ? const BudgetTab()
              : const LockedCard(
                  needs: Access.member,
                  title: 'Budget planner',
                  message: 'Sign in free to split your budget into food, decor, photos, cake and return gifts.',
                ),
        },
        // Everything is free; signing in just keeps the plan safe on every device.
        if (!state.isSignedIn && state.usingCloud)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CardBox(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: HC.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Sign in free to keep this plan on all your devices.', style: body(13)),
                  ),
                  TextButton(onPressed: () => openUnlock(context, Access.member), child: const Text('Sign in')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A small tappable chip under the tabs: weather or cost.
class _Chip extends StatelessWidget {
  const _Chip({required this.emoji, required this.label, required this.onTap, this.warn = false});
  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warn ? const Color(0xFFFFF4E5) : HC.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: warn ? const Color(0xFFF5D9A8) : HC.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {bool danger = false}) {
  final color = danger ? const Color(0xFFB42318) : HC.ink;
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: body(14, color: color)),
      ],
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: const CircleBorder(side: BorderSide(color: HC.line)),
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: HC.ink, size: 20)),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.plan, this.showOnly});
  final Plan plan;

  /// Guests see only the first few steps; the rest is blurred.
  final int? showOnly;

  static Color _dot(StepKind k) => switch (k) {
        StepKind.game => HC.coral,
        StepKind.moment || StepKind.welcome => HC.violet,
        _ => HC.ink,
      };

  @override
  Widget build(BuildContext context) {
    final steps = plan.timeline;
    final limit = showOnly;
    if (limit != null && steps.length > limit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in steps.take(limit)) _row(s, null),
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.6,
                  child: Column(children: [for (final s in steps.skip(limit).take(2)) _row(s, null)]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          LockedCard(
            needs: Access.member,
            title: '${steps.length - limit} more steps in your plan',
            message: 'Sign in free to see the full timeline, every game and your checklist.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in steps) _row(s, context),
        if (plan.backupGames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 80, top: 4),
            child: Text('Backup games if there\'s time: ${plan.backupGames.map((g) => g.name).join(', ')}', style: body(12, color: HC.muted)),
          ),
        const TimelineFooter(),
      ],
    );
  }

  Widget _row(TimelineStep s, BuildContext? context) {
    return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 48,
                  child: Padding(padding: const EdgeInsets.only(top: 12), child: Text(clock(s.start), style: body(12, color: HC.muted, weight: FontWeight.w600))),
                ),
                SizedBox(
                  width: 22,
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: _dot(s.kind), borderRadius: BorderRadius.circular(3))),
                      Expanded(child: Container(width: 2, color: HC.line)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CardBox(
                      radius: 14,
                      onTap: context == null ? null : () => openStepSheet(context, s),
                      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.title, style: body(14, weight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(s.subtitle, style: body(12, color: HC.muted)),
                              ],
                            ),
                          ),
                          if (context != null) const Icon(Icons.more_horiz_rounded, color: HC.muted, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final tasks = state.plan.tasks;
    final open = [for (final t in tasks) if (!e.doneTasks.contains(t.id)) t];
    final finished = [for (final t in tasks) if (e.doneTasks.contains(t.id)) t];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChecklistProgress(done: finished.length, total: tasks.length),
        const RemindersCard(),
        for (final t in open) TaskTile(task: t, switchTab: onNavigate),
        if (finished.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('DONE (${finished.length})', style: overline()),
          const SizedBox(height: 8),
          for (final t in finished) TaskTile(task: t, switchTab: onNavigate),
        ],
        const ChecklistFooter(),
      ],
    );
  }
}
