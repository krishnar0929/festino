import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/cost_estimate.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/task_guide.dart';
import '../widgets/weather_brief.dart';
import 'account_sheet.dart';
import 'cost_estimate_screen.dart';
import 'home_shell.dart';
import 'setup_screen.dart';
import 'weather_screen.dart';

/// One step on the way to the party, shown as a dot on the Home card.
class JourneyStep {
  const JourneyStep(this.label, this.done);
  final String label;
  final bool done;
}

/// The five big steps: details, invites, helpers, to-dos, party day.
List<JourneyStep> journeyFor(EventDetails e, Plan plan) {
  bool isDone(PlanTask t) => e.doneTasks.contains(t.id);
  final helpersLeft = plan.tasks.where((t) => t.id.startsWith('book_') && !isDone(t)).isNotEmpty;
  return [
    JourneyStep('Details', e.venue != null),
    JourneyStep('Invites', e.invitees.isNotEmpty || e.doneTasks.contains('invites')),
    JourneyStep('Helpers', !helpersLeft),
    JourneyStep('To-dos', plan.tasks.every(isDone)),
    JourneyStep('Party day', e.daysToGo < 0),
  ];
}

/// The first open to-do, earliest due first. Null when everything is done.
PlanTask? nextTask(EventDetails e, Plan plan) {
  final open = [for (final t in plan.tasks) if (!e.doneTasks.contains(t.id)) t];
  if (open.isEmpty) return null;
  open.sort((a, b) => b.daysBefore.compareTo(a.daysBefore));
  return open.first;
}

/// Home: what's my party, what do I do next, and what's ready. Everything else is one tap away.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});

  /// Switch tab or open a page (see [HomeTab]).
  final ValueChanged<int> onNavigate;

  static String _firstName(AppState s) {
    final n = (s.profile?['name'] as String?)?.trim() ?? s.accounts?.user?.displayName?.trim() ?? '';
    if (n.isEmpty || n.contains('@')) return '';
    return n.split(' ').first;
  }

  static String _hello() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final plan = state.plan;
    final name = _firstName(state);
    final steps = journeyFor(e, plan);
    final next = nextTask(e, plan);
    final helpersLeft = plan.tasks.where((t) => t.id.startsWith('book_') && !e.doneTasks.contains(t.id)).length;
    final cost = estimateCost(e);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? '${_hello()}!' : '${_hello()}, $name', style: body(14, color: HC.muted)),
                  const SizedBox(height: 2),
                  Text('Your party', style: display(22)),
                ],
              ),
            ),
            Material(
              color: const Color(0xFFEEEAFE),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Account',
                onPressed: () => showAccountSheet(context),
                icon: Icon(state.isSignedIn ? Icons.person_rounded : Icons.person_outline_rounded, color: HC.violet),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PartyCard(event: e, steps: steps, onTap: () => _push(context, SetupScreen(existing: e))),
        const SizedBox(height: 18),
        Text('NEXT UP', style: overline()),
        const SizedBox(height: 8),
        if (next == null)
          _AllDone(onParty: () => onNavigate(HomeTab.party))
        else
          _NextUp(task: next, onNavigate: onNavigate),
        WeatherBriefBuilder(
          event: e,
          builder: (context, brief) {
            if (brief == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _WeatherRow(brief: brief, indoor: e.indoor, onTap: () => _push(context, const WeatherReportScreen())),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Tile(
                icon: Icons.group_rounded,
                color: HC.violet,
                title: 'Guests',
                detail: e.invitees.isEmpty ? 'Not sent yet' : '${e.invitees.length} invited',
                onTap: () => onNavigate(HomeTab.guests),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                icon: Icons.card_giftcard_rounded,
                color: const Color(0xFF13895C),
                title: 'Helpers',
                detail: helpersLeft == 0 ? 'All booked' : '$helpersLeft needed',
                onTap: () => onNavigate(HomeTab.find),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                icon: Icons.payments_outlined,
                color: const Color(0xFFB26A00),
                title: 'Cost',
                detail: cost.high <= 0 ? 'Estimate' : '~${cost.money(cost.mid)}',
                onTap: () => _push(context, const CostEstimateScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SmallLink(icon: Icons.sports_esports_outlined, label: 'Games', onTap: () => onNavigate(HomeTab.games))),
            const SizedBox(width: 10),
            Expanded(child: _SmallLink(icon: Icons.celebration_outlined, label: 'Party day mode', onTap: () => onNavigate(HomeTab.party))),
          ],
        ),
      ],
    );
  }
}

