import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import 'location_service.dart';

/// Weather for the party, from Open-Meteo (free, no API key).
/// Forecasts go up to 16 days ahead.
class EventWeather {
  const EventWeather({
    required this.code,
    required this.high,
    required this.low,
    required this.rainChance,
    required this.partyTemp,
    required this.fahrenheit,
    this.hours = const [],
    this.windMax = 0,
    this.sunset,
  });

  /// Hour by hour, for the party's hours.
  final List<HourWeather> hours;

  /// Strongest wind during the party (mph when [fahrenheit], else km/h).
  final double windMax;
  final DateTime? sunset;

  String get windUnit => fahrenheit ? 'mph' : 'km/h';

  /// WMO weather code for the day.
  final int code;
  final double high;
  final double low;

  /// Highest chance of rain (0–100) during the party hours.
  final int rainChance;

  /// Temperature around the start of the party.
  final double partyTemp;
  final bool fahrenheit;

  String get unit => fahrenheit ? '°F' : '°C';
  String get emoji => weatherEmoji(code);
  String get summary => weatherText(code);

  /// One line of advice for the plan.
  String advice({required bool indoor}) => weatherAdvice(code: code, rainChance: rainChance, temp: partyTemp, fahrenheit: fahrenheit, indoor: indoor);
}

/// One hour of the party.
class HourWeather {
  const HourWeather({required this.hour, required this.code, required this.temp, required this.rainChance, required this.wind});
  final int hour;
  final int code;
  final double temp;
  final int rainChance;
  final double wind;
}

enum WeatherLevel { good, watch, risky }

/// What the weather means for this party: a level, a headline and a friendly line.
class WeatherVerdict {
  const WeatherVerdict(this.level, this.title, this.message);
  final WeatherLevel level;
  final String title;
  final String message;
}

bool _stormy(int code) => code >= 95;
bool _snowy(int code) => (code >= 71 && code <= 77) || code == 85 || code == 86;
bool _wet(int code) => code >= 51 && code <= 82 && !_snowy(code);

/// Rain, storms, wind, snow or heat that could spoil an outdoor party get "risky"
/// (so the host reviews the date or venue); good days get a happy message.
WeatherVerdict assessWeather(EventWeather w, {required bool indoor}) {
  final f = w.fahrenheit ? w.partyTemp : w.partyTemp * 9 / 5 + 32;
  final mph = w.fahrenheit ? w.windMax : w.windMax / 1.609;
  final codes = [w.code, for (final h in w.hours) h.code];
  final storm = codes.any(_stormy);
  final snow = codes.any(_snowy);
  final rainy = w.rainChance >= 50 || (w.hours.isEmpty && _wet(w.code));
  final maybeRain = w.rainChance >= 25;
  final t = '${w.partyTemp.round()}°';

  if (!indoor) {
    if (storm) {
      return const WeatherVerdict(WeatherLevel.risky, '⛈️ Storms are likely during your party',
          'Thunderstorms and outdoor parties don\'t mix. Please review the date or move it indoors.');
    }
    if (snow) {
      return const WeatherVerdict(WeatherLevel.risky, '❄️ Snow is expected', 'Snow makes an outdoor party hard. Consider an indoor venue or another date.');
    }
    if (rainy) {
      return WeatherVerdict(WeatherLevel.risky, '🌧️ ${w.rainChance}% chance of rain during your party',
          'Your party is outdoors. Review the date or venue, or book a tent so the fun stays dry.');
    }
    if (mph >= 25) {
      return WeatherVerdict(WeatherLevel.risky, '💨 Strong wind: up to ${w.windMax.round()} ${w.windUnit}',
          'Balloons, tents and decorations may blow away. Consider a sheltered spot or another date.');
    }
    if (f <= 32) return WeatherVerdict(WeatherLevel.risky, '🥶 Freezing: about $t', 'Too cold to party outside for long. An indoor venue would be kinder to guests.');
    if (f >= 95) return WeatherVerdict(WeatherLevel.risky, '🥵 Very hot: about $t', 'Plan lots of shade, cold water and a cool indoor spot, or move the party to the evening.');
    if (maybeRain) {
      return WeatherVerdict(WeatherLevel.watch, '🌦️ ${w.rainChance}% chance of a shower',
          'Probably fine, but keep a tent or an indoor backup handy just in case.');
    }
    if (mph >= 18) return WeatherVerdict(WeatherLevel.watch, '🌬️ Breezy: up to ${w.windMax.round()} ${w.windUnit}', 'Weigh down balloons, tablecloths and decorations.');
    if (f >= 88) return WeatherVerdict(WeatherLevel.watch, '☀️ Hot day: about $t', 'Plan shade, cold drinks and water games.');
    if (f <= 50) return WeatherVerdict(WeatherLevel.watch, '🧥 Chilly: about $t', 'Patio heaters, blankets and warm drinks will help.');
  } else {
    if (storm || snow) {
      return WeatherVerdict(WeatherLevel.watch, storm ? '⛈️ Storms outside' : '❄️ Snow outside',
          'You\'re indoors, so the party is safe. Guests may be late; share parking and road tips.');
    }
    if (rainy || maybeRain) {
      return WeatherVerdict(WeatherLevel.watch, '☔ Rain outside', 'You\'re indoors. Keep a spot for umbrellas and wet shoes at the door.');
    }
  }
  return WeatherVerdict(WeatherLevel.good, _goodTitle(w, f, indoor), _goodMessage(w, f, indoor));
}

