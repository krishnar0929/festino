import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/services/invite_service.dart';
import 'package:hoopla/services/referrals.dart';

void main() {
  test('new links use festino.web.app, and old Hoopla links still open', () {
    expect(inviteUrl('u1_e1'), startsWith('https://festino.web.app/'));
    expect(inviteLink('ABC123'), 'https://festino.web.app/?ref=ABC123');
    expect(inviteFromUri(Uri.parse('https://hoopla-894ca.web.app/?invite=u1_e1')), ('u1_e1', ''));
    expect(codeFromUri(Uri.parse('https://hoopla-894ca.web.app/?ref=abc123')), 'ABC123');
  });
}
