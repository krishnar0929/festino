import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/weather_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../screens/weather_screen.dart';
import 'place_picker.dart';

/// Weather at the venue on party day, with one line of advice.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key, required this.event});
  final EventDetails event;

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  Future<EventWeather?>? future;

  /// Before the forecast exists (outdoor parties only): the usual weather for the date.
  Future<TypicalWeather?>? usual;
  String? _key;

  String _keyFor(EventDetails e) => '${e.id}|${e.date}|${e.startMinutes}|${e.hours}|${e.indoor}|${e.venue?.lat},${e.venue?.lng}';

  void _load() {
    final e = widget.event;
    final v = e.venue;
    _key = _keyFor(e);
    future = v == null ? null : WeatherService.forEvent(e, v);
    usual = v == null || e.indoor
        ? null
        : future!.then((f) async => f == null ? await WeatherService.typical(e, v) : null).catchError((_) => null);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WeatherCard old) {
    super.didUpdateWidget(old);
    if (_keyFor(widget.event) != _key) _load();
  }

  Future<void> _pickVenue() async {
    final state = AppScope.of(context);
    final p = await pickPlace(context);
    if (p != null) await state.update((e) => e.venue = p);
  }

  void _openReport() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeatherReportScreen()));

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final v = e.venue;
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.dateOnly(e.date).isBefore(today)) return const SizedBox.shrink();

    if (v == null) {
      return _Shell(
        onTap: _pickVenue,
        leading: '📍',
        title: 'Add your venue',
        subtitle: 'See the weather forecast for party day and find helpers near it.',
        trailing: const Icon(Icons.chevron_right_rounded, color: HC.muted),
      );
    }
    return FutureBuilder<EventWeather?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Shell(leading: '🌤️', title: 'Checking the weather in ${v.label}…', subtitle: '', onTap: _openReport);
        }
        final w = snap.data;
        if (snap.hasError) {
          return _Shell(leading: '🌤️', title: 'Weather for ${v.label}', subtitle: 'Couldn\'t load the forecast right now. Tap to try again.', onTap: _openReport);
        }
        if (w == null) {
          final from = forecastFrom(e.date);
          final plain = _Shell(
            leading: '🗓️',
            title: 'Weather in ${v.label}',
            subtitle: 'Forecast from ${DateFormat('MMM d').format(from)}. Tap to see what this date is usually like.',
            onTap: _openReport,
            trailing: const Icon(Icons.chevron_right_rounded, color: HC.muted),
          );
          if (usual == null) return plain;
          return FutureBuilder<TypicalWeather?>(
            future: usual,
            builder: (context, u) {
              final t = u.data;
              if (t == null) return plain;
              final verdict = t.verdict(indoor: e.indoor);
              if (verdict.level == WeatherLevel.good) return plain;
              return _Shell(
                onTap: _openReport,
                leading: '🌦️',
                title: verdict.title,
                subtitle: '${v.label} · usually ${t.low.round()}–${t.high.round()}${t.unit} · forecast from ${DateFormat('MMM d').format(from)}',
                level: WeatherLevel.watch,
                extra: _Extra(message: verdict.message, event: e, fixes: true, risky: false),
              );
            },
          );
        }
        final verdict = assessWeather(w, indoor: e.indoor);
        return _Shell(
          onTap: _openReport,
          leading: w.emoji,
          title: verdict.title,
          subtitle: '${v.label} · ${w.summary} · ${w.high.round()}° / ${w.low.round()}${w.unit} · ${w.rainChance}% rain',
          level: verdict.level,
          extra: _Extra(
            message: verdict.message,
            event: e,
            fixes: verdict.level != WeatherLevel.good && !e.indoor,
            risky: verdict.level == WeatherLevel.risky,
          ),
        );
      },
    );
  }
}

/// The verdict's message, the fix buttons when needed, and a link to the full report.
class _Extra extends StatelessWidget {
  const _Extra({required this.message, required this.event, required this.fixes, required this.risky});
  final String message;
  final EventDetails event;
  final bool fixes;
  final bool risky;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: body(13, color: HC.ink)),
        if (fixes) ...[
          const SizedBox(height: 10),
          if (risky) Text('Please review your plan:', style: body(13, weight: FontWeight.w700)),
          if (risky) const SizedBox(height: 6),
          WeatherFixes(event: event, risky: risky, compact: true),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeatherReportScreen())),
            child: const Text('See hour by hour ›'),
          ),
        ),
      ],
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.leading, required this.title, required this.subtitle, this.onTap, this.trailing, this.level, this.extra});

  /// More content under the row (the weather verdict and fixes).
  final Widget? extra;
  final String leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final WeatherLevel? level;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: switch (level) {
        WeatherLevel.risky => const Color(0xFFFFF1EC),
        WeatherLevel.watch => const Color(0xFFFFF8E1),
        WeatherLevel.good => const Color(0xFFF4FBE6),
        null => HC.card,
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: level == WeatherLevel.risky ? HC.coral : HC.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Row(
            children: [
              Text(leading, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: body(15, weight: FontWeight.w600)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: body(12, color: HC.muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
              if (extra != null) ...[
                const SizedBox(height: 10),
                extra!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
