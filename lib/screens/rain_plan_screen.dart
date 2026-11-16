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
import 'guest_notice.dart';
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

  /// 0 indoors, 1 tent, 2 drier day, 3 covered venue.
  int? picked;

  /// The dry day picked from the forecast (option 2).
  DayOutlook? day;

  /// Send guests a note about the change (date, place or moving indoors).
  bool tellGuests = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final e = AppScope.of(context).event;
    final v = e?.venue;
    if (outlook == null && v != null) outlook = WeatherService.outlook(v).catchError((_) => <DayOutlook>[]);
    // The easiest backup is picked to start with.
    picked ??= (e?.indoor ?? false) ? 1 : 0;
  }

  /// After a change guests should hear about: offer the note (if the switch is on).
  Future<void> _notify(NavigatorState nav, AppState state) async {
    final ev = state.event;
    if (tellGuests && ev != null) await offerGuestNotice(nav.context, ev, 'updated');
  }

  Future<void> _moveIndoors() async {
    final state = AppScope.of(context);
    final swaps = PlanGenerator.indoorSwaps(state.event!);
    await state.update(PlanGenerator.moveIndoors);
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    toast(context, swaps.isEmpty ? 'Moved indoors. Your games already work inside.' : 'Moved indoors and swapped ${swaps.length} outdoor game${swaps.length == 1 ? '' : 's'}.');
    Navigator.of(context).pop();
    await _notify(nav, state);
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
        content: Text('${weatherEmoji(d.code)} ${weatherText(d.code)}, ${d.rainChance}% chance of rain. Same time and place.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, true), child: const Text('Move party')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).update((e) => e.date = DateTime(d.date.year, d.date.month, d.date.day));
    if (!mounted) return;
    final state = AppScope.of(context);
    final nav = Navigator.of(context, rootNavigator: true);
    toast(context, 'Party moved to ${DateFormat('EEE, MMM d').format(d.date)}.');
    Navigator.of(context).pop();
    await _notify(nav, state);
  }

  Future<void> _changeVenue() async {
    final state = AppScope.of(context);
    final p = await pickPlace(context);
    if (p == null || !mounted) return;
    await state.update((e) => e.venue = p);
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    toast(context, 'Venue changed to ${p.label}.');
    Navigator.of(context).pop();
    await _notify(nav, state);
  }

  void _pickDate(EventDetails e) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SetupScreen(existing: e)));

  /// The one button at the bottom, for whichever option is picked.
  (String, VoidCallback)? _action(EventDetails e) {
    switch (picked) {
      case 0:
        return e.indoor ? null : ('Move indoors', _moveIndoors);
      case 1:
        return e.customTasks.any((t) => t.id == 'weather_tent') ? null : ('Add a tent to my plan', _addTent);
      case 2:
        final d = day;
        return d == null ? ('Pick another date', () => _pickDate(e)) : ('Move to ${DateFormat('EEE, MMM d').format(d.date)}', () => _moveTo(d));
      case 3:
        return ('Change venue', _changeVenue);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).event;
    final action = e == null ? null : _action(e);
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
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    Text('Pick one. We\'ll update your plan, and you can tell your guests.', style: body(15, color: HC.muted)),
                    const SizedBox(height: 16),
                    _indoors(e),
                    _tent(e),
                    _drierDay(e),
                    _venue(e),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: e == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (picked != 1)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                        decoration: BoxDecoration(color: HC.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HC.line)),
                        child: Row(
                          children: [
                            Icon(Icons.notifications_active_outlined, size: 20, color: HC.violet),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Tell guests about the change', style: body(14))),
                            Switch.adaptive(value: tellGuests, activeTrackColor: HC.violet, onChanged: (v) => setState(() => tellGuests = v)),
                          ],
                        ),
                      ),
                    if (action != null)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: HC.ink,
                          minimumSize: const Size(0, 54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: action.$2,
                        child: Text(action.$1, style: body(15, color: Colors.white, weight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _option(int i, {required String emoji, required String title, required String subtitle, String? tag, List<Widget> children = const []}) {
    return _Option(
      emoji: emoji,
      title: title,
      subtitle: subtitle,
      tag: tag,
      selected: picked == i,
      onTap: () => setState(() => picked = i),
      children: children,
    );
  }

  Widget _indoors(EventDetails e) {
    final swaps = e.indoor ? const <(Game, Game?)>[] : PlanGenerator.indoorSwaps(e);
    return _option(
      0,
      emoji: '🏠',
      title: 'Move indoors',
      subtitle: e.indoor ? 'Your party is already indoors. 👍' : 'Same day and time, under a roof.',
      tag: e.indoor ? null : 'Easiest',
      children: [
        if (!e.indoor && swaps.isNotEmpty) ...[
          Text('We\'ll swap these games:', style: body(13, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final (old, neu) in swaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(neu == null ? '• ${old.name} → removed' : '• ${old.name} → ${neu.name}', style: body(13)),
            ),
        ],
      ],
    );
  }

  Widget _tent(EventDetails e) {
    final added = e.customTasks.any((t) => t.id == 'weather_tent');
    return _option(
      1,
      emoji: '⛺',
      title: 'Rent a tent',
      subtitle: 'Keeps the party outside. Usually \$150–400 with setup.',
      tag: 'Keeps the outdoors',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _Secondary(
            label: 'Find tent rentals nearby',
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const NearbyScreen(initialCategory: 'Rentals', standalone: true),
            )),
          ),
        ),
        if (added) ...[
          const SizedBox(height: 8),
          Text('✅ Tent is on your checklist and budget.', style: body(12, color: const Color(0xFF1F8A4C), weight: FontWeight.w600)),
        ],
      ],
    );
  }

  Widget _drierDay(EventDetails e) {
    return _option(
      2,
      emoji: '📅',
      title: 'Pick a drier day',
      subtitle: 'Dry days near your date from the forecast.',
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
                        color: day?.date == d.date ? const Color(0xFFEEEAFE) : HC.ground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: day?.date == d.date ? HC.violet : HC.line),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            picked = 2;
                            day = d;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                                if (day?.date == d.date) Icon(Icons.check_circle_rounded, color: HC.violet),
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
      ],
    );
  }

  Widget _venue(EventDetails e) {
    final near = e.venue?.label ?? 'me';
    return _option(
      3,
      emoji: '🏛️',
      title: 'Covered venue',
      subtitle: 'Community halls, party rooms, clubhouses.',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _Secondary(
            label: 'Party halls near $near',
            icon: Icons.map_rounded,
            onTap: () => openLink(context, Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': 'party hall near $near'})),
          ),
        ),
      ],
    );
  }
}

/// One Plan B choice: a card with a round selector. Details show when it's picked.
class _Option extends StatelessWidget {
  const _Option({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.tag,
    this.children = const [],
  });
  final String emoji;
  final String title;
  final String subtitle;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: HC.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: selected ? HC.violet : HC.line, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: const Color(0xFFEEEAFE), borderRadius: BorderRadius.circular(16)),
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: body(16, weight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: body(13, color: HC.muted)),
                            if (tag != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFE3F6EC), borderRadius: BorderRadius.circular(8)),
                                child: Text(tag!, style: body(12, color: const Color(0xFF13895C), weight: FontWeight.w700)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: selected ? HC.violet : HC.line,
                      ),
                    ],
                  ),
                  if (selected && children.isNotEmpty) ...[const SizedBox(height: 12), ...children],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
