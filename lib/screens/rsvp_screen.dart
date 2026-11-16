import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/invite_service.dart';
import '../theme.dart';
import '../widgets/celebration.dart';
import '../widgets/common.dart';
import '../widgets/invitation_card.dart';
import '../widgets/invite_clip_player.dart';
import '../widgets/invite_video_player.dart';

/// What a guest sees when they open an invite link
/// (https://festino.web.app/?invite=...): the invite card and an RSVP form.
/// No app or account needed.
class RsvpScreen extends StatefulWidget {
  const RsvpScreen({super.key, required this.inviteId, this.onPlanOwn, this.guestKey = ''});

  /// From a personal invite link (&g=...), so the host sees this reply next to the right guest.
  final String guestKey;
  final String inviteId;

  /// "Plan your own party with Festino".
  final VoidCallback? onPlanOwn;

  @override
  State<RsvpScreen> createState() => _RsvpScreenState();
}

class _RsvpScreenState extends State<RsvpScreen> {
  late final Future<InviteInfo?> future = InviteService.load(widget.inviteId);
  final nameCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  RsvpStatus? status;
  int adults = 1;
  int kids = 0;
  final diet = <String>{};
  late Future<List<PitchItem>> items = InviteService.pitchItems(widget.inviteId);
  String? myUid;
  bool busy = false;
  bool sent = false;
  String? error;
  static const _nameKey = 'hoopla.rsvpName';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prev = await InviteService.mine(widget.inviteId);
    myUid = FirebaseAuth.instance.currentUser?.uid;
    String? savedName;
    try {
      savedName = (await SharedPreferences.getInstance()).getString(_nameKey);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (prev != null) {
        nameCtrl.text = prev.name;
        noteCtrl.text = prev.note;
        status = prev.status;
        adults = prev.adults == 0 ? 1 : prev.adults;
        kids = prev.kids;
        diet
          ..clear()
          ..addAll(prev.diet);
        sent = true;
      } else if (savedName != null) {
        nameCtrl.text = savedName;
      }
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(InviteInfo info) async {
    final s = status;
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => error = 'Please add your name so ${info.hostLabel} knows who\'s coming.');
      return;
    }
    if (s == null) {
      setState(() => error = 'Tap Going, Maybe or Can\'t go.');
      return;
    }
    final overlay = Celebration.overlayOf(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await InviteService.reply(info.id, name: nameCtrl.text, status: s, adults: adults, kids: kids, note: noteCtrl.text, diet: diet.toList(), guestKey: widget.guestKey);
      myUid = FirebaseAuth.instance.currentUser?.uid;
      try {
        await (await SharedPreferences.getInstance()).setString(_nameKey, nameCtrl.text.trim());
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        busy = false;
        sent = true;
      });
      if (s == RsvpStatus.going) {
        Celebration.show(overlay, title: 'See you there!', message: '${info.hostName.trim().isEmpty ? 'Your host' : info.hostName} will be thrilled. 🎉', emoji: '🥳');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Couldn\'t send your reply. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _claim(InviteInfo info, PitchItem it) async {
    if (nameCtrl.text.trim().isEmpty) {
      toast(context, 'Add your name above first, so ${info.hostLabel} knows who\'s bringing it.');
      return;
    }
    final ok = await InviteService.claim(info.id, it.id, nameCtrl.text);
    if (!mounted) return;
    myUid = FirebaseAuth.instance.currentUser?.uid;
    toast(context, ok ? 'Thank you! You\'re on ${it.label.toLowerCase()}. 🙌' : 'Someone just picked that one. Choose another?');
    setState(() => items = InviteService.pitchItems(info.id));
  }

  Future<void> _unclaim(InviteInfo info, PitchItem it) async {
    await InviteService.unclaim(info.id, it.id);
    if (mounted) setState(() => items = InviteService.pitchItems(info.id));
  }

