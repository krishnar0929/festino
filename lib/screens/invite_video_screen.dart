import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker;
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../models/invite_video.dart';
import '../services/invite_service.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/invitation_card.dart';
import '../widgets/invite_video_player.dart';

/// Photos that make a great invitation video, by event type.
const videoShotIdeas = <String, List<String>>{
  'Birthday': ['A baby or throwback photo', 'Favorite moments from this year', 'A photo with family', 'Last year\'s cake', 'A big smile or funny face'],
  'Housewarming': ['The front door or keys', 'Your favorite room', 'Moving day', 'The garden or view', 'The family at the new home'],
  'Baby shower': ['The bump', 'The couple together', 'Baby clothes or shoes', 'The nursery', 'Scan or announcement photo'],
  'Pooja': ['The deity or altar', 'Diyas and flowers', 'Last year\'s pooja', 'The family', 'Rangoli or decorations'],
  'Anniversary': ['Your wedding photo', 'Your first photo together', 'Favorite trip', 'Photos through the years', 'You two today'],
  'Get-together': ['Last time the gang met', 'The place or backyard', 'Food you\'ll serve', 'A group selfie', 'Something fun planned'],
};

/// Short captions that read well over a photo.
const videoCaptionIdeas = <String, List<String>>{
  'Birthday': ['Look who\'s turning 1! 🎂', 'Our favorite little human', 'One year of smiles 😊', 'Cake time is coming 🎉', 'Party time! 🥳'],
  'Housewarming': ['We got the keys! 🔑', 'Home sweet home 🏡', 'Come see our new place', 'New home, new memories', 'Doors open for you'],
  'Baby shower': ['Baby on the way 🍼', 'Our little miracle', 'Counting down the days', 'Love grows here 💕', 'Shower us with love'],
  'Pooja': ['With blessings 🙏', 'Join us in prayer', 'Light and joy 🪔', 'Together in devotion', 'Prasadam after pooja'],
  'Anniversary': ['Where it all began 💍', 'Still crazy about you', 'Years of love ❤️', 'Here\'s to us 🥂', 'Our story so far'],
  'Get-together': ['Long time no see! 👋', 'Good food, great friends', 'Let\'s make memories', 'The gang is back', 'See you there! 🎉'],
};

/// The style that suits each event best.
String suggestedVideoStyle(String occasion) => switch (occasion) {
      'Anniversary' || 'Pooja' => 'elegant',
      'Baby shower' => 'calm',
      _ => 'fun',
    };

const videoTips = [
  '6–10 photos make a great 30-second video.',
  'Put your best photo first. It\'s the cover.',
  'Mix close-ups with group photos.',
  'Short captions (under 5 words) read best.',
  'Upright (portrait) photos fill the screen best.',
];

class _Slide {
  _Slide({this.url, this.bytes, this.caption = ''});
  String? url;
  Uint8List? bytes;
  String caption;
  Object get source => bytes ?? url!;
}

/// Make the invitation video: pick photos, order them, add captions, pick a style.
/// Guests see it when they open the invite link.
class InviteVideoScreen extends StatefulWidget {
  const InviteVideoScreen({super.key});

  @override
  State<InviteVideoScreen> createState() => _InviteVideoScreenState();
}

class _InviteVideoScreenState extends State<InviteVideoScreen> {
  final slides = <_Slide>[];
  final removed = <String>[];
  String style = 'fun';
  String music = InviteVideo.defaultMusic;

