import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/models/telemetry_quality.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/storage_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardLayout _dashboard = DashboardLayout.defaults();
  DashboardLayout? _editorBaseline;
  late final StorageService _storage;
  Future<void> _saveChain = Future.value();
  Timer? _saveTimer;
  Timer? _freshnessTimer;
  bool _editing = false;
  bool _loaded = false;
  DateTime _now = DateTime.now();
  DashboardOrientation _editingOrientation = DashboardOrientation.portrait;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _storage = ref.read(storageServiceProvider);
    _dashboard = _storage.loadDashboardLayout();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_enqueueSave(_dashboard));
    }
    _freshnessTimer?.cancel();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_enqueueSave(_dashboard));
    });
  }

  Future<void> _enqueueSave(DashboardLayout layout) {
    _saveChain = _saveChain
        .catchError((_) {})
        .then((_) => _storage.saveDashboardLayout(layout));
    return _saveChain;
  }

  void _enterEditor() {
    setState(() {
      _editorBaseline = _dashboard;
      _editing = true;
      _editingOrientation = _currentOrientation;
    });
  }

  Future<void> _saveAndCloseEditor() async {
    _saveTimer?.cancel();
    await _enqueueSave(_dashboard);
    if (!mounted) return;
    setState(() {
      _editing = false;
      _editorBaseline = null;
    });
  }

  Future<void> _discardEditor() async {
    final baseline = _editorBaseline;
    if (baseline == null) return;
    _saveTimer?.cancel();
    setState(() {
      _dashboard = baseline;
      _editing = false;
      _editorBaseline = null;
    });
    await _enqueueSave(baseline);
  }

  DashboardOrientation get _currentOrientation =>
      MediaQuery.orientationOf(context) == Orientation.portrait
          ? DashboardOrientation.portrait
          : DashboardOrientation.landscape;

  DashboardOrientation get _activeOrientation =>
      _editing ? _editingOrientation : _currentOrientation;

  void _updateCurrent(DashboardOrientationLayout layout) {
    setState(
        () => _dashboard = _dashboard.withLayout(_activeOrientation, layout));
    _scheduleSave();
  }

  void _removeTile(DashboardTile tile) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    _updateCurrent(layout.copyWith(
      tiles:
          layout.tiles.where((candidate) => candidate.id != tile.id).toList(),
    ));
  }

  void _moveTile(DashboardTile tile, int columnDelta, int rowDelta) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    final index = layout.tiles.indexOf(tile);
    if (index < 0) return;
    final moved = tile.copyWith(
      column: tile.column + columnDelta,
      row: tile.row + rowDelta,
    );
    final tiles = [...layout.tiles]..[index] = moved;
    try {
      final next = layout.copyWith(tiles: tiles);
      next.validate();
      _updateCurrent(next);
    } on FormatException {
      _showEditorError(AppText.invalidPosition);
    }
  }

  void _resizeTile(DashboardTile tile, int widthDelta, int heightDelta) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    final index = layout.tiles.indexOf(tile);
    final resized = tile.copyWith(
      width: tile.width + widthDelta,
      height: tile.height + heightDelta,
    );
    final tiles = [...layout.tiles]..[index] = resized;
    try {
      final next = layout.copyWith(tiles: tiles);
      next.validate();
      _updateCurrent(next);
    } on FormatException {
      _showEditorError(AppText.invalidSize);
    }
  }

  void _resetCurrent() {
    _updateCurrent(DashboardLayout.defaults().layoutFor(_activeOrientation));
  }

  void _copyOrientation() {
    final source = _dashboard.layoutFor(_editingOrientation);
    final target = _editingOrientation == DashboardOrientation.portrait
        ? DashboardOrientation.landscape
        : DashboardOrientation.portrait;
    final targetGrid = _dashboard.layoutFor(target);
    final transposed =
        source.columns == targetGrid.rows && source.rows == targetGrid.columns;
    final tiles = source.tiles.map((tile) {
      if (transposed) {
        return tile.copyWith(
          column: tile.row,
          row: tile.column,
          width: tile.height,
          height: tile.width,
        );
      }
      return tile.copyWith(
        column: (tile.column * targetGrid.columns / source.columns).floor(),
        row: (tile.row * targetGrid.rows / source.rows).floor(),
        width: math.max(
          1,
          (tile.width * targetGrid.columns / source.columns).round(),
        ),
        height: math.max(
          1,
          (tile.height * targetGrid.rows / source.rows).round(),
        ),
      );
    }).toList();
    try {
      final copied = DashboardOrientationLayout(
        columns: targetGrid.columns,
        rows: targetGrid.rows,
        tiles: tiles,
      );
      copied.validate();
      setState(() => _dashboard = _dashboard.withLayout(target, copied));
      _scheduleSave();
    } on FormatException {
      _showEditorError(AppText.copyFailed);
    }
  }

  void _addMetric(DashboardMetric metric) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    if (layout.tiles.any((tile) => tile.metric == metric)) return;
    final definition = dashboardMeasurementCatalog[metric]!;
    for (var row = 0; row < layout.rows; row++) {
      for (var column = 0; column < layout.columns; column++) {
        final tile = DashboardTile(
          id: metric.name,
          metric: metric,
          kind: definition.kind,
          column: column,
          row: row,
          width: definition.minimumWidth,
          height: definition.minimumHeight,
        );
        if (_fits(tile, layout)) {
          final next = layout.copyWith(tiles: [...layout.tiles, tile]);
          try {
            next.validate();
            _updateCurrent(next);
            return;
          } on FormatException {
            continue;
          }
        }
      }
    }
    _showEditorError(AppText.noGridSpace);
  }

  void _setTileKind(DashboardTile tile, DashboardTileKind kind) {
    _replaceTile(tile, tile.copyWith(kind: kind));
  }

  void _setTileUnit(DashboardTile tile, DashboardUnit unit) {
    _replaceTile(tile, tile.copyWith(unit: unit));
  }

  void _replaceTile(DashboardTile tile, DashboardTile replacement) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    final index = layout.tiles.indexOf(tile);
    if (index < 0) return;
    final tiles = [...layout.tiles]..[index] = replacement;
    final next = layout.copyWith(tiles: tiles);
    try {
      next.validate();
      _updateCurrent(next);
    } on FormatException {
      _showEditorError(AppText.invalidSize);
    }
  }

  void _showEditorError(AppText message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).text(message))),
    );
  }

  bool _fits(DashboardTile candidate, DashboardOrientationLayout layout) {
    if (candidate.column + candidate.width > layout.columns ||
        candidate.row + candidate.height > layout.rows) {
      return false;
    }
    return layout.tiles.every((tile) {
      final separated = candidate.column + candidate.width <= tile.column ||
          tile.column + tile.width <= candidate.column ||
          candidate.row + candidate.height <= tile.row ||
          tile.row + tile.height <= candidate.row;
      return tile.id == candidate.id || separated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = ref.watch(controllerProvider);
    final connected = ref.watch(isConnectedProvider);
    final orientation = _activeOrientation;
    final layout = _dashboard.layoutFor(orientation);

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ARCDASH'),
            Text(strings.text(AppText.rideComputer),
                style: const TextStyle(
                    fontSize: 9, letterSpacing: 1.8, color: Colors.white38)),
          ],
        ),
        actions: [
          _ConnectionPill(
            connected: connected,
            onTap: () => Navigator.of(context).pushNamed('/'),
          ),
          IconButton(
            tooltip: strings
                .text(_editing ? AppText.saveDashboard : AppText.editDashboard),
            onPressed: _editing ? _saveAndCloseEditor : _enterEditor,
            icon: Icon(_editing ? Icons.check : Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_editing)
              _EditorBar(
                orientation: _editingOrientation,
                onOrientationChanged: (value) =>
                    setState(() => _editingOrientation = value),
                onAdd: () => _showMetricPicker(),
                onCopy: _copyOrientation,
                onReset: _resetCurrent,
                onDiscard: _discardEditor,
              ),
            Expanded(
              child: DashboardRenderer(
                layout: layout,
                state: state,
                connected: connected,
                now: _now,
                editing: _editing,
                onRemove: _removeTile,
                onMove: _moveTile,
                onResize: _resizeTile,
                onKindChanged: _setTileKind,
                onUnitChanged: _setTileUnit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMetricPicker() async {
    final selected = await showModalBottomSheet<DashboardMetric>(
      context: context,
      backgroundColor: const Color(0xFF11151A),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: DashboardMetric.values
              .map((metric) => ListTile(
                    title: Text(AppStrings.of(context).metric(metric.name)),
                    leading: const Icon(Icons.add),
                    onTap: () => Navigator.pop(context, metric),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected != null) _addMetric(selected);
  }
}

class _EditorBar extends StatelessWidget {
  final DashboardOrientation orientation;
  final ValueChanged<DashboardOrientation> onOrientationChanged;
  final VoidCallback onAdd;
  final VoidCallback onCopy;
  final VoidCallback onReset;
  final VoidCallback onDiscard;

  const _EditorBar({
    required this.orientation,
    required this.onOrientationChanged,
    required this.onAdd,
    required this.onCopy,
    required this.onReset,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        color: const Color(0xFF11151A),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SegmentedButton<DashboardOrientation>(
                segments: [
                  ButtonSegment(
                      value: DashboardOrientation.portrait,
                      label:
                          Text(AppStrings.of(context).text(AppText.portrait))),
                  ButtonSegment(
                      value: DashboardOrientation.landscape,
                      label:
                          Text(AppStrings.of(context).text(AppText.landscape))),
                ],
                selected: {orientation},
                onSelectionChanged: (value) =>
                    onOrientationChanged(value.single),
              ),
              const SizedBox(width: 12),
              IconButton(
                  tooltip: AppStrings.of(context).text(AppText.addValue),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_box_outlined)),
              IconButton(
                  tooltip: AppStrings.of(context).text(AppText.copyOrientation),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy)),
              IconButton(
                  tooltip: AppStrings.of(context).text(AppText.defaultLayout),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt)),
              IconButton(
                  tooltip: AppStrings.of(context).text(AppText.discardChanges),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  onPressed: onDiscard,
                  icon: const Icon(Icons.undo)),
            ],
          ),
        ),
      );
}

class DashboardRenderer extends StatelessWidget {
  final DashboardOrientationLayout layout;
  final ControllerState state;
  final bool connected;
  final DateTime now;
  final bool editing;
  final ValueChanged<DashboardTile>? onRemove;
  final void Function(DashboardTile, int, int)? onMove;
  final void Function(DashboardTile, int, int)? onResize;
  final void Function(DashboardTile, DashboardTileKind)? onKindChanged;
  final void Function(DashboardTile, DashboardUnit)? onUnitChanged;

  const DashboardRenderer({
    super.key,
    required this.layout,
    required this.state,
    required this.connected,
    required this.now,
    this.editing = false,
    this.onRemove,
    this.onMove,
    this.onResize,
    this.onKindChanged,
    this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / layout.columns;
          final cellHeight = constraints.maxHeight / layout.rows;
          return Stack(
            children: [
              if (editing)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DashboardGridPainter(
                      columns: layout.columns,
                      rows: layout.rows,
                    ),
                  ),
                ),
              for (final tile in layout.tiles)
                Positioned(
                  left: tile.column * cellWidth + 6,
                  top: tile.row * cellHeight + 6,
                  width: tile.width * cellWidth - 12,
                  height: tile.height * cellHeight - 12,
                  child: _TileFrame(
                    tile: tile,
                    editing: editing,
                    onRemove: () => onRemove?.call(tile),
                    onMoveLeft: () => onMove?.call(tile, -1, 0),
                    onMoveRight: () => onMove?.call(tile, 1, 0),
                    onMoveUp: () => onMove?.call(tile, 0, -1),
                    onMoveDown: () => onMove?.call(tile, 0, 1),
                    onWider: () => onResize?.call(tile, 1, 0),
                    onNarrower: () => onResize?.call(tile, -1, 0),
                    onTaller: () => onResize?.call(tile, 0, 1),
                    onShorter: () => onResize?.call(tile, 0, -1),
                    onKindChanged: (kind) => onKindChanged?.call(tile, kind),
                    onUnitChanged: (unit) => onUnitChanged?.call(tile, unit),
                    child: _MetricView(
                      tile: tile,
                      state: state,
                      connected: connected,
                      now: now,
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _DashboardGridPainter extends CustomPainter {
  final int columns;
  final int rows;

  const _DashboardGridPainter({required this.columns, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF263943)
      ..strokeWidth = 1;
    for (var column = 1; column < columns; column++) {
      final x = size.width * column / columns;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < rows; row++) {
      final y = size.height * row / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardGridPainter oldDelegate) =>
      oldDelegate.columns != columns || oldDelegate.rows != rows;
}

class _TileFrame extends StatelessWidget {
  final DashboardTile tile;
  final bool editing;
  final Widget child;
  final VoidCallback onRemove;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onWider;
  final VoidCallback onNarrower;
  final VoidCallback onTaller;
  final VoidCallback onShorter;
  final ValueChanged<DashboardTileKind> onKindChanged;
  final ValueChanged<DashboardUnit> onUnitChanged;

  const _TileFrame({
    required this.tile,
    required this.editing,
    required this.child,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onWider,
    required this.onNarrower,
    required this.onTaller,
    required this.onShorter,
    required this.onKindChanged,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: tile.metric == DashboardMetric.speed
              ? const RadialGradient(
                  colors: [Color(0xFF16232A), Color(0xFF080B0E)], radius: 0.9)
              : const LinearGradient(
                  colors: [Color(0xFF12171C), Color(0xFF0B0E12)]),
          borderRadius: BorderRadius.circular(
              tile.metric == DashboardMetric.speed ? 28 : 18),
          border: Border.all(
            color: editing
                ? const Color(0xFF00E5FF)
                : tile.metric == DashboardMetric.speed
                    ? const Color(0xFF263943)
                    : const Color(0xFF202833),
            width: editing ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: tile.height == 1
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                    : const EdgeInsets.all(14),
                child: child,
              ),
            ),
            if (editing)
              Positioned(
                right: 2,
                top: 2,
                child: PopupMenuButton<_TileCommand>(
                  tooltip:
                      '${AppStrings.of(context).metric(tile.metric.name)} ${AppStrings.of(context).text(AppText.editDashboard)}',
                  onSelected: (command) => switch (command) {
                    _TileCommand.left => onMoveLeft(),
                    _TileCommand.right => onMoveRight(),
                    _TileCommand.up => onMoveUp(),
                    _TileCommand.down => onMoveDown(),
                    _TileCommand.wider => onWider(),
                    _TileCommand.narrower => onNarrower(),
                    _TileCommand.taller => onTaller(),
                    _TileCommand.shorter => onShorter(),
                    _TileCommand.largeValue =>
                      onKindChanged(DashboardTileKind.value),
                    _TileCommand.compactValue =>
                      onKindChanged(DashboardTileKind.compact),
                    _TileCommand.arcDisplay =>
                      onKindChanged(DashboardTileKind.arc),
                    _TileCommand.unitAutomatic =>
                      onUnitChanged(DashboardUnit.automatic),
                    _TileCommand.unitMetric =>
                      onUnitChanged(DashboardUnit.metric),
                    _TileCommand.remove => onRemove(),
                  },
                  itemBuilder: (context) {
                    final strings = AppStrings.of(context);
                    final definition =
                        dashboardMeasurementCatalog[tile.metric]!;
                    return [
                      PopupMenuItem(
                          value: _TileCommand.left,
                          child: Text(
                              AppStrings.of(context).text(AppText.moveLeft))),
                      PopupMenuItem(
                          value: _TileCommand.right,
                          child: Text(
                              AppStrings.of(context).text(AppText.moveRight))),
                      PopupMenuItem(
                          value: _TileCommand.up,
                          child: Text(
                              AppStrings.of(context).text(AppText.moveUp))),
                      PopupMenuItem(
                          value: _TileCommand.down,
                          child: Text(
                              AppStrings.of(context).text(AppText.moveDown))),
                      PopupMenuItem(
                          value: _TileCommand.wider,
                          child: Text(strings.text(AppText.wider))),
                      PopupMenuItem(
                          value: _TileCommand.narrower,
                          child: Text(strings.text(AppText.narrower))),
                      PopupMenuItem(
                          value: _TileCommand.taller,
                          child: Text(strings.text(AppText.taller))),
                      PopupMenuItem(
                          value: _TileCommand.shorter,
                          child: Text(strings.text(AppText.shorter))),
                      if (definition.allowsKind(DashboardTileKind.value))
                        PopupMenuItem(
                            value: _TileCommand.largeValue,
                            child: Text(strings.text(AppText.largeValue))),
                      if (definition.allowsKind(DashboardTileKind.compact))
                        PopupMenuItem(
                            value: _TileCommand.compactValue,
                            child: Text(strings.text(AppText.compactValue))),
                      if (definition.allowsKind(DashboardTileKind.arc))
                        PopupMenuItem(
                            value: _TileCommand.arcDisplay,
                            child: Text(strings.text(AppText.arcDisplay))),
                      if (definition.allowedUnits.length > 1) ...[
                        PopupMenuItem(
                            value: _TileCommand.unitAutomatic,
                            child: Text(strings.text(AppText.unitAutomatic))),
                        PopupMenuItem(
                            value: _TileCommand.unitMetric,
                            child: Text(strings.text(AppText.unitMetric))),
                      ],
                      PopupMenuItem(
                          value: _TileCommand.remove,
                          child: Text(
                              AppStrings.of(context).text(AppText.remove))),
                    ];
                  },
                  icon: const Icon(Icons.more_vert),
                ),
              ),
          ],
        ),
      );
}

enum _TileCommand {
  left,
  right,
  up,
  down,
  wider,
  narrower,
  taller,
  shorter,
  largeValue,
  compactValue,
  arcDisplay,
  unitAutomatic,
  unitMetric,
  remove,
}

class _MetricView extends StatelessWidget {
  final DashboardTile tile;
  final ControllerState state;
  final bool connected;
  final DateTime now;

  const _MetricView({
    required this.tile,
    required this.state,
    required this.connected,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final quality = _quality(tile.metric);
    final reading = _reading(context, tile.metric, quality);
    final strings = AppStrings.of(context);
    final label = strings.metric(tile.metric.name);
    if (tile.metric == DashboardMetric.speed &&
        tile.kind == DashboardTileKind.arc) {
      return _SpeedDial(
        speedKph: state.speedKph,
        quality: quality,
      );
    }
    if (tile.metric == DashboardMetric.power &&
        tile.kind == DashboardTileKind.arc) {
      return _PowerMeter(powerKw: state.powerKw, quality: quality);
    }
    final valueColor = quality != TelemetryFreshness.fresh
        ? const Color(0xFFFFB45C)
        : tile.metric == DashboardMetric.errors
            ? state.hasAnyFault
                ? const Color(0xFFFF5470)
                : const Color(0xFF54E39E)
            : tile.metric == DashboardMetric.regeneration
                ? const Color(0xFF54E39E)
                : Colors.white;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 90 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final labelWidget = Text(label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white54, fontSize: 10, letterSpacing: 1.1));
      final valueWidget = Text(reading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: compact || tile.kind == DashboardTileKind.compact
                ? 17
                : tile.kind == DashboardTileKind.status
                    ? 18
                    : 28,
            fontWeight: FontWeight.w800,
          ));
      if (compact) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: valueWidget,
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          labelWidget,
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: valueWidget,
          ),
        ],
      );
    });
  }

  TelemetryFreshness? _quality(DashboardMetric metric) {
    if (metric == DashboardMetric.connection ||
        metric == DashboardMetric.range ||
        metric == DashboardMetric.trip) {
      return connected
          ? TelemetryFreshness.fresh
          : TelemetryFreshness.disconnected;
    }
    final field = switch (metric) {
      DashboardMetric.speed => ControllerTelemetry.speed,
      DashboardMetric.power ||
      DashboardMetric.regeneration =>
        ControllerTelemetry.power,
      DashboardMetric.voltage => ControllerTelemetry.voltage,
      DashboardMetric.current => ControllerTelemetry.current,
      DashboardMetric.soc => ControllerTelemetry.soc,
      DashboardMetric.range => ControllerTelemetry.range,
      DashboardMetric.profile => ControllerTelemetry.profile,
      DashboardMetric.gear => ControllerTelemetry.gear,
      DashboardMetric.motorTemperature => ControllerTelemetry.motorTemperature,
      DashboardMetric.controllerTemperature =>
        ControllerTelemetry.controllerTemperature,
      DashboardMetric.errors => ControllerTelemetry.errors,
      DashboardMetric.connection => null,
      DashboardMetric.trip => ControllerTelemetry.trip,
    };
    final sample = field == null ? null : state.sample(field);
    if (sample == null) {
      return connected ? null : TelemetryFreshness.disconnected;
    }
    final definition = dashboardMeasurementCatalog[metric]!;
    final effectiveNow =
        sample.capturedAt.isAfter(now) ? sample.capturedAt : now;
    return sample.quality(
      now: effectiveNow,
      connected: connected,
      maxAge: definition.maxAge,
      minimum: definition.minimum,
      maximum: definition.maximum,
    );
  }

  String _reading(BuildContext context, DashboardMetric metric,
      TelemetryFreshness? quality) {
    final strings = AppStrings.of(context);
    if (metric != DashboardMetric.connection &&
        quality != TelemetryFreshness.fresh) {
      return switch (quality) {
        null => strings.text(AppText.missing),
        TelemetryFreshness.stale => strings.text(AppText.stale),
        TelemetryFreshness.invalid => strings.text(AppText.invalid),
        TelemetryFreshness.disconnected => 'OFF',
        TelemetryFreshness.fresh => strings.text(AppText.unknown),
      };
    }
    return switch (metric) {
      DashboardMetric.speed => '${state.speedKph.toStringAsFixed(0)} km/h',
      DashboardMetric.power => '${state.powerKw.toStringAsFixed(1)} kW',
      DashboardMetric.regeneration =>
        '${math.max(-state.powerKw, 0).toStringAsFixed(1)} kW',
      DashboardMetric.voltage => '${state.voltageV.toStringAsFixed(1)} V',
      DashboardMetric.current => '${state.currentA.toStringAsFixed(1)} A',
      DashboardMetric.soc => '${state.battCapPercent} %',
      DashboardMetric.range => state.rangeKm == 0
          ? '65 ± 8 km'
          : '${state.rangeKm.toStringAsFixed(0)} ± ${state.rangeUncertaintyKm.toStringAsFixed(0)} km',
      DashboardMetric.profile => state.rideMode.displayName,
      DashboardMetric.gear => state.gear == null
          ? 'N'
          : !state.isForward
              ? 'R'
              : state.gear == 1
                  ? 'N'
                  : state.gear == 2
                      ? 'D1'
                      : state.gear == 3
                          ? 'D2'
                          : state.gear == 4
                              ? 'D3'
                              : 'N',
      DashboardMetric.motorTemperature =>
        '${state.motorTempC.toStringAsFixed(0)} °C',
      DashboardMetric.controllerTemperature =>
        '${state.controllerTempC.toStringAsFixed(0)} °C',
      DashboardMetric.errors => state.hasAnyFault
          ? AppStrings.of(context).text(AppText.error)
          : AppStrings.of(context).text(AppText.noErrors),
      DashboardMetric.connection => connected
          ? AppStrings.of(context).text(AppText.connected)
          : AppStrings.of(context).text(AppText.disconnected),
      DashboardMetric.trip => state.tripDistanceKm == null
          ? '0.0 km'
          : '${state.tripDistanceKm!.toStringAsFixed(1)} km',
    };
  }
}