  /// 🧺 Pitch In: things to bring and ways to help. Hidden when the host made no list.
  Widget _pitchIn(InviteInfo info) {
    return FutureBuilder<List<PitchItem>>(
      future: items,
      builder: (context, snap) {
        final list = snap.data ?? const <PitchItem>[];
        if (list.isEmpty) return const SizedBox.shrink();
        final taken = list.where((i) => i.claimed).length;
        return Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('🧺 Pitch In', style: display(22))),
                  _Badge('$taken of ${list.length} covered'),
                ],
              ),
              const SizedBox(height: 4),
              Text('Want to help ${info.hostLabel}? Pick something to bring or a way to help.', style: body(13, color: HC.muted)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: taken / list.length, minHeight: 8, backgroundColor: HC.track, color: HC.violet),
              ),
              const SizedBox(height: 12),
              for (final it in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PitchRow(
                    item: it,
                    mine: it.claimedBy == myUid && it.claimed,
                    onClaim: () => _claim(info, it),
                    onUndo: () => _unclaim(info, it),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<InviteInfo?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final info = snap.data;
          if (info == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎈', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text('This invite isn\'t available', style: display(22)),
                    const SizedBox(height: 6),
                    Text('Ask your host to send the link again.', style: body(14, color: HC.muted)),
                  ],
                ),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 32),
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    const Align(alignment: Alignment.centerLeft, child: BackArrow()),
                    const SizedBox(height: 10),
                  ],
                  if (info.cancelled)
                    _NoticeBanner(
                      color: const Color(0xFFFFE4DE),
                      border: const Color(0xFFC0392B),
                      title: '😢 This event has been cancelled',
                      text: info.notice.isNotEmpty ? info.notice : 'The host cancelled this party. Sorry for the change!',
                      by: info.hostName,
                    )
                  else if (info.noticeKind == 'updated')
                    _NoticeBanner(
                      color: const Color(0xFFFFF1C2),
                      border: const Color(0xFFE0A100),
                      title: '🔔 Updated: new details below',
                      text: info.notice.isNotEmpty ? info.notice : 'The date, time or place changed. Please check and update your reply.',
                      by: info.hostName,
                    )
                  else if (info.noticeKind == 'back')
                    _NoticeBanner(
                      color: const Color(0xFFE9F8C6),
                      border: const Color(0xFF5E9E1A),
                      title: '🎉 We\'re back on!',
                      text: info.notice.isNotEmpty ? info.notice : 'The party is happening. Please RSVP below.',
                      by: info.hostName,
                    ),
                  if (info.video.hasClip && !info.cancelled) ...[
                    InviteClipPlayer(url: info.video.clip, autoplay: info.video.clipAutoplay),
                    const SizedBox(height: 14),
                  ] else if (!info.video.isEmpty && !info.cancelled) ...[
                    InviteVideoPlayer(
                      look: info.video.look,
                      photos: info.video.photos,
                      captions: info.video.captions,
                      style: info.video.style,
                      theme: inviteThemeFor(info.theme),
                      title: info.title,
                      when: info.whenLabel,
                      motif: info.motif,
                      music: info.video.music,
                      autoplay: false,
                    ),
                    const SizedBox(height: 14),
                  ],
                  InvitationCard(
                    motif: info.motif,
                    theme: inviteThemeFor(info.theme),
                    title: info.title,
                    hostName: info.hostName,
                    when: info.whenLabel,
                    place: info.venueAddress.isNotEmpty ? info.venueAddress : info.venue,
                    message: info.message,
                    extra: info.extra,
                    photoUrl: info.photoUrl,
                    frame: info.photoFrame,
                    onPlaceTap: info.mapUrl == null ? null : () => openLink(context, info.mapUrl!),
                  ),
                  const SizedBox(height: 18),
                  if (info.cancelled) ...[
                    Text('RSVPs are closed for this event.', textAlign: TextAlign.center, style: body(14, color: HC.muted)),
                  ] else if (sent && status != null) ...[
                    CardBox(
                      color: HC.lime,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${status!.emoji}  You replied: ${status!.label}', style: display(18)),
                          if (status != RsvpStatus.no) Text('$adults adult${adults == 1 ? '' : 's'}${kids > 0 ? ', $kids kid${kids == 1 ? '' : 's'}' : ''}', style: body(14)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (status != RsvpStatus.no)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: HC.ink),
                                  onPressed: () => openLink(context, info.googleCalendarUrl),
                                  icon: const Icon(Icons.event_rounded, size: 18),
                                  label: const Text('Add to calendar'),
                                ),
                              OutlinedButton(onPressed: () => setState(() => sent = false), child: const Text('Change my reply')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text('Will you come?', style: display(22)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final s in RsvpStatus.values) ...[
                          Expanded(
                            child: _Choice(
                              label: s.label,
                              emoji: s.emoji,
                              selected: status == s,
                              onTap: () => setState(() => status = s),
                            ),
                          ),
                          if (s != RsvpStatus.no) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    if (status != null && status != RsvpStatus.no) ...[
                      const SizedBox(height: 14),
                      _Counter(label: 'Adults', value: adults, min: 1, onChanged: (v) => setState(() => adults = v)),
                      const SizedBox(height: 8),
                      _Counter(label: 'Kids', value: kids, min: 0, onChanged: (v) => setState(() => kids = v)),
                      const SizedBox(height: 14),
                      Text('🥗 Food preferences (optional)', style: body(14, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in foodPreferences)
                            FilterChip(
                              label: Text('${foodEmoji[f] ?? ''} $f'),
                              selected: diet.contains(f),
                              showCheckmark: false,
                              selectedColor: HC.lime,
                              backgroundColor: HC.card,
                              side: BorderSide(color: diet.contains(f) ? HC.ink : HC.line),
                              shape: const StadiumBorder(),
                              onSelected: (v) => setState(() => v ? diet.add(f) : diet.remove(f)),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Note for the host (optional)', hintText: 'Allergies, running late, can\'t wait!'),
                    ),
                    if (error != null) Text(error!, style: body(13, color: const Color(0xFFB42318), weight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: HC.violet, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        onPressed: busy ? null : () => _send(info),
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Text('Send my reply', style: display(17, color: Colors.white)),
                      ),
                    ),
                  ],
                  if (!info.cancelled) _pitchIn(info),
                  const SizedBox(height: 28),
                  Center(
                    child: TextButton(
                      onPressed: widget.onPlanOwn,
                      child: const Text('🎈 Planning a party too? Plan it free with Festino'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.emoji, required this.selected, required this.onTap});
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? HC.ink : HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? HC.ink : HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(label, style: body(14, weight: FontWeight.w600, color: selected ? Colors.white : HC.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.min, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: body(15, weight: FontWeight.w600))),
          IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: display(18))),
          IconButton(onPressed: value < 50 ? () => onChanged(value + 1) : null, icon: Icon(Icons.add_circle_outline_rounded, color: HC.violet)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: HC.lime, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: body(12, weight: FontWeight.w700)),
    );
  }
}

