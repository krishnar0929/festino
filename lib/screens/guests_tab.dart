import 'package:flutter/material.dart';

import '../models/event_details.dart';
import '../services/invite_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/invitation_card.dart';
import 'invite_screen.dart';
import 'sign_in_screen.dart';

/// Guests tab: your invitation, one big Share button, and three numbers.
/// Design, video, the guest list and Pitch In open from here.
class GuestsTab extends StatefulWidget {
  const GuestsTab({super.key});

  @override
  State<GuestsTab> createState() => _GuestsTabState();
}

class _GuestsTabState extends State<GuestsTab> {
  Future<List<Rsvp>?>? future;
  String? _key;

  void _load(AppState state) {
    final uid = state.isSignedIn ? state.accounts?.user?.uid : null;
    final e = state.event!;
    _key = '$uid|${e.id}|${e.updatedAt}';
    future = uid == null
        ? Future.value(null)
        : InviteService.rsvps(inviteIdFor(uid, e.id)).then<List<Rsvp>?>((v) => v).catchError((_) => null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final uid = state.isSignedIn ? state.accounts?.user?.uid : null;
    if (state.event != null && '$uid|${state.event!.id}|${state.event!.updatedAt}' != _key) _load(state);
  }

  void _open({int tab = 0, int guestTab = 0, bool share = false}) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => InviteScreen(initialTab: tab, guestTab: guestTab, shareOnOpen: share)))
        .then((_) {
      if (mounted) setState(() => _load(AppScope.of(context)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Guests', style: display(28))),
            if (state.isSignedIn) TextButton(onPressed: () => _open(), child: const Text('Edit invitation')),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: state.isSignedIn ? () => _open() : null,
          child: _MiniCard(event: e),
        ),
        const SizedBox(height: 14),
        if (!state.isSignedIn) ...[
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: HC.violet,
              minimumSize: const Size(0, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => const SignInScreen(reason: 'Sign in free to send invites and see who\'s coming.'),
            )),
            child: Text('Sign in free to send invites', style: body(16, color: Colors.white, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text('So guests\' replies come back to you.', textAlign: TextAlign.center, style: body(13, color: HC.muted)),
        ] else ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: HC.violet,
              minimumSize: const Size(0, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () => _open(tab: 1, share: true),
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            label: Text('Share invitation', style: body(16, color: Colors.white, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text('WhatsApp, Messages, email, or any app', textAlign: TextAlign.center, style: body(13, color: HC.muted)),
          const SizedBox(height: 16),
          FutureBuilder<List<Rsvp>?>(
            future: future,
            builder: (context, snap) {
              final board = groupGuests(e.invitees, snap.data ?? const <Rsvp>[]);
              final pending = board.pending.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Count(n: board.going.length, label: 'Going', bg: const Color(0xFFE3F6EC), fg: const Color(0xFF1F6E43), onTap: () => _open(tab: 2, guestTab: 0))),
                      const SizedBox(width: 10),
                      Expanded(child: _Count(n: pending, label: 'Pending', bg: const Color(0xFFFFF1C2), fg: const Color(0xFF7A5400), onTap: () => _open(tab: 2, guestTab: 1))),
                      const SizedBox(width: 10),
                      Expanded(child: _Count(n: board.cantGo.length, label: 'Can\'t go', bg: const Color(0xFFFFE4DE), fg: const Color(0xFF9A2F1A), onTap: () => _open(tab: 2, guestTab: 2))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pending > 0)
                    _Row(
                      icon: Icons.notifications_active_outlined,
                      label: 'Remind the $pending who haven\'t replied',
                      onTap: () => _open(tab: 2, guestTab: 1),
                    ),
                  _Row(icon: Icons.person_add_alt_1_outlined, label: e.invitees.isEmpty ? 'Add your guest list' : 'Add more guests', onTap: () => _open(tab: 1)),
                  _Row(icon: Icons.movie_creation_outlined, label: e.inviteVideo.isEmpty ? 'Add an invitation video' : 'Edit invitation video', onTap: () => _open()),
                  _Row(icon: Icons.volunteer_activism_outlined, label: 'See all guests and Pitch In', onTap: () => _open(tab: 2)),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// A short preview of the invitation: photo, "You're invited", title and date.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.event});
  final EventDetails event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final t = inviteThemeFor(e.inviteTheme);
    final title = e.inviteTitle.trim().isEmpty ? e.title : e.inviteTitle.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.invitePhoto.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: Image.network(
                  e.invitePhoto,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ] else if (e.inviteMotif.isNotEmpty) ...[
            Text(e.inviteMotif, style: const TextStyle(fontSize: 30, letterSpacing: 4)),
            const SizedBox(height: 10),
          ],
          Text('YOU\'RE INVITED', style: body(12, color: t.accent, weight: FontWeight.w700).copyWith(letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(26, color: t.text)),
          const SizedBox(height: 6),
          Text(inviteWhen(e), maxLines: 2, overflow: TextOverflow.ellipsis, style: body(14, color: t.text.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.n, required this.label, required this.bg, required this.fg, required this.onTap});
  final int n;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$n', style: display(28, color: fg)),
              const SizedBox(height: 2),
              Text(label, style: body(13, color: fg, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: HC.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                Icon(icon, size: 22, color: HC.violet),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: body(15, weight: FontWeight.w600))),
                const Icon(Icons.chevron_right_rounded, color: HC.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
