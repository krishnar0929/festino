import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/screens/home_screen.dart';
import 'package:hoopla/services/cost_estimate.dart';
import 'package:hoopla/services/location_service.dart';
import 'package:hoopla/services/plan_generator.dart';
import 'package:hoopla/services/weather_service.dart';
import 'package:hoopla/widgets/weather_brief.dart';

EventDetails party() => EventDetails(
      id: 'e1',
      occasion: 'Birthday',
      title: "Vir's 1st birthday",
      date: DateTime.now().add(const Duration(days: 60)),
      startMinutes: 16 * 60,
      hours: 3,
      indoor: false,
      guests: 30,
      audience: Audience.kids,
      energy: 2,
    );

void main() {
  test('journey: five steps, moving forward as things get done', () {
    final e = party();
    var steps = journeyFor(e, PlanGenerator.build(e));
    expect(steps.map((s) => s.label), ['Details', 'Invites', 'Helpers', 'To-dos', 'Party day']);
    expect(steps.indexWhere((s) => !s.done), 0);

    e.venue = const Place(label: 'Lewiston, GA', lat: 33.0, lng: -82.0, countryCode: 'us');
    e.doneTasks.add('invites');
    steps = journeyFor(e, PlanGenerator.build(e));
    expect(steps[0].done, isTrue);
    expect(steps[1].done, isTrue);
    expect(steps.last.done, isFalse);
  });

  test('next up is the earliest-due open task, and null when all are done', () {
    final e = party();
    final plan = PlanGenerator.build(e);
    final first = nextTask(e, plan)!;
    for (final t in plan.tasks) {
      expect(first.daysBefore >= t.daysBefore, isTrue, reason: t.id);
    }
    e.doneTasks.add(first.id);
    expect(nextTask(e, plan)?.id, isNot(first.id));
    for (final t in plan.tasks) {
      e.doneTasks.add(t.id);
    }
    expect(nextTask(e, plan), isNull);
  });

  test('weather chip text: nice, rain chance, or a nudge', () {
    const good = WeatherVerdict(WeatherLevel.good, 'Lovely day', '');
    const risky = WeatherVerdict(WeatherLevel.risky, 'Rain likely', '');
    expect(const WeatherBrief(verdict: good, emoji: '☀️', forecast: true).short, 'Looks nice');
    expect(const WeatherBrief(verdict: good, emoji: '☀️', forecast: false).short, 'Usually nice');
    expect(const WeatherBrief(verdict: risky, emoji: '🌧️', forecast: true, rainChance: 60).short, 'Rain 60%');
    expect(const WeatherBrief(verdict: risky, emoji: '⛈️', forecast: true, rainChance: 10).short, 'Check weather');
    expect(const WeatherBrief(verdict: risky, emoji: '🌧️', forecast: true).worry, isTrue);
  });

  test('cost estimate is off until the host turns it on and picks a style', () {
    final e = party();
    expect(e.costOn, isFalse);
    e
      ..costOn = true
      ..costLevel = 'lux';
    final back = EventDetails.fromMap(e.toMap());
    expect(back.costOn, isTrue);
    expect(back.costLevel, 'lux');
    expect([for (final k in costLevels.keys) costLevelName(k)], ['Simple', 'Medium', 'High', 'Pro', 'Luxe']);
    for (final k in costLevels.keys) {
      expect(costLevelHint(k), isNotEmpty);
    }
  });
}
