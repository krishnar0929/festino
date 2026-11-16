/// Kinds of nearby helpers, with the phrase used to search for them on maps.
class HelperCategory {
  const HelperCategory(this.label, this.search);
  final String label;
  final String search;

  Uri get mapsSearch => mapsSearchNear(null);

  /// Google Maps search for this service near a place ("near me" when none).
  Uri mapsSearchNear(String? place) =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$search near ${place == null || place.isEmpty ? 'me' : place}'});
}

const helperCategories = <HelperCategory>[
  HelperCategory('Photographers', 'event photographer'),
  HelperCategory('Videographers', 'event videographer'),
  HelperCategory('Decorators', 'party decorator'),
  HelperCategory('Stage decor', 'stage decoration'),
  HelperCategory('Event planners', 'event planner'),
  HelperCategory('Designers', 'event designer'),
  HelperCategory('Cake makers', 'custom cake bakery'),
  HelperCategory('Panthulu', 'pandit panthulu priest'),
  HelperCategory('Makeup', 'makeup artist'),
  HelperCategory('Cleaners & maids', 'house cleaning service'),
  HelperCategory('Helpers', 'event staff helpers'),
  HelperCategory('Transport', 'party bus van rental'),
  HelperCategory('Anchors / MC', 'event anchor emcee'),
  HelperCategory('DJs', 'DJ for parties'),
  HelperCategory('Singers', 'live singer for events'),
  HelperCategory('Dancers', 'dance performers for events'),
  HelperCategory('Caterers', 'indian caterers'),
  HelperCategory('Rentals', 'party rentals chairs tables'),
  // Artists & entertainers
  HelperCategory('Kids entertainers', 'kids party entertainer clown balloon artist face painter'),
  HelperCategory('Magicians', 'magician for parties'),
  HelperCategory('Stand-up comedians', 'stand up comedian for private events'),
  HelperCategory('Live bands', 'live band for events'),
  HelperCategory('Instrumentalists', 'live musician tabla violin for events'),
  HelperCategory('Mehndi artists', 'mehndi henna artist'),
  HelperCategory('Caricature artists', 'caricature artist for parties'),
];

/// Performers, grouped as "Artists & entertainers".
const artistCategories = ['Anchors / MC', 'DJs', 'Singers', 'Dancers', 'Kids entertainers', 'Magicians', 'Stand-up comedians', 'Live bands', 'Instrumentalists', 'Mehndi artists', 'Caricature artists'];

/// Helpers most events of each kind need.
const helpersByOccasion = <String, List<String>>{
  'Birthday': ['Photographers', 'Decorators', 'Cake makers', 'Cleaners & maids'],
  'Housewarming': ['Panthulu', 'Caterers', 'Decorators', 'Photographers'],
  'Baby shower': ['Photographers', 'Decorators', 'Makeup', 'Caterers'],
  'Pooja': ['Panthulu', 'Caterers', 'Decorators', 'Cleaners & maids'],
  'Anniversary': ['Photographers', 'Cake makers', 'Decorators', 'Singers'],
  'Get-together': ['Caterers', 'Anchors / MC', 'Rentals', 'Cleaners & maids'],
};
