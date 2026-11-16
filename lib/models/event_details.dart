import '../services/invite_service.dart';
import '../services/location_service.dart';
import 'invite_video.dart';
import 'photo_frame.dart';

/// Who the event is mainly for. Drives which games get suggested.
enum Audience { kids, adults, everyone }

extension AudienceLabel on Audience {
  String get label => switch (this) {
        Audience.kids => 'Kids + parents',
        Audience.adults => 'Adults',
        Audience.everyone => 'All ages',
      };
}

const occasions = ['Birthday', 'Housewarming', 'Baby shower', 'Pooja', 'Anniversary', 'Get-together'];

/// More occasions, by group: name → (emoji, the main occasion whose plan,
/// games and helpers fit it best).
const moreOccasions = <String, Map<String, (String, String)>>{
  'Life events': {
    'Graduation': ('🎓', 'Get-together'),
    'Engagement': ('💍', 'Anniversary'),
    'Wedding': ('💒', 'Anniversary'),
    'Wedding reception': ('🥂', 'Anniversary'),
    'Sangeet / Mehndi': ('💃', 'Anniversary'),
    'Bridal shower': ('👰', 'Baby shower'),
    'Bachelor / bachelorette': ('🍾', 'Get-together'),
    'Retirement party': ('🎊', 'Get-together'),
    'Farewell': ('👋', 'Get-together'),
    'Welcome party': ('🤗', 'Get-together'),
    'Promotion / new job': ('🏆', 'Get-together'),
  },
  'Kids and family': {
    'Gender reveal': ('🎈', 'Baby shower'),
    'Naming ceremony': ('👶', 'Pooja'),
    'Annaprasana (first rice)': ('🍚', 'Pooja'),
    'Upanayanam (thread ceremony)': ('🧵', 'Pooja'),
    'Half saree / dhoti ceremony': ('🥻', 'Pooja'),
    'Sweet 16': ('🎀', 'Birthday'),
    'Quinceañera': ('👑', 'Birthday'),
    'Bar / Bat Mitzvah': ('✡️', 'Birthday'),
    'Baptism / christening': ('🕊️', 'Pooja'),
    'First Communion': ('✝️', 'Pooja'),
    'Kids playdate': ('🧸', 'Birthday'),
    'Family reunion': ('🫂', 'Get-together'),
  },
  'Festivals and holidays': {
    'Diwali': ('🪔', 'Pooja'),
    'Holi': ('🎨', 'Get-together'),
    'Ganesh Chaturthi': ('🐘', 'Pooja'),
    'Navratri / Garba': ('💃', 'Get-together'),
    'Sankranti / Pongal': ('🪁', 'Pooja'),
    'Ugadi': ('🌿', 'Pooja'),
    'Satyanarayana Pooja': ('🙏', 'Pooja'),
    'Varalakshmi Vratham': ('🪷', 'Pooja'),
    'Eid': ('🌙', 'Get-together'),
    'Christmas': ('🎄', 'Get-together'),
    'Thanksgiving': ('🦃', 'Get-together'),
    'Friendsgiving': ('🥧', 'Get-together'),
    'New Year': ('🎆', 'Get-together'),
    'Lunar New Year': ('🧧', 'Get-together'),
    'Hanukkah': ('🕎', 'Get-together'),
    'Easter': ('🐣', 'Get-together'),
    'Halloween': ('🎃', 'Get-together'),
    'Fourth of July': ('🎇', 'Get-together'),
  },
  'Get-togethers': {
    'Game night': ('🎲', 'Get-together'),
    'Potluck': ('🍲', 'Get-together'),
    'BBQ / cookout': ('🍔', 'Get-together'),
    'Game-day watch party': ('📺', 'Get-together'),
    'Kitty party': ('👛', 'Get-together'),
    'Office party': ('💼', 'Get-together'),
    'Book club': ('📚', 'Get-together'),
    'Dinner party': ('🍽️', 'Get-together'),
  },
};

const _mainEmoji = {'Birthday': '🎂', 'Housewarming': '🏡', 'Baby shower': '🍼', 'Pooja': '🪔', 'Anniversary': '💍', 'Get-together': '🎉'};

(String, String)? _findMore(String occasion) {
  for (final g in moreOccasions.values) {
    final hit = g[occasion];
    if (hit != null) return hit;
  }
  return null;
}

