import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/data/invite_templates.dart';
import 'package:hoopla/data/sample_providers.dart';
import 'package:hoopla/models/event_details.dart';
import 'package:hoopla/models/invite_video.dart';
import 'package:hoopla/models/provider_profile.dart';
import 'package:hoopla/services/invite_service.dart';
import 'package:hoopla/services/quote_service.dart';
import 'package:hoopla/widgets/invitation_card.dart';

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
  group('Hoopla deals', () {
    final p = ProviderProfile(uid: 'p1', businessName: 'Lens Studio', serviceType: 'Photographers', city: 'Edison', phone: '', dealPercent: 20, dealTerms: 'Over \$300');

    test('deal code is stable per customer and saved with the listing', () {
      expect(p.hasDeal, isTrue);
      expect(p.dealLabel, '20% off with Hoopla');
      expect(p.dealCodeFor('ab12cd34'), 'HOOPLA20-AB12');
      expect(p.dealCodeFor('x'), 'HOOPLA20-XXXX');
      final back = ProviderProfile.fromMap(p.toMap());
      expect((back.dealPercent, back.dealTerms), (20, 'Over \$300'));
      expect(ProviderProfile.fromMap({...p.toMap(), 'dealPercent': 90}).dealPercent, 30);
      expect(ProviderProfile.fromMap(const {}).hasDeal, isFalse);
    });

    test('quote messages mention the deal', () {
      expect(dealLine(p, 'ab12cd34'), contains('20% off (code HOOPLA20-AB12)'));
      final none = ProviderProfile(uid: 'p2', businessName: 'B', serviceType: 'DJs', city: '', phone: '');
      expect(dealLine(none, 'ab12'), isEmpty);
      final q = QuoteRequest.fromDoc('x', {'dealPercent': 20, 'dealCode': 'HOOPLA20-AB12'});
      expect((q.dealPercent, q.dealCode), (20, 'HOOPLA20-AB12'));
    });

    test('some sample providers show a deal', () {
      expect(sampleProvidersFor('Photographers').where((s) => s.hasDeal), isNotEmpty);
    });
  });

  group('invitation designs', () {
    test('every event type has its own designs plus general ones', () {
      for (final o in occasions) {
        final list = templatesFor(o);
        expect(list.where((t) => t.occasions.contains(o)), isNotEmpty, reason: o);
        expect(list.last.occasions, isEmpty);
      }
    });

    test('designs use real styles and fill in the event name', () {
      for (final t in inviteTemplates) {
        expect(inviteThemeFor(t.theme).id, t.theme, reason: t.id);
      }
      final e = party();
      expect(fillTemplate('{title} on {date}', e, 'Friday, February 26'), "Vir's 1st birthday on Friday, February 26");
    });

    test('decoration is saved with the event', () {
      final e = EventDetails.fromMap({...party().toMap(), 'inviteMotif': '🦖🎈'});
      expect(e.inviteMotif, '🦖🎈');
    });
  });

  group('invitation video', () {
    test('saves photos, captions and style, at most 10 photos', () {
      final v = InviteVideo(photos: List.generate(12, (i) => 'p$i'), captions: const ['Hi'], style: 'elegant');
      final m = v.toMap();
      expect((m['photos'] as List).length, 10);
      expect(m['captions'], ['Hi', '', '', '', '', '', '', '', '', '']);
      final back = InviteVideo.fromMap(m);
      expect((back.photos.length, back.style, back.captionAt(0), back.captionAt(5)), (10, 'elegant', 'Hi', ''));
      expect(InviteVideo.fromMap({'style': 'weird'}).style, 'fun');
      expect(InviteVideo.fromMap(null).isEmpty, isTrue);
    });

    test('the invite text points to the video', () {
      final e = party()..inviteVideo = const InviteVideo(photos: ['a']);
      expect(inviteText(e, inviteUrl('x')), contains('Watch our invitation video and RSVP here: https://hoopla-894ca.web.app/?invite=x'));
      expect(inviteText(party(), inviteUrl('x')), contains('Please RSVP here:'));
      expect(EventDetails.fromMap(e.toMap()).inviteVideo.photos, ['a']);
    });
  });
}
