import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/event_details.dart';
import '../services/invite_service.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// What happened to the event: 'cancelled', 'updated' (date, time or place) or 'back' (restored).
typedef NoticeKind = String;

/// The ready-made message for guests. [reasons] and [note] are added as the host picks them.
String noticeText(EventDetails e, NoticeKind kind, {List<String> reasons = const [], String note = '', String url = ''}) {
  final when = '${DateFormat('EEE, MMM d').format(e.date)} at ${clockAmPm(e.startMinutes)}';
  final place = e.venue == null ? '' : ' (${e.venue!.label})';
  final head = switch (kind) {
    'cancelled' => 'Sorry, ${e.inviteHeadline} on ${DateFormat('EEE, MMM d').format(e.date)} is cancelled. 🙏',
    'back' => 'Good news! ${e.inviteHeadline} is back on: $when$place. 🎉',
    _ => 'Update: ${e.inviteHeadline} is now on $when$place.',
  };
  return [
    head,
    if (reasons.isNotEmpty) reasons.join(' '),
    if (note.trim().isNotEmpty) note.trim(),
    if (url.isNotEmpty) kind == 'cancelled' ? 'Details: $url' : 'Please RSVP: $url',
  ].join('\n');
}

const _reasons = <String, List<String>>{
  'cancelled': ['Due to a family emergency.', 'Due to the weather.', 'Someone is unwell.', 'We\'ll share a new date soon.', 'We\'ll miss you! 💛'],
  'updated': ['Due to the weather.', 'We found a better spot.', 'Same fun, new time!', 'Please update your calendar. 🗓️'],
  'back': ['Hope you can still make it!', 'Same plan, same fun.', 'Please RSVP again.'],
};

/// Asks "Let your guests know?" and sends the news by text, email or any app.
/// It also updates the invite page: cancelled events can't be RSVP'd to.
Future<void> offerGuestNotice(BuildContext context, EventDetails e, NoticeKind kind) async {
  final state = AppScope.of(context);
  final uid = state.accounts?.user?.uid;
  if (!state.isSignedIn || !state.usingCloud || uid == null) return;
  // Only events whose invitation was made have guests to tell.
  try {
    if (await InviteService.load(inviteIdFor(uid, e.id)) == null) return;
  } catch (_) {
    return;
  }
  // Update the invite page right away (cancelled closes RSVPs), even if the host sends nothing.
  e
    ..noticeKind = kind
    ..guestNotice = '';
  await state.saveQuietly(e);
  try {
    await InviteService.publish(e, hostName: e.inviteHost, message: e.inviteMessage);
  } catch (_) {}
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HC.ground,
    builder: (_) => _NoticeSheet(event: e, kind: kind, hostUid: state.accounts?.user?.uid),
  );
}

class _NoticeSheet extends StatefulWidget {
  const _NoticeSheet({required this.event, required this.kind, this.hostUid});
  final EventDetails event;
  final NoticeKind kind;
  final String? hostUid;

  @override
  State<_NoticeSheet> createState() => _NoticeSheetState();
}

class _NoticeSheetState extends State<_NoticeSheet> {
  final picked = <String>[];
  final noteCtrl = TextEditingController();
  late final TextEditingController msgCtrl;
  bool onlyComing = false;
  bool edited = false;
  bool published = false;
  Future<GuestBoard?>? board;
  String? inviteId;

  EventDetails get e => widget.event;

  @override
  void initState() {
    super.initState();
    final uid = widget.hostUid;
    if (uid != null) {
      inviteId = inviteIdFor(uid, e.id);
      board = InviteService.rsvps(inviteId!).then<GuestBoard?>((r) => groupGuests(e.invitees, r)).catchError((_) => null);
    }
    msgCtrl = TextEditingController(text: _compose());
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    msgCtrl.dispose();
    super.dispose();
  }

  String _compose() => noticeText(e, widget.kind, reasons: picked, note: noteCtrl.text, url: inviteId == null ? '' : inviteUrl(inviteId!));

  void _refresh() {
    if (!edited) msgCtrl.text = _compose();
    setState(() {});
  }

