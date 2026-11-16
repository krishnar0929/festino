import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/invite_video.dart';
import '../theme.dart';
import 'invitation_card.dart';

/// A fun "star" theme: scene colors, flying props, a banner and cheers.
class StarLook {
  const StarLook({required this.banner, required this.colors, required this.props, required this.cheers, this.field = false, this.text = Colors.white});
  final String banner;
  final List<Color> colors;
  final List<String> props;
  final List<String> cheers;

  /// Draw sports-field lines behind the player card.
  final bool field;
  final Color text;
}

const starLooks = <String, StarLook>{
  'soccer': StarLook(
    banner: 'BIRTHDAY ALL-STAR',
    colors: [Color(0xFF0B7A3B), Color(0xFF39B54A)],
    props: ['⚽', '🥅', '👟', '🏆', '👏', '⭐'],
    cheers: ['GOOOAL! ⚽', 'What a shot!', 'Team captain! 🏆', 'Crowd goes wild! 👏'],
    field: true,
  ),
  'football': StarLook(
    banner: 'BIRTHDAY MVP',
    colors: [Color(0xFF1B4D1B), Color(0xFF3E7D2C)],
    props: ['🏈', '🏆', '📣', '👏', '⭐', '🎉'],
    cheers: ['TOUCHDOWN! 🏈', 'MVP! MVP!', 'What a throw!', 'Hall of fame! 🏆'],
    field: true,
  ),
  'superhero': StarLook(
    banner: 'HERO OF THE DAY',
    colors: [Color(0xFFC1121F), Color(0xFF1D3557)],
    props: ['💥', '⚡', '🦸', '✨', '🌟', '🛡️'],
    cheers: ['POW! 💥', 'Super strength! 💪', 'To the rescue! 🦸', 'Saving the day ⚡'],
  ),
  'rockstar': StarLook(
    banner: 'ROCK STAR',
    colors: [Color(0xFF1A1A2E), Color(0xFF7B2CBF)],
    props: ['🎸', '🎤', '🎶', '⭐', '🤘', '🔥'],
    cheers: ['Encore! 🎤', 'Rock on! 🤘', 'Sold-out show!', 'Living legend 🔥'],
  ),
  'princess': StarLook(
    banner: 'PRINCESS PARTY',
    colors: [Color(0xFFFF8FB1), Color(0xFFFFD6E7)],
    props: ['👑', '✨', '🦄', '💖', '🏰', '🌸'],
    cheers: ['Your royal highness 👑', 'So magical ✨', 'Once upon a time…', 'Sparkle on! 💖'],
    text: Color(0xFF5A1033),
  ),
  'astronaut': StarLook(
    banner: 'BLAST OFF!',
    colors: [Color(0xFF0B1026), Color(0xFF2B2D6E)],
    props: ['🚀', '🪐', '⭐', '🌙', '👽', '☄️'],
    cheers: ['To the moon! 🚀', 'Out of this world!', 'Star explorer ⭐', 'Houston, we have a party!'],
  ),
};

/// Plays the invitation video: a title card, the photos with zooms, fades and
/// captions, and a "see you there" card. 30 seconds, story-style progress bars.
/// Tap to pause; a replay button shows at the end.
class InviteVideoPlayer extends StatefulWidget {
  const InviteVideoPlayer({
    super.key,
    required this.photos,
    required this.captions,
    required this.style,
    required this.theme,
    required this.title,
    this.when = '',
    this.motif = '',
    this.autoplay = true,
    this.music = 'none',
    this.look = 'classic',
  });

  /// 'classic' or a [starLooks] theme (Soccer star, Football MVP, …).
  final String look;

  /// Background music: a built-in track id, 'none', or an https link to a song.
  final String music;

  /// Each item is a download link (String) or picked bytes (Uint8List).
  final List<Object> photos;
  final List<String> captions;
  final String style;
  final InviteTheme theme;
  final String title;
  final String when;
  final String motif;
  final bool autoplay;

