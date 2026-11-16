import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/helpers.dart';
import '../models/event_details.dart';
import '../screens/invite_screen.dart';
import '../screens/nearby_screen.dart';
import '../screens/plan_tabs.dart';
import '../screens/weather_screen.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'reminder_ui.dart';

/// Where a checklist task takes you, why it matters, and a few tips.
class TaskGuide {
  const TaskGuide({required this.emoji, required this.why, this.tips = const [], this.action, this.go, this.second, this.goSecond});
  final String emoji;
  final String why;
  final List<String> tips;

  /// Main button ("Send invites now"), or null when there's nowhere to go.
  final String? action;
  final void Function(BuildContext context)? go;
  final String? second;
  final void Function(BuildContext context)? goSecond;
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// The guide for one task. [switchTab] moves the bottom bar (2 = Games).
TaskGuide guideFor(PlanTask t, EventDetails e, {ValueChanged<int>? switchTab}) {
  if (t.id.startsWith('book_')) {
    final service = t.id.substring(5);
    final known = helperCategories.any((h) => h.label == service);
    return TaskGuide(
      emoji: _serviceEmoji[service] ?? '🤝',
      why: 'Good ${service.toLowerCase()} book up weeks ahead, especially on weekends.',
      tips: const [
        'Ask 2–3 for quotes and compare.',
        'Look for the 🎁 Hoopla deal badge for a discount.',
        'Confirm the date, hours and price in writing.',
      ],
      action: known ? 'Find $service nearby' : null,
      go: known ? (c) => _push(c, NearbyScreen(initialCategory: service, standalone: true)) : null,
    );
  }
  return switch (t.id) {
    'invites' => TaskGuide(
        emoji: '💌',
        why: 'About 4 weeks ahead gives guests time to plan and RSVP.',
        tips: const ['Send each person their own link so you see who replied.', 'Share the card picture to WhatsApp groups.', 'Add an invitation video for the wow factor 🎬'],
        action: 'Send invites now',
        go: (c) => _push(c, const InviteScreen(initialTab: 1)),
        second: 'Design the card',
        goSecond: (c) => _push(c, const InviteScreen(initialTab: 0)),
      ),
    'menu' => TaskGuide(
        emoji: '🍽️',
        why: 'Caterers need your head count and food preferences about 2 weeks ahead.',
        tips: ['Plan for ${e.guests} guests plus 10% extra.', 'Check guests\' food preferences (veg, vegan, no nuts…).', 'Kids menu? Keep it simple and mild.'],
        action: 'Find caterers',
        go: (c) => _push(c, const NearbyScreen(initialCategory: 'Caterers', standalone: true)),
        second: 'See guests\' food preferences',
        goSecond: (c) => _push(c, const InviteScreen(initialTab: 2)),
      ),
    'rsvp' => TaskGuide(
        emoji: '✅',
        why: 'Your final head count sets food, chairs and return gifts.',
        tips: const ['Remind anyone who hasn\'t replied.', 'Share the final number with your caterer.'],
        action: 'See who\'s coming',
        go: (c) => _push(c, const InviteScreen(initialTab: 2)),
      ),
    'gifts' => TaskGuide(
        emoji: '🎁',
        why: 'Return gifts are a sweet thank-you for little guests.',
        tips: ['Plan about ${(e.guests * 0.6).round()} for kids (adjust to your list).', 'Small, safe and mess-free works best.', 'Wrap them the night before.'],
        action: 'Get gift ideas',
        go: (c) => openLink(c, Uri.https('www.google.com', '/search', {'q': 'return gift ideas for kids birthday party'})),
      ),
    'supplies' => TaskGuide(
        emoji: '🧺',
        why: 'Your games need these. Grab them a few days before.',
        tips: const ['Buy a few spares.', 'Pack them in one box for the day.'],
        action: switchTab == null ? null : 'See your games',
        go: switchTab == null
            ? null
            : (c) => switchTab(2),
      ),
    'weather' => TaskGuide(
        emoji: '🌤️',
        why: 'Outdoor parties need a backup if it rains or gets hot.',
        tips: const ['The forecast arrives 16 days before.', 'Plan shade, water and a rain backup.'],
        action: 'See the weather',
        go: (c) => _push(c, const WeatherReportScreen()),
      ),
    'weather_tent' => TaskGuide(
        emoji: '⛺',
        why: 'A tent keeps the party on if it rains.',
        tips: const ['Book 1–2 weeks ahead.', 'Ask about sidewalls and setup time.'],
        action: 'Find tent rentals',
        go: (c) => _push(c, const NearbyScreen(initialCategory: 'Rentals', standalone: true)),
      ),
    _ => const TaskGuide(emoji: '📝', why: 'Your own to-do. Tap "Edit" to change it or its date.'),
  };
}

const _serviceEmoji = {
  'Photographers': '📸',
  'Videographers': '🎥',
  'Decorators': '🎈',
  'Stage decor': '🎭',
  'Event planners': '📋',
  'Designers': '🎨',
  'Cake makers': '🎂',
  'Panthulu': '🙏',
  'Makeup': '💄',
  'Cleaners & maids': '🧹',
  'Helpers': '🙌',
  'Transport': '🚐',
  'Anchors / MC': '🎤',
  'DJs': '🎧',
  'Singers': '🎙️',
  'Dancers': '💃',
  'Caterers': '🍛',
  'Rentals': '🪑',
};

/// Ticks a task on or off.
Future<void> toggleTask(AppState state, String id) => state.update((ev) {
      if (ev.doneTasks.contains(id)) {
        ev.doneTasks.remove(id);
      } else {
        ev.doneTasks.add(id);
      }
    });

/// Due date and how urgent it is.
(DateTime, Color, Color, String) dueInfo(PlanTask t, EventDetails e, bool done) {
  final due = DateUtils.dateOnly(e.date.subtract(Duration(days: t.daysBefore)));
  final today = DateUtils.dateOnly(DateTime.now());
  final days = due.difference(today).inDays;
  final label = DateFormat('MMM d').format(due);
  if (done) return (due, const Color(0xFFE6F6EC), const Color(0xFF1F8A4C), 'Done');
  if (days < 0) return (due, const Color(0xFFFFE4DE), const Color(0xFFC0392B), 'Overdue · $label');
  if (days == 0) return (due, const Color(0xFFFFF1C2), const Color(0xFF8A5A00), 'Today');
  if (days <= 7) return (due, const Color(0xFFFFF1C2), const Color(0xFF8A5A00), 'Due $label');
  return (due, HC.track, HC.muted, 'By $label');
}

/// The task's detail sheet: why, tips, "do it now", reminder, edit, mark done.
Future<void> openTaskDetail(BuildContext context, PlanTask t, {ValueChanged<int>? switchTab}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HC.ground,
    builder: (ctx) => _TaskSheet(task: t, switchTab: switchTab, parent: context),
  );
}

