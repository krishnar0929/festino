import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../models/invite_video.dart';
import '../models/photo_frame.dart';

/// Someone the host invited (from contacts, or typed in).
class Invitee {
  Invitee({required this.name, this.phone = '', this.email = '', DateTime? addedAt, this.sentAt}) : addedAt = addedAt ?? DateTime.now();
  final String name;
  final String phone;
  final String email;
  final DateTime addedAt;

  /// When the host last sent this person the invite from Hoopla (null = not yet).
  DateTime? sentAt;

  String get phoneDigits => phone.replaceAll(RegExp(r'[^0-9+]'), '');
  String get key => phoneDigits.isNotEmpty ? phoneDigits : email.toLowerCase();

  /// Short code in this person's own invite link, so their reply is matched to them.
  String get guestKey => guestKeyFor(key);

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'email': email,
        'addedAt': addedAt.toIso8601String(),
        if (sentAt != null) 'sentAt': sentAt!.toUtc().toIso8601String(),
      };

  factory Invitee.fromMap(Map<String, dynamic> m) => Invitee(
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        addedAt: DateTime.tryParse(m['addedAt'] as String? ?? ''),
        sentAt: DateTime.tryParse(m['sentAt'] as String? ?? '')?.toLocal(),
      );
}

/// A short, stable code for a phone number or email (same on iPhone and web).
/// It goes in the guest's invite link instead of their number.
String guestKeyFor(String key) {
  if (key.isEmpty) return '';
  var h = 7;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) % 2147483647;
  }
  return h.toRadixString(36);
}

/// Turns pasted text ("Priya 732-555-0100, sam@x.com; +91 98480 12345") into invitees.
List<Invitee> parseInvitees(String text) {
  final out = <Invitee>[];
  for (final raw in text.split(RegExp(r'[,;\n]+'))) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+').firstMatch(part)?.group(0);
    final phoneMatch = RegExp(r'\+?\d[\d\s().-]{6,}\d').firstMatch(part)?.group(0);
    if (email == null && phoneMatch == null) continue;
    var name = part;
    if (email != null) name = name.replaceAll(email, '');
    if (phoneMatch != null) name = name.replaceAll(phoneMatch, '');
    name = name.replaceAll(RegExp(r'[<>()"]'), '').trim();
    out.add(Invitee(name: name.isEmpty ? (email ?? phoneMatch!.trim()) : name, phone: phoneMatch?.trim() ?? '', email: email ?? ''));
  }
  return out;
}

enum RsvpStatus { going, maybe, no }

extension RsvpStatusLabel on RsvpStatus {
  String get label => switch (this) {
        RsvpStatus.going => 'Going',
        RsvpStatus.maybe => 'Maybe',
        RsvpStatus.no => 'Can\'t go',
      };
  String get emoji => switch (this) {
        RsvpStatus.going => '🎉',
        RsvpStatus.maybe => '🤔',
        RsvpStatus.no => '😢',
      };
}

class Rsvp {
  const Rsvp({
    required this.uid,
    required this.name,
    required this.status,
    this.adults = 1,
    this.kids = 0,
    this.note = '',
    this.diet = const [],
    this.updatedAt,
    this.guestKey = '',
  });
  final String uid;

  /// From the guest's personal invite link ('' when they opened a shared link).
  final String guestKey;

  /// Food preferences, from [foodPreferences].
  final List<String> diet;
  final String name;
  final RsvpStatus status;
  final int adults;
  final int kids;
  final String note;
  final DateTime? updatedAt;

  int get people => status == RsvpStatus.no ? 0 : adults + kids;

  factory Rsvp.fromDoc(String uid, Map<String, dynamic> m) => Rsvp(
        uid: uid,
        name: m['name'] as String? ?? 'Guest',
        status: RsvpStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => RsvpStatus.maybe),
        adults: (m['adults'] as num?)?.toInt() ?? 1,
        kids: (m['kids'] as num?)?.toInt() ?? 0,
        note: m['note'] as String? ?? '',
        diet: [for (final d in (m['diet'] as List? ?? const [])) if (d is String) d],
        updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
        guestKey: m['guestKey'] as String? ?? '',
      );
}

