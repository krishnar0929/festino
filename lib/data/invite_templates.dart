import '../models/event_details.dart';

/// A ready-made invitation design: style, decoration and words the host can edit.
/// In [title], [message] and [extra], {title} is the event's name and
/// {date} its date, filled in when the design is picked.
class InviteTemplate {
  const InviteTemplate({
    required this.id,
    required this.name,
    required this.occasions,
    required this.theme,
    required this.motif,
    required this.title,
    required this.message,
    this.extra = '',
  });

  final String id;
  final String name;

  /// Event types it suits (empty = any).
  final List<String> occasions;
  final String theme;
  final String motif;
  final String title;
  final String message;
  final String extra;

  bool fits(String occasion) => occasions.isEmpty || occasions.contains(occasion);
}

/// Fills {title} and {date} for this event.
String fillTemplate(String text, EventDetails e, String dateLabel) =>
    text.replaceAll('{title}', e.title).replaceAll('{date}', dateLabel);

const inviteTemplates = <InviteTemplate>[
  // Birthday
  InviteTemplate(
    id: 'bday_dino',
    name: 'Dino party',
    occasions: ['Birthday'],
    theme: 'garden',
    motif: '🦖🎈🌴',
    title: '{title}',
    message: 'Get ready to ROAR! 🦖 Join us for cake, games and a dino-mite time.',
    extra: 'Kids welcome 🧒',
  ),
  InviteTemplate(
    id: 'bday_first',
    name: 'Little one turns 1',
    occasions: ['Birthday'],
    theme: 'blush',
    motif: '🎂🧸🎀',
    title: '{title}',
    message: 'Our little one is turning ONE! 🎉 Come celebrate this big milestone with us.',
  ),
  InviteTemplate(
    id: 'bday_confetti',
    name: 'Confetti pop',
    occasions: ['Birthday'],
    theme: 'confetti',
    motif: '🎉🎊🥳',
    title: '{title}',
    message: 'Let\'s party! 🥳 Cake, music, games and lots of fun.',
  ),
  InviteTemplate(
    id: 'bday_space',
    name: 'Space adventure',
    occasions: ['Birthday'],
    theme: 'midnight',
    motif: '🚀🪐⭐',
    title: '{title}',
    message: 'Blast off with us for an out-of-this-world birthday! 🚀',
  ),
  InviteTemplate(
    id: 'bday_princess',
    name: 'Princess party',
    occasions: ['Birthday'],
    theme: 'blush',
    motif: '👑🦄✨',
    title: '{title}',
    message: 'You\'re invited to a royal celebration! 👑 Come dressed in your sparkliest best.',
    extra: 'Dress code: princesses and superheroes welcome 👑',
  ),
  InviteTemplate(
    id: 'bday_grown',
    name: 'Cheers to another year',
    occasions: ['Birthday'],
    theme: 'gold',
    motif: '🥂✨🎂',
    title: '{title}',
    message: 'Cheers to another trip around the sun! 🥂 Join us for food, drinks and good company.',
  ),
  // Housewarming
  InviteTemplate(
    id: 'home_keys',
    name: 'New keys, new home',
    occasions: ['Housewarming'],
    theme: 'sunshine',
    motif: '🏡🔑🌿',
    title: '{title}',
    message: 'We\'ve got the keys! 🔑 Come see our new home and celebrate with us.',
    extra: 'Parking on the street 🚗',
  ),
  InviteTemplate(
    id: 'home_gruhapravesam',
    name: 'Gruhapravesam',
    occasions: ['Housewarming', 'Pooja'],
    theme: 'royal',
    motif: '🪔🏡🌼',
    title: '{title}',
    message: 'With the blessings of the Almighty, we invite you to our Gruhapravesam. 🙏 Your presence will make it special.',
    extra: 'Pooja followed by lunch 🍛',
  ),
  InviteTemplate(
    id: 'home_cozy',
    name: 'Cozy open house',
    occasions: ['Housewarming', 'Get-together'],
    theme: 'mint',
    motif: '🛋️🪴☕',
    title: '{title}',
    message: 'Drop by anytime! 🪴 Snacks, drinks and a tour of our new place.',
  ),
  // Baby shower
  InviteTemplate(
    id: 'baby_sweet',
    name: 'Oh baby!',
    occasions: ['Baby shower'],
    theme: 'sky',
    motif: '🍼👶🧸',
    title: '{title}',
    message: 'A little one is on the way! 🍼 Join us to shower the parents-to-be with love.',
  ),
  InviteTemplate(
    id: 'baby_seemantham',
    name: 'Seemantham',
    occasions: ['Baby shower'],
    theme: 'royal',
    motif: '🌸🪔💐',
    title: '{title}',
    message: 'Please join us for the Seemantham ceremony and bless the mother-to-be. 🌸',
    extra: 'Lunch will be served 🍛',
  ),
  InviteTemplate(
    id: 'baby_twinkle',
    name: 'Twinkle little star',
    occasions: ['Baby shower'],
    theme: 'mint',
    motif: '⭐🌙☁️',
    title: '{title}',
    message: 'Twinkle twinkle little star, we can\'t wait to meet you! ⭐ Come celebrate with us.',
  ),
  // Pooja
  InviteTemplate(
    id: 'pooja_divine',
    name: 'Divine blessings',
    occasions: ['Pooja'],
    theme: 'royal',
    motif: '🪔🌺🙏',
    title: '{title}',
    message: 'We are performing a pooja and would be honored by your presence. 🙏 Please join us for the pooja and prasadam.',
  ),
  InviteTemplate(
    id: 'pooja_festival',
    name: 'Festival lights',
    occasions: ['Pooja', 'Get-together'],
    theme: 'citrus',
    motif: '🪔✨🌼',
    title: '{title}',
    message: 'Celebrate the festival with us! 🪔 Lights, sweets and togetherness.',
  ),
  // Anniversary
  InviteTemplate(
    id: 'anni_gold',
    name: 'Golden years',
    occasions: ['Anniversary'],
    theme: 'gold',
    motif: '💍🥂✨',
    title: '{title}',
    message: 'Years of love, laughter and happily ever after. 💍 Celebrate with us!',
  ),
  InviteTemplate(
    id: 'anni_romance',
    name: 'Love story',
    occasions: ['Anniversary'],
    theme: 'blush',
    motif: '❤️🌹💕',
    title: '{title}',
    message: 'Join us as we celebrate our love story. ❤️ Dinner, dancing and memories.',
  ),
  // Get-together
  InviteTemplate(
    id: 'gt_bbq',
    name: 'Backyard BBQ',
    occasions: ['Get-together'],
    theme: 'citrus',
    motif: '🍔🌭☀️',
    title: '{title}',
    message: 'Fire up the grill! 🍔 Food, games and good vibes in the backyard.',
    extra: 'Bring your appetite (and a lawn chair) 🪑',
  ),
  InviteTemplate(
    id: 'gt_games',
    name: 'Game night',
    occasions: ['Get-together'],
    theme: 'midnight',
    motif: '🎲🃏🍿',
    title: '{title}',
    message: 'Board games, card games and snacks. 🎲 Bring your competitive side!',
  ),
  // Any event
  InviteTemplate(
    id: 'any_celebrate',
    name: 'Let\'s celebrate',
    occasions: [],
    theme: 'confetti',
    motif: '🎉✨🎈',
    title: '{title}',
    message: 'We\'d love to see you there! 🎉',
  ),
  InviteTemplate(
    id: 'any_elegant',
    name: 'Simply elegant',
    occasions: [],
    theme: 'gold',
    motif: '',
    title: '{title}',
    message: 'The pleasure of your company is requested. ✨',
  ),
  InviteTemplate(
    id: 'any_ocean',
    name: 'Ocean breeze',
    occasions: [],
    theme: 'ocean',
    motif: '🌊🐚☀️',
    title: '{title}',
    message: 'Come celebrate with us! 🌊 Good food, great company.',
  ),
];

/// Designs for this event type first, then designs that suit any event.
List<InviteTemplate> templatesFor(String occasion) => [
      for (final t in inviteTemplates) if (t.occasions.contains(occasion)) t,
      for (final t in inviteTemplates) if (t.occasions.isEmpty) t,
    ];
