/// The 30-second invitation video: photos that play as an animated slideshow
/// (zoom, fades and captions) when guests open the invite link.
class InviteVideo {
  const InviteVideo({
    this.photos = const [],
    this.captions = const [],
    this.style = 'fun',
    this.music = defaultMusic,
    this.look = 'classic',
    this.clip = '',
    this.clipAutoplay = true,
    this.sendClip = true,
    this.clipTheme = 'none',
    this.clipMusic = 'original',
    this.clipVoice = true,
  });

  /// Fun themes laid over the host's own video (confetti, comic bursts, frames…).
  static const clipThemes = {
    'none': '🎬 Plain',
    'confetti': '🎉 Confetti',
    'comic': '💥 Comic pop',
    'frame': '🎈 Party frame',
    'star': '⭐ Movie star',
    'hearts': '💖 Hearts',
    'retro': '📼 Retro film',
  };

  /// One of [clipThemes].
  final String clipTheme;

  /// Background music for the own video: 'original' (just the video's sound),
  /// a built-in track id, or a link to a song (https://… .mp3).
  final String clipMusic;

  /// Keep the video's own sound (voices) under the music.
  final bool clipVoice;

  bool get clipHasMusic => clipMusic != 'original' && clipMusic.isNotEmpty;

  /// Fun themes that turn the photos into a "star" video.
  static const looks = {
    'classic': '✨ Classic',
    'soccer': '⚽ Soccer star',
    'football': '🏈 Football MVP',
    'superhero': '🦸 Superhero',
    'rockstar': '🎸 Rock star',
    'princess': '👑 Princess',
    'astronaut': '🚀 Astronaut',
  };

  /// 'classic' or one of [looks].
  final String look;

  /// The host's own recorded video (download link), or '' to use the photos.
  final String clip;

  /// Play the recorded video as soon as guests open the invite.
  final bool clipAutoplay;

  /// Attach the recorded video file when sharing the invitation.
  final bool sendClip;

  bool get hasClip => clip.isNotEmpty;

  /// Built-in background music (30-second clips in assets/music).
  static const tracks = {
    'celebration': ('Celebration', 'assets/music/celebration.mp3'),
    'happy_times': ('Happy times', 'assets/music/happy_times.mp3'),
  };
  static const defaultMusic = 'celebration';

  /// A built-in track id, 'none', or a link to a song (https://… .mp3).
  final String music;

  bool get hasMusic => music != 'none' && music.isNotEmpty;
  bool get customMusic => music.startsWith('https://');

  String get musicLabel => !hasMusic ? 'No music' : (customMusic ? 'Your song' : (tracks[music]?.$1 ?? 'Celebration'));

  static const maxPhotos = 10;
  static const seconds = 30;

  /// 'fun' (lively zooms), 'elegant' (slow fades) or 'calm' (gentle drift).
  static const styles = {'fun': 'Fun', 'elegant': 'Elegant', 'calm': 'Calm'};

  /// Download links (Firebase Storage), in play order. The first is the cover.
  final List<String> photos;

  /// One caption per photo ('' for none).
  final List<String> captions;
  final String style;

  bool get isEmpty => photos.isEmpty && clip.isEmpty;

  String captionAt(int i) => i < captions.length ? captions[i] : '';

  Map<String, dynamic> toMap() => {
        'photos': photos.take(maxPhotos).toList(),
        'captions': [for (var i = 0; i < photos.length && i < maxPhotos; i++) captionAt(i)],
        'style': style,
        'music': music,
        'look': look,
        'clip': clip,
        'clipAutoplay': clipAutoplay,
        'sendClip': sendClip,
        'clipTheme': clipTheme,
        'clipMusic': clipMusic,
        'clipVoice': clipVoice,
      };

  factory InviteVideo.fromMap(Object? v) {
    if (v is! Map) return const InviteVideo();
    List<String> strings(Object? l) => [for (final x in (l is List ? l : const [])) if (x is String) x];
    final style = v['style'] is String && styles.containsKey(v['style']) ? v['style'] as String : 'fun';
    final m = v['music'];
    final music = m is String && (m == 'none' || tracks.containsKey(m) || (m.startsWith('https://') && m.length <= 500)) ? m : defaultMusic;
    final look = v['look'] is String && looks.containsKey(v['look']) ? v['look'] as String : 'classic';
    final clip = v['clip'] is String && (v['clip'] as String).startsWith('https://') ? v['clip'] as String : '';
    final ct = v['clipTheme'];
    final cm = v['clipMusic'];
    final clipMusic = cm is String && (cm == 'original' || tracks.containsKey(cm) || (cm.startsWith('https://') && cm.length <= 500)) ? cm : 'original';
    return InviteVideo(
      photos: strings(v['photos']).take(maxPhotos).toList(),
      captions: strings(v['captions']),
      style: style,
      music: music,
      look: look,
      clip: clip,
      clipAutoplay: v['clipAutoplay'] is bool ? v['clipAutoplay'] as bool : true,
      sendClip: v['sendClip'] is bool ? v['sendClip'] as bool : true,
      clipTheme: ct is String && clipThemes.containsKey(ct) ? ct : 'none',
      clipMusic: clipMusic,
      clipVoice: v['clipVoice'] is bool ? v['clipVoice'] as bool : true,
    );
  }
}
