import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/games.dart';
import '../models/event_details.dart';
import '../services/plan_generator.dart';
import '../services/weather_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/place_picker.dart';
import 'nearby_screen.dart';
import 'setup_screen.dart';

/// Plan B for bad weather: move indoors (games swapped for you), stay out under
/// a tent, move to a drier day from the forecast, or find a covered venue.
class RainPlanScreen extends StatefulWidget {
  const RainPlanScreen({super.key});

  @override
  State<RainPlanScreen> createState() => _RainPlanScreenState();
}

class _RainPlanScreenState extends State<RainPlanScreen> {
  Future<List<DayOutlook>>? outlook;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = AppScope.of(context).event?.venue;
    if (outlook == null && v != null) outlook = WeatherService.outlook(v).catchError((_) => <DayOutlook>[]);
  }

  Future<void> _moveIndoors() async {
    final state = AppScope.of(context);
    final swaps = PlanGenerator.indoorSwaps(state.event!);
    await state.update(PlanGenerator.moveIndoors);
    if (!mounted) return;
    toast(context, swaps.isEmpty ? 'Moved indoors. Your games already work inside.' : 'Moved indoors and swapped ${swaps.length} outdoor game${swaps.length == 1 ? '' : 's'}.');
    Navigator.of(context).pop();
  }

  Future<void> _addTent() async {
    await AppScope.of(context).update((e) {
      if (!e.customTasks.any((t) => t.id == 'weather_tent')) {
        e.customTasks.add(CustomTask(id: 'weather_tent', label: 'Book a tent or canopy (rain backup)', daysBefore: 10));
      }
      final items = PlanGenerator.budgetItems(e);
      if (!items.any((b) => b.id == 'weather_tent')) items.add(BudgetItem(id: 'weather_tent', label: 'Tent / canopy rental', planned: 150));
      e.budgetItems = items;
    });
    if (mounted) toast(context, 'Added "Book a tent" to your checklist and a tent line to your budget.');
  }

  Future<void> _moveTo(DayOutlook d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move to ${DateFormat('EEEE, MMM d').format(d.date)}?'),
        content: Text('${weatherEmoji(d.code)} ${weatherText(d.code)}, ${d.rainChance}% chance of rain. Same time and place. '
            'Remember to tell your guests about the new date.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, true), child: const Text('Move party')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).update((e) => e.date = DateTime(d.date.year, d.date.month, d.date.day));
    if (!mounted) return;
    toast(context, 'Party moved to ${DateFormat('EEE, MMM d').format(d.date)}. Send your guests an update from Invitation.');
    Navigator.of(context).pop();
  }

  Future<void> _changeVenue() async {
    final state = AppScope.of(context);
    final p = await pickPlace(context);
    if (p != null) await state.update((e) => e.venue = p);
  }

  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).event;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: Center(child: BackArrow())),
        leadingWidth: 60,
        title: const Text('Plan B'),
      ),
      body: e == null
          ? const SizedBox.shrink()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Text('Keep the party on, rain or shine ☂️', style: display(24)),
                    const SizedBox(height: 4),
                    Text('Pick the backup that suits you. You can mix them, like a tent plus indoor games.', style: body(14, color: HC.muted)),
                    const SizedBox(height: 18),
                    _indoors(e),
                    _tent(e),
                    _drierDay(e),
                    _venue(e),
                    const SizedBox(height: 6),
                    Text('Changed the date or place? Let guests know from Invitation & guests on the Plan page.', style: body(12, color: HC.muted)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _indoors(EventDetails e) {
    final swaps = e.indoor ? const <(Game, Game?)>[] : PlanGenerator.indoorSwaps(e);
    return _Option(
      emoji: '🏠',
      title: 'Move it indoors',
      subtitle: e.indoor ? 'Your party is already indoors. 👍' : 'Same day, same time, under a roof. We swap outdoor-only games for indoor ones.',
      children: [
        if (!e.indoor && swaps.isNotEmpty) ...[
          for (final (old, neu) in swaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(neu == null ? '• ${old.name} → removed' : '• ${old.name} → ${neu.name}', style: body(13)),
            ),
          const SizedBox(height: 6),
        ],
        if (!e.indoor) _Primary(label: 'Move indoors', icon: Icons.home_rounded, onTap: _moveIndoors),
      ],
    );
  }

  Widget _tent(EventDetails e) {
    final added = e.customTasks.any((t) => t.id == 'weather_tent');
    return _Option(
      emoji: '⛺',
      title: 'Stay outside under a tent',
      subtitle: 'A pop-up canopy or rented tent keeps guests dry. Rentals usually run \$150–400 with setup.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Secondary(
              label: 'Find tent rentals nearby',
              icon: Icons.search_rounded,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const NearbyScreen(initialCategory: 'Rentals', standalone: true),
              )),
            ),
            if (!added) _Secondary(label: 'Add tent to my plan', icon: Icons.add_rounded, onTap: _addTent),
          ],
        ),
        if (added) ...[
          const SizedBox(height: 8),
          Text('✅ Tent is on your checklist and budget.', style: body(12, color: const Color(0xFF1F8A4C), weight: FontWeight.w600)),
        ],
      ],
    );
  }

  Widget _drierDay(EventDetails e) {
    return _Option(
      emoji: '📅',
      title: 'Move to a drier day',
      subtitle: 'Dry days near your date from the 16-day forecast.',
      children: [
        if (e.venue == null)
          Text('Add your venue to see the forecast.', style: body(13, color: HC.muted))
        else
          FutureBuilder<List<DayOutlook>>(
            future: outlook,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
              }
              final days = drierDays(snap.data ?? const [], e.date);
              if (days.isEmpty) {
                return Text('No clearly dry days in the forecast yet. Pick another date yourself, or try a tent or indoors.', style: body(13, color: HC.muted));
              }
              return Column(
                children: [
                  for (final d in days)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: HC.ground,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: HC.line)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _moveTo(d),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: Row(
                              children: [
                                Text(weatherEmoji(d.code), style: const TextStyle(fontSize: 26)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(DateFormat('EEEE, MMM d').format(d.date), style: body(14, weight: FontWeight.w700)),
                                      Text('${weatherText(d.code)} · ${d.high.round()}° / ${d.low.round()}° · ${d.rainChance}% rain', style: body(12, color: HC.muted)),
                                    ],
                                  ),
                                ),
                                Text('Pick', style: body(13, color: HC.violet, weight: FontWeight.w700)),
                                const Icon(Icons.chevron_right_rounded, color: HC.violet),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        _Secondary(
          label: 'Pick another date',
          icon: Icons.event_rounded,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SetupScreen(existing: e))),
        ),
      ],
    );
  }

  Widget _venue(EventDetails e) {
    final near = e.venue?.label ?? 'me';
    return _Option(
      emoji: '🏛️',
      title: 'Find a covered venue',
      subtitle: 'Community halls, restaurant party rooms, clubhouses, or a friend\'s garage or porch.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Secondary(
              label: 'Party halls near $near',
              icon: Icons.map_rounded,
              onTap: () => openLink(context, Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': 'party hall near $near'})),
            ),
            _Secondary(label: 'Change venue', icon: Icons.place_rounded, onTap: _changeVenue),
          ],
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.emoji, required this.title, required this.subtitle, required this.children});
  final String emoji;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CardBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: display(18)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: body(13, color: HC.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[const SizedBox(height: 12), ...children],
          ],
        ),
      ),
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 46)),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: HC.line), minimumSize: const Size(0, 42)),
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: HC.violet),
        label: Text(label, style: body(13, weight: FontWeight.w600)),
      );
}
