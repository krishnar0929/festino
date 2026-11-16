/// The 30-second invitation video: photos that play as an animated slideshow
/// (zoom, fades and captions) when guests open the invite link.
class InviteVideo {
  const InviteVideo({this.photos = const [], this.captions = const [], this.style = 'fun'});

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
      };

  factory InviteVideo.fromMap(Object? v) {
    if (v is! Map) return const InviteVideo();
    List<String> strings(Object? l) => [for (final x in (l is List ? l : const [])) if (x is String) x];
    final style = v['style'] is String && styles.containsKey(v['style']) ? v['style'] as String : 'fun';
    return InviteVideo(photos: strings(v['photos']).take(maxPhotos).toList(), captions: strings(v['captions']), style: style);
  }
}