/// One row on the host's guest board: someone invited, someone who replied, or both.
class GuestEntry {
  const GuestEntry({this.invitee, this.rsvp});
  final Invitee? invitee;
  final Rsvp? rsvp;

  String get name => (rsvp?.name.trim().isNotEmpty ?? false) ? rsvp!.name : (invitee?.name ?? 'Guest');
  bool get replied => rsvp != null;
}

/// Guests split the way hosts think about them: going, still pending, can't go.
class GuestBoard {
  const GuestBoard({this.going = const [], this.pending = const [], this.cantGo = const []});
  final List<GuestEntry> going;

  /// "Maybe" replies first, then people who haven't replied.
  final List<GuestEntry> pending;
  final List<GuestEntry> cantGo;

  int get total => going.length + pending.length + cantGo.length;

  /// Adults + kids coming.
  int get people => going.fold(0, (n, g) => n + (g.rsvp?.people ?? 0));
}

/// Matches replies to the guest list (by personal link, then by name) and groups everyone.
GuestBoard groupGuests(List<Invitee> invitees, List<Rsvp> rsvps) {
  String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String first(String s) => norm(s).split(' ').first;
  final open = List<Invitee>.of(invitees);
  final going = <GuestEntry>[], maybe = <GuestEntry>[], no = <GuestEntry>[];

  Invitee? match(Rsvp r) {
    if (r.guestKey.isNotEmpty) {
      for (final i in open) {
        if (i.guestKey == r.guestKey) return i;
      }
    }
    final n = norm(r.name);
    if (n.isEmpty) return null;
    for (final i in open) {
      if (norm(i.name) == n) return i;
    }
    final byFirst = [for (final i in open) if (first(i.name) == first(r.name)) i];
    return byFirst.length == 1 ? byFirst.first : null;
  }

  for (final r in rsvps) {
    final i = match(r);
    if (i != null) open.remove(i);
    final entry = GuestEntry(invitee: i, rsvp: r);
    switch (r.status) {
      case RsvpStatus.going:
        going.add(entry);
      case RsvpStatus.maybe:
        maybe.add(entry);
      case RsvpStatus.no:
        no.add(entry);
    }
  }
  return GuestBoard(
    going: going,
    pending: [...maybe, for (final i in open) GuestEntry(invitee: i)],
    cantGo: no,
  );
}

/// 🥗 Food preferences guests can tick on the RSVP page.
const foodPreferences = ['Vegetarian', 'Non-veg', 'Jain', 'Vegan', 'Eggless', 'No onion-garlic', 'Gluten-free', 'Nut allergy'];

const foodEmoji = {
  'Vegetarian': '🥦',
  'Non-veg': '🍗',
  'Jain': '🌿',
  'Vegan': '🌱',
  'Eggless': '🥚',
  'No onion-garlic': '🧄',
  'Gluten-free': '🌾',
  'Nut allergy': '🥜',
};

/// How many going guests picked each food preference (most first).
List<MapEntry<String, int>> foodSummary(List<Rsvp> list) {
  final counts = <String, int>{};
  for (final r in list) {
    if (r.status == RsvpStatus.no) continue;
    for (final d in r.diet) {
      counts[d] = (counts[d] ?? 0) + 1;
    }
  }
  return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// 🧺 Pitch In: one thing to bring, or one way to help. One guest claims it.
class PitchItem {
  const PitchItem({
    required this.id,
    required this.label,
    required this.emoji,
    this.help = false,
    this.order = 0,
    this.claimedBy = '',
    this.claimedName = '',
  });

  final String id;
  final String label;
  final String emoji;

  /// A way to help (setup, cleanup) rather than something to bring.
  final bool help;
  final int order;
  final String claimedBy;
  final String claimedName;

  bool get claimed => claimedBy.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'label': label,
        'emoji': emoji,
        'help': help,
        'order': order,
        'claimedBy': claimedBy,
        'claimedName': claimedName,
        'claimedAt': null,
      };

  factory PitchItem.fromDoc(String id, Map<String, dynamic> m) => PitchItem(
        id: id,
        label: m['label'] as String? ?? '',
        emoji: m['emoji'] as String? ?? '🧺',
        help: m['help'] as bool? ?? false,
        order: (m['order'] as num?)?.toInt() ?? 0,
        claimedBy: m['claimedBy'] as String? ?? '',
        claimedName: m['claimedName'] as String? ?? '',
      );
}