class _TaskSheet extends StatelessWidget {
  const _TaskSheet({required this.task, required this.parent, this.switchTab});
  final PlanTask task;

  /// The page under the sheet: actions run there once the sheet closes.
  final BuildContext parent;
  final ValueChanged<int>? switchTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final t = state.plan.tasks.firstWhere((x) => x.id == task.id, orElse: () => task);
    final done = e.doneTasks.contains(t.id);
    final g = guideFor(t, e, switchTab: switchTab);
    final (_, bg, fg, dueLabel) = dueInfo(t, e, done);


    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: HC.track, borderRadius: BorderRadius.circular(16)),
                child: Text(g.emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: display(22)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                      child: Text(dueLabel, style: body(12, color: fg, weight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(g.why, style: body(15)),
          if (g.tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final tip in g.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡 ', style: TextStyle(fontSize: 14)),
                    Expanded(child: Text(tip, style: body(14, color: HC.muted))),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (g.action != null && g.go != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 52)),
              onPressed: () {
                Navigator.of(context).pop();
                g.go!(parent);
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              label: Text(g.action!),
            ),
          if (g.second != null && g.goSecond != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: const BorderSide(color: HC.line)),
              onPressed: () {
                Navigator.of(context).pop();
                g.goSecond!(parent);
              },
              child: Text(g.second!, style: body(14, weight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: BorderSide(color: done ? HC.line : const Color(0xFF1F8A4C)),
              backgroundColor: done ? null : const Color(0xFFE6F6EC),
            ),
            onPressed: () {
              toggleTask(state, t.id);
              Navigator.of(context).pop();
              if (!done) toast(parent, 'Nice! "${t.label}" is done ✅');
            },
            icon: Icon(done ? Icons.undo_rounded : Icons.check_circle_rounded, color: done ? HC.muted : const Color(0xFF1F8A4C)),
            label: Text(done ? 'Mark not done' : 'Mark done', style: body(14, weight: FontWeight.w700, color: done ? HC.muted : const Color(0xFF1F8A4C))),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!done) ...[TaskReminderButton(task: t, event: e), Text('Reminder', style: body(13, color: HC.muted))],
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  editTask(parent, t);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  removeTask(parent, t);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One checklist row: round check, icon, task, due chip, and a chevron to open it.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.switchTab});
  final PlanTask task;
  final ValueChanged<int>? switchTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final t = task;
    final done = e.doneTasks.contains(t.id);
    final g = guideFor(t, e, switchTab: switchTab);
    final (_, bg, fg, dueLabel) = dueInfo(t, e, done);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done ? HC.ground : HC.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openTaskDetail(context, t, switchTab: switchTab),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
            child: Row(
              children: [
                Semantics(
                  checked: done,
                  label: done ? 'Mark ${t.label} not done' : 'Mark ${t.label} done',
                  child: InkResponse(
                    radius: 24,
                    onTap: () => toggleTask(state, t.id),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? const Color(0xFF1F8A4C) : Colors.transparent,
                          border: Border.all(color: done ? const Color(0xFF1F8A4C) : HC.muted, width: 2),
                        ),
                        child: done ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: done ? HC.track : const Color(0xFFF1EEFF), borderRadius: BorderRadius.circular(12)),
                  child: Text(g.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: body(15, weight: FontWeight.w600, color: done ? HC.muted : HC.ink)
                            .copyWith(decoration: done ? TextDecoration.lineThrough : null),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                            child: Text(dueLabel, style: body(11, color: fg, weight: FontWeight.w700)),
                          ),
                          if (!done && e.taskReminders.containsKey(t.id)) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.notifications_active_rounded, size: 14, color: HC.violet),
                          ],
                          if (!done && g.action != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(g.action!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11, color: HC.violet, weight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: HC.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "4 of 12 done" with a progress bar and a cheer.
class ChecklistProgress extends StatelessWidget {
  const ChecklistProgress({super.key, required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    final cheer = switch (pct) {
      >= 1 => 'All done! You\'re ready to party 🎉',
      >= 0.66 => 'Almost there! 💪',
      >= 0.33 => 'Great progress 👏',
      > 0 => 'Nice start ✨',
      _ => 'Tap a task to see where to do it',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$done of $total done', style: display(18)),
              const Spacer(),
              Text(cheer, style: body(12, color: HC.muted, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: HC.track,
              valueColor: AlwaysStoppedAnimation(HC.violet),
            ),
          ),
        ],
      ),
    );
  }
}
