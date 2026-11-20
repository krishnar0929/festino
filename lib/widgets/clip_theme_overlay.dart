import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A fun theme drawn on top of the host's own invitation video: falling
/// confetti, comic "WOW!" bursts, a party frame, a movie-star marquee, floating
/// hearts or an old film look. It loops on its own clock while the video plays.
class ClipThemeOverlay extends StatefulWidget {
  const ClipThemeOverlay({super.key, required this.theme, required this.playing, this.title = '', this.when = ''});

  /// One of InviteVideo.clipThemes.
  final String theme;

  /// Moves only while the video plays.
  final bool playing;
  final String title;
  final String when;

  @override
  State<ClipThemeOverlay> createState() => _ClipThemeOverlayState();
}

class _ClipThemeOverlayState extends State<ClipThemeOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(ClipThemeOverlay old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing || old.theme != widget.theme) _run();
  }

  void _run() {
    if (widget.playing && widget.theme != 'none') {
      clock.repeat();
    } else {
      clock.stop();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.theme == 'none') return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: clock,
        builder: (context, _) {
          final t = clock.value;
          return switch (widget.theme) {
            'confetti' => CustomPaint(painter: _ConfettiPainter(t), size: Size.infinite),
            'comic' => _Comic(t: t),
            'frame' => _Frame(title: widget.title, when: widget.when),
            'star' => _Star(t: t, title: widget.title),
            'hearts' => CustomPaint(painter: _HeartsPainter(t), size: Size.infinite),
            'retro' => CustomPaint(painter: _FilmPainter(t), size: Size.infinite),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}

/// The retro theme also tints the video: a warm sepia.
const retroTint = ColorFilter.matrix(<double>[
  0.393, 0.769, 0.189, 0, 0,
  0.349, 0.686, 0.168, 0, 0,
  0.272, 0.534, 0.131, 0, 0,
  0, 0, 0, 1, 0,
]);

const _party = [Color(0xFFFF6B4A), Color(0xFFFFB020), Color(0xFFC8F560), Color(0xFF8B7BFF), Color(0xFF2EC4B6), Colors.white];

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(7);
    for (var i = 0; i < 46; i++) {
      final x0 = r.nextDouble() * size.width;
      final speed = 0.6 + r.nextDouble() * 0.8;
      final phase = r.nextDouble();
      final y = ((t * speed + phase) % 1.0) * (size.height + 40) - 20;
      final x = x0 + math.sin((t * 2 * math.pi * speed) + i) * 14;
      final paint = Paint()..color = _party[i % _party.length];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((t * 6 + phase) * math.pi);
      if (i.isEven) {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -2.5, 10, 5), const Radius.circular(1.5)), paint);
      } else {
        canvas.drawCircle(Offset.zero, 3.2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.t);
  final double t;

  void _heart(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx, o.dy + s * 0.35)
      ..cubicTo(o.dx - s, o.dy - s * 0.35, o.dx - s * 0.45, o.dy - s, o.dx, o.dy - s * 0.4)
      ..cubicTo(o.dx + s * 0.45, o.dy - s, o.dx + s, o.dy - s * 0.35, o.dx, o.dy + s * 0.35);
    c.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(3);
    const colors = [Color(0xFFFF5C8A), Color(0xFFFF8FB1), Color(0xFFFFFFFF), Color(0xFFFF6B4A)];
    for (var i = 0; i < 22; i++) {
      final x0 = r.nextDouble() * size.width;
      final speed = 0.4 + r.nextDouble() * 0.6;
      final phase = r.nextDouble();
      final p = (t * speed + phase) % 1.0;
      final y = size.height + 20 - p * (size.height + 40);
      final x = x0 + math.sin(p * 2 * math.pi + i) * 18;
      final s = 8 + r.nextDouble() * 10;
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: (1 - p).clamp(0.0, 1.0) * 0.9);
      _heart(canvas, Offset(x, y), s, paint);
    }
  }

  @override
  bool shouldRepaint(_HeartsPainter old) => old.t != t;
}

