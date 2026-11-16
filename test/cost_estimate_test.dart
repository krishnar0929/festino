import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/data/helpers.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/services/cost_estimate.dart';
import 'package:hoopla/services/location_service.dart';

EventDetails party({int guests = 30, int hours = 3, DateTime? date, bool indoor = true, String occasion = 'Birthday'}) => EventDetails(
      id: 'e1',
      occasion: occasion,
      title: 'Party',
      date: date ?? DateTime(2027, 3, 10), // a Wednesday in March
      startMinutes: 16 * 60,
      hours: hours,
      indoor: indoor,
      guests: guests,
      audience: Audience.kids,
      energy: 2,
    );

void main() {
  test('totals follow the ticked items; select all adds everything that applies', () {
    final e = party();
    final some = estimateCost(e, picks: {'food'}, venueKind: 'home');
    final food = some.lines.firstWhere((l) => l.item.id == 'food');
    expect(some.low, closeTo(food.low, 0.01));
    expect(some.high, closeTo(food.high, 0.01));
    final all = estimateCost(e, picks: {for (final i in costItems) i.id}, venueKind: 'home');
    expect(all.picked.any((l) => l.item.id == 'venue'), isFalse, reason: 'no venue cost at home');
    expect(all.high, greaterThan(some.high));
    expect(estimateCost(e, picks: {}).picked, isEmpty);
  });

  test('more guests, more hours and a fancier level cost more', () {
    double total(EventDetails e, String level) => estimateCost(e, level: level, picks: {'food', 'photo', 'decor'}, venueKind: 'hall').mid;
    expect(total(party(guests: 80), 'medium'), greaterThan(total(party(guests: 30), 'medium')));
    expect(total(party(hours: 5), 'medium'), greaterThan(total(party(hours: 3), 'medium')));
    expect(total(party(), 'lux'), greaterThan(total(party(), 'pro')));
    expect(total(party(), 'pro'), greaterThan(total(party(), 'simple')));
  });

  test('season, weekday and area change the price', () {
    double food(DateTime d, {String area = 'average'}) =>
        estimateCost(party(date: d), picks: {'food'}, venueKind: 'home', area: area).mid;
    final decSat = food(DateTime(2027, 12, 11)); // Saturday in December
    final febWed = food(DateTime(2027, 2, 10)); // Wednesday in February
    expect(decSat, greaterThan(febWed));
    expect(food(DateTime(2027, 3, 10), area: 'higher'), greaterThan(food(DateTime(2027, 3, 10))));
    final notes = estimateCost(party(date: DateTime(2027, 12, 11))).notes.join(' ');
    expect(notes, allOf(contains('busy season'), contains('Saturdays')));
  });

  test('India uses rupee prices', () {
    final e = party()..venue = const Place(label: 'Hyderabad', lat: 17.4, lng: 78.5, countryCode: 'in');
    final est = estimateCost(e, picks: {'food'}, venueKind: 'home');
    expect(est.india, isTrue);
    expect(est.money(est.low), startsWith('₹'));
    expect(estimateCost(party(), picks: {'food'}).money(1234), '\$1,250');
  });

  test('suggested items fit the occasion and choices are saved', () {
    expect(defaultCostPicks(party()), containsAll(['food', 'cake', 'artists', 'gifts']));
    expect(defaultCostPicks(party(occasion: 'Pooja')), contains('priest'));
    expect(defaultCostPicks(party(occasion: 'Diwali')), contains('priest'));
    final e = party()
      ..costLevel = 'pro'
      ..costPicks = ['food', 'dj']
      ..venueKind = 'restaurant'
      ..areaCost = 'higher';
    final back = EventDetails.fromMap(e.toMap());
    expect((back.costLevel, back.costPicks, back.venueKind, back.areaCost), ('pro', ['food', 'dj'], 'restaurant', 'higher'));
    for (final i in costItems) {
      if (i.helper != null) expect(helperCategories.any((c) => c.label == i.helper), isTrue, reason: i.helper);
    }
    expect(artistCategories.every((a) => helperCategories.any((c) => c.label == a)), isTrue);
  });
}
