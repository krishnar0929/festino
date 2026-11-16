import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/event_details.dart';
import '../services/budget_match.dart';
import '../services/plan_generator.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'nearby_screen.dart';

final _money = NumberFormat.simpleCurrency(decimalDigits: 0);
String money(num v) => _money.format(v);
const _danger = Color(0xFFB42318);
const _good = Color(0xFF1F8A4C);

String _newId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

// ============================================================ checklist

/// Edit a checklist task's words or due date.
Future<void> editTask(BuildContext context, PlanTask t) async {
  final state = AppScope.of(context);
  final r = await _taskDialog(context, heading: 'Edit task', label: t.label, daysBefore: t.daysBefore);
  if (r == null) return;
  await state.update((e) {
    e.customTasks.removeWhere((c) => c.id == t.id);
    e.customTasks.add(CustomTask(id: t.id, label: r.$1, daysBefore: r.$2));
  });
}

Future<void> removeTask(BuildContext context, PlanTask t) async {
  final state = AppScope.of(context);
  await state.update((e) {
    if (t.id.startsWith('task_')) {
      e.customTasks.removeWhere((c) => c.id == t.id);
    } else if (!e.hiddenTasks.contains(t.id)) {
      e.hiddenTasks.add(t.id);
    }
    e.taskReminders.remove(t.id);
  });
  if (context.mounted) toast(context, 'Removed "${t.label}".');
}

/// (label, days before the party), or null.
Future<(String, int)?> _taskDialog(BuildContext context, {required String heading, String label = '', int daysBefore = 7}) {
  final state = AppScope.of(context);
  final party = DateUtils.dateOnly(state.event!.date);
  final ctrl = TextEditingController(text: label);
  var due = party.subtract(Duration(days: daysBefore));
  return showDialog<(String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: label.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Task', hintText: 'e.g. Pick up the cake'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_rounded, color: HC.violet),
              title: Text('Due ${DateFormat('EEE, MMM d').format(due)}'),
              subtitle: Text(_daysLabel(party.difference(due).inDays)),
              trailing: const Text('Change'),
              onTap: () async {
                final now = DateUtils.dateOnly(DateTime.now());
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: due.isBefore(now) ? now : due,
                  firstDate: now.isBefore(party) ? now : party,
                  lastDate: party,
                );
                if (picked != null) setD(() => due = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HC.violet),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, (ctrl.text.trim(), party.difference(due).inDays.clamp(0, 3650)));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

String _daysLabel(int d) => d <= 0 ? 'On party day' : (d == 1 ? '1 day before the party' : '$d days before the party');

/// Under the checklist: add a task, bring back removed ones.
class ChecklistFooter extends StatelessWidget {
  const ChecklistFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final hidden = e.hiddenTasks.length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final r = await _taskDialog(context, heading: 'Add a task');
              if (r == null) return;
              await state.update((ev) => ev.customTasks.add(CustomTask(id: _newId('task'), label: r.$1, daysBefore: r.$2)));
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a task'),
          ),
          if (hidden > 0)
            TextButton.icon(
              onPressed: () => state.update((ev) => ev.hiddenTasks.clear()),
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: Text('Bring back $hidden removed'),
            ),
        ],
      ),
    );
  }
}

// ============================================================ budget

/// Your budget: total, each line's planned amount, who's doing it (your own vendor or one
/// from Hoopla), the real cost and whether it's paid.
class BudgetTab extends StatefulWidget {
  const BudgetTab({super.key});

