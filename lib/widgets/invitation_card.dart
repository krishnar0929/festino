import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// A look for the invitation card.
class InviteTheme {
  const InviteTheme({
    required this.id,
    required this.name,
    required this.colors,
    required this.accent,
    required this.text,
    required this.muted,
    required this.panel,
  });

  final String id;
  final String name;
  final List<Color> colors;

  /// "YOU'RE INVITED" and the icons.
  final Color accent;
  final Color text;
  final Color muted;

  /// Background of the message box.
  final Color panel;
}

const inviteThemes = <InviteTheme>[
  InviteTheme(
    id: 'midnight',
    name: 'Midnight',
    colors: [HC.ink, Color(0xFF3B2C8F)],
    accent: HC.lime,
    text: Colors.white,
    muted: HC.nightMuted,
    panel: Color(0x1FFFFFFF),
  ),
  InviteTheme(
    id: 'confetti',
    name: 'Confetti',
    colors: [Color(0xFF6C4CF5), Color(0xFFFF5FA2)],
    accent: Color(0xFFFFE066),
    text: Colors.white,
    muted: Color(0xFFF6EBFF),
    panel: Color(0x26FFFFFF),
  ),
  InviteTheme(
    id: 'sunshine',
    name: 'Sunshine',
    colors: [Color(0xFFFFB347), Color(0xFFFFE29A)],
    accent: Color(0xFF8A3200),
    text: HC.ink,
    muted: Color(0xFF5C4A2E),
    panel: Color(0x40FFFFFF),
  ),
  InviteTheme(
    id: 'garden',
    name: 'Garden',
    colors: [Color(0xFF1F6F50), Color(0xFF6DBB75)],
    accent: Color(0xFFFFF3B0),
    text: Colors.white,
    muted: Color(0xFFE2F5E9),
    panel: Color(0x26FFFFFF),
  ),
  InviteTheme(
    id: 'blush',
    name: 'Blush',
    colors: [Color(0xFFFFC9D6), Color(0xFFFFF1F4)],
    accent: Color(0xFFC2255C),
    text: HC.ink,
    muted: Color(0xFF7A5560),
    panel: Color(0x66FFFFFF),
  ),
  InviteTheme(
    id: 'ocean',
    name: 'Ocean',
    colors: [Color(0xFF0B3D91), Color(0xFF2EC4B6)],
    accent: Color(0xFFB8F2E6),
    text: Colors.white,
    muted: Color(0xFFD7F3F0),
    panel: Color(0x26FFFFFF),
  ),
];

InviteTheme inviteThemeFor(String id) => inviteThemes.firstWhere((t) => t.id == id, orElse: () => inviteThemes.first);

/// The invitation itself: optional photo, headline, host, when and where, and a note.
class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.theme,
    required this.title,
    required this.when,
    this.hostName = '',
    this.place = '',
    this.message = '',
    this.photoUrl = '',
    this.photoBytes,
    this.onPlaceTap,
  });

  final InviteTheme theme;
  final String title;
  final String when;
  final String hostName;
  final String place;
  final String message;
  final String photoUrl;

  /// A photo picked on this device (shown before or instead of [photoUrl]).
  final Uint8List? photoBytes;
  final VoidCallback? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final hasPhoto = photoBytes != null || photoUrl.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPhoto)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: photoBytes != null
                  ? Image.memory(photoBytes!, fit: BoxFit.cover)
                  : Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, __, ___) => Container(color: t.panel, alignment: Alignment.center, child: const Text('🎉', style: TextStyle(fontSize: 48))),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOU\'RE INVITED', style: overline(color: t.accent)),
                const SizedBox(height: 8),
                Text(title.isEmpty ? 'Our party' : title, style: display(30, color: t.text)),
                if (hostName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Hosted by $hostName', style: body(14, color: t.muted)),
                ],
                const SizedBox(height: 18),
                _Line(icon: Icons.event_rounded, text: when, theme: t),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(onTap: onPlaceTap, child: _Line(icon: Icons.place_rounded, text: place, theme: t, link: onPlaceTap != null)),
                ],
                if (message.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: t.panel, borderRadius: BorderRadius.circular(16)),
                    child: Text(message.trim(), style: body(15, color: t.text)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.theme, this.link = false});
  final IconData icon;
  final String text;
  final InviteTheme theme;
  final bool link;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: body(15, color: theme.text, weight: FontWeight.w600)
                .copyWith(decoration: link ? TextDecoration.underline : null, decorationColor: theme.muted),
          ),
        ),
      ],
    );
  }
}
