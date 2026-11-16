import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/invite_video.dart';
import '../theme.dart';
import 'invitation_card.dart';

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
  });

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

  @override
  void initState() {
    super.initState();
    clock.addStatusListener((_) => setState(() {}));
    if (widget.autoplay) clock.forward();
  }

  @override
  void didUpdateWidget(InviteVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.photos.length != widget.photos.length || old.style != widget.style) {
      segments = _segments();
      clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
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
    setState(() {});
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
    if (s.photo == -1) return _card(opening: true, p: p);
    if (s.photo == -2) return _card(opening: false, p: p);
    return _photo(s.photo, p);
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
                  if (!clock.isAnimating)
                    Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(
                          clock.isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded,
                          size: 36,
                          color: HC.ink,
                          semanticLabel: clock.isCompleted ? 'Replay' : 'Play',
                        ),
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