class _ConnectionPill extends StatelessWidget {
  final bool connected;
  final VoidCallback onTap;

  const _ConnectionPill({required this.connected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Material(
          color: connected ? const Color(0xFF123328) : const Color(0xFF271D20),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.bluetooth,
                      size: 16,
                      color: connected
                          ? const Color(0xFF54E39E)
                          : const Color(0xFFFFB45C)),
                  const SizedBox(width: 6),
                  Text(
                      AppStrings.of(context)
                          .text(connected ? AppText.live : AppText.connect),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SpeedDial extends StatelessWidget {
  final double speedKph;
  final TelemetryFreshness? quality;

  const _SpeedDial({
    required this.speedKph,
    required this.quality,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('speed-dial'),
      label: quality == TelemetryFreshness.fresh
          ? '${AppStrings.of(context).metric('speed')} ${speedKph.round()} km/h'
          : 'Geschwindigkeit ${_qualityLabel(context, quality)}',
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
                child: CustomPaint(
                    painter: _SpeedDialPainter(
                        speedKph:
                            quality == TelemetryFreshness.fresh ? speedKph : 0,
                        active: quality == TelemetryFreshness.fresh))),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    quality == TelemetryFreshness.fresh
                        ? speedKph.round().toString()
                        : '–',
                    style: TextStyle(
                        fontSize: math.min(constraints.maxHeight * 0.29, 82),
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3)),
                const SizedBox(height: 8),
                Text('km/h',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
                const SizedBox(height: 8),
                Text(
                    quality == TelemetryFreshness.disconnected
                        ? 'OFF'
                        : AppStrings.of(context).text(
                            quality == TelemetryFreshness.fresh
                                ? AppText.controller
                                : _qualityText(quality)),
                    style: TextStyle(
                        color: quality == TelemetryFreshness.fresh
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFFFB45C),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedDialPainter extends CustomPainter {
  final double speedKph;
  final bool active;

  const _SpeedDialPainter({required this.speedKph, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.39;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * 0.72;
    const sweep = math.pi * 1.56;
    final track = Paint()
      ..color = const Color(0xFF243039)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    final progress = (speedKph / 120).clamp(0.0, 1.0);
    final activePaint = Paint()
      ..shader = const SweepGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF54E39E), Color(0xFFFFB45C)],
          stops: [0, 0.72, 1]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    if (active) {
      canvas.drawArc(rect, start, sweep * progress, false, activePaint);
    }
    final tickPaint = Paint()..strokeWidth = 2;
    for (var i = 0; i <= 12; i++) {
      final angle = start + sweep * i / 12;
      tickPaint.color =
          i / 12 <= progress && active ? Colors.white : const Color(0xFF52616A);
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius + 18);
      final inner = center +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius + (i.isEven ? 4 : 9));
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedDialPainter oldDelegate) =>
      oldDelegate.speedKph != speedKph || oldDelegate.active != active;
}

class _PowerMeter extends StatelessWidget {
  final double powerKw;
  final TelemetryFreshness? quality;

  const _PowerMeter({required this.powerKw, required this.quality});

  @override
  Widget build(BuildContext context) {
    final regen = powerKw < 0;
    final fresh = quality == TelemetryFreshness.fresh;
    final color = !fresh
        ? Colors.white24
        : regen
            ? const Color(0xFF54E39E)
            : powerKw >= 15
                ? const Color(0xFFFF5470)
                : powerKw >= 8
                    ? const Color(0xFFFFB45C)
                    : const Color(0xFF00E5FF);
    final normalized = fresh ? (powerKw.abs() / 20).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: fresh
          ? '${regen ? 'Rekuperation' : 'Leistung'} ${powerKw.abs().toStringAsFixed(1)} Kilowatt'
          : 'Leistung ${_qualityLabel(context, quality)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(regen ? Icons.battery_charging_full : Icons.bolt,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    AppStrings.of(context)
                        .text(regen ? AppText.regeneration : AppText.power),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                    fresh
                        ? '${powerKw.abs().toStringAsFixed(1)} kW'
                        : quality == TelemetryFreshness.disconnected
                            ? 'OFF'
                            : AppStrings.of(context)
                                .text(_qualityText(quality)),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: normalized,
                minHeight: 8,
                backgroundColor: const Color(0xFF263039),
                valueColor: AlwaysStoppedAnimation(color)),
          ),
        ],
      ),
    );
  }
}

AppText _qualityText(TelemetryFreshness? quality) => switch (quality) {
      null => AppText.missing,
      TelemetryFreshness.stale => AppText.stale,
      TelemetryFreshness.invalid => AppText.invalid,
      TelemetryFreshness.disconnected => AppText.disconnected,
      TelemetryFreshness.fresh => AppText.controller,
    };

String _qualityLabel(BuildContext context, TelemetryFreshness? quality) =>
    AppStrings.of(context).text(_qualityText(quality));