/// The main occasion whose plan fits [occasion] (typed-in occasions are guessed from their words).
String occasionKind(String occasion) {
  if (occasions.contains(occasion)) return occasion;
  final more = _findMore(occasion);
  if (more != null) return more.$2;
  final o = occasion.toLowerCase();
  if (RegExp(r'birthday|bday|b-day|turning \d').hasMatch(o)) return 'Birthday';
  if (RegExp(r'wedding|anniversar|engage').hasMatch(o)) return 'Anniversary';
  if (RegExp(r'house|home').hasMatch(o)) return 'Housewarming';
  if (RegExp(r'baby|shower|seemantham').hasMatch(o)) return 'Baby shower';
  if (RegExp(r'pooja|puja|vrat|havan|prayer|temple|blessing').hasMatch(o)) return 'Pooja';
  return 'Get-together';
}

/// An emoji for any occasion.
String occasionIcon(String occasion) => _mainEmoji[occasion] ?? _findMore(occasion)?.$1 ?? _mainEmoji[occasionKind(occasion)] ?? '🎉';

/// How lively the party should be: 0 Calm, 1 Lively, 2 Loud, 3 Wild.
const energyLevels = ['Calm', 'Lively', 'Loud', 'Wild'];

/// A helper the user saved from the Nearby tab (photographer, panthulu, ...).
class ShortlistVendor {
  ShortlistVendor({required this.id, required this.category, required this.name, this.phone = '', this.note = ''});

  final String id;
  final String category;
  final String name;
  final String phone;
  final String note;

  Map<String, dynamic> toMap() => {'id': id, 'category': category, 'name': name, 'phone': phone, 'note': note};

