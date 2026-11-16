import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/event_details.dart';

/// How fancy the party is, from Simple to Very high (multiplies every price).
const costLevels = <String, (String, double)>{
  'simple': ('Simple', 0.55),
  'medium': ('Medium', 1.0),
  'high': ('High', 1.6),
  'pro': ('Professional', 2.4),
  'lux': ('Very high', 3.6),
};

/// Short name for a level: Simple, Medium, High, Pro, Luxe.
String costLevelName(String key) => switch (key) {
      'pro' => 'Pro',
      'lux' => 'Luxe',
      _ => costLevels[key]?.$1 ?? key,
    };

/// One line on what a level means.
String costLevelHint(String key) => switch (key) {
      'simple' => 'Home-style: do-it-yourself food and decor, few extras.',
      'medium' => 'Typical: catered food, cake, some decor and a photographer.',
      'high' => 'Nicer venue, fuller menu, more decor and entertainment.',
      'pro' => 'Professional everything: planner-style decor, pro photo and video.',
      'lux' => 'Top end: premium venue, designer decor, live entertainment.',
      _ => '',
    };

/// Where the party happens (changes the venue line and food).
const venueKinds = <String, String>{
  'home': '🏠 Home / backyard',
  'hall': '🏛️ Rented hall',
  'restaurant': '🍽️ Restaurant',
  'park': '🌳 Park / outdoors',
};

/// How pricey the area is.
const areaCosts = <String, (String, double)>{
  'lower': ('Smaller town', 0.85),
  'average': ('Average', 1.0),
  'higher': ('Big city', 1.3),
};

enum CostBasis { perGuest, perHour, flat }

/// One thing a party can spend on, priced at the Medium level.
class CostItem {
  const CostItem(this.id, this.label, this.emoji, this.basis, this.usd, this.inr, {this.helper, this.seasonal = true});
  final String id;
  final String label;
  final String emoji;
  final CostBasis basis;

  /// (low, high) at Medium, in US dollars and in Indian rupees.
  final (double, double) usd;
  final (double, double) inr;

  /// Nearby category that sells it ("Find" link).
  final String? helper;

  /// Busy season and weekends raise the price.
  final bool seasonal;
}

const costItems = <CostItem>[
  CostItem('venue', 'Venue / hall', '🏛️', CostBasis.flat, (400, 1000), (10000, 30000)),
  CostItem('food', 'Food & drinks', '🍛', CostBasis.perGuest, (18, 30), (350, 700), helper: 'Caterers'),
  CostItem('cake', 'Cake & desserts', '🎂', CostBasis.perGuest, (2.5, 4.5), (60, 120), helper: 'Cake makers'),
  CostItem('decor', 'Decorations', '🎈', CostBasis.flat, (250, 600), (8000, 20000), helper: 'Decorators'),
  CostItem('photo', 'Photographer', '📸', CostBasis.perHour, (100, 175), (2500, 5000), helper: 'Photographers'),
  CostItem('video', 'Videographer', '🎥', CostBasis.perHour, (125, 225), (3000, 6000), helper: 'Videographers'),
  CostItem('artists', 'Entertainment & artists', '🎤', CostBasis.flat, (250, 700), (5000, 20000), helper: 'Kids entertainers'),
  CostItem('dj', 'DJ & sound', '🎧', CostBasis.perHour, (100, 200), (2000, 5000), helper: 'DJs'),
  CostItem('rentals', 'Chairs, tables & tent', '🪑', CostBasis.perGuest, (6, 12), (100, 250), helper: 'Rentals'),
  CostItem('gifts', 'Return gifts / favors', '🎁', CostBasis.perGuest, (3, 8), (100, 300), seasonal: false),
  CostItem('priest', 'Priest / panthulu', '🪔', CostBasis.flat, (150, 350), (2500, 7000), helper: 'Panthulu'),
  CostItem('makeup', 'Makeup & mehndi', '💄', CostBasis.flat, (150, 400), (3000, 10000), helper: 'Makeup'),
  CostItem('cleaning', 'Cleaning & helpers', '🧹', CostBasis.perHour, (40, 80), (400, 800), helper: 'Cleaners & maids'),
  CostItem('transport', 'Transport', '🚐', CostBasis.flat, (150, 400), (3000, 8000), helper: 'Transport'),
  CostItem('invites', 'Invitations', '💌', CostBasis.flat, (0, 40), (0, 1000), seasonal: false),
];

/// What most parties of this kind need (what's ticked before the host changes it).
List<String> defaultCostPicks(EventDetails e) {
  final kind = e.kind;
  final kids = e.audience == Audience.kids;
  final venue = venueKindFor(e);
  return [
    if (venue != 'home') 'venue',
    'food',
    if (kind == 'Birthday' || kind == 'Anniversary') 'cake',
    'decor',
    'photo',
    if (kind == 'Birthday' && kids) ...['artists', 'gifts'],
    if (kind == 'Pooja' || kind == 'Housewarming') 'priest',
    if (kind == 'Baby shower') 'makeup',
    if (kind == 'Anniversary' || kind == 'Get-together') 'dj',
    if (venue == 'home' || venue == 'park') 'rentals',
    'cleaning',
    'invites',
  ];
}

/// The host's venue type, or a sensible guess.
String venueKindFor(EventDetails e) =>
    venueKinds.containsKey(e.venueKind) ? e.venueKind : (e.indoor ? (e.guests > 60 ? 'hall' : 'home') : 'park');

/// Busy months cost more (holidays, wedding season); quiet months less.
double seasonFactor(DateTime d) => switch (d.month) {
      11 || 12 => 1.15,
      5 || 6 || 10 => 1.1,
      1 || 2 => 0.9,
      _ => 1.0,
    };

