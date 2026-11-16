import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/services/invite_service.dart';
import 'package:hoopla/services/referrals.dart';

void main() {
  test('new links use festino.web.app, and old Hoopla links still open', () {
    expect(inviteUrl('u1_e1'), startsWith('https://festino.web.app/'));
    expect(inviteLink('K7Q2MX'), 'https://festino.web.app/?ref=K7Q2MX');
    expect(inviteFromUri(Uri.parse('https://hoopla-894ca.web.app/?invite=u1_e1')), ('u1_e1', ''));
    expect(codeFromUri(Uri.parse('https://hoopla-894ca.web.app/?ref=k7q2mx')), 'K7Q2MX');
  });
}
