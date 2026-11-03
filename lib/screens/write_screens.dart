import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/providers/write_provider.dart';
import 'package:arcdash/services/write/write_log.dart';
import 'package:arcdash/services/write/write_service.dart';

const _ok = Color(0xFF54E39E);
const _bad = Color(0xFFFF6B6B);
const _warn = Color(0xFFFFB45C);

/// Plans [values] (allowlisted field key → raw value) and opens the review
/// screen. Nothing is sent until the rider confirms there.
Future<void> startControllerWrite(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, int> values,
  required String title,
  List<String> notes = const [],
}) async {
  final service = ref.read(controllerWriteServiceProvider);
  final ChangeSet set;
  try {
    set = service.plan(values, title: title, notes: notes);
  } on WriteRefused catch (e) {
    _snack(context, e.message);
    return;
  }
  if (set.changes.isEmpty) {
    _snack(context, 'The controller already has these values.');
    return;
  }
  await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WriteReviewScreen(changeSet: set)));
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));
}

/// Name / old / new for every change and one confirm for the whole set.
class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({super.key, required this.changeSet});
  final ChangeSet changeSet;

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  bool _writing = false;

  Future<void> _confirm() async {
    final service = ref.read(controllerWriteServiceProvider);
    setState(() => _writing = true);
    try {
      final result = await service.apply(widget.changeSet);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => WriteResultScreen(result: result)));
    } on WriteRefused catch (e) {
      if (!mounted) return;
      setState(() => _writing = false);
      _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.changeSet;
    final reason =
        ref.watch(controllerWriteServiceProvider).refusalReason();
    return Scaffold(
      appBar: AppBar(title: const Text('Review changes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(set.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final c in set.changes)
              Card(
                key: ValueKey('change-${c.field.key}'),
                child: ListTile(
                  title: Text(c.field.label +
                      (c.field.experimental ? '  (experimental)' : '')),
                  subtitle: Text('${c.oldText}  →  ${c.newText}'),
                ),
              ),
            for (final n in set.notes)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(n),
              ),
            const SizedBox(height: 12),
            const Text(
                'Before writing, FarSure saves a full backup of the current '
                'settings. After writing it saves to the controller, reads '
                'the values back and checks them. Only stopped bikes can be '
                'written.'),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(reason, style: const TextStyle(color: _bad)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('confirm-write'),
              onPressed: _writing ? null : _confirm,
              icon: _writing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_alt),
              label: Text(_writing
                  ? 'Writing and checking…'
                  : 'Write ${set.changes.length} '
                      'change${set.changes.length == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-field verify result; offers to restore the old values on mismatch.
class WriteResultScreen extends ConsumerWidget {
  const WriteResultScreen({super.key, required this.result});
  final WriteResult result;

  static String titleFor(WriteOutcome o) => switch (o) {
        WriteOutcome.ok => 'Written and checked',
        WriteOutcome.partial => 'Partly written',
        WriteOutcome.failed => 'Write failed',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = result.outcome;
    final color = switch (outcome) {
      WriteOutcome.ok => _ok,
      WriteOutcome.partial => _warn,
      WriteOutcome.failed => _bad,
    };
    return Scaffold(
      appBar: AppBar(title: Text(titleFor(outcome))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Icon(
                switch (outcome) {
                  WriteOutcome.ok => Icons.check_circle,
                  WriteOutcome.partial => Icons.rule,
                  WriteOutcome.failed => Icons.error_outline,
                },
                color: color,
                size: 48),
            const SizedBox(height: 8),
            Text(result.message,
                key: const ValueKey('write-result-message'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (outcome == WriteOutcome.partial)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('The saved values are kept and verified. Rejected '
                    'values stayed as they were on the controller.'),
              ),
            if (result.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(result.error!),
              ),
            for (final f in result.fields)
              ListTile(
                title: Text(f.change.field.label),
                subtitle: Text('${f.change.oldText} → ${f.change.newText}'
                    '${f.readBackRaw != null && f.verify != VerifyResult.ok ? '\nRead back: ${f.change.field.format(f.readBackRaw!)}' : ''}'),
                trailing: Text(f.outcome.text,
                    style: TextStyle(
                        color: f.outcome.verified ? _ok : _bad)),
              ),
            const SizedBox(height: 8),
            Text('Backup: ${result.backup.uri.pathSegments.last}\n'
                'Log: ${result.log.uri.pathSegments.last} (Saved files › Write log)'),
            if (result.needsRestore) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('restore-old'),
                icon: const Icon(Icons.restore),
                label: const Text('Restore the unconfirmed values'),
                onPressed: () {
                  final service = ref.read(controllerWriteServiceProvider);
                  try {
                    final set = service.planRestore(result);
                    if (set.changes.isEmpty) {
                      _snack(context, 'The controller already has the old values.');
                      return;
                    }
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => WriteReviewScreen(changeSet: set)));
                  } on WriteRefused catch (e) {
                    _snack(context, e.message);
                  }
                },
              ),
            ],
            if (outcome != WriteOutcome.ok &&
                result.fields.any((f) => f.outcome.verified)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('result-undo-to-backup'),
                icon: const Icon(Icons.undo),
                label: const Text('Undo to backup'),
                onPressed: () async {
                  final service = ref.read(controllerWriteServiceProvider);
                  try {
                    final session = WriteLogSession.decode(
                        await result.log.readAsString());
                    final set = await service.planUndo(session);
                    if (!context.mounted) return;
                    if (set.changes.isEmpty) {
                      _snack(context,
                          'The controller already has the backup values.');
                      return;
                    }
                    await Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => WriteReviewScreen(changeSet: set)));
                  } on WriteRefused catch (e) {
                    if (context.mounted) _snack(context, e.message);
                  } on Object catch (e) {
                    if (context.mounted) _snack(context, 'Undo failed: $e');
                  }
                },
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

/// One write log file with a one-tap "Undo to backup".
class WriteLogDetailScreen extends ConsumerWidget {
  const WriteLogDetailScreen({super.key, required this.file});
  final File file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Write log')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: file.readAsString(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return snap.hasError
                  ? Center(child: Text('Could not read: ${snap.error}'))
                  : const Center(child: CircularProgressIndicator());
            }
            final WriteLogSession s;
            try {
              s = WriteLogSession.decode(snap.data!);
            } on Object catch (e) {
              return Center(child: Text('Not a write log: $e'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.title, style: Theme.of(context).textTheme.titleMedium),
                Text('${s.timeLabel} · ${s.controllerName} · '
                    '${s.kind.name} · ${s.outcome.label}'),
                Text(s.message),
                if (s.error != null) Text(s.error!),
                const SizedBox(height: 8),
                for (final r in s.rows)
                  ListTile(
                    title: Text(r.label),
                    subtitle: Text('${r.oldText} → ${r.newText}'),
                    trailing: Text(r.outcome.text),
                  ),
                Text('Backup: ${s.backupFile}'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('undo-to-backup'),
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo to backup'),
                  onPressed: () async {
                    final service = ref.read(controllerWriteServiceProvider);
                    try {
                      final set = await service.planUndo(s);
                      if (!context.mounted) return;
                      if (set.changes.isEmpty) {
                        _snack(context,
                            'The controller already has the backup values.');
                        return;
                      }
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => WriteReviewScreen(changeSet: set)));
                    } on WriteRefused catch (e) {
                      if (context.mounted) _snack(context, e.message);
                    }
                  },
                ),
                const SizedBox(height: 4),
                const Text('Undo puts back only the settings this write '
                    'changed, using the backup saved just before it.'),
              ],
            );
          },
        ),
      ),
    );
  }
}