  /// Puts the news on the invite page (once) so late visitors see it too.
  Future<void> _publish() async {
    if (published) return;
    final state = AppScope.of(context);
    final note = [...picked, noteCtrl.text.trim()].where((s) => s.isNotEmpty).join(' ');
    e
      ..guestNotice = note
      ..noticeKind = widget.kind;
    await state.saveQuietly(e);
    try {
      await InviteService.publish(e, hostName: e.inviteHost, message: e.inviteMessage);
      published = true;
    } catch (_) {}
  }

  Future<List<Invitee>> _people() async {
    if (!onlyComing) return e.invitees;
    final b = await board;
    if (b == null) return e.invitees;
    return [
      for (final g in [...b.going, ...b.pending.where((p) => p.replied)])
        if (g.invitee != null) g.invitee!,
    ];
  }

  Future<void> _send(String how, BuildContext from) async {
    await _publish();
    if (!mounted) return;
    final text = msgCtrl.text.trim();
    final people = await _people();
    if (!mounted) return;
    final subject = switch (widget.kind) {
      'cancelled' => 'Cancelled: ${e.inviteHeadline}',
      'back' => 'Back on: ${e.inviteHeadline}',
      _ => 'Update: ${e.inviteHeadline}',
    };
    switch (how) {
      case 'sms':
        final phones = [for (final p in people) if (p.phoneDigits.isNotEmpty) p.phoneDigits];
        if (phones.isEmpty) {
          toast(context, 'No phone numbers on your guest list. Use WhatsApp or Share instead.');
          return;
        }
        openLink(context, InviteService.smsTo(phones, text));
      case 'email':
        final emails = [for (final p in people) if (p.email.isNotEmpty) p.email];
        if (emails.isEmpty) {
          toast(context, 'No emails on your guest list. Use WhatsApp or Share instead.');
          return;
        }
        openLink(context, InviteService.emailTo(emails, subject, text));
      case 'whatsapp':
        openLink(context, Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'));
      case 'share':
        final box = from.findRenderObject() as RenderBox?;
        try {
          // ignore: deprecated_member_use
          await Share.share(text, subject: subject, sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
        } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final title = switch (kind) {
      'cancelled' => 'Let your guests know?',
      'back' => 'Tell guests it\'s back on?',
      _ => 'Send an update to guests?',
    };
    final sub = switch (kind) {
      'cancelled' => 'Your invite page now says "This event has been cancelled" and RSVPs are closed.',
      'back' => 'Your invite page is open again for RSVPs.',
      _ => 'Your invite page shows the new details with an "Updated" badge.',
    };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: display(24)),
          const SizedBox(height: 4),
          Text(sub, style: body(13, color: HC.muted)),
          const SizedBox(height: 14),
          Text('Add a reason (optional)', style: body(13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _reasons[kind] ?? const <String>[])
                FilterChip(
                  label: Text(r, style: body(12)),
                  selected: picked.contains(r),
                  selectedColor: HC.lime,
                  showCheckmark: false,
                  onSelected: (on) {
                    on ? picked.add(r) : picked.remove(r);
                    _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Add your own note', hintText: 'Please keep the gifts, we\'ll celebrate soon! 💛'),
            onChanged: (_) => _refresh(),
          ),
          const SizedBox(height: 8),
          Text('Message', style: body(13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: msgCtrl,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => edited = true,
          ),
          if (e.invitees.isNotEmpty) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: onlyComing,
              activeColor: HC.violet,
              title: Text('Only people who said Going or Maybe', style: body(14, weight: FontWeight.w600)),
              subtitle: Text(onlyComing ? 'Skips people who can\'t come or haven\'t replied' : 'Everyone on your guest list (${e.invitees.length})',
                  style: body(12, color: HC.muted)),
              onChanged: (v) => setState(() => onlyComing = v),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SendButton(emoji: '✉️', label: 'Text all', onTap: (b) => _send('sms', b))),
              const SizedBox(width: 8),
              Expanded(child: _SendButton(emoji: '📧', label: 'Email all', onTap: (b) => _send('email', b))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _SendButton(emoji: '💬', label: 'WhatsApp', onTap: (b) => _send('whatsapp', b))),
              const SizedBox(width: 8),
              Expanded(child: _SendButton(emoji: '📤', label: 'Other apps', onTap: (b) => _send('share', b))),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              await _publish();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Just update the invite page'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Not now', style: body(14, color: HC.muted)),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.emoji, required this.label, required this.onTap});
  final String emoji;
  final String label;
  final void Function(BuildContext from) onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(label, style: body(14, weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