/// The big colored card: name, date and place, days to go, and the 5-dot journey.
class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.event, required this.steps, required this.onTap});
  final EventDetails event;
  final List<JourneyStep> steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final days = e.daysToGo;
    final current = steps.indexWhere((s) => !s.done);
    final at = current < 0 ? steps.length - 1 : current;
    final place = e.venue?.label ?? '';
    return Material(
      color: HC.violet,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(26, color: Colors.white)),
                        const SizedBox(height: 8),
                        Text(
                          [DateFormat('EEE, MMM d').format(e.date), clockAmPm(e.startMinutes), if (place.isNotEmpty) place].join(' · '),
                          style: body(14, color: const Color(0xFFE4DDFF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                    child: days > 1
                        ? Column(
                            children: [
                              Text('$days', style: display(24, color: Colors.white)),
                              Text('days', style: body(11, color: Colors.white, weight: FontWeight.w600)),
                            ],
                          )
                        : Text(days == 1 ? 'Tomorrow!' : (days == 0 ? 'Today!' : 'Done 🎉'), style: body(14, color: Colors.white, weight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Semantics(
                      label: '${steps[i].label}: ${steps[i].done ? 'done' : (i == at ? 'now' : 'to do')}',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == at && current >= 0 ? 28 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: steps[i].done || i == at ? Colors.white : Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    current < 0 ? 'All steps done' : 'Step ${at + 1} of ${steps.length} · ${steps[at].label}',
                    style: body(13, color: Colors.white, weight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one thing to do next, with one button.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.task, required this.onNavigate});
  final PlanTask task;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final g = guideFor(task, e, switchTab: onNavigate);
    final (_, _, fg, dueLabel) = dueInfo(task, e, false);
    final go = g.go;
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openTaskDetail(context, task, switchTab: onNavigate),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFEEEAFE), borderRadius: BorderRadius.circular(14)),
                    child: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(16, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(dueLabel, style: body(13, color: fg, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mark done',
                    onPressed: () => toggleTask(state, task.id),
                    icon: const Icon(Icons.check_circle_outline_rounded, color: HC.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: HC.ink,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  if (go != null) {
                    go(context);
                  } else {
                    openTaskDetail(context, task, switchTab: onNavigate);
                  }
                },
                child: Text(g.action ?? 'Open', style: body(15, color: Colors.white, weight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone({required this.onParty});
  final VoidCallback onParty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: HC.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HC.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You\'re all set! 🎉', style: body(16, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Every to-do is done. On the day, party day mode runs the games and keeps time.', style: body(13, color: HC.muted)),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.ink, minimumSize: const Size(0, 50)),
            onPressed: onParty,
            child: const Text('Open party day mode'),
          ),
        ],
      ),
    );
  }
}

/// Weather in one line: amber when there's something to plan for, green when it looks nice.
class _WeatherRow extends StatelessWidget {
  const _WeatherRow({required this.brief, required this.indoor, required this.onTap});
  final WeatherBrief brief;
  final bool indoor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final worry = brief.worry;
    final bg = worry ? const Color(0xFFFFF4E5) : const Color(0xFFE9F8EF);
    final border = worry ? const Color(0xFFF5D9A8) : const Color(0xFFBFE6CD);
    final fg = worry ? const Color(0xFF8A5A00) : const Color(0xFF1F6E43);
    final sub = worry
        ? (indoor ? 'Tap for the forecast' : 'Outdoor party · see Plan B')
        : (brief.forecast ? 'Great party weather' : 'Forecast comes closer to the day');
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Text(brief.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(brief.verdict.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(15, weight: FontWeight.w600)),
                    Text(sub, style: body(13, color: fg)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.title, required this.detail, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(title, style: body(14, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12, color: HC.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallLink extends StatelessWidget {
  const _SmallLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        side: const BorderSide(color: HC.line),
        backgroundColor: HC.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: HC.violet),
      label: Text(label, style: body(13, weight: FontWeight.w600)),
    );
  }
}
