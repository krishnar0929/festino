import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/services/invite_service.dart';
import 'package:hoopla/services/location_service.dart';

void main() {
  final e = EventDetails(
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
  )..venue = const Place(label: 'Edison, NJ', address: '12 Oak Tree Rd, Edison', lat: 40.5, lng: -74.4);

  test('pasted numbers and emails become guests', () {
    final list = parseInvitees('Priya 732 555 0100, sam@example.com\n+91 98480 12345; hello');
    expect(list, hasLength(3));
    expect(list[0].name, 'Priya');
    expect(list[0].phoneDigits, '7325550100');
    expect(list[1].email, 'sam@example.com');
    expect(list[2].phoneDigits, '+919848012345');
  });

  test('headcount adds up the people who are going', () {
    final s = RsvpSummary.of(const [
      Rsvp(uid: 'a', name: 'A', status: RsvpStatus.going, adults: 2, kids: 1),
      Rsvp(uid: 'b', name: 'B', status: RsvpStatus.going, adults: 1),
      Rsvp(uid: 'c', name: 'C', status: RsvpStatus.maybe, adults: 2),
      Rsvp(uid: 'd', name: 'D', status: RsvpStatus.no, adults: 0),
    ]);
    expect((s.going, s.maybe, s.no), (2, 1, 1));
    expect((s.adults, s.kids, s.people, s.replies), (3, 1, 4, 4));
  });

  test('the invite text has the date, venue and RSVP link', () {
    final t = inviteText(e, inviteUrl('u1_e1'), hostName: 'Krishna', message: 'Come celebrate!');
    expect(t, contains("Vir's 1st birthday"));
    expect(t, contains('Fri, Feb 26 at 4:00 PM'));
    expect(t, contains('12 Oak Tree Rd, Edison'));
    expect(t, contains('https://hoopla-894ca.web.app/?invite=u1_e1'));
    expect(inviteIdFor('u1', 'e1'), 'u1_e1');
  });

  test('bulk email goes out as BCC', () {
    final u = InviteService.emailTo(['a@x.com', 'b@x.com'], 'Hi', 'Body');
    expect(u.toString(), startsWith('mailto:?bcc=a@x.com,b@x.com&subject=Hi'));
  });

  test('calendar link uses the party time', () {
    final info = InviteInfo.fromDoc('u1_e1', {
      'hostName': 'Krishna',
      'title': "Vir's 1st birthday",
      'date': '2027-02-26',
      'startMinutes': 16 * 60,
      'hours': 3,
      'venueAddress': '12 Oak Tree Rd, Edison',
    });
    expect(info.googleCalendarUrl.queryParameters['dates'], '20270226T160000/20270226T190000');
    expect(info.whenLabel, 'Friday, February 26 · 4:00 PM – 7:00 PM');
  });

  test('guest list survives a save and load', () {
    final x = EventDetails.fromMap((e..invitees.add(Invitee(name: 'Priya', phone: '732 555 0100'))..inviteMessage = 'Yay').toMap());
    expect(x.invitees.single.name, 'Priya');
    expect(x.inviteMessage, 'Yay');
  });

  test('Pitch In ideas fit the party', () {
    final items = suggestPitchIn(e);
    final labels = [for (final i in items) i.label];
    expect(labels, contains('Drinks (4 cases)'));
    expect(labels, contains('Balloons & decorations'));
    expect(labels, contains("Kids' games helper"));
    expect(items.where((i) => i.help), isNotEmpty);
    expect(labels.any((l) => l.contains('canopy')), isFalse, reason: 'indoor party');
  });

  test('food preferences are counted for people who are coming', () {
    final f = foodSummary(const [
      Rsvp(uid: 'a', name: 'A', status: RsvpStatus.going, diet: ['Vegetarian', 'Nut allergy']),
      Rsvp(uid: 'b', name: 'B', status: RsvpStatus.maybe, diet: ['Vegetarian']),
      Rsvp(uid: 'c', name: 'C', status: RsvpStatus.no, diet: ['Vegan']),
    ]);
    expect(f.first.key, 'Vegetarian');
    expect(f.first.value, 2);
    expect(f.any((x) => x.key == 'Vegan'), isFalse);
  });

  test('personal links carry a short guest code that is the same every time', () {
    final p = Invitee(name: 'Priya', phone: '+1 732 555 0100');
    expect(p.guestKey, isNotEmpty);
    expect(p.guestKey, guestKeyFor('+17325550100'));
    expect(p.guestKey, isNot(Invitee(name: 'Sam', email: 'sam@example.com').guestKey));
    expect(inviteUrl('u1_e1', guest: p.guestKey), 'https://hoopla-894ca.web.app/?invite=u1_e1&g=${p.guestKey}');
    expect(inviteUrl('u1_e1'), 'https://hoopla-894ca.web.app/?invite=u1_e1');
  });

  test('guests split into going, pending and can\'t go', () {
    final priya = Invitee(name: 'Priya Rao', phone: '7325550100');
    final sam = Invitee(name: 'Sam', email: 'sam@example.com');
    final anu = Invitee(name: 'Anu', phone: '7325550199');
    final ravi = Invitee(name: 'Ravi', phone: '7325550111');
    final board = groupGuests([priya, sam, anu, ravi], [
      // Matched by personal link even though the typed name differs.
      Rsvp(uid: 'a', name: 'P', status: RsvpStatus.going, adults: 2, kids: 1, guestKey: priya.guestKey),
      // Matched by name.
      const Rsvp(uid: 'b', name: 'sam', status: RsvpStatus.no, adults: 0),
      const Rsvp(uid: 'c', name: 'Anu', status: RsvpStatus.maybe),
      // Opened a shared group link; not on the list.
      const Rsvp(uid: 'd', name: 'Kiran', status: RsvpStatus.going, adults: 1),
    ]);
    expect(board.going.map((g) => g.name), ['P', 'Kiran']);
    expect(board.going.first.invitee, priya);
    expect(board.cantGo.single.invitee, sam);
    expect(board.pending.map((g) => g.name), ['Anu', 'Ravi']);
    expect(board.pending.first.replied, isTrue);
    expect(board.pending.last.replied, isFalse);
    expect(board.people, 4);
    expect(board.total, 5);
  });

  test('sent date and invitation design are saved with the event', () {
    final p = Invitee(name: 'Priya', phone: '7325550100', sentAt: DateTime(2026, 11, 15, 10));
    expect(Invitee.fromMap(p.toMap()).sentAt, DateTime(2026, 11, 15, 10));
    final ev = EventDetails.fromMap({
      ...e.toMap(),
      'inviteTitle': 'Vir turns 1!',
      'invitePhoto': 'https://example.com/p.jpg',
      'inviteTheme': 'confetti',
    });
    expect(ev.inviteHeadline, 'Vir turns 1!');
    expect(ev.invitePhoto, 'https://example.com/p.jpg');
    expect(ev.inviteTheme, 'confetti');
    expect(e.inviteHeadline, "Vir's 1st birthday");
    expect(inviteText(ev, inviteUrl('x')), contains('Vir turns 1!'));
  });
}
