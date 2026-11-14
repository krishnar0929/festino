import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/services/event_store.dart';
import 'package:hoopla/state/app_state.dart';

class _MemoryStore implements EventStore {
  final list = <EventDetails>[];
  @override
  Future<List<EventDetails>> loadAll() async => List.of(list);
  @override
  Future<void> save(EventDetails e) async {
    list.removeWhere((x) => x.id == e.id);
    list.insert(0, e);
  }

  @override
  Future<void> delete(String id) async => list.removeWhere((x) => x.id == id);
  @override
  Future<void> deleteAll() async => list.clear();
}

EventDetails ev(String id, DateTime date, {String status = 'active'}) => EventDetails(
      id: id,
      occasion: 'Birthday',
      title: id,
      date: date,
      startMinutes: 16 * 60,
      hours: 3,
      indoor: true,
      guests: 20,
      audience: Audience.kids,
      energy: 1,
    )..status = status;

void main() {
  test('events sort into upcoming, celebrated and cancelled', () {
    final now = DateTime.now();
    final s = AppState(_MemoryStore())
      ..events = [
        ev('later', now.add(const Duration(days: 40))),
        ev('soon', now.add(const Duration(days: 3))),
        ev('today', now),
        ev('last-year', now.subtract(const Duration(days: 300))),
        ev('gone', now.add(const Duration(days: 10)), status: 'cancelled'),
      ];
    expect([for (final e in s.upcomingEvents) e.id], ['today', 'soon', 'later']);
    expect([for (final e in s.pastEvents) e.id], ['last-year']);
    expect([for (final e in s.cancelledEvents) e.id], ['gone']);
  });

  test('delete removes an event for good; plan again copies a past one', () async {
    final store = _MemoryStore();
    final past = ev('last-year', DateTime.now().subtract(const Duration(days: 300)))..doneTasks.add('menu');
    final s = AppState(store)..events = [past];
    final copy = await s.planAgain(past);
    expect(copy.id, isNot(past.id));
    expect(copy.doneTasks, isEmpty);
    expect(s.upcomingEvents.map((e) => e.id), contains(copy.id));
    await s.deleteEvent(past.id);
    expect(s.events.any((e) => e.id == past.id), isFalse);
    expect(store.list.any((e) => e.id == past.id), isFalse);
  });
}
