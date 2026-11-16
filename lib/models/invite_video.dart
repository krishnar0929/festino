/// The 30-second invitation video: photos that play as an animated slideshow
/// (zoom, fades and captions) when guests open the invite link.
class InviteVideo {
  const InviteVideo({this.photos = const [], this.captions = const [], this.style = 'fun', this.music = defaultMusic});

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

  bool get isEmpty => photos.isEmpty;

  String captionAt(int i) => i < captions.length ? captions[i] : '';

  Map<String, dynamic> toMap() => {
        'photos': photos.take(maxPhotos).toList(),
        'captions': [for (var i = 0; i < photos.length && i < maxPhotos; i++) captionAt(i)],
        'style': style,
        'music': music,
      };

  factory InviteVideo.fromMap(Object? v) {
    if (v is! Map) return const InviteVideo();
    List<String> strings(Object? l) => [for (final x in (l is List ? l : const [])) if (x is String) x];
    final style = v['style'] is String && styles.containsKey(v['style']) ? v['style'] as String : 'fun';
    final m = v['music'];
    final music = m is String && (m == 'none' || tracks.containsKey(m) || (m.startsWith('https://') && m.length <= 500)) ? m : defaultMusic;
    return InviteVideo(photos: strings(v['photos']).take(maxPhotos).toList(), captions: strings(v['captions']), style: style, music: music);
  }
}