  @override
  State<InviteVideoPlayer> createState() => _InviteVideoPlayerState();
}

class _Segment {
  const _Segment(this.start, this.end, this.photo);
  final double start;
  final double end;

  /// Photo index, -1 for the title card, -2 for the closing card.
  final int photo;
  double progress(double t) => ((t - start) / (end - start)).clamp(0.0, 1.0);
}

class _InviteVideoPlayerState extends State<InviteVideoPlayer> with SingleTickerProviderStateMixin {
  static const total = InviteVideo.seconds * 1.0;
  late final AnimationController clock = AnimationController(vsync: this, duration: const Duration(seconds: InviteVideo.seconds));
  late List<_Segment> segments = _segments();

  List<_Segment> _segments() {
    const intro = 3.5, outro = 3.5;
    final n = widget.photos.length;
    final each = n == 0 ? 0.0 : (total - intro - outro) / n;
    return [
      const _Segment(0, intro, -1),
      for (var i = 0; i < n; i++) _Segment(intro + i * each, intro + (i + 1) * each, i),
      _Segment(total - (n == 0 ? total - intro : outro), total, -2),
    ];
  }

  VideoPlayerController? audio;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    clock.addStatusListener((s) {
      if (s == AnimationStatus.completed) audio?.pause();
      setState(() {});
    });
    _loadMusic();
    // Browsers only allow sound after a tap, so on the web the video waits for one.
    if (widget.autoplay) clock.forward();
  }

  Future<void> _loadMusic() async {
    final m = widget.music;
    if (m.isEmpty || m == 'none') return;
    final c = m.startsWith('https://')
        ? VideoPlayerController.networkUrl(Uri.parse(m))
        : VideoPlayerController.asset(InviteVideo.tracks[m]?.$2 ?? InviteVideo.tracks.values.first.$2);
    audio = c;
    try {
      await c.initialize();
      await c.setVolume(muted ? 0 : 1);
      if (!mounted || audio != c) return;
      if (clock.isAnimating) await _syncMusic();
    } catch (_) {
      if (audio == c) audio = null;
      c.dispose();
    }
    if (mounted) setState(() {});
  }

  /// Keeps the music at the same moment as the pictures.
  Future<void> _syncMusic() async {
    final c = audio;
    if (c == null || !c.value.isInitialized) return;
    if (clock.isAnimating) {
      final at = Duration(milliseconds: (clock.value * InviteVideo.seconds * 1000).round());
      final len = c.value.duration;
      await c.seekTo(len > Duration.zero && at > len ? Duration(milliseconds: at.inMilliseconds % len.inMilliseconds) : at);
      await c.play();
    } else {
      await c.pause();
    }
  }

  @override
  void didUpdateWidget(InviteVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.music != widget.music) {
      audio?.dispose();
      audio = null;
      _loadMusic();
    }
    if (old.photos.length != widget.photos.length || old.style != widget.style || old.look != widget.look) {
      segments = _segments();
      clock.forward(from: 0);
      _syncMusic();
    }
  }

  @override
  void dispose() {
    audio?.dispose();
    clock.dispose();
    super.dispose();
  }

  void _toggle() {
    if (clock.isCompleted) {
      clock.forward(from: 0);
    } else if (clock.isAnimating) {
      clock.stop();
    } else {
      clock.forward();
    }
    _syncMusic();
    setState(() {});
  }

  void _toggleMute() {
    setState(() => muted = !muted);
    audio?.setVolume(muted ? 0 : 1);
  }

  /// Zoom range and fade length for the chosen style.
  (double, double, double) get _feel => switch (widget.style) {
        'elegant' => (1.04, 1.16, 1.0),
        'calm' => (1.0, 1.08, 0.8),
        _ => (1.0, 1.28, 0.45),
      };

  Widget _image(Object src) {
    if (src is Uint8List) return Image.memory(src, fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true);
    return Image.network(
      src as String,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (_, __, ___) => Container(color: widget.theme.colors.first),
    );
  }

  Widget _photo(int i, double p) {
    final (from, to, _) = _feel;
    // Each photo drifts a different way so the video feels alive.
    final dir = const [Alignment.topLeft, Alignment.bottomRight, Alignment.topRight, Alignment.bottomLeft, Alignment.center][i % 5];
    final caption = i < widget.captions.length ? widget.captions[i].trim() : '';
    final capIn = ((p - 0.15) / 0.2).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: Transform.scale(
            scale: from + (to - from) * Curves.easeOut.transform(p),
            alignment: dir,
            child: _image(widget.photos[i]),
          ),
        ),
        if (caption.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 22,
            child: Opacity(
              opacity: capIn,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - Curves.easeOutBack.transform(capIn))),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
                    child: Text(caption, textAlign: TextAlign.center, style: display(20, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card({required bool opening, required double p}) {
    final t = widget.theme;
    final pop = Curves.easeOutBack.transform(((p) / 0.35).clamp(0.0, 1.0));
    final fun = widget.style == 'fun';
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Transform.scale(
          scale: 0.85 + 0.15 * pop,
          child: Opacity(
            opacity: pop.clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.motif.isNotEmpty || fun)
                  Transform.rotate(
                    angle: fun ? math.sin(p * math.pi * 4) * 0.08 : 0,
                    child: Text(widget.motif.isNotEmpty ? widget.motif : '🎉', style: const TextStyle(fontSize: 44, letterSpacing: 6)),
                  ),
                const SizedBox(height: 14),
                Text(opening ? 'YOU\'RE INVITED' : 'SEE YOU THERE!', style: overline(color: t.accent)),
                const SizedBox(height: 8),
                Text(widget.title, textAlign: TextAlign.center, style: display(30, color: t.text)),
                if (widget.when.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(widget.when, textAlign: TextAlign.center, style: body(15, color: t.muted, weight: FontWeight.w600)),
                ],
                if (!opening) ...[
                  const SizedBox(height: 14),
                  Text('Tap RSVP below 👇', style: body(15, color: t.text, weight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(_Segment s, double t) {
    final p = s.progress(t);
    final star = starLooks[widget.look];
    if (star != null) {
      if (s.photo < 0) return _starCard(star, opening: s.photo == -1, p: p, t: t);
      return _starPhoto(star, s.photo, p, t);
    }
    if (s.photo == -1) return _card(opening: true, p: p);
    if (s.photo == -2) return _card(opening: false, p: p);
    return _photo(s.photo, p);
  }

  /// Scene behind a star slide: colors, field lines and flying props.
  Widget _scene(StarLook look, double t, {required Widget child}) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: BoxDecoration(gradient: LinearGradient(colors: look.colors, begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            if (look.field) CustomPaint(painter: _FieldPainter()),
            for (var k = 0; k < 9; k++)
              Positioned(
                left: (((k * 0.137 + t * (k.isEven ? 0.035 : -0.028)) % 1.0 + 1.0) % 1.0) * w - 16,
                top: (0.08 + ((k * 0.381) % 0.84)) * h + math.sin(t * 2.4 + k) * 14,
                child: Transform.rotate(
                  angle: math.sin(t * 1.7 + k * 2) * 0.5,
                  child: Opacity(opacity: 0.85, child: Text(look.props[k % look.props.length], style: TextStyle(fontSize: 22.0 + (k % 3) * 8))),
                ),
              ),
            child,
          ],
        );
      },
    );
  }

  Widget _banner(StarLook look, double p) {
    final pop = Curves.easeOutBack.transform((p / 0.25).clamp(0.0, 1.0));
    return Transform.scale(
      scale: 0.6 + 0.4 * pop,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFFFFD84D), borderRadius: BorderRadius.circular(10)),
        child: Text(look.banner, style: display(20, color: HC.ink)),
      ),
    );
  }

  Widget _starPhoto(StarLook look, int i, double p, double t) {
    final pop = Curves.easeOutBack.transform((p / 0.25).clamp(0.0, 1.0));
    final caption = i < widget.captions.length && widget.captions[i].trim().isNotEmpty ? widget.captions[i].trim() : look.cheers[i % look.cheers.length];
    final capIn = ((p - 0.2) / 0.2).clamp(0.0, 1.0);
    final flash = (1 - p * 6).clamp(0.0, 1.0);
    return _scene(
      look,
      t,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: 34, left: 0, right: 0, child: Center(child: _banner(look, p))),
          Center(
            child: Transform.rotate(
              angle: math.sin(p * math.pi * 2) * 0.05 + (i.isEven ? -0.03 : 0.03),
              child: Transform.scale(
                scale: (0.55 + 0.45 * pop) * (1 + 0.06 * p),
                child: FractionallySizedBox(
                  widthFactor: 0.66,
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: _image(widget.photos[i])),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Opacity(
              opacity: capIn,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - Curves.easeOutBack.transform(capIn))),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                    child: Text(caption, textAlign: TextAlign.center, style: display(20, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
          if (flash > 0) IgnorePointer(child: Container(color: Colors.white.withValues(alpha: flash * 0.7))),
        ],
      ),
    );
  }

  Widget _starCard(StarLook look, {required bool opening, required double p, required double t}) {
    final pop = Curves.easeOutBack.transform((p / 0.35).clamp(0.0, 1.0));
    return _scene(
      look,
      t,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Transform.scale(
            scale: 0.8 + 0.2 * pop,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _banner(look, p),
                const SizedBox(height: 16),
                Text(opening ? 'YOU\'RE INVITED' : 'SEE YOU THERE!', style: overline(color: look.text)),
                const SizedBox(height: 8),
                Text(widget.title, textAlign: TextAlign.center, style: display(30, color: look.text)),
                if (widget.when.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(widget.when, textAlign: TextAlign.center, style: body(15, color: look.text, weight: FontWeight.w700)),
                ],
                if (!opening) ...[
                  const SizedBox(height: 14),
                  Text('Tap RSVP below 👇', style: body(15, color: look.text, weight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: clock,
            builder: (context, _) {
              final t = clock.value * total;
              var i = segments.indexWhere((s) => t < s.end);
              if (i < 0) i = segments.length - 1;
              final s = segments[i];
              final fade = _feel.$3;
              final crossfade = i > 0 && t - s.start < fade;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (crossfade) _segment(segments[i - 1], t),
                  Opacity(opacity: crossfade ? ((t - s.start) / fade).clamp(0.0, 1.0) : 1, child: _segment(s, t)),
                  // Story-style progress bars.
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: Row(
                      children: [
                        for (final seg in segments)
                          Expanded(
                            flex: ((seg.end - seg.start) * 10).round().clamp(1, 1000),
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: seg.progress(t),
                                child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.music != 'none' && widget.music.isNotEmpty)
                    Positioned(
                      right: 8,
                      top: 20,
                      child: IconButton(
                        tooltip: muted ? 'Sound on' : 'Mute',
                        onPressed: _toggleMute,
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35)),
                        icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  if (!clock.isAnimating)
                    Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Icon(
                              clock.isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded,
                              size: 36,
                              color: HC.ink,
                              semanticLabel: clock.isCompleted ? 'Replay' : 'Play',
                            ),
                          ),
                          if (clock.value == 0) ...[
                            const SizedBox(height: 10),
                            Text(
                              widget.music != 'none' && widget.music.isNotEmpty ? 'Tap to play with music 🎵' : 'Tap to play',
                              style: body(14, color: Colors.white, weight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


/// White field lines for the soccer and football themes.
class _FieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (var k = 1; k < 6; k++) {
      final y = size.height * k / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width * 0.18, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
