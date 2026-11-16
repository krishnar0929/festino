import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/cost_estimate.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'nearby_screen.dart';

/// "What will my party cost?": pick a level, tick what you need (or Select all),
/// and see a low–high total that follows your guests, hours, date, place,
/// venue type and area. "Use as my budget" fills the Budget tab.
class CostEstimateScreen extends StatefulWidget {
  const CostEstimateScreen({super.key});

  @override
  State<CostEstimateScreen> createState() => _CostEstimateScreenState();
}

class _CostEstimateScreenState extends State<CostEstimateScreen> {
  late String level;
  late String venue;
  late String area;
  late Set<String> picks;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final e = AppScope.of(context).event!;
    level = costLevels.containsKey(e.costLevel) ? e.costLevel : 'medium';
    venue = venueKindFor(e);
    area = areaCosts.containsKey(e.areaCost) ? e.areaCost : 'average';
    picks = e.costPicks?.toSet() ?? defaultCostPicks(e).toSet();
  }

  /// Remembers the choices on the event (quietly, as they change).
  void _set(VoidCallback f) {
    setState(f);
    AppScope.of(context).update((e) {
      e.costLevel = level;
      e.venueKind = venue;
      e.areaCost = area;
      e.costPicks = picks.toList();
    });
  }

  Future<void> _useAsBudget(CostEstimate est) async {
    final state = AppScope.of(context);
    final e = state.event!;
    final hasOwn = (e.budgetItems ?? const <BudgetItem>[]).any((b) => b.vendor.isNotEmpty || b.actual != null || b.paid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this as your budget?'),
        content: Text(
          'Your budget becomes ${est.money(est.mid)} (the middle of the range), with one line for each ticked item.'
          '${hasOwn ? '\n\nYour current budget lines (vendors, real costs, paid) will be replaced.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HC.violet), onPressed: () => Navigator.pop(ctx, true), child: const Text('Use it')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await state.update((ev) {
      ev.budget = est.mid.roundToDouble();
      ev.budgetItems = [
        for (final l in est.picked) BudgetItem(id: 'est_${l.item.id}', label: l.item.label, planned: l.mid.roundToDouble()),
      ];
    });
    if (!mounted) return;
    toast(context, 'Budget set to ${est.money(est.mid)}. Track real costs in the Budget tab.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).event!;
    final est = estimateCost(e, level: level, picks: picks, venueKind: venue, area: area);
    final usable = [for (final l in est.lines) if (l.included) l.item.id];
    final allOn = usable.every(picks.contains);

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(padding: EdgeInsets.only(left: 8), child: Center(child: BackArrow())),
        leadingWidth: 60,
        title: const Text('Cost estimate'),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(color: HC.card, border: Border(top: BorderSide(color: HC.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimated total · ${est.picked.length} items', style: body(12, color: HC.muted)),
                    Text(est.picked.isEmpty ? '—' : '${est.money(est.low)}–${est.money(est.high)}', style: display(22)),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: HC.violet, minimumSize: const Size(0, 48)),
                onPressed: est.picked.isEmpty ? null : () => _useAsBudget(est),
                child: const Text('Use as budget'),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text('What will it cost?', style: display(26)),
              const SizedBox(height: 4),
              Text(
                '${e.guests} guests · ${e.hours} hrs · ${DateFormat('EEE, MMM d').format(e.date)}${e.venue == null ? '' : ' · ${e.venue!.label}'}',
                style: body(13, color: HC.muted),
              ),
              const SizedBox(height: 18),
              const SectionLabel('Level'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in costLevels.entries)
                    Pill(label: l.value.$1, small: true, selected: level == l.key, selectedColor: HC.violet, onTap: () => _set(() => level = l.key)),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('Venue'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in venueKinds.entries)
                    Pill(label: v.value, small: true, selected: venue == v.key, selectedColor: HC.violet, onTap: () => _set(() => venue = v.key)),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('Area'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in areaCosts.entries)
                    Pill(label: a.value.$1, small: true, selected: area == a.key, selectedColor: HC.violet, onTap: () => _set(() => area = a.key)),
                ],
              ),
              const SizedBox(height: 12),
              for (final n in est.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $n', style: body(12, color: HC.muted)),
                ),
              const SizedBox(height: 16),
              Material(
                color: HC.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HC.line)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: allOn,
                      activeColor: HC.violet,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('Select all', style: body(15, weight: FontWeight.w700)),
                      subtitle: Text('Full party cost', style: body(12, color: HC.muted)),
                      onChanged: (v) => _set(() {
                        if (v == true) {
                          picks.addAll(usable);
                        } else {
                          picks.clear();
                        }
                      }),
                    ),
                    for (final l in est.lines) ...[
                      const Divider(height: 1, color: HC.line),
                      _LineRow(
                        line: l,
                        est: est,
                        checked: picks.contains(l.item.id) && l.included,
                        onChanged: l.included ? (v) => _set(() => v ? picks.add(l.item.id) : picks.remove(l.item.id)) : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Tick only what you\'ll pay for. Doing it yourself (home cooking, your own decorations)? Leave it unticked.',
                  style: body(12, color: HC.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.est, required this.checked, required this.onChanged});
  final CostLine line;
  final CostEstimate est;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final it = line.item;
    final off = onChanged == null;
    return InkWell(
      onTap: off ? null : () => onChanged!(!checked),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            Checkbox(value: checked, activeColor: HC.violet, onChanged: off ? null : (v) => onChanged!(v ?? false)),
            Text(it.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.label, style: body(15, weight: FontWeight.w600, color: off ? HC.muted : HC.ink)),
                  Text(line.how, style: body(12, color: HC.muted)),
                  if (it.helper != null && !off)
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => NearbyScreen(initialCategory: it.helper, standalone: true),
                      )),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Find ${it.helper!.toLowerCase()} · deals ›', style: body(12, color: HC.violet, weight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(off ? '—' : est.range(line),
                style: body(14, weight: FontWeight.w700, color: checked ? HC.ink : HC.muted)),
          ],
        ),
      ),
    );
  }
}
