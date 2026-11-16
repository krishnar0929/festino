import 'package:flutter/material.dart';

import '../theme.dart';
import 'games_screen.dart';
import 'guests_tab.dart';
import 'home_screen.dart';
import 'nearby_screen.dart';
import 'party_screen.dart';
import 'plan_screen.dart';

/// Where [HomeShell]'s `go` can take you: one of the four tabs, or a full page.
class HomeTab {
  static const home = 0;
  static const plan = 1;
  static const guests = 2;
  static const find = 3;

  /// Not tabs: these open as their own page.
  static const games = 10;
  static const party = 11;
}

/// Opens the games list as its own page (it used to be a tab).
void openGames(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: HC.ground,
        appBar: AppBar(backgroundColor: HC.ground, surfaceTintColor: Colors.transparent),
        body: const GamesScreen(),
      ),
    ));

/// Opens party-day mode (timer, scoreboard, what's next) as its own page.
void openPartyMode(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: HC.ink,
        appBar: AppBar(backgroundColor: HC.ink, foregroundColor: Colors.white, surfaceTintColor: Colors.transparent),
        body: const PartyScreen(),
      ),
    ));

/// Bottom navigation: Home · Plan · Guests · Find.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = HomeTab.home;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Plan'),
    (Icons.group_outlined, Icons.group_rounded, 'Guests'),
    (Icons.search_rounded, Icons.search_rounded, 'Find'),
  ];

  void go(int where) {
    switch (where) {
      case HomeTab.games:
        openGames(context);
      case HomeTab.party:
        openPartyMode(context);
      default:
        setState(() => index = where.clamp(0, _tabs.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onNavigate: go),
      PlanScreen(onNavigate: go),
      const GuestsTab(),
      const NearbyScreen(),
    ];

    return Scaffold(
      backgroundColor: HC.ground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: IndexedStack(index: index, children: pages),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: HC.card,
          border: Border(top: BorderSide(color: HC.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => go(i),
                      child: Semantics(
                        selected: i == index,
                        button: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(i == index ? _tabs[i].$2 : _tabs[i].$1, color: i == index ? HC.violet : HC.muted),
                            const SizedBox(height: 4),
                            Text(
                              _tabs[i].$3,
                              style: body(11, color: i == index ? HC.violet : HC.muted, weight: i == index ? FontWeight.w700 : FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
