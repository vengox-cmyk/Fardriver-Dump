import 'dart:convert';

enum DashboardOrientation { portrait, landscape }

enum DashboardMetric {
  speed,
  power,
  regeneration,
  voltage,
  current,
  soc,
  range,
  profile,
  gear,
  motorTemperature,
  controllerTemperature,
  errors,
  connection,
  trip,
}

enum DashboardTileKind { value, compact, status, arc, bar, circle }

enum DashboardUnit { automatic, metric }

class DashboardMeasurementDefinition {
  final DashboardTileKind defaultKind;
  final Set<DashboardTileKind> allowedKinds;
  final Set<DashboardUnit> allowedUnits;
  final int minimumWidth;
  final int minimumHeight;
  final Duration maxAge;
  final double? minimum;
  final double? maximum;

  const DashboardMeasurementDefinition({
    required this.defaultKind,
    this.allowedKinds = const {},
    this.allowedUnits = const {DashboardUnit.automatic},
    this.minimumWidth = 1,
    this.minimumHeight = 1,
    this.maxAge = const Duration(seconds: 2),
    this.minimum,
    this.maximum,
  });

  DashboardTileKind get kind => defaultKind;

  bool allowsKind(DashboardTileKind kind) =>
      kind == defaultKind || allowedKinds.contains(kind);

  int minimumWidthFor(DashboardTileKind kind) {
    if (kind == DashboardTileKind.compact ||
        kind == DashboardTileKind.value ||
        kind == DashboardTileKind.status) {
      return 1;
    }
    return minimumWidth;
  }

  int minimumHeightFor(DashboardTileKind kind) {
    if (kind == DashboardTileKind.compact ||
        kind == DashboardTileKind.value ||
        kind == DashboardTileKind.status) {
      return 1;
    }
    return minimumHeight;
  }
}

const dashboardMeasurementCatalog =
    <DashboardMetric, DashboardMeasurementDefinition>{
  DashboardMetric.speed: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.arc,
    allowedKinds: {
      DashboardTileKind.value,
      DashboardTileKind.compact,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    allowedUnits: {
      DashboardUnit.automatic,
      DashboardUnit.metric,
    },
    minimumWidth: 3,
    minimumHeight: 3,
    minimum: 0,
    maximum: 120,
  ),
  DashboardMetric.power: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.arc,
    allowedKinds: {
      DashboardTileKind.value,
      DashboardTileKind.compact,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    minimum: -60,
    maximum: 60,
  ),
  DashboardMetric.regeneration: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    minimum: -60,
    maximum: 60,
  ),
  DashboardMetric.voltage: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    maxAge: Duration(seconds: 5),
    minimum: 0,
    maximum: 150,
  ),
  DashboardMetric.current: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    minimum: -600,
    maximum: 600,
  ),
  DashboardMetric.soc: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    maxAge: Duration(seconds: 10),
    minimum: 0,
    maximum: 100,
  ),
  DashboardMetric.range: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
    },
    allowedUnits: {
      DashboardUnit.automatic,
      DashboardUnit.metric,
    },
    maxAge: Duration(seconds: 10),
    minimum: 0,
  ),
  DashboardMetric.profile: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.status,
    allowedKinds: {DashboardTileKind.value, DashboardTileKind.compact},
  ),
  DashboardMetric.gear: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {DashboardTileKind.compact, DashboardTileKind.circle},
    maxAge: Duration(seconds: 5),
    minimum: 0,
    maximum: 3,
  ),
  DashboardMetric.motorTemperature: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    maxAge: Duration(seconds: 10),
    minimum: -50,
    maximum: 250,
  ),
  DashboardMetric.controllerTemperature: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {
      DashboardTileKind.compact,
      DashboardTileKind.arc,
      DashboardTileKind.bar,
      DashboardTileKind.circle,
    },
    maxAge: Duration(seconds: 10),
    minimum: -50,
    maximum: 250,
  ),
  DashboardMetric.errors: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.status,
    allowedKinds: {DashboardTileKind.value},
    maxAge: Duration(seconds: 5),
    minimum: 0,
    maximum: 1,
  ),
  DashboardMetric.connection: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.status,
    allowedKinds: {DashboardTileKind.value},
  ),
  DashboardMetric.trip: DashboardMeasurementDefinition(
    defaultKind: DashboardTileKind.value,
    allowedKinds: {DashboardTileKind.compact},
    allowedUnits: {
      DashboardUnit.automatic,
      DashboardUnit.metric,
    },
    maxAge: Duration(seconds: 10),
    minimum: 0,
  ),
};