/// Ideas for the Pitch In list, from the party's occasion, size and place.
List<PitchItem> suggestPitchIn(EventDetails e) {
  final big = e.guests >= 40;
  var n = 0;
  PitchItem item(String emoji, String label, {bool help = false}) =>
      PitchItem(id: 'i${n++}', label: label, emoji: emoji, help: help, order: n);
  final drinks = (e.guests / 12).ceil().clamp(1, 20);
  return [
    item('🥤', 'Drinks ($drinks case${drinks == 1 ? '' : 's'})'),
    item('🧊', 'Ice (${big ? 4 : 2} bags)'),
    item('🍉', 'Fruit platter'),
    item('🍿', 'Snacks & chips'),
    item('🍮', 'Dessert or sweets'),
    if (e.kind == 'Pooja' || e.kind == 'Housewarming') ...[
      item('🌼', 'Flowers & garlands'),
      item('🥥', 'Coconuts & fruits for pooja'),
    ],
    if (e.kind == 'Birthday') ...[
      item('🎈', 'Balloons & decorations'),
      item('🎁', 'Return gift bags'),
    ],
    if (e.kind == 'Baby shower') item('🧸', 'Games prizes'),
    item('🍽️', 'Plates, cups & napkins'),
    if (!e.indoor) item('🪑', 'Extra chairs or a canopy'),
    item('🔊', 'Speaker for music'),
    item('🛠️', 'Setup help (1 hour before)', help: true),
    if (e.audience != Audience.adults) item('🎲', 'Kids\' games helper', help: true),
    item('🧹', 'Cleanup crew (after the party)', help: true),
  ];
}

/// Headcount from RSVPs.
class RsvpSummary {
  const RsvpSummary({this.going = 0, this.maybe = 0, this.no = 0, this.adults = 0, this.kids = 0});
  final int going;
  final int maybe;
  final int no;

  /// People coming (adults + kids of "Going" replies).
  final int adults;
  final int kids;
  int get people => adults + kids;
  int get replies => going + maybe + no;

  factory RsvpSummary.of(List<Rsvp> list) {
    var g = 0, m = 0, n = 0, a = 0, k = 0;
    for (final r in list) {
      switch (r.status) {
        case RsvpStatus.going:
          g++;
          a += r.adults;
          k += r.kids;
        case RsvpStatus.maybe:
          m++;
        case RsvpStatus.no:
          n++;
      }
    }
    return RsvpSummary(going: g, maybe: m, no: n, adults: a, kids: k);
  }
}

/// The public invite guests open from the link (invites/{hostUid}_{eventId}).
class InviteInfo {
  const InviteInfo({
    required this.id,
    required this.hostUid,
    required this.hostName,
    required this.title,
    required this.occasion,
    required this.date,
    required this.startMinutes,
    required this.hours,
    required this.venue,
    required this.venueAddress,
    required this.message,
    this.lat,
    this.lng,
    this.photoUrl = '',
    this.theme = 'midnight',
    this.photoFrame = const PhotoFrame(),
    this.extra = '',
    this.motif = '',
    this.video = const InviteVideo(),
    this.status = 'active',
    this.notice = '',
    this.noticeKind = '',
  });