/// Saturdays cost the most, weekdays the least.
double dayFactor(DateTime d) => switch (d.weekday) {
      DateTime.saturday => 1.1,
      DateTime.friday || DateTime.sunday => 1.05,
      _ => 0.95,
    };

/// One priced line of the estimate.
class CostLine {
  const CostLine(this.item, this.low, this.high, this.how, {this.included = true});
  final CostItem item;
  final double low;
  final double high;

  /// "30 guests × $18–30", "3 hrs × $100–175"…
  final String how;

  /// False for lines that don't apply (a venue at home).
  final bool included;
  double get mid => (low + high) / 2;
}

/// The whole estimate: every line, plus totals for the ticked ones.
class CostEstimate {
  const CostEstimate({required this.lines, required this.picks, required this.india, required this.notes});
  final List<CostLine> lines;
  final Set<String> picks;
  final bool india;

  /// What changed the prices ("February: quieter season −10%").
  final List<String> notes;

  Iterable<CostLine> get picked => lines.where((l) => picks.contains(l.item.id) && l.included);
  double get low => picked.fold(0, (a, l) => a + l.low);
  double get high => picked.fold(0, (a, l) => a + l.high);
  double get mid => (low + high) / 2;

  String money(num v) => formatMoney(v, india: india);
  String range(CostLine l) => l.high <= 0 ? 'Free' : '${money(l.low)}–${money(l.high)}';
}

/// "$1,800" or "₹1,80,000", rounded to a friendly number.
String formatMoney(num v, {required bool india}) {
  final step = v >= 10000 ? 100 : (v >= 1000 ? 50 : (v >= 100 ? 10 : 1));
  final r = (v / step).round() * step;
  return india
      ? NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(r)
      : NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0).format(r);
}

/// Estimates what the party costs, item by item, from its guests, hours, date,
/// place, venue type, area and the chosen level.
CostEstimate estimateCost(
  EventDetails e, {
  String? level,
  Set<String>? picks,
  String? venueKind,
  String? area,
}) {
  final india = e.venue?.countryCode == 'in';
  final lvl = costLevels[level ?? e.costLevel]?.$2 ?? 1.0;
  final areaF = areaCosts[area ?? e.areaCost]?.$2 ?? 1.0;
  final venue = venueKinds.containsKey(venueKind) ? venueKind! : venueKindFor(e);
  final season = seasonFactor(e.date), day = dayFactor(e.date);
  final g = math.max(1, e.guests);
  final hours = math.max(1, e.hours);
  // Decor and entertainment grow with the crowd, but slower than per-guest items.
  final crowd = (math.sqrt(g / 30)).clamp(0.7, 3.0);
  final cur = india ? '₹' : '\$';

  String num0(double v) => formatMoney(v, india: india);

  final lines = <CostLine>[];
  for (final it in costItems) {
    var (lo, hi) = india ? it.inr : it.usd;
    var how = '';
    var included = true;
    switch (it.basis) {
      case CostBasis.perGuest:
        how = '$g guests × ${num0(lo * lvl * areaF)}–${num0(hi * lvl * areaF)}';
        lo *= g;
        hi *= g;
      case CostBasis.perHour:
        final h = it.id == 'cleaning' ? hours + 2 : hours;
        how = '$h hrs × ${num0(lo * lvl * areaF)}–${num0(hi * lvl * areaF)}';
        lo *= h;
        hi *= h;
      case CostBasis.flat:
        if (it.id == 'decor' || it.id == 'artists') {
          lo *= crowd;
          hi *= crowd;
          how = 'For about $g guests';
        } else {
          how = 'One-time';
        }
    }
    if (it.id == 'venue') {
      // Bigger crowds need bigger rooms.
      final size = g <= 25 ? 0.5 : (g <= 60 ? 1.0 : (g <= 120 ? 2.0 : 3.8));
      lo *= size;
      hi *= size;
      switch (venue) {
        case 'home':
          included = false;
          how = 'Your home: no venue cost';
        case 'restaurant':
          included = false;
          how = 'Included in the restaurant\'s food price';
        case 'park':
          lo *= 0.15;
          hi *= 0.3;
          how = 'Park permit or pavilion';
        default:
          how = 'Hall for about $g guests';
      }
    }
    if (it.id == 'food' && venue == 'restaurant') {
      lo *= 1.4;
      hi *= 1.4;
      how = '$how (restaurant prices)';
    }
    if (it.id == 'invites') how = 'Free with Hoopla · printed cards cost extra';
    final f = lvl * areaF * (it.seasonal ? season * day : 1.0);
    lines.add(CostLine(it, lo * f, hi * f, how, included: included));
  }

  final notes = <String>[
    if (season > 1) '${DateFormat('MMMM').format(e.date)} is a busy season (+${((season - 1) * 100).round()}%)',
    if (season < 1) '${DateFormat('MMMM').format(e.date)} is a quieter season (−${((1 - season) * 100).round()}%)',
    if (day > 1) '${DateFormat('EEEE').format(e.date)}s cost a little more (+${((day - 1) * 100).round()}%)',
    if (day < 1) 'Weekday party: a little cheaper (−${((1 - day) * 100).round()}%)',
    if (areaF != 1) '${areaCosts[area ?? e.areaCost]!.$1} prices (${areaF > 1 ? '+' : '−'}${((areaF - 1).abs() * 100).round()}%)',
    'Prices in $cur. Rough ranges: real quotes vary by provider.',
  ];

  return CostEstimate(
    lines: lines,
    picks: picks ?? (e.costPicks?.toSet() ?? defaultCostPicks(e).toSet()),
    india: india,
    notes: notes,
  );
}