class DashboardTile {
  final String id;
  final DashboardMetric metric;
  final DashboardTileKind kind;
  final int column;
  final int row;
  final int width;
  final int height;
  final DashboardUnit unit;

  const DashboardTile({
    required this.id,
    required this.metric,
    required this.kind,
    required this.column,
    required this.row,
    required this.width,
    required this.height,
    this.unit = DashboardUnit.automatic,
  });

  DashboardTile copyWith({
    int? column,
    int? row,
    int? width,
    int? height,
    DashboardTileKind? kind,
    DashboardUnit? unit,
  }) =>
      DashboardTile(
        id: id,
        metric: metric,
        kind: kind ?? this.kind,
        column: column ?? this.column,
        row: row ?? this.row,
        width: width ?? this.width,
        height: height ?? this.height,
        unit: unit ?? this.unit,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'metric': metric.name,
        'kind': kind.name,
        'column': column,
        'row': row,
        'width': width,
        'height': height,
        if (unit != DashboardUnit.automatic) 'unit': unit.name,
      };

  factory DashboardTile.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('invalid dashboard tile');
    final metric =
        DashboardMetric.values.where((e) => e.name == value['metric']);
    final kind = DashboardTileKind.values.where((e) => e.name == value['kind']);
    final unitName = value['unit'];
    final units = DashboardUnit.values.where((e) => e.name == unitName);
    final fields = [
      value['column'],
      value['row'],
      value['width'],
      value['height']
    ];
    if (value['id'] is! String ||
        metric.length != 1 ||
        kind.length != 1 ||
        fields.any((field) => field is! int) ||
        (unitName != null && units.length != 1)) {
      throw const FormatException('invalid dashboard tile');
    }
    return DashboardTile(
      id: value['id'] as String,
      metric: metric.single,
      kind: kind.single,
      column: value['column'] as int,
      row: value['row'] as int,
      width: value['width'] as int,
      height: value['height'] as int,
      unit: unitName == null ? DashboardUnit.automatic : units.single,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardTile &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class DashboardOrientationLayout {
  final int columns;
  final int rows;
  final List<DashboardTile> tiles;

  const DashboardOrientationLayout({
    required this.columns,
    required this.rows,
    required this.tiles,
  });

  DashboardOrientationLayout copyWith({List<DashboardTile>? tiles}) =>
      DashboardOrientationLayout(
        columns: columns,
        rows: rows,
        tiles: tiles ?? this.tiles,
      );

  void validate() {
    if (columns < 1 ||
        rows < 1 ||
        tiles.map((tile) => tile.id).toSet().length != tiles.length) {
      throw const FormatException('invalid dashboard layout');
    }
    for (final tile in tiles) {
      if (tile.id.trim().isEmpty ||
          tile.column < 0 ||
          tile.row < 0 ||
          tile.width < 1 ||
          tile.height < 1 ||
          tile.column + tile.width > columns ||
          tile.row + tile.height > rows) {
        throw const FormatException('dashboard tile outside grid');
      }
      final definition = dashboardMeasurementCatalog[tile.metric];
      if (definition == null || !definition.allowsKind(tile.kind)) {
        throw const FormatException('unsupported dashboard tile kind');
      }
      if (!definition.allowedUnits.contains(tile.unit)) {
        throw const FormatException('unsupported dashboard unit');
      }
      if (tile.width < definition.minimumWidthFor(tile.kind) ||
          tile.height < definition.minimumHeightFor(tile.kind)) {
        throw const FormatException('dashboard tile is too small');
      }
    }
    for (var index = 0; index < tiles.length; index++) {
      for (var other = index + 1; other < tiles.length; other++) {
        final first = tiles[index];
        final second = tiles[other];
        final separated = first.column + first.width <= second.column ||
            second.column + second.width <= first.column ||
            first.row + first.height <= second.row ||
            second.row + second.height <= first.row;
        if (!separated) {
          throw const FormatException('overlapping dashboard tiles');
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
        'columns': columns,
        'rows': rows,
        'tiles': tiles.map((tile) => tile.toJson()).toList(),
      };

  factory DashboardOrientationLayout.fromJson(Object? value) {
    if (value is! Map ||
        value['columns'] is! int ||
        value['rows'] is! int ||
        value['tiles'] is! List) {
      throw const FormatException('invalid dashboard layout');
    }
    final layout = DashboardOrientationLayout(
      columns: value['columns'] as int,
      rows: value['rows'] as int,
      tiles: (value['tiles'] as List).map(DashboardTile.fromJson).toList(),
    );
    layout.validate();
    return layout;
  }
}

class DashboardLayout {
  static const schemaVersion = 2;
  final DashboardOrientationLayout portrait;
  final DashboardOrientationLayout landscape;

  const DashboardLayout({required this.portrait, required this.landscape});

  static DashboardLayout defaults() => DashboardLayout(
        portrait: DashboardOrientationLayout(
          columns: 4,
          rows: 8,
          tiles: const [
            DashboardTile(
                id: 'speed',
                metric: DashboardMetric.speed,
                kind: DashboardTileKind.arc,
                column: 0,
                row: 0,
                width: 4,
                height: 4),
            DashboardTile(
                id: 'power',
                metric: DashboardMetric.power,
                kind: DashboardTileKind.arc,
                column: 0,
                row: 4,
                width: 4,
                height: 2),
            DashboardTile(
                id: 'soc',
                metric: DashboardMetric.soc,
                kind: DashboardTileKind.value,
                column: 0,
                row: 6,
                width: 2,
                height: 1),
            DashboardTile(
                id: 'range',
                metric: DashboardMetric.range,
                kind: DashboardTileKind.value,
                column: 2,
                row: 6,
                width: 2,
                height: 1),
            DashboardTile(
                id: 'profile',
                metric: DashboardMetric.profile,
                kind: DashboardTileKind.status,
                column: 0,
                row: 7,
                width: 2,
                height: 1),
            DashboardTile(
                id: 'errors',
                metric: DashboardMetric.errors,
                kind: DashboardTileKind.status,
                column: 2,
                row: 7,
                width: 2,
                height: 1),
          ],
        ),
        landscape: DashboardOrientationLayout(
          columns: 12,
          rows: 6,
          tiles: const [
            DashboardTile(
              id: 'power',
              metric: DashboardMetric.power,
              kind: DashboardTileKind.arc,
              column: 0,
              row: 0,
              width: 12,
              height: 2,
            ),
            DashboardTile(
              id: 'soc',
              metric: DashboardMetric.soc,
              kind: DashboardTileKind.value,
              column: 0,
              row: 2,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'range',
              metric: DashboardMetric.range,
              kind: DashboardTileKind.value,
              column: 0,
              row: 3,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'trip',
              metric: DashboardMetric.trip,
              kind: DashboardTileKind.value,
              column: 0,
              row: 4,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'profile',
              metric: DashboardMetric.profile,
              kind: DashboardTileKind.status,
              column: 0,
              row: 5,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'speed',
              metric: DashboardMetric.speed,
              kind: DashboardTileKind.arc,
              column: 3,
              row: 2,
              width: 6,
              height: 4,
            ),
            DashboardTile(
              id: 'motorTemperature',
              metric: DashboardMetric.motorTemperature,
              kind: DashboardTileKind.value,
              column: 9,
              row: 2,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'controllerTemperature',
              metric: DashboardMetric.controllerTemperature,
              kind: DashboardTileKind.value,
              column: 9,
              row: 3,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'errors',
              metric: DashboardMetric.errors,
              kind: DashboardTileKind.status,
              column: 9,
              row: 4,
              width: 3,
              height: 1,
            ),
            DashboardTile(
              id: 'connection',
              metric: DashboardMetric.connection,
              kind: DashboardTileKind.status,
              column: 9,
              row: 5,
              width: 3,
              height: 1,
            ),
          ],
        ),
      );

  List<DashboardTile> forOrientation(DashboardOrientation orientation) =>
      orientation == DashboardOrientation.portrait
          ? portrait.tiles
          : landscape.tiles;

  DashboardOrientationLayout layoutFor(DashboardOrientation orientation) =>
      orientation == DashboardOrientation.portrait ? portrait : landscape;

  DashboardLayout withLayout(DashboardOrientation orientation,
          DashboardOrientationLayout layout) =>
      orientation == DashboardOrientation.portrait
          ? DashboardLayout(portrait: layout, landscape: landscape)
          : DashboardLayout(portrait: portrait, landscape: layout);

  Map<String, Object?> toJson() => {
        'version': schemaVersion,
        'portrait': portrait.toJson(),
        'landscape': landscape.toJson(),
      };

  factory DashboardLayout.fromJson(Object? value) {
    if (value is! Map || value['version'] != schemaVersion) {
      throw const FormatException('unknown dashboard schema');
    }
    return DashboardLayout(
      portrait: DashboardOrientationLayout.fromJson(value['portrait']),
      landscape: DashboardOrientationLayout.fromJson(value['landscape']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardLayout &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