  /// False while the host reviews the photos; true once the video is made.
  bool generated = false;
  bool making = false;
  bool busy = false;
  bool changed = false;
  int version = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final e = AppScope.of(context).event!;
    final v = e.inviteVideo;
    style = v.isEmpty ? suggestedVideoStyle(e.occasion) : v.style;
    music = v.isEmpty ? InviteVideo.defaultMusic : v.music;
    generated = !v.isEmpty;
    for (var i = 0; i < v.photos.length; i++) {
      slides.add(_Slide(url: v.photos[i], caption: v.captionAt(i)));
    }
  }

  void _edit(VoidCallback f) => setState(() {
        f();
        changed = true;
        version++;
      });

  Future<void> _addPhotos() async {
    final room = InviteVideo.maxPhotos - slides.length;
    if (room <= 0) {
      toast(context, 'You can use up to ${InviteVideo.maxPhotos} photos.');
      return;
    }
    try {
      final files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (files.isEmpty) return;
      final picked = <_Slide>[];
      for (final f in files.take(room)) {
        picked.add(_Slide(bytes: await f.readAsBytes()));
      }
      _edit(() => slides.addAll(picked));
      if (files.length > room && mounted) toast(context, 'Added $room. The video holds up to ${InviteVideo.maxPhotos} photos.');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t add those photos. $e');
    }
  }

  Future<void> _slideMenu(int i, String occasion) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: HC.ground,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.short_text_rounded), title: Text(slides[i].caption.isEmpty ? 'Add a caption' : 'Edit caption'), onTap: () => Navigator.pop(ctx, 'caption')),
            if (i > 0) ListTile(leading: const Icon(Icons.arrow_back_rounded), title: Text(i == 1 ? 'Make it the cover (first)' : 'Move earlier'), onTap: () => Navigator.pop(ctx, 'earlier')),
            if (i < slides.length - 1) ListTile(leading: const Icon(Icons.arrow_forward_rounded), title: const Text('Move later'), onTap: () => Navigator.pop(ctx, 'later')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Remove photo'), onTap: () => Navigator.pop(ctx, 'remove')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'caption':
        await _caption(i, occasion);
      case 'earlier':
        _edit(() => slides.insert(i - 1, slides.removeAt(i)));
      case 'later':
        _edit(() => slides.insert(i + 1, slides.removeAt(i)));
      case 'remove':
        _edit(() {
          final s = slides.removeAt(i);
          if (s.url != null) removed.add(s.url!);
        });
    }
  }

  Future<void> _caption(int i, String occasion) async {
    final ctrl = TextEditingController(text: slides[i].caption);
    final ideas = videoCaptionIdeas[occasion] ?? videoCaptionIdeas['Get-together']!;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Caption for photo ${i + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: ctrl, autofocus: true, maxLength: 40, decoration: const InputDecoration(hintText: 'A few words')),
            Text('Ideas', style: body(12, color: HC.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final idea in ideas) ActionChip(label: Text(idea, style: body(12)), onPressed: () => ctrl.text = idea)],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('No caption')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Done')),
        ],
      ),
    );
    ctrl.dispose();
    if (text != null) _edit(() => slides[i].caption = text.trim());
  }

  Future<void> _save({bool clear = false}) async {
    final state = AppScope.of(context);
    final e = state.event!;
    setState(() => busy = true);
    try {
      if (clear) {
        removed.addAll([for (final s in slides) if (s.url != null) s.url!]);
        slides.clear();
      }
      for (final s in slides) {
        if (s.url == null && s.bytes != null) s.url = await InviteService.uploadPhoto(e.id, s.bytes!);
      }
      final video = InviteVideo(
        photos: [for (final s in slides) s.url!],
        captions: [for (final s in slides) s.caption],
        style: style,
        music: music,
      );
      await state.update((ev) => ev.inviteVideo = video);
      await InviteService.publish(state.event!, hostName: state.event!.inviteHost, message: state.event!.inviteMessage);
      for (final url in removed) {
        InviteService.deletePhoto(url);
      }
      removed.clear();
      if (!mounted) return;
      toast(context, clear ? 'Video removed from your invitation.' : 'Video saved! Guests see it when they open your invite.');
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) toast(context, 'Couldn\'t save the video. Check your connection. $err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// From reviewed photos to the video, with a short "making it" moment.
  Future<void> _make() async {
    setState(() => making = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      making = false;
      generated = true;
      changed = true;
      version++;
    });
  }

  Future<void> _songLink() async {
    final ctrl = TextEditingController(text: music.startsWith('https://') ? music : '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use a song from online'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste a direct link to an MP3 or M4A file. The first 30 seconds play with your video.', style: body(13, color: HC.muted)),
            const SizedBox(height: 10),
            TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://…/song.mp3')),
            const SizedBox(height: 10),
            Text('Free party music you can use: Pixabay Music (download, then upload it anywhere that gives a link, like Google Drive or Dropbox). Only use songs you have the right to share.',
                style: body(12, color: HC.muted)),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openLink(ctx, Uri.parse('https://pixabay.com/music/search/party/')),
              child: const Text('Browse free party music ›'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Use this song')),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.isEmpty) return;
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || url.length > 500) {
      if (mounted) toast(context, 'That doesn\'t look like a song link. It should start with https://');
      return;
    }
    _edit(() => music = url);
    if (mounted) toast(context, 'Song added. Play the video to hear it.');
  }

  Widget _musicPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Music'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in InviteVideo.tracks.entries)
              Pill(
                label: '🎵 ${t.value.$1}${t.key == InviteVideo.defaultMusic ? ' (default)' : ''}',
                small: true,
                selected: music == t.key,
                selectedColor: HC.violet,
                onTap: () => _edit(() => music = t.key),
              ),
            Pill(
              label: music.startsWith('https://') ? '🔗 Your song ✓' : '🔗 Song from online',
              small: true,
              selected: music.startsWith('https://'),
              selectedColor: HC.violet,
              onTap: _songLink,
            ),
            Pill(label: '🔇 No music', small: true, selected: music == 'none', selectedColor: HC.violet, onTap: () => _edit(() => music = 'none')),
          ],
        ),
        const SizedBox(height: 4),
        Text('Guests tap play to hear it, and can mute it anytime.', style: body(12, color: HC.muted)),
      ],
    );
  }

  Widget _review(EventDetails e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your photos (${slides.length}/${InviteVideo.maxPhotos})', style: display(18))),
            if (slides.length < InviteVideo.maxPhotos) TextButton.icon(onPressed: busy ? null : _addPhotos, icon: const Icon(Icons.add_rounded), label: const Text('Add more')),
          ],
        ),
        Text('Check your photos before making the video. Tap one to add a caption, move it or remove it. The first is the cover.', style: body(12, color: HC.muted)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
          children: [for (var i = 0; i < slides.length; i++) _thumb(i, e.occasion, size: double.infinity)],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 54)),
          onPressed: making ? null : _make,
          icon: making
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Icon(Icons.auto_awesome_rounded, color: HC.lime),
          label: Text(making ? 'Making your video…' : 'Make my video (${slides.length} photos)'),
        ),
        if (slides.length < 6)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Tip: 6–10 photos make the best video. You have ${slides.length}.', textAlign: TextAlign.center, style: body(12, color: HC.muted)),
          ),
      ],
    );
  }

  Future<bool> _confirmLeave() async {
    if (!changed) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your video changes will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).event!;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: BackArrow(onPressed: () async {
              if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
            }),
          ),
        ),
        leadingWidth: 60,
        title: const Text('Invitation video'),
        actions: [
          if (generated && slides.isNotEmpty)
            TextButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text('30 seconds that make guests say "wow" 🎬', style: display(22)),
              const SizedBox(height: 4),
              Text('Your photos become an animated video with zooms and captions. Guests watch it when they open your invite link.', style: body(13, color: HC.muted)),
              const SizedBox(height: 16),
              if (slides.isEmpty)
                _emptyState(e)
              else if (!generated)
                _review(e)
              else ...[
                InviteVideoPlayer(
                  music: music,
                  key: ValueKey(version),
                  photos: [for (final s in slides) s.source],
                  captions: [for (final s in slides) s.caption],
                  style: style,
                  theme: inviteThemeFor(e.inviteTheme),
                  title: e.inviteHeadline,
                  when: '${DateFormat('EEE, MMM d').format(e.date)} · ${clockAmPm(e.startMinutes)}',
                  motif: e.inviteMotif,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Photos (${slides.length}/${InviteVideo.maxPhotos})', style: display(18))),
                    if (slides.length < InviteVideo.maxPhotos) TextButton.icon(onPressed: busy ? null : _addPhotos, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
                  ],
                ),
                Text('Tap a photo to add a caption, move it or remove it. The first one is the cover.', style: body(12, color: HC.muted)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 124,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: slides.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _thumb(i, e.occasion),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const SectionLabel('Style'),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in InviteVideo.styles.entries)
                    Pill(
                      label: '${s.value}${s.key == suggestedVideoStyle(e.occasion) ? ' ⭐' : ''}',
                      small: true,
                      selected: style == s.key,
                      selectedColor: HC.violet,
                      onTap: () => _edit(() => style = s.key),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('⭐ suggested for a ${e.occasion.toLowerCase()}. Fun: lively zooms. Elegant: slow fades. Calm: gentle drift.', style: body(12, color: HC.muted)),
              const SizedBox(height: 20),
              _musicPicker(),
              const SizedBox(height: 20),
              _ideas(e),
              if (slides.isNotEmpty && generated) ...[
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 52)),
                  onPressed: busy ? null : _save,
                  child: Text(busy ? 'Saving…' : 'Save video'),
                ),
              ],
              if (!e.inviteVideo.isEmpty) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: busy ? null : () => _save(clear: true), child: const Text('Remove video from invitation')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(EventDetails e) {
    return CardBox(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Text('🎬', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 6),
          Text('Pick 6–10 photos to start', style: display(18)),
          const SizedBox(height: 4),
          Text('We\'ll turn them into a 30-second video with your title, date and "RSVP below".', textAlign: TextAlign.center, style: body(13, color: HC.muted)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(220, 50)),
            onPressed: busy ? null : _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Choose photos'),
          ),
        ],
      ),
    );
  }

  Widget _thumb(int i, String occasion, {double size = 92}) {
    final s = slides[i];
    return GestureDetector(
      onTap: () => _slideMenu(i, occasion),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: s.bytes != null
                        ? Image.memory(s.bytes!, fit: BoxFit.cover)
                        : Image.network(s.url!, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: i == 0 ? HC.lime : Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text(i == 0 ? 'Cover' : '${i + 1}', style: body(11, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(s.caption.isEmpty ? '+ caption' : s.caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: body(11, color: s.caption.isEmpty ? HC.violet : HC.ink, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _ideas(EventDetails e) {
    final shots = videoShotIdeas[e.occasion] ?? videoShotIdeas['Get-together']!;
    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💡 Photo ideas for a ${e.occasion.toLowerCase()}', style: body(15, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final s in shots) Text('• $s', style: body(13)),
          const SizedBox(height: 12),
          Text('Tips', style: body(14, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final t in videoTips) Text('• $t', style: body(12, color: HC.muted)),
        ],
      ),
    );
  }
}
