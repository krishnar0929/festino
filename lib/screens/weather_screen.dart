import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/plan_generator.dart';
import '../services/weather_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/place_picker.dart';
import 'rain_plan_screen.dart';
import 'setup_screen.dart';

/// Party-day weather in full: hour by hour for the party, wind and sunset,
/// a warning (with fixes) when it could spoil an outdoor party, and a happy
/// note when it looks good. Before the forecast exists: the usual weather.
class WeatherReportScreen extends StatefulWidget {
  const WeatherReportScreen({super.key});

  @override
  State<WeatherReportScreen> createState() => _WeatherReportScreenState();
}

class _WeatherReportScreenState extends State<WeatherReportScreen> {
  Future<EventWeather?>? forecast;
  Future<TypicalWeather?>? usual;
  String? _key;

  String _keyFor(EventDetails e) => '${e.id}|${e.date}|${e.startMinutes}|${e.hours}|${e.venue?.lat},${e.venue?.lng}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final e = AppScope.of(context).event;
    if (e != null && _keyFor(e) != _key) _load(e);
  }

  void _load(EventDetails e) {
    _key = _keyFor(e);
    final v = e.venue;
    if (v == null) {
      forecast = null;
      usual = null;
      return;
    }
    forecast = WeatherService.forEvent(e, v);
    usual = forecast!.then((f) async => f == null ? await WeatherService.typical(e, v) : null).catchError((_) => null);
  }

  void _refresh() {
    final e = AppScope.of(context).event;
    if (e != null) setState(() => _load(e));
  }

  Future<void> _changeVenue() async {
    final state = AppScope.of(context);
    final p = await pickPlace(context);
    if (p != null) await state.update((e) => e.venue = p);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: Center(child: BackArrow())),
        leadingWidth: 60,
        title: const Text('Weather'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: e == null
          ? const SizedBox.shrink()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    _header(e),
                    const SizedBox(height: 14),
                    if (e.venue == null)
                      _AddVenue(onTap: _changeVenue)
                    else
                      FutureBuilder<EventWeather?>(
                        future: forecast,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                          }
                          if (snap.hasError) {
                            return _Note(
                              emoji: '📡',
                              title: 'Couldn\'t load the forecast',
                              message: 'Check your connection and tap refresh.',
                            );
                          }
                          final w = snap.data;
                          return w == null ? _usual(e) : _forecast(e, w);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _header(EventDetails e) {
    final end = e.startMinutes + e.hours * 60;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.venue?.label ?? 'No venue yet', style: display(24)),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('EEEE, MMMM d').format(e.date)} · ${clockAmPm(e.startMinutes)}–${clockAmPm(end)} · ${e.indoor ? 'Indoor' : 'Outdoor'}',
                style: body(13, color: HC.muted),
              ),
            ],
          ),
        ),
        if (e.venue != null) TextButton(onPressed: _changeVenue, child: const Text('Change venue')),
      ],
    );
  }

  // ---- the real forecast (16 days out)

  Widget _forecast(EventDetails e, EventWeather w) {
    final v = assessWeather(w, indoor: e.indoor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(
          level: v.level,
          big: w.emoji,
          headline: '${w.summary} · ${w.high.round()}° / ${w.low.round()}${w.unit}',
          title: v.title,
          message: v.message,
        ),
        if (w.hours.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('DURING YOUR PARTY', style: overline()),
          const SizedBox(height: 8),
          CardBox(
            padding: const EdgeInsets.all(6),
            child: w.hours.length <= 6
                ? Row(children: [for (final h in w.hours) Expanded(child: _HourChip(h: h, unit: w.unit))])
                : SizedBox(
                    height: 112,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [for (final h in w.hours) SizedBox(width: 64, child: _HourChip(h: h, unit: w.unit))],
                    ),
                  ),
          ),
        ],
        if (v.level != WeatherLevel.good && !e.indoor) ...[
          const SizedBox(height: 20),
          Text('WHAT YOU CAN DO', style: overline()),
          const SizedBox(height: 8),
          const _WeatherActions(),
        ],
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            _Fact(emoji: '💧', label: 'Rain chance', value: '${w.rainChance}%'),
            _Fact(emoji: '🌡️', label: 'At the start', value: '${w.partyTemp.round()}${w.unit}'),
            _Fact(emoji: '💨', label: 'Wind (max)', value: '${w.windMax.round()} ${w.windUnit}'),
            _Fact(emoji: '🌇', label: 'Sunset', value: w.sunset == null ? '—' : DateFormat('h:mm a').format(w.sunset!)),
          ],
        ),
        const SizedBox(height: 14),
        Text('Forecast from Open-Meteo. It gets more accurate closer to the day, so check back.', style: body(12, color: HC.muted)),
      ],
    );
  }

  // ---- before the forecast: the usual weather

  Widget _usual(EventDetails e) {
    final from = forecastFrom(e.date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Note(
          emoji: '🗓️',
          title: 'Forecast arrives ${DateFormat('MMM d').format(from)}',
          message: 'Weather forecasts reach 16 days ahead. Until then, here\'s what this date is usually like.',
        ),
        const SizedBox(height: 12),
        FutureBuilder<TypicalWeather?>(
          future: usual,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
            }
            final t = snap.data;
            if (t == null) {
              return Text('Couldn\'t load past weather for this place.', style: body(13, color: HC.muted));
            }
            final v = t.verdict(indoor: e.indoor);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(
                  level: v.level,
                  big: t.rainyShare >= 0.4 ? '🌦️' : '🌤️',
                  headline: 'Usually ${t.low.round()}–${t.high.round()}${t.unit}',
                  title: v.title,
                  message: v.message,
                ),
                if (v.level != WeatherLevel.good && !e.indoor) ...[
                  const SizedBox(height: 14),
                  const _WeatherActions(),
                ],
                const SizedBox(height: 10),
                Text('Based on ${DateFormat('MMMM d').format(e.date)} ±2 days over the past ${t.years} years.', style: body(12, color: HC.muted)),
              ],
            );
          },
        ),
      ],
    );
  }
}