class _FilmPainter extends CustomPainter {
  _FilmPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Paint()..color = const Color(0xE6111111);
    final hole = Paint()..color = const Color(0xFFF5E6C8);
    const w = 18.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height), band);
    canvas.drawRect(Rect.fromLTWH(size.width - w, 0, w, size.height), band);
    final shift = (t * 4 % 1.0) * 24;
    for (var y = -24.0 + shift; y < size.height; y += 24) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5, y, 8, 12), const Radius.circular(2)), hole);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 13, y, 8, 12), const Radius.circular(2)), hole);
    }
    // Flicker and a few scratches.
    final flick = (math.sin(t * 2 * math.pi * 9) + 1) / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.03 + flick * 0.03));
    final r = math.Random((t * 30).floor());
    final scratch = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 0; i < 2; i++) {
      final x = w + r.nextDouble() * (size.width - 2 * w);
      canvas.drawLine(Offset(x, 0), Offset(x + 3, size.height), scratch);
    }
    final vignette = Paint()
      ..shader = RadialGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)], stops: const [0.6, 1])
          .createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(_FilmPainter old) => old.t != t;
}

/// "WOW!", "YAY!", "BOOM!" bursts that pop in turn.
class _Comic extends StatelessWidget {
  const _Comic({required this.t});
  final double t;

  static const words = [
    ('WOW!', Alignment(-0.6, -0.65), Color(0xFFFFB020)),
    ('YAY!', Alignment(0.6, -0.25), Color(0xFFC8F560)),
    ('BOOM!', Alignment(-0.45, 0.45), Color(0xFFFF6B4A)),
    ('PARTY!', Alignment(0.5, 0.7), Color(0xFF8B7BFF)),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < words.length; i++)
          Builder(builder: (context) {
            final start = i / words.length;
            final local = ((t - start) % 1.0) * words.length;
            final shown = local < 1.6;
            final pop = shown ? Curves.elasticOut.transform((local / 0.6).clamp(0.0, 1.0)) : 0.0;
            final fade = local > 1.2 ? (1 - (local - 1.2) / 0.4).clamp(0.0, 1.0) : 1.0;
            return Align(
              alignment: words[i].$2,
              child: Opacity(
                opacity: shown ? fade : 0,
                child: Transform.scale(
                  scale: 0.2 + pop * 0.8,
                  child: Transform.rotate(angle: (i.isEven ? -1 : 1) * 0.18, child: _Burst(text: words[i].$1, color: words[i].$3)),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _Burst extends StatelessWidget {
  const _Burst({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarburstPainter(color),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Text(
          text,
          style: GoogleFonts.bangers(fontSize: 34, color: const Color(0xFF17142B), letterSpacing: 1.5),
        ),
      ),
    );
  }
}

class _StarburstPainter extends CustomPainter {
  _StarburstPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rx = size.width / 2, ry = size.height / 2;
    final path = Path();
    const n = 14;
    for (var i = 0; i <= n * 2; i++) {
      final a = i * math.pi / n;
      final k = i.isEven ? 1.0 : 0.72;
      final p = Offset(c.dx + math.cos(a) * rx * k, c.dy + math.sin(a) * ry * k);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF17142B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_StarburstPainter old) => old.color != color;
}

/// A colorful dotted frame with a "You're invited" banner.
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.when});
  final String title;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFFF6B4A), width: 10),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _DotsPainter())),
        Positioned(
          left: 22,
          right: 22,
          bottom: 26,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xE617142B), borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('YOU\'RE INVITED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: const Color(0xFFC8F560))),
                if (title.isNotEmpty)
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GoogleFonts.kaushanScript(fontSize: 24, color: Colors.white)),
                if (when.isNotEmpty) Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE4DDFF))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var i = 0;
    void dot(Offset o) => canvas.drawCircle(o, 3.5, Paint()..color = _party[(i++) % 4 + 1]);
    for (var x = 20.0; x < size.width - 10; x += 22) {
      dot(Offset(x, 5));
      dot(Offset(x, size.height - 5));
    }
    for (var y = 20.0; y < size.height - 10; y += 22) {
      dot(Offset(5, y));
      dot(Offset(size.width - 5, y));
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

/// Movie-star look: a lit marquee on top and "Starring" credits below.
class _Star extends StatelessWidget {
  const _Star({required this.t, required this.title});
  final double t;
  final String title;

  @override
  Widget build(BuildContext context) {
    final on = (t * 12).floor();
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            color: const Color(0xE617142B),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 12; i++)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (i + on).isEven ? const Color(0xFFFFD54F) : const Color(0x55FFD54F),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('★ NOW SHOWING ★', style: GoogleFonts.bangers(fontSize: 24, color: const Color(0xFFFFD54F), letterSpacing: 2)),
              ],
            ),
          ),
        ),
        if (title.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                Text('STARRING IN', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white)),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.bangers(fontSize: 30, color: const Color(0xFFFFD54F), letterSpacing: 1.5, shadows: const [Shadow(color: Colors.black, blurRadius: 6)]),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
