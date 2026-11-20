import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Where people reach the Festino team.
const supportEmail = 'northbitapps@gmail.com';
const appStoreId = '6831895941';
const appStoreUrl = 'https://apps.apple.com/app/id$appStoreId';

/// What the message is about (the "query type" in Contact us).
enum FeedbackType { question, problem, idea, account, helpers, deals, praise, other }

extension FeedbackTypeLabel on FeedbackType {
  String get label => switch (this) {
        FeedbackType.question => 'Question',
        FeedbackType.problem => 'Something isn\'t working',
        FeedbackType.idea => 'Idea or suggestion',
        FeedbackType.account => 'Account and sign-in',
        FeedbackType.helpers => 'Helpers and listings',
        FeedbackType.deals => 'Deals and payments',
        FeedbackType.praise => 'Compliment',
        FeedbackType.other => 'Something else',
      };
}

/// Saves Contact us messages to the `feedback` collection, for the admin
/// dashboard (or the Firebase console). Each message has: uid, email, type
/// (query type), message, rating, location, country, timezone, locale,
/// platform, appVersion, plan, status ('new'), clientTime and createdAt.
/// The app can add messages but never read, change or delete them.
class FeedbackService {
  static Future<void> send({
    required FeedbackType type,
    required int rating,
    required String message,
    String? email,
    String? plan,
    String location = '',
    String country = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not connected.');
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    await FirebaseFirestore.instance.collection('feedback').add({
      'uid': uid,
      'type': type.name,
      'location': location.length > 200 ? location.substring(0, 200) : location,
      'country': country.length > 10 ? '' : country,
      'timezone': '${now.timeZoneName} (UTC$sign$hh:$mm)',
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'clientTime': now.toIso8601String(),
      'status': 'new',
      'rating': rating,
      'message': message.trim(),
      'email': (email == null || email.trim().isEmpty) ? null : email.trim(),
      'plan': plan,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': version,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// mailto: link for "Email us", with the app version filled in.
  static Uri mailto({String subject = 'Festino help', String body = ''}) =>
      Uri(scheme: 'mailto', path: supportEmail, query: _query({'subject': subject, 'body': body}));

  static String _query(Map<String, String> params) => params.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
