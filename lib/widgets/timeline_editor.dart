import 'package:flutter/material.dart';

import '../data/games.dart';
import '../models/event_details.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Tap a timeline step: see more, edit, swap the game, move it, or remove it.
Future<void> openStepSheet(BuildContext context, TimelineStep step) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HC.ground,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _StepSheet(step: step),
  );
}

class _StepSheet extends StatelessWidget {
  const _StepSheet({required this.step});
  final TimelineStep step;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = step;
    final g = s.game;
    final steps = state.plan.timeline;
    final index = steps.indexWhere((x) => x.key == s.key);
    final nav = Navigator.of(context);

    Future<void> edit(void Function(List<CustomStep>) change) async {
      nav.pop();
      await state.editTimeline(change);
    }

    int at(List<CustomStep> list) => list.indexWhere((c) => c.key == s.key);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${clockAmPm(s.start)} – ${clockAmPm(s.start + s.minutes)} · ${s.minutes} min', style: body(13, color: HC.muted, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(s.title, style: display(24)),
          const SizedBox(height: 6),
          Text(s.subtitle, style: body(14, color: HC.muted)),
          if (g != null) ...[
            const SizedBox(height: 14),
            CardBox(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to play', style: body(14, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(g.howTo, style: body(14)),
                  if (g.needs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('You\'ll need: ${g.needs.join(', ')}', style: body(13, color: HC.muted)),
                  ],
                  const SizedBox(height: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => openLink(context, g.videoSearch),
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('Watch how to play'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Group(children: [
            _Action(
              icon: Icons.edit_outlined,
              label: 'Edit',
              sub: 'Name, details or how long',
              onTap: () async {
                final result = await _editDialog(context, title: s.title, details: s.subtitle, minutes: s.minutes);
                if (result == null) return;
                await edit((list) {
                  final i = at(list);
                  if (i < 0) return;
                  list[i]
                    ..title = result.$1
                    ..subtitle = result.$2
                    ..minutes = result.$3;
                });
              },
            ),
            if (g != null)
              _Action(
                icon: Icons.swap_horiz_rounded,
                label: 'Swap for another game',
                sub: 'Games that suit this party',
                onTap: () async {
                  final pick = await pickGame(context, exclude: {for (final x in steps) if (x.game != null) x.game!.id});
                  if (pick == null) return;
                  await edit((list) {
                    final i = at(list);
                    if (i < 0) return;
                    list[i] = CustomStep(
                      key: 'game_${pick.id}',
                      title: pick.name,
                      subtitle: '${pick.audienceLabel} · ${pick.minutes} min${pick.needs.isEmpty ? '' : ' · ${pick.needs.first}'}',
                      minutes: pick.minutes,
                      kind: 'game',
                      gameId: pick.id,
                    );
                  });
                },
              ),
            if (index > 0)
              _Action(
                icon: Icons.arrow_upward_rounded,
                label: 'Move earlier',
                onTap: () => edit((list) {
                  final i = at(list);
                  if (i > 0) list.insert(i - 1, list.removeAt(i));
                }),
              ),
            if (index >= 0 && index < steps.length - 1)
              _Action(
                icon: Icons.arrow_downward_rounded,
                label: 'Move later',
                onTap: () => edit((list) {
                  final i = at(list);
                  if (i >= 0 && i < list.length - 1) list.insert(i + 1, list.removeAt(i));
                }),
              ),
            _Action(
              icon: Icons.delete_outline_rounded,
              label: 'Remove from timeline',
              danger: true,
              onTap: () => edit((list) => list.removeWhere((c) => c.key == s.key)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Edit a step: (title, details, minutes), or null when cancelled.
Future<(String, String, int)?> _editDialog(BuildContext context, {String title = '', String details = '', int minutes = 15, String heading = 'Edit step'}) {
  final t = TextEditingController(text: title);
  final d = TextEditingController(text: details);
  var mins = minutes;
  return showDialog<(String, String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(heading),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: t, autofocus: title.isEmpty, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What happens')),
              const SizedBox(height: 10),
              TextField(controller: d, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Details (optional)')),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text('How long', style: body(14, weight: FontWeight.w600))),
                  IconButton(onPressed: mins > 5 ? () => setD(() => mins -= 5) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                  Text('$mins min', style: body(15, weight: FontWeight.w700)),
                  IconButton(onPressed: mins < 240 ? () => setD(() => mins += 5) : null, icon: Icon(Icons.add_circle_outline_rounded, color: HC.violet)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.violet),
            onPressed: () {
              if (t.text.trim().isEmpty) return;
              Navigator.pop(ctx, (t.text.trim(), d.text.trim(), mins));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Pick a game that suits the current party (best fit first).
Future<Game?> pickGame(BuildContext context, {Set<String> exclude = const {}}) {
  final state = AppScope.of(context);
  final options = [for (final g in PlanGenerator.rankedGames(state.event!)) if (!exclude.contains(g.id)) g];
  return showModalBottomSheet<Game>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HC.ground,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Pick a game', style: display(22)),
          Text('Best fit for this party first.', style: body(13, color: HC.muted)),
          const SizedBox(height: 10),
          if (options.isEmpty) Text('Every game that fits is already in your plan.', style: body(14, color: HC.muted)),
          for (final g in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                onTap: () => Navigator.pop(ctx, g),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(g.name, style: body(15, weight: FontWeight.w700))),
                        Text('${g.minutes} min', style: body(12, color: HC.muted)),
                      ],
                    ),
                    Text('${g.audienceLabel}${g.needs.isEmpty ? '' : ' · ${g.needs.join(', ')}'}', style: body(12, color: HC.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Under the timeline: add an activity or a game, reset, and a note when it runs long or short.
class TimelineFooter extends StatelessWidget {
  const TimelineFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final plan = state.plan;
    final total = plan.timeline.fold<int>(0, (a, s) => a + s.minutes);
    final diff = total - e.hours * 60;
    final custom = e.customTimeline != null;

    Future<void> addActivity() async {
      final r = await _editDialog(context, heading: 'Add an activity', minutes: 15);
      if (r == null) return;
      await state.editTimeline((list) {
        var i = list.indexWhere((c) => c.kind == 'food' || c.kind == 'wrap');
        if (i < 0) i = list.length;
        list.insert(i, CustomStep(key: 'custom_${DateTime.now().millisecondsSinceEpoch}', title: r.$1, subtitle: r.$2, minutes: r.$3, kind: 'custom'));
      });
    }

    Future<void> addGame() async {
      final g = await pickGame(context, exclude: {for (final s in plan.timeline) if (s.game != null) s.game!.id});
      if (g == null) return;
      await state.editTimeline((list) {
        var i = list.indexWhere((c) => c.kind == 'food' || c.kind == 'wrap');
        if (i < 0) i = list.length;
        list.insert(
          i,
          CustomStep(
            key: 'game_${g.id}',
            title: g.name,
            subtitle: '${g.audienceLabel} · ${g.minutes} min${g.needs.isEmpty ? '' : ' · ${g.needs.first}'}',
            minutes: g.minutes,
            kind: 'game',
            gameId: g.id,
          ),
        );
      });
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tap any step to see more, edit, swap, move or remove it.', style: body(12, color: HC.muted)),
          if (custom && diff.abs() >= 10)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                diff > 0
                    ? '⏰ Your timeline runs ${diff} min past the ${e.hours}-hour party (ends ${clockAmPm(e.startMinutes + total)}).'
                    : '⏳ ${-diff} min free before the party ends. Add a game or let people mingle.',
                style: body(12, color: diff > 0 ? const Color(0xFFB42318) : HC.violet, weight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: addActivity,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add activity'),
              ),
              OutlinedButton.icon(
                onPressed: addGame,
                icon: const Icon(Icons.sports_esports_outlined, size: 18),
                label: const Text('Add a game'),
              ),
              if (custom)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset the timeline?'),
                        content: const Text('Your edits to the timeline go away and Hoopla builds it fresh. Your games stay.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my edits')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (ok == true) await state.resetTimeline();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset to suggested'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: HC.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60, color: HC.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.sub, this.danger = false});
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : HC.violet;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: body(15, weight: FontWeight.w600, color: danger ? color : HC.ink)),
      subtitle: sub == null ? null : Text(sub!, style: body(12, color: HC.muted)),
    );
  }
}
