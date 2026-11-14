import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/services/plan_generator.dart';
import 'package:hoopla/services/reminder_plan.dart';

EventDetails party() => EventDetails(
      id: 'e1',
      occasion: 'Birthday',
      title: "Vir's 1st birthday",
      date: DateTime(2027, 2, 26),
      startMinutes: 16 * 60,
      hours: 3,
      indoor: true,
      guests: 40,
      audience: Audience.kids,
      energy: 1,
    )..gameIds = ['bubble_chase', 'pass_the_parcel'];

void main() {
  group('timeline edits', () {
    test('an edited timeline keeps its order and times add up', () {
      final e = party();
      final steps = PlanGenerator.toCustom(PlanGenerator.build(e));
      // Move the last step to the front and shorten the first.
      steps.insert(0, steps.removeLast());
      steps[1].minutes = 10;
      e.customTimeline = steps;
      final t = PlanGenerator.build(e).timeline;
      expect(t.first.key, steps.first.key);
      expect(t.first.start, 16 * 60);
      expect(t[1].start, 16 * 60 + steps.first.minutes);
      expect(t[2].start, t[1].start + 10);
    });

    test('games added or removed in the Games tab follow into an edited timeline', () {
      final e = party();
      e.customTimeline = PlanGenerator.toCustom(PlanGenerator.build(e));
      e.gameIds = ['pass_the_parcel', 'freeze_dance'];
      final keys = [for (final s in PlanGenerator.build(e).timeline) s.key];
      expect(keys, isNot(contains('game_bubble_chase')));
      expect(keys, contains('game_freeze_dance'));
      expect(keys.indexOf('game_freeze_dance'), lessThan(keys.indexOf('food')));
    });

    test('reset goes back to the suggested timeline', () {
      final e = party()..customTimeline = [CustomStep(key: 'custom_1', title: 'Only this', subtitle: '', minutes: 30, kind: 'custom')];
      // The two chosen games join the edited timeline (the Games tab stays in charge of games).
      expect([for (final s in PlanGenerator.build(e).timeline) s.key], ['custom_1', 'game_bubble_chase', 'game_pass_the_parcel']);
      e.gameIds = [];
      expect(PlanGenerator.build(e).timeline, hasLength(1));
      e.customTimeline = null;
      expect(PlanGenerator.build(e).timeline.length, greaterThan(3));
    });
  });

  group('checklist edits', () {
    test('remove, rename and add tasks', () {
      final e = party()
        ..hiddenTasks.add('menu')
        ..customTasks.addAll([
          CustomTask(id: 'invites', label: 'Send WhatsApp invites', daysBefore: 20),
          CustomTask(id: 'task_1', label: 'Pick up the cake', daysBefore: 0),
        ]);
      final tasks = PlanGenerator.build(e).tasks;
      expect(tasks.any((t) => t.id == 'menu'), isFalse);
      expect(tasks.firstWhere((t) => t.id == 'invites').label, 'Send WhatsApp invites');
      expect(tasks.last.label, 'Pick up the cake');
    });
  });

  group('budget', () {
    test('the suggested split uses the total', () {
      final e = party()..budget = 1000;
      final items = PlanGenerator.budgetItems(e);
      expect(items.first.label, 'Food');
      expect(items.first.planned, 400);
    });

    test('own items with vendors survive a save and load', () {
      final e = party()
        ..budgetItems = [BudgetItem(id: 'b1', label: 'Photography', planned: 500, vendor: 'Ravi Photography', actual: 450, paid: true)];
      final back = EventDetails.fromMap(e.toMap());
      final b = back.budgetItems!.single;
      expect((b.vendor, b.cost, b.paid), ('Ravi Photography', 450.0, true));
      expect(EventDetails.fromMap(party().toMap()).budgetItems, isNull);
    });
  });

  test('My list items with a due date get a reminder', () {
    final e = party()..todos.add(TodoItem(id: 't1', text: 'Buy diyas', due: DateTime(2027, 2, 20)));
    final r = planReminders(e: e, tasks: const [], now: DateTime(2027, 2, 1));
    final todo = r.firstWhere((x) => x.key == 'todo_t1');
    expect(todo.when, DateTime(2027, 2, 20, 9));
    expect(todo.title, contains('Buy diyas'));
  });
}
