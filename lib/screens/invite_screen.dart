import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/invite_templates.dart';
import '../models/event_details.dart';
import '../models/invite_video.dart';
import '../models/photo_frame.dart';
import '../services/invite_service.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/invitation_card.dart';
import '../widgets/invite_clip_player.dart';
import '../widgets/invite_video_player.dart';
import 'invite_video_screen.dart';
import 'sign_in_screen.dart';

/// Turns what's painted inside a [RepaintBoundary] into a PNG.
Future<Uint8List?> capturePng(GlobalKey key) async {
  try {
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final image = await obj.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Where the share sheet points from (needed on iPad).
Rect? originOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

String inviteWhen(EventDetails e) =>
    '${DateFormat('EEEE, MMMM d').format(e.date)} · ${clockAmPm(e.startMinutes)} – ${clockAmPm(e.startMinutes + e.hours * 60)}';

String invitePlace(EventDetails e) => e.venue == null ? '' : (e.venue!.address.isNotEmpty ? e.venue!.address : e.venue!.label);

/// Invitations, in three tabs:
/// Design (photo, title, message, theme, preview, save and share the card),
/// Send (WhatsApp, iMessage, email, share sheet, guest list) and
/// Guests (going, pending, can't go, reminders, Pitch In).
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, this.initialTab = 0, this.guestTab = 0, this.shareOnOpen = false});

  /// 0 Design, 1 Send, 2 Guests.
  final int initialTab;

  /// On the Guests tab: 0 going, 1 pending, 2 can't go.
  final int guestTab;

  /// Open the share sheet as soon as the invite link is ready.
  final bool shareOnOpen;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
  Future<String>? publishing;
  String? inviteId;
  Future<List<Rsvp>>? replies;
  Future<List<PitchItem>>? pitch;

  final titleCtrl = TextEditingController();
  final messageCtrl = TextEditingController();
  final hostCtrl = TextEditingController();
  final extraCtrl = TextEditingController();
  String theme = 'midnight';
  String motif = '';
  String photoUrl = '';
  PhotoFrame frame = const PhotoFrame();
  Uint8List? photoBytes;
  bool uploading = false;
  bool dirty = false;
  bool saving = false;

  /// Inner tab on Guests: 0 going, 1 pending, 2 can't go.
  late int guestTab = widget.guestTab.clamp(0, 2);

  final _cardKey = GlobalKey();
  final _sendCardKey = GlobalKey();
  final _templatesKey = GlobalKey();
  final _textKey = GlobalKey();
  final _videoKey = GlobalKey();
  final _titleFocus = FocusNode();
  bool _started = false;

  bool get _canPickContacts => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static const _contacts = MethodChannel('hoopla/contacts');

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      _hideKeyboard();
      if (!tabs.indexIsChanging && tabs.index != 0 && dirty) _saveDesign(quiet: true);
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_started && state.isSignedIn && state.event != null) {
      _started = true;
      final e = state.event!;
      titleCtrl.text = e.inviteTitle;
      messageCtrl.text = e.inviteMessage.isNotEmpty ? e.inviteMessage : _defaultMessage(e);
      theme = e.inviteTheme;
      motif = e.inviteMotif;
      photoUrl = e.invitePhoto;
      frame = e.invitePhotoFrame;
      hostCtrl.text = e.inviteHost.isNotEmpty ? e.inviteHost : _accountName(state);
      extraCtrl.text = e.inviteExtra;
      publishing = InviteService.publish(e, hostName: _host, message: messageCtrl.text);
      publishing!.then((id) {
        if (!mounted) return;
        setState(() {
          inviteId = id;
          replies = InviteService.rsvps(id);
          pitch = InviteService.pitchItems(id);
        });
        if (widget.shareOnOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openSharePicker(context);
          });
        }
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    _titleFocus.dispose();
    titleCtrl.dispose();
    messageCtrl.dispose();
    hostCtrl.dispose();
    extraCtrl.dispose();
    super.dispose();
  }

  static String _defaultMessage(EventDetails e) => switch (e.kind) {
        'Birthday' => 'Come celebrate with us! Cake, games and lots of fun. 🎂',
        'Housewarming' => 'We\'ve moved in! Join us to bless our new home. 🏡',
        'Baby shower' => 'A little one is on the way! Celebrate with us. 🍼',
        'Pooja' => 'Please join us for the pooja and prasadam. 🙏',
        'Anniversary' => 'Celebrate this special day with us. 💍',
        _ => 'We\'d love to see you there! 🎉',
      };

  /// A real name from the account (never the email), or ''.
  static String _accountName(AppState s) {
    final n = (s.profile?['name'] as String?)?.trim();
    if (n != null && n.isNotEmpty && !n.contains('@')) return n;
    final d = s.accounts?.user?.displayName?.trim();
    if (d != null && d.isNotEmpty && !d.contains('@')) return d;
    return '';
  }

  /// "Hosted by" on the invitation, as the host typed it.
  String get _host => hostCtrl.text.trim();

  /// Closes the keyboard so it can't pop up over sheets and share menus.
  static void _hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  // ---------------------------------------------------------------- design

  void _changed(VoidCallback f) => setState(() {
        f();
        dirty = true;
      });

  /// Saves the design to the event and updates what guests see.
  Future<void> _saveDesign({bool quiet = false}) async {
    if (saving) return;
    final state = AppScope.of(context);
    setState(() => saving = true);
    try {
      await state.update((e) {
        e.inviteTitle = titleCtrl.text.trim() == e.title ? '' : titleCtrl.text.trim();
        e.inviteMessage = messageCtrl.text.trim();
        e.inviteTheme = theme;
        e.inviteMotif = motif;
        e.invitePhoto = photoUrl;
        e.invitePhotoFrame = frame;
        e.inviteHost = _host;
        e.inviteExtra = extraCtrl.text.trim();
      });
      await InviteService.publish(state.event!, hostName: _host, message: messageCtrl.text);
      if (mounted) {
        setState(() => dirty = false);
        if (!quiet) toast(context, 'Invitation saved. Guests see the new design.');
      }
    } catch (err) {
      if (mounted) toast(context, 'Couldn\'t save the invitation. Check your connection.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    _hideKeyboard();
    final camera = !kIsWeb;
    ImageSource? source = ImageSource.gallery;
    if (camera) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from photos'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null) return;
    final state = AppScope.of(context);
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        photoBytes = bytes;
        frame = const PhotoFrame();
        uploading = true;
      });
      final url = await InviteService.uploadPhoto(state.event!.id, bytes);
      final old = photoUrl;
      photoUrl = url;
      dirty = true;
      await _saveDesign(quiet: true);
      InviteService.deletePhoto(old);
      if (mounted) toast(context, 'Photo added. Tap "Adjust" to crop or zoom it.');
    } catch (err) {
      if (mounted) {
        setState(() => photoBytes = null);
        toast(context, 'Couldn\'t add that photo. $err');
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    final old = photoUrl;
    setState(() {
      photoBytes = null;
      photoUrl = '';
      dirty = true;
    });
    await _saveDesign(quiet: true);
    InviteService.deletePhoto(old);
  }

  /// Crop the photo: pick a shape, drag to choose what shows, pinch or slide to zoom.
  Future<void> _adjustPhoto() async {
    _hideKeyboard();
    var f = frame;
    var startZoom = f.zoom;
    final result = await showModalBottomSheet<PhotoFrame>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HC.ground,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Adjust photo', style: display(22))),
                  TextButton(onPressed: () => setS(() => f = const PhotoFrame()), child: const Text('Reset')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in PhotoFrame.shapes.entries)
                    Pill(
                      label: s.value,
                      small: true,
                      selectedColor: HC.violet,
                      selected: f.shape == s.key,
                      onTap: () => setS(() => f = f.copyWith(shape: s.key)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: LayoutBuilder(
                  builder: (ctx, box) => GestureDetector(
                    onScaleStart: (_) => startZoom = f.zoom,
                    onScaleUpdate: f.whole
                        ? null
                        : (d) => setS(() {
                              final half = box.maxWidth / 2;
                              f = f.copyWith(
                                x: f.x - d.focalPointDelta.dx / half / f.zoom,
                                y: f.y - d.focalPointDelta.dy / half / f.zoom,
                                zoom: d.pointerCount > 1 ? startZoom * d.scale : f.zoom,
                              );
                            }),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: FramedPhoto(frame: f, bytes: photoBytes, url: photoUrl),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (f.whole)
                Text('The whole photo shows, nothing is cut. Pick Square, Wide or Tall to crop.', style: body(13, color: HC.muted))
              else ...[
                Text('Drag the photo to choose what shows. Pinch or use the slider to zoom.', style: body(13, color: HC.muted)),
                Row(
                  children: [
                    const Icon(Icons.zoom_out_rounded, color: HC.muted),
                    Expanded(
                      child: Slider(
                        value: f.zoom,
                        min: 1,
                        max: 3,
                        activeColor: HC.violet,
                        onChanged: (v) => setS(() => f = f.copyWith(zoom: v)),
                      ),
                    ),
                    const Icon(Icons.zoom_in_rounded, color: HC.muted),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 50)),
                onPressed: () => Navigator.pop(ctx, f),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      frame = result;
      dirty = true;
    });
    await _saveDesign(quiet: true);
  }

  /// Uses a ready-made design: its style, decoration and words (all still editable).
  void _applyTemplate(InviteTemplate t, EventDetails e) {
    _hideKeyboard();
    final date = DateFormat('EEEE, MMMM d').format(e.date);
    _changed(() {
      theme = t.theme;
      motif = t.motif;
      titleCtrl.text = fillTemplate(t.title, e, date);
      messageCtrl.text = fillTemplate(t.message, e, date);
      if (t.extra.isNotEmpty) extraCtrl.text = fillTemplate(t.extra, e, date);
    });
    toast(context, '"${t.name}" applied. Edit the names and words below to make it yours.');
  }

  Widget _templates(EventDetails e) {
    final list = templatesFor(e.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('✨ Designs for your ${e.occasion.toLowerCase()}', style: display(18)),
        const SizedBox(height: 2),
        Text('Pick one to start, then change the names and words.', style: body(12, color: HC.muted)),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final t = list[i];
              final th = inviteThemeFor(t.theme);
              final on = t.theme == theme && t.motif == motif;
              return GestureDetector(
                onTap: () => _applyTemplate(t, e),
                child: Semantics(
                  button: true,
                  selected: on,
                  label: '${t.name} design',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: th.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: on ? HC.violet : Colors.transparent, width: 3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.motif.isEmpty ? '✨' : t.motif, style: const TextStyle(fontSize: 22, letterSpacing: 2)),
                        const Spacer(),
                        Text('YOU\'RE INVITED', style: body(8, color: th.accent, weight: FontWeight.w700)),
                        Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(13, color: th.text, weight: FontWeight.w700)),
                        if (on) Text('✓ Using', style: body(11, color: th.accent, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _videoSection(EventDetails e, AppState state) {
    final v = e.inviteVideo;
    Future<void> open() async {
      await _ready();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InviteVideoScreen()));
    }

    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('🎬', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invitation video', style: body(16, weight: FontWeight.w700)),
                    Text(
                      v.isEmpty
                          ? 'Turn 6–10 photos into a 30-second video guests watch when they open your invite.'
                          : v.hasClip
                              ? 'Your own video${v.clipTheme == 'none' ? '' : ' · ${InviteVideo.clipThemes[v.clipTheme]}'}${v.clipHasMusic ? ' · 🎵 music' : ''} · ${v.clipAutoplay ? 'plays when guests open the invite' : 'guests tap to play'}'
                              : '${v.photos.length} photos · ${InviteVideo.looks[v.look]} · 🎵 ${v.musicLabel} · plays on your invite page',
                      style: body(12, color: HC.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (v.hasClip) ...[
            const SizedBox(height: 12),
            InviteClipPlayer(
              url: v.clip,
              autoplay: false,
              theme: v.clipTheme,
              music: v.clipMusic,
              keepVoice: v.clipVoice,
              title: titleCtrl.text.trim().isEmpty ? e.title : titleCtrl.text.trim(),
              when: '${DateFormat('EEE, MMM d').format(e.date)} · ${clockAmPm(e.startMinutes)}',
            ),
          ] else if (!v.isEmpty) ...[
            const SizedBox(height: 12),
            InviteVideoPlayer(
              look: v.look,
              photos: v.photos,
              captions: v.captions,
              style: v.style,
              theme: inviteThemeFor(theme),
              title: titleCtrl.text.trim().isEmpty ? e.title : titleCtrl.text.trim(),
              when: '${DateFormat('EEE, MMM d').format(e.date)} · ${clockAmPm(e.startMinutes)}',
              motif: motif,
              autoplay: false,
              music: v.music,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: HC.line)),
            onPressed: open,
            icon: Icon(v.isEmpty ? Icons.movie_creation_outlined : Icons.edit_outlined, size: 20, color: HC.violet),
            label: Text(v.isEmpty ? 'Create a video' : 'Edit video', style: body(14, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Scrolls the design page to a section (templates, text fields, video).
  void _scrollTo(GlobalKey key) {
    final c = key.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300), alignment: 0.05);
  }

  /// One row of tools under the card: Photo, Crop, Text, Video, Designs.
  Widget _toolsRow(EventDetails e, bool hasPhoto) {
    Future<void> openVideo() async {
      await _ready();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InviteVideoScreen()));
    }

    final tools = <(IconData, String, VoidCallback?)>[
      (Icons.add_photo_alternate_outlined, hasPhoto ? 'Photo' : 'Add photo', uploading ? null : _pickPhoto),
      (Icons.crop_rounded, 'Crop', hasPhoto && !uploading ? _adjustPhoto : null),
      (Icons.text_fields_rounded, 'Text', () {
        _scrollTo(_textKey);
        _titleFocus.requestFocus();
      }),
      (Icons.movie_creation_outlined, 'Video', openVideo),
      (Icons.auto_awesome_outlined, 'Designs', () => _scrollTo(_templatesKey)),
    ];
    return Row(
      children: [
        for (final t in tools)
          Expanded(
            child: Semantics(
              button: true,
              label: t.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: t.$3,
                child: Opacity(
                  opacity: t.$3 == null ? 0.4 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: HC.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HC.line)),
                          child: Icon(t.$1, color: HC.ink, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The big "Share invitation" button: waits for the invite link, then opens the share sheet.
  Future<void> _share(BuildContext from) async {
    if (inviteId == null) {
      toast(context, 'Getting your invitation ready…');
      try {
        await publishing;
      } catch (_) {}
      if (!mounted) return;
      if (inviteId == null) {
        toast(context, 'Couldn\'t get your invite link. Check your connection and try again.');
        return;
      }
    }
    await _openSharePicker(from);
  }

  Widget _card(EventDetails e, AppState state, {GlobalKey? key}) {
    final card = InvitationCard(
      theme: inviteThemeFor(theme),
      title: titleCtrl.text.trim().isEmpty ? e.title : titleCtrl.text.trim(),
      hostName: _host,
      when: inviteWhen(e),
      place: invitePlace(e),
      message: messageCtrl.text,
      extra: extraCtrl.text,
      photoUrl: photoUrl,
      photoBytes: photoBytes,
      frame: frame,
      motif: motif,
    );
    return key == null ? card : RepaintBoundary(key: key, child: card);
  }

  // ---------------------------------------------------------------- sending

  String _text(AppState state, {Invitee? guest}) => inviteText(
        state.event!,
        inviteUrl(inviteId!, guest: guest?.guestKey ?? ''),
        hostName: _host,
        message: messageCtrl.text,
      );

  String _reminder(AppState state, Invitee guest) {
    final e = state.event!;
    final first = guest.name.trim().split(' ').first;
    return 'Hi $first! Just a reminder about ${e.inviteHeadline} on ${DateFormat('EEE, MMM d').format(e.date)} at ${clockAmPm(e.startMinutes)}. '
        'Can you let us know if you can make it? ${inviteUrl(inviteId!, guest: guest.guestKey)}';
  }

  Future<void> _markSent(Iterable<Invitee> people) async {
    final keys = {for (final p in people) p.key};
    if (keys.isEmpty) return;
    final now = DateTime.now();
    await AppScope.of(context).update((ev) {
      for (final i in ev.invitees) {
        if (keys.contains(i.key)) i.sentAt = now;
      }
    });
  }

  Future<void> _ready() async {
    _hideKeyboard();
    if (dirty) await _saveDesign(quiet: true);
  }

  /// Shares the card picture plus the RSVP link (WhatsApp, iMessage, Mail, Instagram, …).
  Uint8List? _clipBytes;
  String _clipBytesFor = '';

  /// The host's recorded video as a file to attach (downloaded once).
  Future<Uint8List?> _clipFile(String url) async {
    if (_clipBytesFor == url && _clipBytes != null) return _clipBytes;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      _clipBytes = r.bodyBytes;
      _clipBytesFor = url;
      return _clipBytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareCard(BuildContext from, {Uint8List? png, bool withText = true, bool? withVideo, bool withPicture = true}) async {
    _hideKeyboard();
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    final v = state.event!.inviteVideo;
    // "Send the video with the invitation": attach the recorded clip so it plays in the chat.
    if (withText && v.hasClip && (withVideo ?? v.sendClip) && !kIsWeb) {
      toast(context, 'Getting your video ready…');
      final bytes = await _clipFile(v.clip);
      if (!mounted) return;
      if (bytes != null) {
        final mov = v.clip.toLowerCase().contains('.mov');
        try {
          // ignore: deprecated_member_use
          await Share.shareXFiles(
            [XFile.fromData(bytes, mimeType: mov ? 'video/quicktime' : 'video/mp4', name: mov ? 'invitation.mov' : 'invitation.mp4')],
            text: _text(state),
            subject: 'You\'re invited: ${state.event!.inviteHeadline}',
            sharePositionOrigin: from.mounted ? originOf(from) : null,
          );
          return;
        } catch (_) {}
      }
      if (mounted) toast(context, 'Couldn\'t attach the video, so sharing the card instead.');
    }
    final image = withPicture ? png ?? await capturePng(_cardKey) ?? await capturePng(_sendCardKey) : null;
    final rect = from.mounted ? originOf(from) : null;
    try {
      if (image == null) {
        // ignore: deprecated_member_use
        await Share.share(_text(state), subject: 'You\'re invited: ${state.event!.inviteHeadline}', sharePositionOrigin: rect);
        return;
      }
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile.fromData(image, mimeType: 'image/png', name: 'invitation.png')],
        text: withText ? _text(state) : null,
        subject: 'You\'re invited: ${state.event!.inviteHeadline}',
        sharePositionOrigin: rect,
      );
    } catch (_) {
      if (withText) await _copy(state);
    }
  }

  /// Festino's own share menu: WhatsApp, Instagram, Facebook, Messages, Gmail, …
  Future<void> _openSharePicker(BuildContext from, {Uint8List? png}) async {
    _hideKeyboard();
    await _ready();
    if (!mounted) return;
    final image = png ?? await capturePng(_cardKey) ?? await capturePng(_sendCardKey);
    if (!mounted) return;
    _hideKeyboard();
    final choice = await showModalBottomSheet<_ShareChoice>(
      context: from.mounted ? from : context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: HC.card,
      builder: (ctx) {
        final v = AppScope.of(context).event!.inviteVideo;
        return _SharePicker(hasImage: image != null, hasVideo: v.hasClip && !kIsWeb, videoOn: v.sendClip);
      },
    );
    _hideKeyboard();
    if (choice == null || !mounted) return;
    final pick = choice.app;
    final state = AppScope.of(context);
    final text = _text(state);
    final url = inviteUrl(inviteId!);
    final subject = 'You\'re invited: ${state.event!.inviteHeadline}';
    switch (pick) {
      case 'all':
        await _shareCard(from, png: image, withVideo: choice.video, withPicture: choice.picture);
      case 'whatsapp':
        openLink(context, Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'));
      case 'instagram':
        toast(context, 'Pick Instagram in the list, then post it to your story or send it in a message.');
        await _shareCard(from, png: image, withText: false);
      case 'facebook':
        openLink(context, Uri.https('www.facebook.com', '/sharer/sharer.php', {'u': url}));
      case 'messages':
        openLink(context, InviteService.smsTo(const [], text));
      case 'gmail':
        await _openGmail(subject, text);
      case 'email':
        openLink(context, InviteService.emailTo(const [], subject, text));
      case 'telegram':
        openLink(context, Uri.https('t.me', '/share/url', {'url': url, 'text': text.replaceAll(url, '').trim()}));
      case 'x':
        openLink(context, Uri.https('twitter.com', '/intent/tweet', {'text': text}));
      case 'copy':
        await _copy(state);
      case 'save':
        await _shareCard(from, png: image, withText: false);
    }
  }

  /// Gmail app on iPhone if it's installed, Gmail on the web otherwise.
  Future<void> _openGmail(String subject, String body) async {
    if (!kIsWeb) {
      final app = Uri.parse('googlegmail:///co?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
      try {
        if (await launchUrl(app, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (!mounted) return;
    openLink(context, Uri.https('mail.google.com', '/mail/', {'view': 'cm', 'fs': '1', 'su': subject, 'body': body}));
  }

  Future<void> _shareText(BuildContext from) async {
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    try {
      // ignore: deprecated_member_use
      await Share.share(_text(state), subject: 'You\'re invited: ${state.event!.inviteHeadline}', sharePositionOrigin: from.mounted ? originOf(from) : null);
    } catch (_) {
      await _copy(state);
    }
  }

  Future<void> _copy(AppState state) async {
    await Clipboard.setData(ClipboardData(text: _text(state)));
    if (mounted) toast(context, 'Invite copied. Paste it in any chat or group.');
  }

  Future<void> _whatsApp() async {
    await _ready();
    if (!mounted) return;
    openLink(context, Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_text(AppScope.of(context)))}'));
  }

  Future<void> _textAll() async {
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    final people = [for (final i in state.event!.invitees) if (i.phoneDigits.isNotEmpty) i];
    openLink(context, InviteService.smsTo([for (final p in people) p.phoneDigits], _text(state)));
    await _markSent(people);
  }

  Future<void> _emailAll() async {
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    final people = [for (final i in state.event!.invitees) if (i.email.isNotEmpty) i];
    openLink(context, InviteService.emailTo([for (final p in people) p.email], 'You\'re invited: ${state.event!.inviteHeadline}', _text(state)));
    await _markSent(people);
  }

  Future<void> _sendOne(Invitee p, String how, {bool remind = false}) async {
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    final text = remind ? _reminder(state, p) : _text(state, guest: p);
    final digits = p.phoneDigits.replaceAll('+', '');
    switch (how) {
      case 'whatsapp':
        openLink(context, Uri.https('wa.me', '/$digits', {'text': text}));
      case 'sms':
        openLink(context, InviteService.smsTo([p.phoneDigits], text));
      case 'email':
        openLink(context, InviteService.emailTo([p.email], remind ? 'Reminder: ${state.event!.inviteHeadline}' : 'You\'re invited: ${state.event!.inviteHeadline}', text));
    }
    await _markSent([p]);
  }

  Future<void> _remindAllPending(List<GuestEntry> pending) async {
    final people = [for (final g in pending) if (g.invitee != null && g.invitee!.phoneDigits.isNotEmpty && !g.replied) g.invitee!];
    if (people.isEmpty) {
      toast(context, 'No phone numbers to remind. Use WhatsApp or Share instead.');
      return;
    }
    final state = AppScope.of(context);
    final e = state.event!;
    final text = 'Hi! Just a reminder about ${e.inviteHeadline} on ${DateFormat('EEE, MMM d').format(e.date)}. '
        'Please RSVP so we can plan: ${inviteUrl(inviteId!)}';
    openLink(context, InviteService.smsTo([for (final p in people) p.phoneDigits], text));
    await _markSent(people);
  }

  Future<void> _openPreview() async {
    _hideKeyboard();
    await _ready();
    if (!mounted) return;
    final state = AppScope.of(context);
    final e = state.event!;
    final go = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _InvitePreview(
        card: (key) => _card(e, state, key: key),
        onShareCard: (from, png) => _openSharePicker(from, png: png),
        onSaveImage: (from, png) => _shareCard(from, png: png, withText: false),
        onWhatsApp: _whatsApp,
        onText: _textAll,
        onEmail: _emailAll,
      ),
    ));
    if (go == 'send' && mounted) tabs.animateTo(1);
  }

  // ---------------------------------------------------------------- guest list

  Future<void> _addInvitees(List<Invitee> people) async {
    if (people.isEmpty) return;
    final state = AppScope.of(context);
    var added = 0;
    await state.update((e) {
      final have = {for (final i in e.invitees) i.key};
      for (final p in people) {
        if (p.key.isEmpty || !have.add(p.key)) continue;
        e.invitees.add(p);
        added++;
      }
    });
    if (mounted) toast(context, added == 0 ? 'They\'re already on your list.' : 'Added $added to your guest list.');
  }

  Future<void> _pickContacts() async {
    try {
      final raw = await _contacts.invokeMethod<List<dynamic>>('pick') ?? const [];
      final people = <Invitee>[
        for (final m in raw)
          if (m is Map)
            Invitee(
              name: '${m['name'] ?? ''}'.trim().isEmpty ? '${m['phone'] ?? m['email'] ?? 'Guest'}' : '${m['name']}'.trim(),
              phone: '${m['phone'] ?? ''}',
              email: '${m['email'] ?? ''}',
            ),
      ];
      await _addInvitees(people);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t open your contacts. Type numbers instead.');
    }
  }

  Future<void> _typeContacts() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add numbers or emails'),
        content: TextField(
          controller: ctrl,
          minLines: 4,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'One per line or separated by commas:\nPriya 732 555 0100\nsam@example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    final people = parseInvitees(text);
    if (people.isEmpty && mounted) {
      toast(context, 'No phone numbers or emails found.');
      return;
    }
    await _addInvitees(people);
  }

  // ---------------------------------------------------------------- Pitch In

  void _reloadPitch() => setState(() => pitch = InviteService.pitchItems(inviteId!));
  void _reloadReplies() => setState(() => replies = InviteService.rsvps(inviteId!));

  Future<void> _suggestPitch(EventDetails e, int have) async {
    try {
      await InviteService.addItems(inviteId!, suggestPitchIn(e), startOrder: have);
      _reloadPitch();
      if (mounted) toast(context, 'Added ideas from your plan. Remove any you don\'t need.');
    } catch (err) {
      if (mounted) toast(context, 'Couldn\'t add the list: $err');
    }
  }

  Future<void> _addPitchItem(int have) async {
    final ctrl = TextEditingController();
    var help = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add to Pitch In'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'e.g. Samosas (40) or Parking helper'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('This is a way to help, not an item'),
                value: help,
                onChanged: (v) => setD(() => help = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final label = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || label.isEmpty) return;
    await InviteService.addItems(inviteId!, [PitchItem(id: '', label: label, emoji: help ? '🙌' : '🧺', help: help)], startOrder: have);
    _reloadPitch();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event;
    final ready = e != null && state.isSignedIn;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: Center(child: BackArrow())),
        leadingWidth: 60,
        title: const Text('Invitation'),
        actions: [
          if (ready && tabs.index == 0 && dirty)
            TextButton(onPressed: saving ? null : _saveDesign, child: Text(saving ? 'Saving…' : 'Save')),
        ],
        bottom: ready
            ? TabBar(
                controller: tabs,
                labelColor: HC.ink,
                unselectedLabelColor: HC.muted,
                indicatorColor: HC.violet,
                labelStyle: body(15, weight: FontWeight.w700),
                tabs: const [Tab(text: '🎨 Design'), Tab(text: '📤 Send'), Tab(text: '👥 Guests')],
              )
            : null,
      ),
      body: e == null
          ? const SizedBox.shrink()
          : !state.isSignedIn
              ? _signInFirst(context)
              : FutureBuilder<String>(
                  future: publishing,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Couldn\'t create the invite. Check your connection.', style: body(14, color: HC.muted)));
                    }
                    if (!snap.hasData || inviteId == null) return const Center(child: CircularProgressIndicator());
                    return TabBarView(
                      controller: tabs,
                      children: [
                        _wrap(_designTab(context, state, e)),
                        _wrap(_sendTab(context, state, e)),
                        _wrap(_guestsTab(context, state, e)),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _wrap(List<Widget> children) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideKeyboard,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: children,
            ),
          ),
        ),
      );

  Widget _signInFirst(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💌', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text('Design invitations and track RSVPs', style: display(22), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('Sign in free so guests\' replies come back to you.', style: body(14, color: HC.muted), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(220, 50)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => const SignInScreen(reason: 'Sign in free to send invites and see who\'s coming.'),
            )),
            child: const Text('Sign in free'),
          ),
        ],
      ),
    );
  }

  // ---- 🎨 Design

  List<Widget> _designTab(BuildContext context, AppState state, EventDetails e) {
    final hasPhoto = photoBytes != null || photoUrl.isNotEmpty;
    return [
      GestureDetector(
        onTap: hasPhoto || uploading ? null : _pickPhoto,
        child: Stack(
          children: [
            _card(e, state, key: _cardKey),
            if (uploading)
              const Positioned(top: 12, right: 12, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
          ],
        ),
      ),
      if (!hasPhoto) ...[
        const SizedBox(height: 6),
        Text('Tap the card to add a photo', textAlign: TextAlign.center, style: body(12, color: HC.muted)),
      ],
      const SizedBox(height: 14),
      _toolsRow(e, hasPhoto),
      const SizedBox(height: 18),
      const SectionLabel('Colors'),
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: inviteThemes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final t = inviteThemes[i];
            final on = t.id == theme;
            return GestureDetector(
              onTap: () => _changed(() => theme = t.id),
              child: Semantics(
                button: true,
                selected: on,
                label: '${t.name} style',
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        border: Border.all(color: on ? HC.violet : HC.line, width: on ? 3 : 1),
                      ),
                      child: on ? Icon(Icons.check_rounded, color: t.text) : null,
                    ),
                    const SizedBox(height: 4),
                    Text(t.name, style: body(12, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? HC.ink : HC.muted)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      if (motif.isNotEmpty) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            label: Text('Decoration  $motif', style: body(13)),
            onDeleted: () => _changed(() => motif = ''),
            deleteButtonTooltipMessage: 'Remove decoration',
          ),
        ),
      ],
      const SizedBox(height: 16),
      Builder(
        builder: (b) => FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: () => _share(b),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: Text('Share invitation', style: body(16, color: Colors.white, weight: FontWeight.w700)),
        ),
      ),
      TextButton.icon(
        onPressed: _openPreview,
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('Preview how guests see it'),
      ),
      const SizedBox(height: 14),
      KeyedSubtree(key: _templatesKey, child: _templates(e)),
      if (hasPhoto) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: uploading ? null : _removePhoto,
            icon: const Icon(Icons.hide_image_outlined, size: 18),
            label: const Text('Remove photo'),
          ),
        ),
      ],
      const SizedBox(height: 20),
      KeyedSubtree(key: _textKey, child: const SectionLabel('Title')),
      TextField(
        controller: titleCtrl,
        focusNode: _titleFocus,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: e.title, helperText: 'Leave empty to use your event name'),
        onChanged: (_) => _changed(() {}),
        onTapOutside: (_) => _hideKeyboard(),
      ),
      const SizedBox(height: 8),
      const SectionLabel('Hosted by'),
      TextField(
        controller: hostCtrl,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'e.g. Krishna & Anu, or The Mula family',
          helperText: 'Your names as guests know you. Leave empty to hide.',
        ),
        onChanged: (_) => _changed(() {}),
        onTapOutside: (_) => _hideKeyboard(),
      ),
      const SizedBox(height: 8),
      const SectionLabel('Message'),
      TextField(
        controller: messageCtrl,
        minLines: 3,
        maxLines: 6,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Dress code, parking, gifts, anything guests should know'),
        onChanged: (_) => _changed(() {}),
        onTapOutside: (_) => _hideKeyboard(),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final idea in _messageIdeas(e))
            ActionChip(
              label: Text(idea, style: body(12)),
              onPressed: () => _changed(() {
                final now = messageCtrl.text.trim();
                messageCtrl.text = now.isEmpty ? idea : '$now $idea';
              }),
            ),
        ],
      ),
      const SizedBox(height: 18),
      const SectionLabel('More details (optional)'),
      TextField(
        controller: extraCtrl,
        minLines: 2,
        maxLines: 5,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Dress code, parking, gift registry, RSVP by, contact number…'),
        onChanged: (_) => _changed(() {}),
        onTapOutside: (_) => _hideKeyboard(),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final idea in const ['Dress code: festive 👗', 'Parking on the street 🚗', 'No gifts please 🎁', 'Kids welcome 🧒'])
            ActionChip(
              label: Text(idea, style: body(12)),
              onPressed: () => _changed(() {
                final now = extraCtrl.text.trim();
                extraCtrl.text = now.isEmpty ? idea : '$now\n$idea';
              }),
            ),
        ],
      ),
      const SizedBox(height: 18),
      KeyedSubtree(key: _videoKey, child: _videoSection(e, state)),
      const SizedBox(height: 18),
      Text('Date, time and place come from your plan. Edit them with ✏️ on the Plan page.', style: body(12, color: HC.muted)),
      if (dirty) ...[
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HC.ink, minimumSize: const Size(0, 50)),
          onPressed: saving ? null : _saveDesign,
          child: Text(saving ? 'Saving…' : 'Save invitation'),
        ),
      ],
    ];
  }

  static List<String> _messageIdeas(EventDetails e) => [
        _defaultMessage(e),
        'Dinner will be served. 🍽️',
        'Your presence is the only gift we need. 💛',
        'Please RSVP by ${DateFormat('MMM d').format(e.date.subtract(const Duration(days: 7)))}.',
      ];

  // ---- 📤 Send

  List<Widget> _sendTab(BuildContext context, AppState state, EventDetails e) {
    final phones = e.invitees.where((i) => i.phoneDigits.isNotEmpty).length;
    final emails = e.invitees.where((i) => i.email.isNotEmpty).length;
    return [
      CardBox(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _openPreview,
              child: SizedBox(
                width: 112,
                height: 150,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: 380, child: _card(e, state, key: _sendCardKey)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your invitation', style: display(18)),
                  const SizedBox(height: 2),
                  Text('Send the picture with the RSVP link to WhatsApp, iMessage, Gmail, Instagram…', style: body(12, color: HC.muted)),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (b) => FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 44)),
                      onPressed: () => _openSharePicker(b),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share the card'),
                    ),
                  ),
                  Wrap(
                    children: [
                      TextButton(onPressed: _openPreview, child: const Text('Preview')),
                      TextButton(onPressed: () => tabs.animateTo(0), child: const Text('Edit design')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text('Or send the link', style: display(18)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
        children: [
          _SendTile(emoji: '💬', label: 'WhatsApp', sub: 'Chats or groups', onTap: _whatsApp),
          _SendTile(emoji: '✉️', label: 'Messages', sub: phones == 0 ? 'iMessage / SMS' : 'All $phones numbers', onTap: _textAll),
          _SendTile(emoji: '📧', label: 'Email', sub: emails == 0 ? 'Gmail, Outlook…' : 'All $emails (BCC)', onTap: _emailAll),
          Builder(builder: (b) => _SendTile(emoji: '📤', label: 'More…', sub: 'Any app', onTap: () => _shareText(b))),
          _SendTile(emoji: '🔗', label: 'Copy', sub: 'Invite + link', onTap: () => _copy(state)),
          _SendTile(emoji: '👀', label: 'Guest page', sub: 'What guests see', onTap: () => openLink(context, Uri.parse(inviteUrl(inviteId!)))),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(child: Text('Guest list (${e.invitees.length})', style: display(18))),
          if (e.invitees.isNotEmpty)
            Text('${e.invitees.where((i) => i.sentAt != null).length} sent', style: body(13, color: HC.muted, weight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 4),
      Text('Send each person their own link and their reply shows up under Guests automatically.', style: body(12, color: HC.muted)),
      const SizedBox(height: 10),
      Row(
        children: [
          if (_canPickContacts) ...[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: HC.line)),
                onPressed: _pickContacts,
                icon: Icon(Icons.contacts_rounded, size: 18, color: HC.violet),
                label: Text('Pick contacts', style: body(14, weight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: HC.line)),
              onPressed: _typeContacts,
              icon: Icon(Icons.keyboard_rounded, size: 18, color: HC.violet),
              label: Text('Type numbers / emails', style: body(14, weight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      if (e.invitees.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Add people here to send them their own invite, or just share the card to a WhatsApp group.', style: body(13, color: HC.muted)),
        )
      else ...[
        const SizedBox(height: 10),
        Material(
          color: HC.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < e.invitees.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: HC.line),
                _InviteeRow(
                  person: e.invitees[i],
                  status: e.invitees[i].sentAt == null ? 'Not sent yet' : 'Sent ${DateFormat('MMM d').format(e.invitees[i].sentAt!)}',
                  onSend: (how) => _sendOne(e.invitees[i], how),
                  onRemove: () => state.update((ev) => ev.invitees.removeWhere((x) => x.key == e.invitees[i].key)),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  // ---- 👥 Guests

  List<Widget> _guestsTab(BuildContext context, AppState state, EventDetails e) {
    return [
      FutureBuilder<List<Rsvp>>(
        future: replies,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          final list = snap.data ?? const <Rsvp>[];
          final board = groupGuests(e.invitees, list);
          final groups = [board.going, board.pending, board.cantGo];
          final shown = groups[guestTab];
          final food = foodSummary(list);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('${board.total} invited · ${board.people} coming', style: display(18))),
                  IconButton(tooltip: 'Refresh', onPressed: _reloadReplies, icon: const Icon(Icons.refresh_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Stat(value: '${board.going.length}', label: 'Going', emoji: '🎉', color: HC.lime, selected: guestTab == 0, onTap: () => setState(() => guestTab = 0))),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(value: '${board.pending.length}', label: 'Pending', emoji: '⏳', color: const Color(0xFFFFF1C2), selected: guestTab == 1, onTap: () => setState(() => guestTab = 1))),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(value: '${board.cantGo.length}', label: 'Can\'t go', emoji: '😢', color: const Color(0xFFFFE0D8), selected: guestTab == 2, onTap: () => setState(() => guestTab = 2))),
                ],
              ),
              const SizedBox(height: 12),
              Segmented(
                options: ['Going (${board.going.length})', 'Pending (${board.pending.length})', 'Can\'t go (${board.cantGo.length})'],
                selected: guestTab,
                height: 40,
                onChanged: (i) => setState(() => guestTab = i),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    switch (guestTab) {
                      0 => board.total == 0 ? 'No one invited yet. Send your invitation from the Send tab.' : 'No one has said yes yet. Replies show up here.',
                      1 => 'Everyone has replied. 🎉',
                      _ => 'No one has said no. 🙌',
                    },
                    textAlign: TextAlign.center,
                    style: body(14, color: HC.muted),
                  ),
                )
              else ...[
                if (guestTab == 1 && shown.any((g) => !g.replied && (g.invitee?.phoneDigits.isNotEmpty ?? false)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), side: const BorderSide(color: HC.line)),
                      onPressed: () => _remindAllPending(shown),
                      icon: Icon(Icons.notifications_active_outlined, size: 18, color: HC.violet),
                      label: Text('Remind everyone who hasn\'t replied', style: body(14, weight: FontWeight.w600)),
                    ),
                  ),
                for (final g in shown) _GuestRow(entry: g, onRemind: (how) => _sendOne(g.invitee!, how, remind: true)),
              ],
              if (food.isNotEmpty) ...[
                const SizedBox(height: 14),
                CardBox(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🥗 Food preferences', style: body(14, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in food)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: HC.track, borderRadius: BorderRadius.circular(20)),
                              child: Text('${foodEmoji[f.key] ?? ''} ${f.value} ${f.key}', style: body(12, weight: FontWeight.w600)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Share this with your caterer when you ask for a quote.', style: body(11, color: HC.muted)),
                    ],
                  ),
                ),
              ],
              if (board.people > 0 && board.people != e.guests) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await state.update((ev) => ev.guests = board.people);
                    if (context.mounted) toast(context, 'Guest count set to ${board.people}. Your plan and budget use it now.');
                  },
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text('Use ${board.people} as my guest count (now ${e.guests})'),
                ),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 28),
      _pitchIn(e),
    ];
  }

  Widget _pitchIn(EventDetails e) {
    return FutureBuilder<List<PitchItem>>(
      future: pitch,
      builder: (context, snap) {
        final list = snap.data ?? const <PitchItem>[];
        final taken = list.where((i) => i.claimed).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('🧺 Pitch In', style: display(18))),
                if (list.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: HC.lime, borderRadius: BorderRadius.circular(20)),
                    child: Text('$taken of ${list.length} covered', style: body(12, weight: FontWeight.w700)),
                  ),
                IconButton(tooltip: 'Refresh', onPressed: _reloadPitch, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            Text('Guests pick what to bring or how to help, right on the invite page.', style: body(12, color: HC.muted)),
            const SizedBox(height: 10),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2.5)))
            else if (list.isEmpty)
              CardBox(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Let guests chip in: drinks, desserts, setup help, cleanup crew…', style: body(14)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: HC.violet),
                          onPressed: () => _suggestPitch(e, 0),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: HC.lime),
                          label: const Text('Suggest a list from my plan'),
                        ),
                        OutlinedButton(onPressed: () => _addPitchItem(0), child: const Text('Add my own')),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              Material(
                color: HC.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: HC.line),
                      ListTile(
                        leading: Text(list[i].emoji, style: const TextStyle(fontSize: 22)),
                        title: Text(list[i].label, style: body(14, weight: FontWeight.w600)),
                        subtitle: Text(
                          list[i].claimed ? '✅ ${list[i].claimedName}' : (list[i].help ? 'Helping hand · open' : 'Open'),
                          style: body(12, color: list[i].claimed ? const Color(0xFF1F8A4C) : HC.muted, weight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded, size: 18, color: HC.muted),
                          onPressed: () async {
                            await InviteService.removeItem(inviteId!, list[i].id);
                            _reloadPitch();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addPitchItem(list.length),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add item or helper'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Full-screen look at the invitation, with save and share buttons.
class _InvitePreview extends StatefulWidget {
  const _InvitePreview({
    required this.card,
    required this.onShareCard,
    required this.onSaveImage,
    required this.onWhatsApp,
    required this.onText,
    required this.onEmail,
  });

  final Widget Function(GlobalKey key) card;
  final Future<void> Function(BuildContext from, Uint8List? png) onShareCard;
  final Future<void> Function(BuildContext from, Uint8List? png) onSaveImage;
  final Future<void> Function() onWhatsApp;
  final Future<void> Function() onText;
  final Future<void> Function() onEmail;

  @override
  State<_InvitePreview> createState() => _InvitePreviewState();
}

class _InvitePreviewState extends State<_InvitePreview> {
  final _key = GlobalKey();

  Future<void> _withPng(BuildContext from, Future<void> Function(BuildContext, Uint8List?) action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final png = await capturePng(_key);
    if (!from.mounted) return;
    await action(from, png);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HC.ground,
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: Center(child: BackArrow())),
        leadingWidth: 60,
        title: const Text('Preview'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text('This is what your guests see.', textAlign: TextAlign.center, style: body(13, color: HC.muted)),
                const SizedBox(height: 12),
                widget.card(_key),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (b) => OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), side: const BorderSide(color: HC.line), backgroundColor: HC.card),
                          onPressed: () => _withPng(b, widget.onSaveImage),
                          icon: const Icon(Icons.download_rounded, size: 20, color: HC.ink),
                          label: Text(kIsWeb ? 'Download' : 'Save image', style: body(15, weight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Builder(
                        builder: (b) => FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 50)),
                          onPressed: () => _withPng(b, widget.onShareCard),
                          icon: const Icon(Icons.ios_share_rounded, size: 20),
                          label: const Text('Share card'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _MiniAction(emoji: '💬', label: 'WhatsApp', onTap: widget.onWhatsApp)),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniAction(emoji: '✉️', label: 'Messages', onTap: widget.onText)),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniAction(emoji: '📧', label: 'Email', onTap: widget.onEmail)),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop('send'),
                  icon: const Icon(Icons.people_alt_outlined, size: 18),
                  label: const Text('Send to my guest list'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tip: "Share card" sends the picture with the RSVP link. Pick WhatsApp, Messages or Gmail from the list.',
                  textAlign: TextAlign.center,
                  style: body(12, color: HC.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.emoji, required this.label, required this.onTap});
  final String emoji;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              Text(label, style: body(12, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendTile extends StatelessWidget {
  const _SendTile({required this.emoji, required this.label, required this.sub, required this.onTap});
  final String emoji;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HC.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(label, style: body(14, weight: FontWeight.w700)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(11, color: HC.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Send buttons for one person: WhatsApp, text and email, each with their own link.
class _SendButtons extends StatelessWidget {
  const _SendButtons({required this.person, required this.onSend, this.verb = 'Send'});
  final Invitee person;
  final void Function(String how) onSend;
  final String verb;

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p.phoneDigits.isNotEmpty)
          IconButton(
            tooltip: '$verb on WhatsApp',
            onPressed: () => onSend('whatsapp'),
            icon: const Icon(Icons.chat_rounded, size: 20, color: Color(0xFF1FA855)),
          ),
        if (p.phoneDigits.isNotEmpty)
          IconButton(
            tooltip: '$verb a text',
            onPressed: () => onSend('sms'),
            icon: Icon(Icons.sms_outlined, size: 20, color: HC.violet),
          ),
        if (p.email.isNotEmpty)
          IconButton(
            tooltip: '$verb an email',
            onPressed: () => onSend('email'),
            icon: Icon(Icons.mail_outline_rounded, size: 20, color: HC.violet),
          ),
      ],
    );
  }
}

class _InviteeRow extends StatelessWidget {
  const _InviteeRow({required this.person, required this.status, required this.onSend, required this.onRemove});
  final Invitee person;
  final String status;
  final void Function(String how) onSend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final sent = p.sentAt != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          CircleAvatar(radius: 18, backgroundColor: HC.track, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: body(14, weight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w600)),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(12, color: sent ? const Color(0xFF1F8A4C) : HC.muted, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _SendButtons(person: p, onSend: onSend),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: HC.muted),
            onSelected: (_) => onRemove(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove from list'))],
          ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.entry, required this.onRemind});
  final GuestEntry entry;
  final void Function(String how) onRemind;

  @override
  Widget build(BuildContext context) {
    final r = entry.rsvp;
    final i = entry.invitee;
    final String line;
    if (r == null) {
      line = i?.sentAt == null ? 'Not sent yet' : 'Invited ${DateFormat('MMM d').format(i!.sentAt!)} · no reply yet';
    } else if (r.status == RsvpStatus.no) {
      line = 'Can\'t make it';
    } else {
      line = '${r.status.label} · ${r.adults} adult${r.adults == 1 ? '' : 's'}${r.kids > 0 ? ', ${r.kids} kid${r.kids == 1 ? '' : 's'}' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(r?.status.emoji ?? '⏳', style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: body(15, weight: FontWeight.w600)),
                  Text(line, style: body(12, color: HC.muted)),
                  if (r != null && r.diet.isNotEmpty) Text(r.diet.map((d) => '${foodEmoji[d] ?? ''} $d').join('  '), style: body(12, color: HC.violet)),
                  if (r != null && r.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('"${r.note}"', style: body(13)),
                  ],
                ],
              ),
            ),
            if (i != null && (r == null || r.status == RsvpStatus.maybe)) _SendButtons(person: i, onSend: onRemind, verb: 'Remind by'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.emoji, required this.color, required this.selected, required this.onTap});
  final String value;
  final String label;
  final String emoji;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? HC.ink : Colors.transparent, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$emoji $value', style: display(22)),
              Text(label, style: body(12, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line for the Plan page: "5 going · 3 pending · 1 can't go".
class InviteStatusLine extends StatefulWidget {
  const InviteStatusLine({super.key, required this.event, required this.hostUid, required this.style});
  final EventDetails event;
  final String? hostUid;
  final TextStyle style;

  @override
  State<InviteStatusLine> createState() => _InviteStatusLineState();
}

class _InviteStatusLineState extends State<InviteStatusLine> {
  Future<List<Rsvp>?>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(InviteStatusLine old) {
    super.didUpdateWidget(old);
    if (old.event.id != widget.event.id || old.event.updatedAt != widget.event.updatedAt || old.hostUid != widget.hostUid) _load();
  }

  void _load() {
    final uid = widget.hostUid;
    future = uid == null
        ? Future.value(null)
        : InviteService.rsvps(inviteIdFor(uid, widget.event.id)).then<List<Rsvp>?>((v) => v).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return FutureBuilder<List<Rsvp>?>(
      future: future,
      builder: (context, snap) {
        final list = snap.data ?? const <Rsvp>[];
        if (e.invitees.isEmpty && list.isEmpty) {
          return Text('Design · Share · Track RSVPs', style: widget.style);
        }
        final b = groupGuests(e.invitees, list);
        return Text('🎉 ${b.going.length} going · ⏳ ${b.pending.length} pending · 😢 ${b.cantGo.length} can\'t go', style: widget.style);
      },
    );
  }
}


/// What the host picked in the share sheet.
class _ShareChoice {
  const _ShareChoice(this.app, {required this.picture, required this.video});
  final String app;
  final bool picture;
  final bool video;
}

/// The share sheet: big app icons, then switches for the card picture and the video.
class _SharePicker extends StatefulWidget {
  const _SharePicker({required this.hasImage, this.hasVideo = false, this.videoOn = true});
  final bool hasImage;

  /// The host recorded their own video, which can go along with the invite.
  final bool hasVideo;
  final bool videoOn;

  @override
  State<_SharePicker> createState() => _SharePickerState();
}

class _SharePickerState extends State<_SharePicker> {
  late bool picture = widget.hasImage;
  late bool video = widget.hasVideo && widget.videoOn;

  static final _apps = <(String, String, Color, IconData?, String?)>[
    ('whatsapp', 'WhatsApp', Color(0xFF25D366), Icons.chat_rounded, null),
    ('messages', 'Messages', Color(0xFF34C759), Icons.sms_rounded, null),
    ('email', 'Email', Color(0xFF1F6FEB), Icons.alternate_email_rounded, null),
    ('instagram', 'Instagram', Color(0xFFD6336C), Icons.camera_alt_rounded, null),
    ('gmail', 'Gmail', Color(0xFFEA4335), Icons.mail_rounded, null),
    ('facebook', 'Facebook', Color(0xFF1877F2), null, 'f'),
    ('copy', 'Copy link', Color(0xFF5E5A72), Icons.link_rounded, null),
    ('all', 'More', HC.ink, Icons.more_horiz_rounded, null),
  ];

  void _go(String app) => Navigator.pop(context, _ShareChoice(app, picture: picture, video: video));

  Widget _switch(IconData icon, String label, bool value, ValueChanged<bool> onChanged, {bool top = false}) {
    return Container(
      decoration: BoxDecoration(border: top ? const Border(top: BorderSide(color: HC.line)) : null),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: HC.violet),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: body(14))),
          Switch.adaptive(value: value, activeTrackColor: HC.violet, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = [
      for (final a in _apps)
        if (widget.hasImage || a.$1 != 'instagram') a,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send to guests', style: display(22)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
              children: [
                for (final a in apps)
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _go(a.$1),
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(color: a.$3, borderRadius: BorderRadius.circular(18)),
                          alignment: Alignment.center,
                          child: a.$4 != null ? Icon(a.$4, color: Colors.white, size: 26) : Text(a.$5!, style: display(26, color: Colors.white)),
                        ),
                        const SizedBox(height: 6),
                        Text(a.$2, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: body(12, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(color: HC.ground, borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (widget.hasImage) _switch(Icons.image_outlined, 'Attach the card picture', picture, (v) => setState(() => picture = v)),
                  if (widget.hasVideo) _switch(Icons.movie_outlined, 'Attach your video', video, (v) => setState(() => video = v), top: widget.hasImage),
                  if (widget.hasImage)
                    InkWell(
                      onTap: () => _go('save'),
                      child: Container(
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: HC.line))),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        child: Row(
                          children: [
                            Icon(Icons.download_rounded, size: 20, color: HC.violet),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Save to Photos', style: body(14))),
                            const Icon(Icons.chevron_right_rounded, color: HC.muted),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Each message includes your RSVP link, so replies show up in Guests. '
              'WhatsApp, Messages and email send the link; tap More to send the picture or video too.',
              textAlign: TextAlign.center,
              style: body(12, color: HC.muted),
            ),
          ],
        ),
      ),
    );
  }
}