  /// 'active' or 'cancelled' (then RSVPs are closed).
  final String status;
  bool get cancelled => status == 'cancelled';

  /// The host's news for guests, and what it's about ('cancelled', 'updated', 'back' or '').
  final String notice;
  final String noticeKind;

  final String motif;

  /// The invitation video guests watch on the invite page.
  final InviteVideo video;

  /// Extra text under the message (dress code, parking, …).
  final String extra;

  /// For sentences: the host's names, or "your host".
  String get hostLabel => hostName.trim().isEmpty ? 'your host' : hostName;

  final PhotoFrame photoFrame;

  final String photoUrl;
  final String theme;

  final String id;
  final String hostUid;
  final String hostName;
  final String title;
  final String occasion;
  final DateTime date;
  final int startMinutes;
  final int hours;
  final String venue;
  final String venueAddress;
  final String message;
  final double? lat;
  final double? lng;

  DateTime get start => DateTime(date.year, date.month, date.day).add(Duration(minutes: startMinutes));
  DateTime get end => start.add(Duration(hours: hours));

  String get whenLabel =>
      '${DateFormat('EEEE, MMMM d').format(date)} · ${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';

  Uri? get mapUrl {
    final where = venueAddress.isNotEmpty ? venueAddress : venue;
    if (where.isEmpty && lat == null) return null;
    return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': lat != null ? '$lat,$lng' : where});
  }

  /// "Add to Google Calendar" link (local time, so it shows at the party's time).
  Uri get googleCalendarUrl {
    String t(DateTime d) => DateFormat("yyyyMMdd'T'HHmmss").format(d);
    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${t(start)}/${t(end)}',
      'details': '${message.isEmpty ? '' : '$message\n\n'}${hostName.trim().isEmpty ? 'Invitation' : 'Invited by $hostName'} on Hoopla',
      'location': venueAddress.isNotEmpty ? venueAddress : venue,
    });
  }

  factory InviteInfo.fromDoc(String id, Map<String, dynamic> m) => InviteInfo(
        id: id,
        hostUid: m['hostUid'] as String? ?? '',
        hostName: m['hostName'] as String? ?? '',
        extra: m['extra'] as String? ?? '',
        motif: m['motif'] as String? ?? '',
        status: m['status'] as String? ?? 'active',
        notice: m['notice'] as String? ?? '',
        noticeKind: m['noticeKind'] as String? ?? '',
        video: InviteVideo.fromMap(m['video']),
        title: m['title'] as String? ?? 'A party',
        occasion: m['occasion'] as String? ?? '',
        date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
        startMinutes: (m['startMinutes'] as num?)?.toInt() ?? 0,
        hours: (m['hours'] as num?)?.toInt() ?? 3,
        venue: m['venue'] as String? ?? '',
        venueAddress: m['venueAddress'] as String? ?? '',
        message: m['message'] as String? ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        photoUrl: m['photoUrl'] as String? ?? '',
        theme: m['theme'] as String? ?? 'midnight',
        photoFrame: PhotoFrame.fromMap(m['photoFrame']),
      );
}

String inviteIdFor(String hostUid, String eventId) => '${hostUid}_$eventId';

/// Short invite links (/i/<id>) show a personal preview card in WhatsApp,
/// iMessage and others (cover photo, title, date). They need the invitePreview
/// Firebase function; set to false to go back to plain ?invite= links.
const usePreviewLinks = true;

/// The invite link. With [guest], the link is personal so the reply is matched to that guest.
String inviteUrl(String inviteId, {String guest = ''}) => usePreviewLinks
    ? 'https://hoopla-894ca.web.app/i/$inviteId${guest.isEmpty ? '' : '?g=$guest'}'
    : 'https://hoopla-894ca.web.app/?invite=$inviteId${guest.isEmpty ? '' : '&g=$guest'}';