Color levelColor(WeatherLevel l) => switch (l) {
      WeatherLevel.good => const Color(0xFFE9F8C6),
      WeatherLevel.watch => const Color(0xFFFFF1C2),
      WeatherLevel.risky => const Color(0xFFFFE0D8),
    };

class _Hero extends StatelessWidget {
  const _Hero({required this.level, required this.big, required this.headline, required this.title, required this.message});
  final WeatherLevel level;
  final String big;
  final String headline;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: levelColor(level),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: level == WeatherLevel.risky ? HC.coral : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(big, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 12),
              Expanded(child: Text(headline, style: display(20))),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: body(17, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message, style: body(14)),
        ],
      ),
    );
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({required this.h, required this.unit});
  final HourWeather h;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final wet = h.rainChance >= 50;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: wet ? const Color(0xFFFFF4E5) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(clockAmPm(h.hour * 60).replaceAll(':00', ''), maxLines: 1, style: body(11, color: HC.muted, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(weatherEmoji(h.code), style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text('${h.temp.round()}°', style: body(14, weight: FontWeight.w700)),
          Text('${h.rainChance}%', style: body(11, color: const Color(0xFF1F5FBF), weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The two choices when the weather may spoil an outdoor party.
class _WeatherActions extends StatelessWidget {
  const _WeatherActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: HC.violet,
            minimumSize: const Size(0, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RainPlanScreen())),
          icon: const Icon(Icons.alt_route_rounded, size: 20),
          label: Text('See Plan B options', style: body(15, color: Colors.white, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            side: const BorderSide(color: HC.line),
            backgroundColor: HC.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () {
            toast(context, 'Keeping your plan. We\'ll keep checking the forecast.');
            Navigator.of(context).maybePop();
          },
          child: Text('Keep the plan', style: body(15, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Text('Forecasts change. Check back a few days before the party.', textAlign: TextAlign.center, style: body(12, color: HC.muted)),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.emoji, required this.label, required this.value});
  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: body(11, color: HC.muted)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(16, weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fix extends StatelessWidget {
  const _Fix({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(side: const BorderSide(color: HC.line), backgroundColor: HC.card, minimumSize: const Size(0, 42)),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: HC.violet),
      label: Text(label, style: body(13, weight: FontWeight.w600)),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.emoji, required this.title, required this.message});
  final String emoji;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: body(15, weight: FontWeight.w700)),
                Text(message, style: body(13, color: HC.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddVenue extends StatelessWidget {
  const _AddVenue({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Note(emoji: '📍', title: 'Add your venue', message: 'We\'ll show the weather where your party is.'),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 48)),
          onPressed: onTap,
          child: const Text('Add venue'),
        ),
      ],
    );
  }
}


/// "Please review your plan": one-tap fixes for weather that could spoil an outdoor party.
/// Used on the Plan page (so nobody misses it) and in the full weather report.
class WeatherFixes extends StatelessWidget {
  const WeatherFixes({super.key, required this.event, required this.risky, this.compact = false});
  final EventDetails event;
  final bool risky;

  /// Inside the Plan page's weather card: no box, no heading.
  final bool compact;

  Future<void> _moveIndoors(BuildContext context) async {
    final state = AppScope.of(context);
    final swaps = PlanGenerator.indoorSwaps(state.event!);
    await state.update(PlanGenerator.moveIndoors);
    if (context.mounted) {
      toast(context, swaps.isEmpty ? 'Moved indoors. Your games already work inside.' : 'Moved indoors and swapped ${swaps.length} outdoor game${swaps.length == 1 ? '' : 's'} for indoor ones.');
    }
  }

  Future<void> _changeVenue(BuildContext context) async {
    final state = AppScope.of(context);
    final p = await pickPlace(context);
    if (p != null) await state.update((e) => e.venue = p);
  }

  void _changeDate(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SetupScreen(existing: event)));

  Future<void> _addTent(BuildContext context) async {
    await AppScope.of(context).update((e) {
      if (!e.customTasks.any((t) => t.id == 'weather_tent')) {
        e.customTasks.add(CustomTask(id: 'weather_tent', label: 'Book a tent or canopy (rain backup)', daysBefore: 10));
      }
      final items = PlanGenerator.budgetItems(e);
      if (!items.any((b) => b.id == 'weather_tent')) items.add(BudgetItem(id: 'weather_tent', label: 'Tent / canopy rental', planned: 150));
      e.budgetItems = items;
    });
    if (context.mounted) toast(context, 'Added "Book a tent" to your checklist and a tent line to your budget.');
  }

  @override
  Widget build(BuildContext context) {
    final tent = event.customTasks.any((t) => t.id == 'weather_tent');
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 42)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RainPlanScreen())),
          icon: const Icon(Icons.alt_route_rounded, size: 18),
          label: const Text('See Plan B'),
        ),
        _Fix(icon: Icons.home_rounded, label: 'Move indoors', onTap: () => _moveIndoors(context)),
        _Fix(icon: Icons.event_rounded, label: 'Change date', onTap: () => _changeDate(context)),
        _Fix(icon: Icons.place_rounded, label: 'Change venue', onTap: () => _changeVenue(context)),
        if (!tent) _Fix(icon: Icons.umbrella_rounded, label: 'Add a tent', onTap: () => _addTent(context)),
      ],
    );
    final done = tent
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('✅ Tent is on your checklist and budget.', style: body(12, color: const Color(0xFF1F8A4C), weight: FontWeight.w600)),
          )
        : const SizedBox.shrink();
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [buttons, done]);
    }
    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(risky ? 'Please review your plan' : 'Have a backup ready', style: body(15, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(risky ? 'Your party is outdoors. A quick change now saves the day.' : 'Probably fine, but it\'s good to be ready.', style: body(13, color: HC.muted)),
          const SizedBox(height: 10),
          buttons,
          done,
        ],
      ),
    );
  }
}