String _goodTitle(EventWeather w, double f, bool indoor) {
  if (w.code == 0 && f >= 65 && f <= 85) return '☀️ Perfect party weather!';
  if (w.code <= 2) return '🌤️ Lovely weather for your party!';
  return '🎉 Weather looks good for your party!';
}

String _goodMessage(EventWeather w, double f, bool indoor) {
  final t = '${w.partyTemp.round()}°';
  final parts = <String>[
    indoor ? '$t and ${weatherText(w.code).toLowerCase()} outside. Guests will arrive happy and on time.' : '$t and ${weatherText(w.code).toLowerCase()}. Made for outdoor games and fun.',
  ];
  final s = w.sunset;
  if (s != null && !indoor) parts.add('Golden hour around ${DateFormat('h:mm a').format(s)}: grab the group photos then 📸');
  return parts.join(' ');
}

/// What the weather is usually like around the party date (past years).
class TypicalWeather {
  const TypicalWeather({required this.high, required this.low, required this.rainyShare, required this.years, required this.fahrenheit});
  final double high;
  final double low;

  /// Share of days (0–1) with real rain (1 mm or more) around this date.
  final double rainyShare;
  final int years;
  final bool fahrenheit;

  String get unit => fahrenheit ? '°F' : '°C';

  WeatherVerdict verdict({required bool indoor}) {
    final pct = (rainyShare * 100).round();
    final f = fahrenheit ? high : high * 9 / 5 + 32;
    if (!indoor && rainyShare >= 0.4) {
      return WeatherVerdict(WeatherLevel.watch, '🌦️ It often rains around this date',
          'About $pct% of days were rainy in past years. Line up a tent or an indoor backup, just in case.');
    }
    if (!indoor && f <= 45) {
      return const WeatherVerdict(WeatherLevel.watch, '🧥 Usually cold around this date', 'Outdoor guests will need heaters, blankets and warm drinks.');
    }
    if (!indoor && f >= 92) {
      return const WeatherVerdict(WeatherLevel.watch, '🥵 Usually very hot around this date', 'Plan shade, cold water, or an evening start.');
    }
    return WeatherVerdict(WeatherLevel.good, '🙂 Usually pleasant around this date', 'Rain on about $pct% of days in past years. The real forecast arrives closer to the party.');
  }
}

/// Averages past years' daily answers from Open-Meteo's archive.
TypicalWeather? summarizeTypical(List<Map<String, dynamic>> years, {required bool fahrenheit}) {
  final highs = <double>[], lows = <double>[];
  var rainy = 0, days = 0, counted = 0;
  for (final y in years) {
    final d = y['daily'] as Map<String, dynamic>?;
    if (d == null) continue;
    final hi = (d['temperature_2m_max'] as List?) ?? const [];
    final lo = (d['temperature_2m_min'] as List?) ?? const [];
    final pr = (d['precipitation_sum'] as List?) ?? const [];
    var any = false;
    for (var i = 0; i < hi.length; i++) {
      if (hi[i] is! num || i >= lo.length || lo[i] is! num) continue;
      highs.add((hi[i] as num).toDouble());
      lows.add((lo[i] as num).toDouble());
      days++;
      any = true;
      if (i < pr.length && pr[i] is num && (pr[i] as num) >= 1) rainy++;
    }
    if (any) counted++;
  }
  if (days == 0) return null;
  double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
  return TypicalWeather(high: avg(highs), low: avg(lows), rainyShare: rainy / days, years: counted, fahrenheit: fahrenheit);
}

