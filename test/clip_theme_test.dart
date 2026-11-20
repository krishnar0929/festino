import 'package:flutter_test/flutter_test.dart';
import 'package:hoopla/models/invite_video.dart';

void main() {
  test('own video keeps its theme, music and voice choice', () {
    const v = InviteVideo(clip: 'https://x/clip.mov', clipTheme: 'comic', clipMusic: 'happy_times', clipVoice: false);
    final back = InviteVideo.fromMap(v.toMap());
    expect((back.clipTheme, back.clipMusic, back.clipVoice), ('comic', 'happy_times', false));
    expect(back.clipHasMusic, isTrue);
  });

  test('old saved videos default to plain, original sound', () {
    final v = InviteVideo.fromMap({'clip': 'https://x/clip.mp4', 'clipTheme': 'nope', 'clipMusic': 'http://bad'});
    expect((v.clipTheme, v.clipMusic, v.clipVoice, v.clipHasMusic), ('none', 'original', true, false));
    expect(InviteVideo.clipThemes.keys, containsAll(['none', 'confetti', 'comic', 'frame', 'star', 'hearts', 'retro']));
  });
}