  factory ShortlistVendor.fromMap(Map<String, dynamic> m) => ShortlistVendor(
        id: m['id'] as String? ?? '',
        category: m['category'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        note: m['note'] as String? ?? '',
      );
}

/// A game reel the user saved (for example from Instagram) to play later.
class SavedLink {
  SavedLink({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toMap() => {'title': title, 'url': url};

  factory SavedLink.fromMap(Map<String, dynamic> m) =>
      SavedLink(title: m['title'] as String? ?? 'Saved game', url: m['url'] as String? ?? '');
}

/// Everything the user told us about their event, plus their choices.
class EventDetails {
  EventDetails({
    required this.id,
    required this.occasion,
    required this.title,
    required this.date,
    required this.startMinutes,
    required this.hours,
    required this.indoor,
    required this.guests,
    required this.audience,
    required this.energy,
    List<String>? gameIds,
    List<String>? doneTasks,
    List<ShortlistVendor>? shortlist,
    List<SavedLink>? savedLinks,
    Map<String, DateTime>? taskReminders,
    List<Invitee>? invitees,
    this.customTimeline,
    List<CustomTask>? customTasks,
    List<String>? hiddenTasks,
    this.budgetItems,
    List<TodoItem>? todos,
    this.inviteMessage = '',
    this.inviteTitle = '',
    this.invitePhoto = '',
    this.inviteTheme = 'midnight',
    this.inviteHost = '',
    this.inviteMotif = '',
    this.guestNotice = '',
    this.noticeKind = '',
    this.inviteVideo = const InviteVideo(),
    this.inviteExtra = '',
    this.invitePhotoFrame = const PhotoFrame(),
    this.budget,
    this.venue,
    this.status = 'active',
    DateTime? updatedAt,
  })  : gameIds = gameIds ?? [],
        doneTasks = doneTasks ?? [],
        shortlist = shortlist ?? [],
        savedLinks = savedLinks ?? [],
        taskReminders = taskReminders ?? {},
        invitees = invitees ?? [],
        customTasks = customTasks ?? [],
        hiddenTasks = hiddenTasks ?? [],
        todos = todos ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String occasion;

  /// The main occasion whose plan fits this one (a Graduation plans like a Get-together).
  String get kind => occasionKind(occasion);
  String title;
  DateTime date;

  /// Start time as minutes after midnight (16:00 = 960).
  int startMinutes;
  int hours;
  bool indoor;
  int guests;
  Audience audience;
  int energy;

  /// Games the user has in their plan, in play order.
  List<String> gameIds;
  List<String> doneTasks;
  List<ShortlistVendor> shortlist;
  List<SavedLink> savedLinks;

  /// The host's own timeline (after editing, moving or removing steps).
  /// Null means Hoopla's suggested timeline.
  List<CustomStep>? customTimeline;

  /// Checklist tasks the host added, or suggested ones they edited (same id).
  List<CustomTask> customTasks;

  /// Suggested checklist tasks the host removed.
  List<String> hiddenTasks;

  /// The host's own budget (amounts, vendors, paid). Null = Hoopla's suggested split.
  List<BudgetItem>? budgetItems;

  /// "My list": the host's own to-dos and notes.
  List<TodoItem> todos;

  /// People the host invited (their RSVPs live in invites/{hostUid}_{id}/rsvps).
  List<Invitee> invitees;

  /// The host's note on the invite.
  String inviteMessage;

  /// The invitation's headline ('' = the event title).
  String inviteTitle;

  /// Photo on the invitation (download link in Firebase Storage), or ''.
  String invitePhoto;

  /// Look of the invitation card (see inviteThemes).
  String inviteTheme;

  /// "Hosted by" names on the invitation ('' = not shown).
  String inviteHost;

  /// Any other text on the invitation: dress code, parking, RSVP by…
  String inviteExtra;

  /// Emoji decoration from the chosen design, e.g. "🦖🎈🌴".
  String inviteMotif;

  /// News for guests on the invite page (reason and note), and what it's about:
  /// '' (nothing), 'cancelled', 'updated' or 'back'.
  String guestNotice;
  String noticeKind;

  /// The 30-second invitation video (photos played as a slideshow).
  InviteVideo inviteVideo;

  /// How the invitation photo is cropped.
  PhotoFrame invitePhotoFrame;

  /// What the invitation says at the top.
  String get inviteHeadline => inviteTitle.trim().isNotEmpty ? inviteTitle.trim() : title;

  /// Reminders the user set on checklist tasks: task id → when to remind.
  Map<String, DateTime> taskReminders;
  double? budget;

  /// Where the party is (for the weather and for finding providers nearby).
  /// Null until the user picks one.
  Place? venue;

  /// 'active' or 'cancelled'. Cancelled events stay in My events and can be restored.
  String status;
  DateTime updatedAt;

  bool get isActive => status == 'active';

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  int get daysToGo {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return day.difference(today).inDays;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'occasion': occasion,
        'title': title,
        'date': DateTime(date.year, date.month, date.day).toIso8601String(),
        'startMinutes': startMinutes,
        'hours': hours,
        'indoor': indoor,
        'guests': guests,
        'audience': audience.name,
        'energy': energy,
        'gameIds': gameIds,
        'doneTasks': doneTasks,
        'shortlist': shortlist.map((v) => v.toMap()).toList(),
        'savedLinks': savedLinks.map((l) => l.toMap()).toList(),
        'invitees': invitees.map((i) => i.toMap()).toList(),
        'customTimeline': customTimeline?.map((c) => c.toMap()).toList(),
        'customTasks': customTasks.map((c) => c.toMap()).toList(),
        'hiddenTasks': hiddenTasks,
        'budgetItems': budgetItems?.map((b) => b.toMap()).toList(),
        'todos': todos.map((t) => t.toMap()).toList(),
        'inviteMessage': inviteMessage,
        'inviteTitle': inviteTitle,
        'invitePhoto': invitePhoto,
        'inviteTheme': inviteTheme,
        'inviteHost': inviteHost,
        'inviteMotif': inviteMotif,
        'guestNotice': guestNotice,
        'noticeKind': noticeKind,
        'inviteVideo': inviteVideo.toMap(),
        'inviteExtra': inviteExtra,
        'invitePhotoFrame': invitePhotoFrame.toMap(),
        'taskReminders': {for (final r in taskReminders.entries) r.key: r.value.toUtc().toIso8601String()},
        'budget': budget,
        'venue': venue?.toMap(),
        'status': status,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory EventDetails.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>> maps(Object? v) =>
        (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return EventDetails(
      id: m['id'] as String? ?? newId(),
      occasion: m['occasion'] as String? ?? occasions.first,
      title: m['title'] as String? ?? '',
      date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
      startMinutes: (m['startMinutes'] as num?)?.toInt() ?? 16 * 60,
      hours: (m['hours'] as num?)?.toInt() ?? 3,
      indoor: m['indoor'] as bool? ?? true,
      guests: (m['guests'] as num?)?.toInt() ?? 30,
      audience: Audience.values.firstWhere((a) => a.name == m['audience'], orElse: () => Audience.kids),
      energy: (m['energy'] as num?)?.toInt() ?? 1,
      gameIds: List<String>.from(m['gameIds'] as List? ?? const []),
      doneTasks: List<String>.from(m['doneTasks'] as List? ?? const []),
      shortlist: maps(m['shortlist']).map(ShortlistVendor.fromMap).toList(),
      savedLinks: maps(m['savedLinks']).map(SavedLink.fromMap).toList(),
      invitees: maps(m['invitees']).map(Invitee.fromMap).toList(),
      customTimeline: m['customTimeline'] is List ? maps(m['customTimeline']).map(CustomStep.fromMap).toList() : null,
      customTasks: maps(m['customTasks']).map(CustomTask.fromMap).toList(),
      hiddenTasks: List<String>.from(m['hiddenTasks'] as List? ?? const []),
      budgetItems: m['budgetItems'] is List ? maps(m['budgetItems']).map(BudgetItem.fromMap).toList() : null,
      todos: maps(m['todos']).map(TodoItem.fromMap).toList(),
      inviteMessage: m['inviteMessage'] as String? ?? '',
      inviteTitle: m['inviteTitle'] as String? ?? '',
      invitePhoto: m['invitePhoto'] as String? ?? '',
      inviteTheme: m['inviteTheme'] as String? ?? 'midnight',
      inviteHost: m['inviteHost'] as String? ?? '',
      inviteMotif: m['inviteMotif'] as String? ?? '',
      guestNotice: m['guestNotice'] as String? ?? '',
      noticeKind: m['noticeKind'] as String? ?? '',
      inviteVideo: InviteVideo.fromMap(m['inviteVideo']),
      inviteExtra: m['inviteExtra'] as String? ?? '',
      invitePhotoFrame: PhotoFrame.fromMap(m['invitePhotoFrame']),
      taskReminders: {
        for (final r in (m['taskReminders'] as Map? ?? const {}).entries)
          if (DateTime.tryParse('${r.value}') != null) '${r.key}': DateTime.parse('${r.value}').toLocal(),
      },
      budget: (m['budget'] as num?)?.toDouble(),
      venue: Place.fromMap(m['venue']),
      status: m['status'] as String? ?? 'active',
      updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '')?.toLocal(),
    );
  }
}

/// One step of a timeline the host edited.
class CustomStep {
  CustomStep({required this.key, required this.title, required this.subtitle, required this.minutes, required this.kind, this.gameId});

  /// Stable id for the step ("game_freeze_dance", "food", "custom_1700000000").
  final String key;
  String title;
  String subtitle;
  int minutes;

  /// welcome, game, moment, food, wrap, free or custom.
  final String kind;
  final String? gameId;

  Map<String, dynamic> toMap() => {'key': key, 'title': title, 'subtitle': subtitle, 'minutes': minutes, 'kind': kind, 'gameId': gameId};

  factory CustomStep.fromMap(Map<String, dynamic> m) => CustomStep(
        key: m['key'] as String? ?? '',
        title: m['title'] as String? ?? '',
        subtitle: m['subtitle'] as String? ?? '',
        minutes: (m['minutes'] as num?)?.toInt() ?? 10,
        kind: m['kind'] as String? ?? 'free',
        gameId: m['gameId'] as String?,
      );
}

/// A checklist task the host added or edited. [daysBefore] = due that many days before the party.
class CustomTask {
  CustomTask({required this.id, required this.label, required this.daysBefore});
  final String id;
  String label;
  int daysBefore;

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'daysBefore': daysBefore};

  factory CustomTask.fromMap(Map<String, dynamic> m) =>
      CustomTask(id: m['id'] as String? ?? '', label: m['label'] as String? ?? '', daysBefore: (m['daysBefore'] as num?)?.toInt() ?? 7);
}

/// One line of the host's budget: what it's for, the planned amount, and (once booked)
/// who's doing it, what it actually costs and whether it's paid.
class BudgetItem {
  BudgetItem({
    required this.id,
    required this.label,
    this.planned = 0,
    this.vendor = '',
    this.vendorPhone = '',
    this.actual,
    this.paid = false,
  });

  final String id;
  String label;
  double planned;

  /// Their own photographer, cook, decorator... (or one found on Hoopla).
  String vendor;
  String vendorPhone;
  double? actual;
  bool paid;

  /// What it really costs if known, otherwise the plan.
  double get cost => actual ?? planned;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'planned': planned,
        'vendor': vendor,
        'vendorPhone': vendorPhone,
        'actual': actual,
        'paid': paid,
      };

  factory BudgetItem.fromMap(Map<String, dynamic> m) => BudgetItem(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        planned: (m['planned'] as num?)?.toDouble() ?? 0,
        vendor: m['vendor'] as String? ?? '',
        vendorPhone: m['vendorPhone'] as String? ?? '',
        actual: (m['actual'] as num?)?.toDouble(),
        paid: m['paid'] as bool? ?? false,
      );
}

/// A to-do on "My list".
class TodoItem {
  TodoItem({required this.id, required this.text, this.done = false, this.due});
  final String id;
  String text;
  bool done;
  DateTime? due;

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'done': done, 'due': due?.toIso8601String()};

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'] as String? ?? '',
        text: m['text'] as String? ?? '',
        done: m['done'] as bool? ?? false,
        due: DateTime.tryParse(m['due'] as String? ?? ''),
      );
}
