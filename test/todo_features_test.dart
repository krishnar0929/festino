import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/models/invite_video.dart';
import 'package:hoopla/screens/guest_notice.dart';
import 'package:hoopla/services/invite_service.dart';
import 'package:hoopla/services/plan_generator.dart';
import 'package:hoopla/theme.dart';
import 'package:hoopla/widgets/task_guide.dart';

EventDetails party() => EventDetails(
      id: 'e1',
      occasion: 'Birthday',
      title: "Vir's 1st birthday",
      date: DateTime(2027, 2, 26),
      startMinutes: 16 * 60,
      hours: 3,
      indoor: true,
      guests: 30,
      audience: Audience.kids,
      energy: 2,
    );

void main() {
  test('every checklist task has a guide, and booking tasks open their service', () {
    final e = party();
    for (final t in PlanGenerator.build(e).tasks) {
      final g = guideFor(t, e, switchTab: (_) {});
      expect(g.why, isNotEmpty, reason: t.id);
      if (t.id == 'invites' || t.id.startsWith('book_') || t.id == 'menu' || t.id == 'rsvp') {
        expect(g.action, isNotNull, reason: t.id);
      }
    }
    expect(guideFor(const PlanTask('book_Photographers', 'Book photographer', 21), e).action, 'Find Photographers nearby');
    expect(guideFor(const PlanTask('task_1', 'Call grandma', 3), e).action, isNull);
  });

  test('due chip: done, overdue, soon, later', () {
    final e = party()..date = DateTime.now().add(const Duration(days: 30));
    expect(dueInfo(const PlanTask('a', 'A', 10), e, true).$4, 'Done');
    expect(dueInfo(const PlanTask('a', 'A', 40), e, false).$4, startsWith('Overdue'));
    expect(dueInfo(const PlanTask('a', 'A', 26), e, false).$4, startsWith('Due'));
    expect(dueInfo(const PlanTask('a', 'A', 2), e, false).$4, startsWith('By'));
  });

  test('app colors switch the main color', () {
    expect(appColorFor('ocean').name, 'Ocean');
    expect(appColorFor('nope').id, 'violet');
    applyAppColor('forest');
    expect(HC.violet, appColorFor('forest').color);
    applyAppColor('violet');
    expect(HC.violet, appColors.first.color);
  });

  test('guest notices read well and save with the event', () {
    final e = party();
    final c = noticeText(e, 'cancelled', reasons: const ['Due to the weather.'], note: 'Keep the gifts!', url: inviteUrl('x'));
    expect(c, startsWith("Sorry, Vir's 1st birthday on Fri, Feb 26 is cancelled."));
    expect(c, contains('Due to the weather.\nKeep the gifts!\nDetails: '));
    expect(noticeText(e, 'updated'), startsWith("Update: Vir's 1st birthday is now on Fri, Feb 26 at 4:00 PM"));
    expect(noticeText(e, 'back', url: 'u'), endsWith('Please RSVP: u'));
    final back = EventDetails.fromMap({...e.toMap(), 'guestNotice': 'Sorry!', 'noticeKind': 'cancelled'});
    expect((back.guestNotice, back.noticeKind), ('Sorry!', 'cancelled'));
    final info = InviteInfo.fromDoc('x', {'title': 'P', 'status': 'cancelled', 'notice': 'Sorry!'});
    expect((info.cancelled, info.notice), (true, 'Sorry!'));
  });

  test('video music: built-in tracks, a song link, or none', () {
    expect(const InviteVideo().music, 'celebration');
    expect(InviteVideo.fromMap({'music': 'happy_times'}).musicLabel, 'Happy times');
    expect(InviteVideo.fromMap({'music': 'https://example.com/song.mp3'}).customMusic, isTrue);
    expect(InviteVideo.fromMap({'music': 'http://insecure.mp3'}).music, 'celebration');
    expect(InviteVideo.fromMap({'music': 'none'}).hasMusic, isFalse);
    expect(InviteVideo.fromMap(const InviteVideo(photos: ['a'], music: 'none').toMap()).music, 'none');
  });
}