/// One day of the 16-day outlook (to find a drier day for the party).
class DayOutlook {
  const DayOutlook({required this.date, required this.code, required this.high, required this.low, required this.rainChance});
  final DateTime date;
  final int code;
  final double high;
  final double low;
  final int rainChance;
}

List<DayOutlook> parseOutlook(Map<String, dynamic> json) {
  final d = json['daily'] as Map<String, dynamic>?;
  if (d == null) return const [];
  final days = (d['time'] as List?) ?? const [];
  num at(String k, int i) {
    final l = (d[k] as List?) ?? const [];
    return i < l.length && l[i] is num ? l[i] as num : 0;
  }

  return [
    for (var i = 0; i < days.length; i++)
      if (DateTime.tryParse('${days[i]}') != null)
        DayOutlook(
          date: DateTime.parse('${days[i]}'),
          code: at('weather_code', i).toInt(),
          high: at('temperature_2m_max', i).toDouble(),
          low: at('temperature_2m_min', i).toDouble(),
          rainChance: at('precipitation_probability_max', i).round(),
        ),
  ];
}

/// Dry days (under 30% rain, no storms or snow) closest to the party date, best first.
List<DayOutlook> drierDays(List<DayOutlook> days, DateTime party, {DateTime? now, int take = 4}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final p = DateTime(party.year, party.month, party.day);
  final ok = [
    for (final d in days)
      if (d.date.isAfter(today) && d.date != p && d.rainChance < 30 && !_stormy(d.code) && !_snowy(d.code)) d,
  ];
  ok.sort((a, b) {
    final da = a.date.difference(p).inDays.abs(), db = b.date.difference(p).inDays.abs();
    return da != db ? da.compareTo(db) : a.rainChance.compareTo(b.rainChance);
  });
  return ok.take(take).toList();
}

const forecastDays = 16;

/// The day the forecast for [date] becomes available.
DateTime forecastFrom(DateTime date) => DateTime(date.year, date.month, date.day).subtract(const Duration(days: forecastDays - 1));

String weatherEmoji(int code) {
  if (code == 0) return '☀️';
  if (code <= 2) return '🌤️';
  if (code == 3) return '☁️';
  if (code == 45 || code == 48) return '🌫️';
  if (code >= 95) return '⛈️';
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return '❄️';
  if (code >= 51) return '🌧️';
  return '🌤️';
}

String weatherText(int code) {
  if (code == 0) return 'Clear and sunny';
  if (code <= 2) return 'Mostly sunny';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Foggy';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'Rain';
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return 'Snow';
  if (code >= 95) return 'Thunderstorms';
  return 'Mixed';
}

String weatherAdvice({required int code, required int rainChance, required double temp, required bool fahrenheit, required bool indoor}) {
  final f = fahrenheit ? temp : temp * 9 / 5 + 32;
  final stormy = code >= 95;
  final wet = rainChance >= 40 || (code >= 51 && code <= 82);
  if (!indoor) {
    if (stormy) return 'Storms are likely. Book a tent or move the games indoors.';
    if (wet) return '$rainChance% chance of rain. Have a tent or an indoor backup ready.';
    if (f >= 88) return 'Hot day. Plan shade, cold water and water games.';
    if (f <= 50) return 'Chilly outside. Patio heaters, blankets and warm drinks help.';
    return 'Great weather for outdoor games!';
  }
  if (stormy || wet) return 'Rain expected. Keep a spot for umbrellas and wet shoes at the door.';
  if (f >= 88) return 'Hot day. Keep the AC on and drinks cold.';
  if (f <= 32) return 'Freezing out. Remind guests about icy roads and parking.';
  return 'Nice day for it. Guests will arrive happy.';
}

class WeatherService {
  WeatherService._();

