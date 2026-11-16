import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// Plays the host's own recorded invitation video.
/// With [autoplay] it starts right away: muted in browsers (they block sound
/// until a tap), with a "Tap for sound" button.
class InviteClipPlayer extends StatefulWidget {
  const InviteClipPlayer({super.key, required this.url, this.autoplay = true});
  final String url;
  final bool autoplay;

  @override
  State<InviteClipPlayer> createState() => _InviteClipPlayerState();
}

class _InviteClipPlayerState extends State<InviteClipPlayer> {
  late VideoPlayerController c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool ready = false;
  bool failed = false;
  bool muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(InviteClipPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      c.dispose();
      c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      ready = false;
      failed = false;
      _init();
    }
  }

  Future<void> _init() async {
    final ctrl = c;
    try {
      await ctrl.initialize();
      ctrl.addListener(_tick);
      if (widget.autoplay) {
        if (kIsWeb) {
          muted = true;
          await ctrl.setVolume(0);
        }
        await ctrl.play();
      }
      if (mounted && ctrl == c) setState(() => ready = true);
    } catch (_) {
      if (mounted && ctrl == c) setState(() => failed = true);
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_tick);
    c.dispose();
    super.dispose();
  }

  void _toggle() {
    final v = c.value;
    if (v.isPlaying) {
      c.pause();
    } else {
      if (v.position >= v.duration && v.duration > Duration.zero) c.seekTo(Duration.zero);
      c.play();
    }
  }

  void _sound() {
    setState(() => muted = !muted);
    c.setVolume(muted ? 0 : 1);
    if (!muted && !c.value.isPlaying) c.play();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: HC.track, borderRadius: BorderRadius.circular(24)),
        child: Text('🎬 The video couldn\'t play here.', style: body(14, color: HC.muted)),
      );
    }
    if (!ready) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(24)),
        child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
      );
    }
    final v = c.value;
    final ended = !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration;
    final aspect = v.aspectRatio <= 0 ? 9 / 16 : v.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: AspectRatio(
          aspectRatio: aspect,
          child: GestureDetector(
            onTap: _toggle,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black, child: VideoPlayer(c)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: VideoProgressColors(playedColor: HC.violet, bufferedColor: Colors.white38, backgroundColor: Colors.white24),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: muted
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.black54, minimumSize: const Size(0, 36)),
                          onPressed: _sound,
                          icon: const Icon(Icons.volume_up_rounded, size: 18),
                          label: const Text('Tap for sound'),
                        )
                      : IconButton(
                          tooltip: 'Mute',
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          onPressed: _sound,
                          icon: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
                        ),
                ),
                if (!v.isPlaying)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(ended ? Icons.replay_rounded : Icons.play_arrow_rounded, size: 36, color: HC.ink, semanticLabel: ended ? 'Replay' : 'Play'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
