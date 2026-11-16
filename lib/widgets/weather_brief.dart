import 'package:flutter/material.dart';

import '../models/event_details.dart';
import '../services/weather_service.dart';

/// A short take on party-day weather: the verdict, an emoji, and whether it's a
/// real forecast or just what the date is usually like.
class WeatherBrief {
  const WeatherBrief({required this.verdict, required this.emoji, required this.forecast, this.rainChance});
  final WeatherVerdict verdict;
  final String emoji;
  final bool forecast;

  /// Chance of rain during the party (real forecasts only).
  final int? rainChance;

  bool get worry => verdict.level != WeatherLevel.good;

  /// "Rain 60%" / "Looks nice" for small chips.
  String get short {
    final r = rainChance;
    if (verdict.level == WeatherLevel.good) return forecast ? 'Looks nice' : 'Usually nice';
    if (r != null && r >= 25) return 'Rain $r%';
    return verdict.level == WeatherLevel.risky ? 'Check weather' : 'Watch weather';
  }
}

/// Loads [WeatherBrief] for an event. Null when there's no venue or it can't load.
Future<WeatherBrief?> loadWeatherBrief(EventDetails e) async {
  final v = e.venue;
  if (v == null) return null;
  try {
    final w = await WeatherService.forEvent(e, v);
    if (w != null) {
      return WeatherBrief(verdict: assessWeather(w, indoor: e.indoor), emoji: w.emoji, forecast: true, rainChance: w.rainChance);
    }
    final t = await WeatherService.typical(e, v);
    if (t == null) return null;
    return WeatherBrief(verdict: t.verdict(indoor: e.indoor), emoji: t.rainyShare >= 0.4 ? '🌦️' : '🌤️', forecast: false);
  } catch (_) {
    return null;
  }
}

/// Builds with the event's [WeatherBrief], reloading only when the date, time or place change.
class WeatherBriefBuilder extends StatefulWidget {
  const WeatherBriefBuilder({super.key, required this.event, required this.builder});
  final EventDetails event;
  final Widget Function(BuildContext context, WeatherBrief? brief) builder;

  @override
  State<WeatherBriefBuilder> createState() => _WeatherBriefBuilderState();
}

class _WeatherBriefBuilderState extends State<WeatherBriefBuilder> {
  Future<WeatherBrief?>? future;
  String? _key;

  String _keyFor(EventDetails e) => '${e.id}|${e.date}|${e.startMinutes}|${e.hours}|${e.indoor}|${e.venue?.lat},${e.venue?.lng}';

  void _load() {
    _key = _keyFor(widget.event);
    future = loadWeatherBrief(widget.event);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WeatherBriefBuilder old) {
    super.didUpdateWidget(old);
    if (_keyFor(widget.event) != _key) _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherBrief?>(
      future: future,
      builder: (context, snap) => widget.builder(context, snap.data),
    );
  }
}
