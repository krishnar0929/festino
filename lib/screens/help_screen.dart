import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'feedback_sheet.dart';
import 'refer_screen.dart';

/// Help & feedback: contact us, send feedback, rate Festino, refer a friend.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (${i.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & feedback')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text('We\'re here to help 👋', style: display(26)),
              const SizedBox(height: 6),
              Text('A real person reads every message, usually within a day.', style: body(14, color: HC.muted)),
              const SizedBox(height: 20),
              _Row(
                icon: Icons.support_agent_rounded,
                title: 'Contact us',
                subtitle: 'Questions, problems or ideas: send us a message',
                onTap: () => showFeedbackSheet(context),
              ),
              _Row(
                icon: Icons.star_outline_rounded,
                title: 'Rate Festino',
                subtitle: 'Stars and a review help other party planners find us',
                onTap: () => showRateSheet(context),
              ),
              const SizedBox(height: 12),
              CardBox(
                color: HC.lime,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferScreen())),
                child: Row(
                  children: [
                    const Text('🎁', style: TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invite friends', style: display(17)),
                          const SizedBox(height: 2),
                          Text('Festino is free. Share it with friends and with providers you trust.', style: body(13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (version.isNotEmpty)
                Text('Festino $version', textAlign: TextAlign.center, style: body(12, color: HC.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: HC.track, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: HC.violet),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(15, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: body(13, color: HC.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: HC.muted),
          ],
        ),
      ),
    );
  }
}