  /// Null when the date is past or more than 16 days away.
  static Future<EventWeather?> forEvent(EventDetails e, Place venue, {DateTime? now}) async {
    final today = DateTime((now ?? DateTime.now()).year, (now ?? DateTime.now()).month, (now ?? DateTime.now()).day);
    final day = DateTime(e.date.year, e.date.month, e.date.day);
    if (day.isBefore(today) || day.difference(today).inDays >= forecastDays) return null;
    final ymd = DateFormat('yyyy-MM-dd').format(day);
    final f = venue.usesFahrenheit;
    final res = await http.get(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': venue.lat.toStringAsFixed(4),
      'longitude': venue.lng.toStringAsFixed(4),
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,sunset',
      'hourly': 'temperature_2m,precipitation_probability,weather_code,wind_speed_10m',
      'temperature_unit': f ? 'fahrenheit' : 'celsius',
      'wind_speed_unit': f ? 'mph' : 'kmh',
      'timezone': 'auto',
      'start_date': ymd,
      'end_date': ymd,
    })).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw StateError('Weather is unavailable right now.');
    return parseWeather(jsonDecode(res.body) as Map<String, dynamic>, e, fahrenheit: f);
  }

  /// The next 16 days at the venue, day by day.
  static Future<List<DayOutlook>> outlook(Place venue) async {
    final f = venue.usesFahrenheit;
    final res = await http.get(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': venue.lat.toStringAsFixed(4),
      'longitude': venue.lng.toStringAsFixed(4),
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'temperature_unit': f ? 'fahrenheit' : 'celsius',
      'timezone': 'auto',
      'forecast_days': '$forecastDays',
    })).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw StateError('Weather is unavailable right now.');
    return parseOutlook(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// The usual weather around the party date over the past 5 years (±2 days each year).
  static Future<TypicalWeather?> typical(EventDetails e, Place venue) async {
    final f = venue.usesFahrenheit;
    final calls = <Future<Map<String, dynamic>?>>[];
    for (var y = 1; y <= 5; y++) {
      final mid = DateTime(e.date.year - y, e.date.month, e.date.day);
      final fmt = DateFormat('yyyy-MM-dd');
      calls.add(http
          .get(Uri.https('archive-api.open-meteo.com', '/v1/archive', {
            'latitude': venue.lat.toStringAsFixed(4),
            'longitude': venue.lng.toStringAsFixed(4),
            'start_date': fmt.format(mid.subtract(const Duration(days: 2))),
            'end_date': fmt.format(mid.add(const Duration(days: 2))),
            'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum',
            'temperature_unit': f ? 'fahrenheit' : 'celsius',
            'timezone': 'auto',
          }))
          .timeout(const Duration(seconds: 12))
          .then<Map<String, dynamic>?>((r) => r.statusCode == 200 ? jsonDecode(r.body) as Map<String, dynamic> : null)
          .catchError((_) => null));
    }
    final years = [for (final y in await Future.wait(calls)) if (y != null) y];
    return summarizeTypical(years, fahrenheit: f);
  }
}

/// Reads Open-Meteo's answer for one day.
EventWeather? parseWeather(Map<String, dynamic> json, EventDetails e, {required bool fahrenheit}) {
  final daily = json['daily'] as Map<String, dynamic>?;
  final hourly = json['hourly'] as Map<String, dynamic>?;
  if (daily == null || (daily['weather_code'] as List?)?.isEmpty != false) return null;
  num first(String key) => ((daily[key] as List).first as num?) ?? 0;

  final startHour = e.startMinutes ~/ 60;
  final endHour = (startHour + e.hours).clamp(startHour + 1, 24);
  var rain = 0;
  double? temp;
  var windMax = 0.0;
  final hours = <HourWeather>[];
  if (hourly != null) {
    final temps = (hourly['temperature_2m'] as List?) ?? const [];
    final rains = (hourly['precipitation_probability'] as List?) ?? const [];
    final codes = (hourly['weather_code'] as List?) ?? const [];
    final winds = (hourly['wind_speed_10m'] as List?) ?? const [];
    num at(List l, int i, num d) => i < l.length && l[i] is num ? l[i] as num : d;
    for (var h = startHour; h < endHour && h < rains.length; h++) {
      final r = (rains[h] as num?)?.round() ?? 0;
      if (r > rain) rain = r;
    }
    for (var h = startHour; h < endHour && h < temps.length; h++) {
      final wind = at(winds, h, 0).toDouble();
      if (wind > windMax) windMax = wind;
      hours.add(HourWeather(
        hour: h,
        code: at(codes, h, first('weather_code')).toInt(),
        temp: at(temps, h, 0).toDouble(),
        rainChance: at(rains, h, 0).round(),
        wind: wind,
      ));
    }
    if (startHour < temps.length) temp = (temps[startHour] as num?)?.toDouble();
  }
  final sunsets = (daily['sunset'] as List?) ?? const [];
  final sunset = sunsets.isEmpty ? null : DateTime.tryParse('${sunsets.first}');
  return EventWeather(
    code: first('weather_code').toInt(),
    high: first('temperature_2m_max').toDouble(),
    low: first('temperature_2m_min').toDouble(),
    rainChance: rain,
    partyTemp: temp ?? first('temperature_2m_max').toDouble(),
    fahrenheit: fahrenheit,
    hours: hours,
    windMax: windMax,
    sunset: sunset,
  );
}