/// Reads an invite from a link: /i/<id>?g=… or ?invite=<id>&g=…
(String?, String) inviteFromUri(Uri u) {
  final seg = u.pathSegments;
  final id = seg.length >= 2 && seg[0] == 'i' ? seg[1] : u.queryParameters['invite'];
  return (id == null || id.isEmpty ? null : id, u.queryParameters['g'] ?? '');
}

/// The text sent with every invite.
String inviteText(EventDetails e, String url, {String hostName = '', String message = ''}) {
  final when = '${DateFormat('EEE, MMM d').format(e.date)} at ${DateFormat('h:mm a').format(DateTime(2000, 1, 1, e.startMinutes ~/ 60, e.startMinutes % 60))}';
  final where = e.venue == null ? '' : '\n📍 ${e.venue!.address.isNotEmpty ? e.venue!.address : e.venue!.label}';
  return [
    '🎉 You\'re invited: ${e.inviteHeadline}!',
    '🗓 $when$where',
    if (message.trim().isNotEmpty) '\n${message.trim()}',
    if (e.inviteExtra.trim().isNotEmpty) e.inviteExtra.trim(),
    e.inviteVideo.isEmpty ? '\nPlease RSVP here: $url' : '\n🎬 Watch our invitation video and RSVP here: $url',
    if (hostName.isNotEmpty) '— $hostName',
  ].join('\n');
}

class InviteService {
  InviteService._();

  static final _db = FirebaseFirestore.instance;
  static DocumentReference<Map<String, dynamic>> _doc(String id) => _db.collection('invites').doc(id);

