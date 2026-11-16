import 'package:flutter/material.dart';

import '../models/event_details.dart';
import '../theme.dart';

/// "More occasions": every common occasion by group, with search. Returns the pick.
Future<String?> pickMoreOccasion(BuildContext context, {String? current, bool all = false}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HC.ground,
    builder: (_) => _MoreOccasions(current: current, all: all),
  );
}

/// "Other": type the occasion yourself.
Future<String?> typeOccasion(BuildContext context, {String initial = ''}) async {
  final ctrl = TextEditingController(text: initial);
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('What\'s the occasion?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Citizenship party, Cricket finals, Pet\'s birthday'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          Text('We\'ll plan it like the closest kind of party. You can change anything after.', style: body(12, color: HC.muted)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Use this')),
      ],
    ),
  );
  ctrl.dispose();
  final t = text?.trim() ?? '';
  return t.isEmpty ? null : t;
}

class _MoreOccasions extends StatefulWidget {
  const _MoreOccasions({this.current, this.all = false});
  final String? current;

  /// Every occasion (popular ones first), for the main "What's the occasion?" picker.
  final bool all;

  @override
  State<_MoreOccasions> createState() => _MoreOccasionsState();
}

class _MoreOccasionsState extends State<_MoreOccasions> {
  String q = '';

  Widget _chip(String label, String value) => ChoiceChip(
        label: Text(label, style: body(14, weight: FontWeight.w600, color: value == widget.current ? Colors.white : HC.ink)),
        selected: value == widget.current,
        selectedColor: HC.ink,
        backgroundColor: HC.card,
        showCheckmark: false,
        side: const BorderSide(color: HC.line),
        shape: const StadiumBorder(),
        onSelected: (_) => Navigator.pop(context, value),
      );

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(widget.all ? 'What\'s the occasion?' : 'More occasions', style: display(24)),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search: wedding, Diwali, graduation…'),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 8),
          if (widget.all && occasions.any((o) => query.isEmpty || o.toLowerCase().contains(query))) ...[
            const SizedBox(height: 14),
            Text('POPULAR', style: overline()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in occasions)
                  if (query.isEmpty || o.toLowerCase().contains(query)) _chip('${occasionIcon(o)} $o', o),
              ],
            ),
          ],
          for (final group in moreOccasions.entries) ...[
            if (group.value.keys.any((o) => query.isEmpty || o.toLowerCase().contains(query))) ...[
              const SizedBox(height: 14),
              Text(group.key.toUpperCase(), style: overline()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in group.value.entries)
                    if (query.isEmpty || o.key.toLowerCase().contains(query))
                      _chip('${o.value.$1} ${o.key}', o.key),
                ],
              ),
            ],
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: const BorderSide(color: HC.line)),
            onPressed: () async {
              final typed = await typeOccasion(context, initial: q.trim());
              if (typed != null && context.mounted) Navigator.pop(context, typed);
            },
            icon: Icon(Icons.edit_outlined, color: HC.violet),
            label: Text('Not here? Type your own', style: body(14, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
