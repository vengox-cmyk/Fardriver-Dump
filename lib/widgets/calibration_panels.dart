import 'package:flutter/material.dart';

import 'package:arcdash/models/calibration_guidance.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';

const _green = Color(0xFF54E39E);
const _amber = Color(0xFFFFB45C);

/// Capture-progress checklist (v1.2.3): one progress bar per real fit
/// requirement, in plain words. Display only — nothing to tap, so it is
/// safe to glance at while riding.
class CaptureChecklist extends StatelessWidget {
  const CaptureChecklist(
      {super.key,
      required this.analysis,
      required this.fit,
      this.dense = false});

  final CalibrationAnalysis analysis;
  final CalibrationFit? fit;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final progress = CaptureProgress.of(analysis, fit);
    return Column(
      key: const ValueKey('capture-checklist'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in progress.requirements.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 4 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(
                      r.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: r.done ? _green : Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(r.title,
                        key: ValueKey('capture-req-$i'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: r.progress,
                  minHeight: dense ? 5 : 7,
                  color: r.done ? _green : _amber,
                ),
                if (!r.done || !dense)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(r.hint,
                        key: ValueKey('capture-hint-$i'),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Plain-language result: with a fit, the suggestion in words; without one,
/// why the seconds were rejected and what to do about each reason.
class PlainResultCard extends StatelessWidget {
  const PlainResultCard(
      {super.key, required this.analysis, required this.fit, this.ble});

  final CalibrationAnalysis analysis;
  final CalibrationFit? fit;
  final BleSpeedSettings? ble;

  @override
  Widget build(BuildContext context) {
    final f = fit;
    final lines = rejectionBreakdown(analysis);
    return Card(
      key: const ValueKey('calibration-plain-result'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f == null ? 'No result yet' : 'Result in plain words',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(f == null ? noFitSummary(analysis) : fitSummary(f, ble: ble),
                key: const ValueKey('calibration-plain-summary')),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                  f == null
                      ? 'Why seconds were not used, and what to do:'
                      : 'Seconds not used (normal on any ride):',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 4),
              for (final l in lines)
                Padding(
                  key: ValueKey('rejection-${l.advice.verdict.code}'),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${l.seconds} s ${l.advice.what}. ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: l.advice.fix,
                        style: const TextStyle(color: Colors.white70)),
                  ])),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