  /// Creates or updates the public invite for an event. Returns its id.
  static Future<String> publish(EventDetails e, {required String hostName, required String message}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) throw StateError('Sign in to send invites.');
    final id = inviteIdFor(u.uid, e.id);
    await _doc(id).set({
      'hostUid': u.uid,
      'eventId': e.id,
      'hostName': hostName.trim(),
      'extra': e.inviteExtra.trim(),
      'motif': e.inviteMotif,
      'status': e.status,
      'notice': e.guestNotice,
      'noticeKind': e.noticeKind,
      'video': e.inviteVideo.toMap(),
      'title': e.inviteHeadline,
      'photoUrl': e.invitePhoto,
      'theme': e.inviteTheme,
      'photoFrame': e.invitePhotoFrame.toMap(),
      'occasion': e.occasion,
      'date': DateFormat('yyyy-MM-dd').format(e.date),
      'startMinutes': e.startMinutes,
      'hours': e.hours,
      'venue': e.venue?.label ?? '',
      'venueAddress': e.venue?.address ?? '',
      'lat': e.venue?.lat,
      'lng': e.venue?.lng,
      'message': message.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// Uploads the invitation photo (already resized) and returns its download link.
  static Future<String> uploadPhoto(String eventId, Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) throw StateError('Sign in to add a photo.');
    if (bytes.length > 8 * 1024 * 1024) throw StateError('That photo is too big (8 MB max).');
    final ref = FirebaseStorage.instance.ref('invites/${u.uid}/${eventId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Most a recorded invitation video may weigh.
  static const maxVideoBytes = 100 * 1024 * 1024;

  /// Uploads the host's recorded video and returns its download link.
  static Future<String> uploadVideo(String eventId, Uint8List bytes, {String contentType = 'video/mp4'}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) throw StateError('Sign in to add a video.');
    if (bytes.length > maxVideoBytes) throw StateError('That video is too big. Try a shorter clip.');
    final ext = contentType.contains('quicktime') ? 'mov' : 'mp4';
    final ref = FirebaseStorage.instance.ref('invites/${u.uid}/${eventId}_clip_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Removes an old invitation photo. Ignores photos that are already gone.
  static Future<void> deletePhoto(String url) async {
    if (url.isEmpty) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }

  static Future<InviteInfo?> load(String id) async {
    final snap = await _doc(id).get();
    final data = snap.data();
    return data == null ? null : InviteInfo.fromDoc(id, data);
  }

  /// Every reply, newest first (host only).
  static Future<List<Rsvp>> rsvps(String inviteId) async {
    final snap = await _doc(inviteId).collection('rsvps').limit(500).get();
    final list = [for (final d in snap.docs) Rsvp.fromDoc(d.id, d.data())];
    list.sort((a, b) => (b.updatedAt ?? DateTime(2100)).compareTo(a.updatedAt ?? DateTime(2100)));
    return list;
  }

  /// This device's own reply, if any.
  static Future<Rsvp?> mine(String inviteId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final d = await _doc(inviteId).collection('rsvps').doc(uid).get();
      return d.exists ? Rsvp.fromDoc(uid, d.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> reply(
    String inviteId, {
    required String name,
    required RsvpStatus status,
    int adults = 1,
    int kids = 0,
    String note = '',
    List<String> diet = const [],
    String guestKey = '',
  }) async {
    var uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await FirebaseAuth.instance.signInAnonymously();
      uid = FirebaseAuth.instance.currentUser!.uid;
    }
    await _doc(inviteId).collection('rsvps').doc(uid).set({
      'name': name.trim(),
      'status': status.name,
      'adults': status == RsvpStatus.no ? 0 : adults,
      'kids': status == RsvpStatus.no ? 0 : kids,
      'note': note.trim(),
      'diet': status == RsvpStatus.no ? const <String>[] : diet.take(8).toList(),
      if (guestKey.isNotEmpty) 'guestKey': guestKey,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- 🧺 Pitch In ----------

  static CollectionReference<Map<String, dynamic>> _items(String inviteId) => _doc(inviteId).collection('pitchIn');

  static Future<List<PitchItem>> pitchItems(String inviteId) async {
    final snap = await _items(inviteId).limit(100).get();
    final list = [for (final d in snap.docs) PitchItem.fromDoc(d.id, d.data())];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Host: adds items (keeps what's already there).
  static Future<void> addItems(String inviteId, List<PitchItem> items, {int startOrder = 0}) async {
    final batch = _db.batch();
    var i = startOrder;
    for (final it in items) {
      final ref = _items(inviteId).doc();
      batch.set(ref, {...it.toMap(), 'order': i++});
    }
    await batch.commit();
  }

  static Future<void> removeItem(String inviteId, String itemId) => _items(inviteId).doc(itemId).delete();

  /// Guest: "I'll bring this". Returns false when someone else just took it.
  static Future<bool> claim(String inviteId, String itemId, String name) async {
    var uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await FirebaseAuth.instance.signInAnonymously();
      uid = FirebaseAuth.instance.currentUser!.uid;
    }
    try {
      await _items(inviteId).doc(itemId).update({
        'claimedBy': uid,
        'claimedName': name.trim(),
        'claimedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  static Future<void> unclaim(String inviteId, String itemId) =>
      _items(inviteId).doc(itemId).update({'claimedBy': '', 'claimedName': '', 'claimedAt': null});

  /// Text-message link to many numbers at once (iPhone and Android differ).
  static Uri smsTo(List<String> numbers, String body) {
    final list = numbers.where((n) => n.isNotEmpty).toList();
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (ios) {
      if (list.length <= 1) return Uri.parse('sms:${list.isEmpty ? '' : list.first}&body=${Uri.encodeComponent(body)}');
      return Uri.parse('sms:/open?addresses=${list.join(',')}&body=${Uri.encodeComponent(body)}');
    }
    return Uri.parse('sms:${list.join(';')}?body=${Uri.encodeComponent(body)}');
  }

  /// Email to many people at once (BCC, so guests don't see each other's addresses).
  static Uri emailTo(List<String> emails, String subject, String body) => Uri(
        scheme: 'mailto',
        query: [
          if (emails.isNotEmpty) 'bcc=${emails.join(',')}',
          'subject=${Uri.encodeComponent(subject)}',
          'body=${Uri.encodeComponent(body)}',
        ].join('&'),
      );
}
