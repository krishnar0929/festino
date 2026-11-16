/// How a photo sits in the invitation: its shape, which part shows, and zoom.
class PhotoFrame {
  const PhotoFrame({this.shape = 'whole', this.x = 0, this.y = 0, this.zoom = 1});

  /// 'whole' (the full photo, nothing cut), 'square', 'wide' (4:3) or 'tall' (4:5).
  final String shape;

  /// Which part of the photo shows, from -1 (left/top) to 1 (right/bottom).
  final double x;
  final double y;

  /// 1 to 3.
  final double zoom;

  static const shapes = {'whole': 'Whole photo', 'square': 'Square', 'wide': 'Wide', 'tall': 'Tall'};

  bool get whole => shape == 'whole' || !shapes.containsKey(shape);

  /// Width ÷ height of the frame (null = the photo's own shape).
  double? get aspect => switch (shape) {
        'square' => 1,
        'wide' => 4 / 3,
        'tall' => 4 / 5,
        _ => null,
      };

  PhotoFrame copyWith({String? shape, double? x, double? y, double? zoom}) => PhotoFrame(
        shape: shape ?? this.shape,
        x: (x ?? this.x).clamp(-1.0, 1.0),
        y: (y ?? this.y).clamp(-1.0, 1.0),
        zoom: (zoom ?? this.zoom).clamp(1.0, 3.0),
      );

  Map<String, dynamic> toMap() => {'shape': shape, 'x': x, 'y': y, 'zoom': zoom};

  factory PhotoFrame.fromMap(Object? v) {
    if (v is! Map) return const PhotoFrame();
    double n(Object? o, double d) => o is num ? o.toDouble() : d;
    return const PhotoFrame().copyWith(
      shape: v['shape'] is String ? v['shape'] as String : 'whole',
      x: n(v['x'], 0),
      y: n(v['y'], 0),
      zoom: n(v['zoom'], 1),
    );
  }
}
