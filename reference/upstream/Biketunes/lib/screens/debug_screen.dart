import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/providers/controller_provider.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(controllerProvider.notifier);
    final packets = notifier.debugPackets;
    final rate = notifier.packetRate;

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'RAW DEBUG',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${rate.toStringAsFixed(1)} Hz',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2030)),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Legend
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  _LegendDot(color: const Color(0xFF00E5FF), label: 'E2/E8/EE (live data)'),
                  const SizedBox(width: 16),
                  _LegendDot(color: const Color(0xFF39FF14), label: 'F4/D6 (temps)'),
                  const SizedBox(width: 16),
                  _LegendDot(color: const Color(0xFFFF9800), label: 'other'),
                ],
              ),
            ),
            Expanded(
              child: packets.isEmpty
                  ? const _EmptyDebug()
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: packets.length,
                      itemBuilder: (ctx, i) {
                        final packet = packets[packets.length - 1 - i];
                        return _PacketRow(
                          packet: packet,
                          index: packets.length - i,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          final text = packets.join('\n');
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        backgroundColor: const Color(0xFF1A2030),
        child: const Icon(Icons.copy, size: 18, color: Color(0xFF00E5FF)),
      ),
    );
  }
}

class _PacketRow extends StatelessWidget {
  final String packet;
  final int index;

  const _PacketRow({required this.packet, required this.index});

  Color _rowColor(String packet) {
    if (packet.contains('[0xE2]') ||
        packet.contains('[0xE8]') ||
        packet.contains('[0xEE]')) {
      return const Color(0xFF00E5FF);
    }
    if (packet.contains('[0xF4]') || packet.contains('[0xD6]')) {
      return const Color(0xFF39FF14);
    }
    return const Color(0xFFFF9800);
  }

  @override
  Widget build(BuildContext context) {
    final color = _rowColor(packet);
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: color.withOpacity(0.5), width: 2),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$index',
            style: TextStyle(
              color: color.withOpacity(0.4),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              packet,
              style: const TextStyle(
                color: Color(0xFF8899AA),
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4A5568),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _EmptyDebug extends StatelessWidget {
  const _EmptyDebug();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 48, color: Color(0xFF2A3548)),
          SizedBox(height: 16),
          Text(
            'No packets received yet',
            style: TextStyle(color: Color(0xFF4A5568), fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            'Connect to controller to see live data',
            style: TextStyle(color: Color(0xFF2A3548), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