  @override
  State<BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends State<BudgetTab> {
  TextEditingController? _total;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_total == null) {
      final b = AppScope.of(context).event?.budget;
      _total = TextEditingController(text: b == null ? '' : b.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    _total?.dispose();
    super.dispose();
  }

  /// Saves the lines as the host's own (first edit copies the suggested split).
  Future<void> _edit(void Function(List<BudgetItem> items) change) {
    final state = AppScope.of(context);
    return state.update((e) {
      final items = [for (final b in PlanGenerator.budgetItems(e)) BudgetItem.fromMap(b.toMap())];
      change(items);
      e.budgetItems = items;
    });
  }

  Future<void> _openItem(BudgetItem? item) async {
    final r = await showModalBottomSheet<_ItemResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: HC.ground,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ItemSheet(item: item),
    );
    if (r == null) return;
    await _edit((items) {
      if (r.delete) {
        items.removeWhere((b) => b.id == item?.id);
        return;
      }
      final i = items.indexWhere((b) => b.id == item?.id);
      if (i < 0) {
        items.add(r.item);
      } else {
        items[i] = r.item;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final e = state.event!;
    final items = PlanGenerator.budgetItems(e);
    final total = e.budget;
    final planned = items.fold<double>(0, (a, b) => a + b.planned);
    final committed = items.fold<double>(0, (a, b) => a + (b.vendor.isNotEmpty || b.actual != null ? b.cost : 0));
    final paid = items.fold<double>(0, (a, b) => a + (b.paid ? b.cost : 0));
    final custom = e.budgetItems != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your total budget', style: body(12, color: HC.muted)),
              const SizedBox(height: 6),
              TextField(
                controller: _total,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: display(24),
                decoration: const InputDecoration(hintText: 'Enter an amount', prefixText: '\$ '),
                onChanged: (v) => state.update((ev) => ev.budget = double.tryParse(v)),
              ),
              if (total != null && total > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (paid / total).clamp(0, 1).toDouble(),
                    minHeight: 10,
                    backgroundColor: HC.track,
                    color: _good,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _Tally('Planned', money(planned), planned > total ? _danger : HC.ink),
                    _Tally('Booked', money(committed), HC.violet),
                    _Tally('Paid', money(paid), _good),
                    _Tally(planned > total ? 'Over by' : 'Left to plan', money((total - planned).abs()), planned > total ? _danger : HC.muted),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(custom ? 'Your budget' : 'Suggested split', style: overline())),
            if (custom)
              TextButton(
                onPressed: () => state.update((ev) => ev.budgetItems = null),
                child: const Text('Reset to suggested'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final b in items) _BudgetRow(item: b, onTap: () => _openItem(b)),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openItem(null),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add expense or your own vendor'),
          ),
        ),
        const SizedBox(height: 6),
        Text('Tap a line to change the amount, add who\'s doing it (your own photographer, cook…), the real cost, or mark it paid.',
            style: body(12, color: HC.muted)),
      ],
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: body(11, color: HC.muted)),
        Text(value, style: body(15, color: color, weight: FontWeight.w700)),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.item, required this.onTap});
  final BudgetItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = item;
    final service = budgetServices[b.label];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        onTap: onTap,
        radius: 14,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(b.label, style: body(15, weight: FontWeight.w600))),
                if (b.paid)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _good.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text('Paid', style: body(11, color: _good, weight: FontWeight.w700)),
                  ),
                Text(money(b.cost), style: body(15, weight: FontWeight.w700)),
                const Icon(Icons.chevron_right_rounded, color: HC.muted),
              ],
            ),
            if (b.vendor.isNotEmpty)
              Text('👤 ${b.vendor}${b.actual != null && b.actual != b.planned ? ' · planned ${money(b.planned)}' : ''}', style: body(12, color: HC.violet, weight: FontWeight.w600))
            else if (service != null)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => NearbyScreen(initialCategory: service, standalone: true, startWithinBudget: b.planned > 0),
                )),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    b.planned > 0 ? 'Find $service within ${money(b.planned)} ›' : 'Find ${service.toLowerCase()} ›',
                    style: body(12, color: HC.violet, weight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemResult {
  const _ItemResult(this.item, {this.delete = false});
  final BudgetItem item;
  final bool delete;
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});
  final BudgetItem? item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final label = TextEditingController(text: widget.item?.label ?? '');
  late final planned = TextEditingController(text: (widget.item?.planned ?? 0) > 0 ? widget.item!.planned.toStringAsFixed(0) : '');
  late final vendor = TextEditingController(text: widget.item?.vendor ?? '');
  late final phone = TextEditingController(text: widget.item?.vendorPhone ?? '');
  late final actual = TextEditingController(text: widget.item?.actual?.toStringAsFixed(0) ?? '');
  late bool paid = widget.item?.paid ?? false;

  @override
  void dispose() {
    for (final c in [label, planned, vendor, phone, actual]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (label.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _ItemResult(BudgetItem(
        id: widget.item?.id ?? _newId('b'),
        label: label.text.trim(),
        planned: double.tryParse(planned.text) ?? 0,
        vendor: vendor.text.trim(),
        vendorPhone: phone.text.trim(),
        actual: double.tryParse(actual.text),
        paid: paid,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item == null ? 'Add to your budget' : 'Edit ${widget.item!.label}', style: display(22)),
            const SizedBox(height: 14),
            TextField(controller: label, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What it\'s for', hintText: 'e.g. Mehndi artist')),
            const SizedBox(height: 10),
            TextField(controller: planned, keyboardType: TextInputType.number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Planned amount', prefixText: '\$ ')),
            const SizedBox(height: 18),
            Text('WHO\'S DOING IT (OPTIONAL)', style: overline()),
            const SizedBox(height: 8),
            TextField(controller: vendor, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your vendor or person', hintText: 'e.g. Ravi Photography, Aunty\'s catering')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Their phone (optional)')),
            const SizedBox(height: 10),
            TextField(controller: actual, keyboardType: TextInputType.number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Actual cost (optional)', prefixText: '\$ ')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Paid'),
              value: paid,
              activeTrackColor: _good,
              onChanged: (v) => setState(() => paid = v),
            ),
            if (phone.text.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openLink(context, Uri(scheme: 'tel', path: phone.text.replaceAll(RegExp(r'[^0-9+]'), ''))),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: Text('Call ${vendor.text.trim().isEmpty ? 'them' : vendor.text.trim()}'),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: HC.violet, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
            if (widget.item != null)
              TextButton(
                onPressed: () => Navigator.pop(context, _ItemResult(widget.item!, delete: true)),
                child: Text('Remove from budget', style: body(14, color: _danger, weight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ my list

/// "My list": the host's own to-dos and notes, with optional due dates.
class MyListTab extends StatefulWidget {
  const MyListTab({super.key});

  @override
  State<MyListTab> createState() => _MyListTabState();
}

class _MyListTabState extends State<MyListTab> {
  final ctrl = TextEditingController();
  DateTime? due;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    final state = AppScope.of(context);
    final when = due;
    ctrl.clear();
    setState(() => due = null);
    await state.update((e) => e.todos.add(TodoItem(id: _newId('todo'), text: text, due: when)));
  }

  Future<void> _pickDue() async {
    final party = AppScope.of(context).event!.date;
    final now = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: due ?? now,
      firstDate: now,
      lastDate: party.isAfter(now) ? party.add(const Duration(days: 30)) : now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => due = d);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final todos = [...state.event!.todos]..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999));
      });
    final open = todos.where((t) => !t.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          todos.isEmpty ? 'Your own to-dos, notes and reminders, anything that\'s not on the checklist.' : '$open to do · ${todos.length - open} done',
          style: body(13, color: HC.muted),
        ),
        const SizedBox(height: 10),
        CardBox(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'e.g. Call Amma about the menu',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    helperText: due == null ? null : 'Due ${DateFormat('EEE, MMM d').format(due!)}',
                  ),
                ),
              ),
              IconButton(tooltip: 'Due date', onPressed: _pickDue, icon: Icon(Icons.event_rounded, color: due == null ? HC.muted : HC.violet)),
              IconButton.filled(
                tooltip: 'Add',
                style: IconButton.styleFrom(backgroundColor: HC.violet),
                onPressed: _add,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (todos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                const Text('📝', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 6),
                Text('Nothing here yet', style: body(14, weight: FontWeight.w600)),
                Text('Add things like "Borrow chairs from Ravi" or "Buy diyas".', style: body(13, color: HC.muted)),
              ],
            ),
          ),
        for (final t in todos)
          Dismissible(
            key: ValueKey(t.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: _danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.delete_outline_rounded, color: _danger),
            ),
            onDismissed: (_) => state.update((e) => e.todos.removeWhere((x) => x.id == t.id)),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                radius: 14,
                padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: t.done,
                      activeColor: HC.violet,
                      onChanged: (v) => state.update((e) {
                        for (final x in e.todos) {
                          if (x.id == t.id) x.done = v ?? false;
                        }
                      }),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.text,
                            style: body(14, weight: FontWeight.w500, color: t.done ? HC.muted : HC.ink)
                                .copyWith(decoration: t.done ? TextDecoration.lineThrough : null),
                          ),
                          if (t.due != null)
                            Text(
                              'Due ${DateFormat('EEE, MMM d').format(t.due!)}',
                              style: body(12, color: !t.done && t.due!.isBefore(DateUtils.dateOnly(DateTime.now())) ? _danger : HC.muted),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20, color: HC.muted),
                      onSelected: (v) async {
                        if (v == 'remove') {
                          await state.update((e) => e.todos.removeWhere((x) => x.id == t.id));
                          return;
                        }
                        final c = TextEditingController(text: t.text);
                        final text = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Edit'),
                            content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
                            ],
                          ),
                        );
                        c.dispose();
                        if (text == null || text.trim().isEmpty) return;
                        await state.update((e) {
                          for (final x in e.todos) {
                            if (x.id == t.id) x.text = text.trim();
                          }
                        });
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (todos.isNotEmpty) Text('Swipe left to delete.', style: body(11, color: HC.muted)),
      ],
    );
  }
}