/// One Pitch In item: free ("I'll bring it"), yours ("You're on it · Undo") or taken by someone.
class _PitchRow extends StatelessWidget {
  const _PitchRow({required this.item, required this.mine, required this.onClaim, required this.onUndo});
  final PitchItem item;
  final bool mine;
  final VoidCallback onClaim;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final taken = it.claimed && !mine;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFF1FBD9) : (taken ? HC.ground : HC.card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mine ? HC.lime : HC.line, width: mine ? 2 : 1),
      ),
      child: Row(
        children: [
          Text(it.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.label,
                  style: body(14, weight: FontWeight.w600, color: taken ? HC.muted : HC.ink)
                      .copyWith(decoration: taken ? TextDecoration.lineThrough : null),
                ),
                if (it.help) Text('Helping hand', style: body(11, color: HC.violet, weight: FontWeight.w600)),
              ],
            ),
          ),
          if (mine)
            TextButton(onPressed: onUndo, child: const Text('You\'re on it · Undo'))
          else if (taken)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: HC.track, borderRadius: BorderRadius.circular(12)),
              child: Text(it.claimedName, style: body(12, weight: FontWeight.w600)),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: HC.ink,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onClaim,
              child: Text(it.help ? 'I\'ll help' : 'I\'ll bring it'),
            ),
        ],
      ),
    );
  }
}


/// News from the host at the top of the invite page.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.color, required this.border, required this.title, required this.text, this.by = ''});
  final Color color;
  final Color border;
  final String title;
  final String text;
  final String by;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: display(19)),
          const SizedBox(height: 6),
          Text(text, style: body(15)),
          if (by.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('— ${by.trim()}', style: body(13, color: HC.muted, weight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
