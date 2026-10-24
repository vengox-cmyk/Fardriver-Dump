import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/snapshot_builder.dart';

/// Passive capture of the configuration blocks that the controller already
/// streams after the existing 0xA0 start-stream command.
///
/// This class only *listens*: it has no access to the BLE transport and never
/// sends anything. Once every config block (0x00-0xD0 + 0x5D) has been seen
/// within the builder timeout, the complete snapshot is persisted through
/// [ParameterSnapshotRepository] so it can be exported later while offline.
class ParameterCaptureService {
  static const source = 'live';

  /// Blocks a snapshot must contain to be saved/exported (0x00-0xD0).
  static final Set<int> requiredBlocks =
      Set.unmodifiable(FardriverParamCatalog.mandatoryBlocks);

  /// Blocks captured when streamed; if still missing once [timeout] has
  /// passed since the capture started, the snapshot is saved without them.
  static final Set<int> optionalBlocks =
      Set.unmodifiable(FardriverParamCatalog.optionalBlocks);

  static final Set<int> _configBlocks =
      Set.unmodifiable(FardriverParamCatalog.configBlocks);

  final ParameterSnapshotRepository? _repository;
  final String Function() _controllerId;
  final DateTime Function() _clock;
  final String appVersion;
  final ParameterSnapshotBuilder _builder;
  final Duration timeout;

  bool _started = false;
  String? _lastSavedSignature;
  PersistedParameterSnapshot? _latest;
  Future<void>? _pendingSave;

  ParameterCaptureService({
    ParameterSnapshotRepository? repository,
    required String Function() controllerId,
    DateTime Function()? clock,
    this.appVersion = '',
    Duration timeout = const Duration(seconds: 10),
  })  : _repository = repository,
        _controllerId = controllerId,
        _clock = clock ?? DateTime.now,
        timeout = timeout,
        _builder = ParameterSnapshotBuilder(timeout: timeout);

  /// Latest complete snapshot captured in this app session (null until done).
  PersistedParameterSnapshot? get latest => _latest;

  /// Completes when the most recent persistence call has finished.
  Future<void> get pendingSave => _pendingSave ?? Future.value();

  double progress() {
    if (!_started) return 0;
    return _builder.snapshot(at: _clock()).progress;
  }

  /// Feed one parsed status packet. Non-config packets only advance the
  /// optional-block timeout; their data is ignored.
  void addBlock(int address, List<int> data) {
    final now = _clock();
    final isConfig = _configBlocks.contains(address) &&
        data.length == FardriverParamCatalog.blockLength;
    if (!isConfig) {
      if (_started) _maybeSave(now);
      return;
    }
    if (!_started) {
      final id = _controllerId().trim();
      _builder.begin(
        controllerId: id.isEmpty ? 'unknown' : id,
        requiredAddresses: requiredBlocks,
        at: now,
      );
      _started = true;
    }
    _builder.addBlock(address: address, bytes: data, at: now);
    _maybeSave(now);
  }

  void _maybeSave(DateTime now) {
    final snapshot = _builder.snapshot(at: now);
    if (!snapshot.isComplete) return; // a mandatory block is still missing
    final missingOptional = optionalBlocks
        .where((b) => !snapshot.blocks.containsKey(b))
        .toList()
      ..sort();
    if (missingOptional.isNotEmpty &&
        now.difference(snapshot.startedAt) < timeout) {
      return; // give the optional blocks until the capture timeout
    }
    final signature = _signature(snapshot.blocks);
    if (signature == _lastSavedSignature) return;
    _lastSavedSignature = signature;
    final persisted = PersistedParameterSnapshot(
      controller: identityFromBlocks(snapshot.blocks, snapshot.controllerId),
      requiredAddresses: requiredBlocks,
      rawBlocks: snapshot.blocks,
      metadata: {
        'controllerId': snapshot.controllerId,
        'appVersion': appVersion,
        'missingOptionalBlocks': missingOptional,
      },
      source: source,
      capturedAt: now,
      complete: true,
    );
    _latest = persisted;
    final repository = _repository;
    if (repository != null) {
      _pendingSave = repository.save(persisted).catchError((Object _) {
        _lastSavedSignature = null; // retry on the next complete cycle
      });
    }
  }

  /// Call on disconnect: partially collected blocks are discarded.
  void reset() {
    _started = false;
  }

  static String _signature(Map<int, List<int>> blocks) {
    final keys = blocks.keys.toList()..sort();
    return keys.map((k) => '$k:${blocks[k]!.join(',')}').join(';');
  }

  /// Controller identity derived from the streamed blocks. Fields that the
  /// controller leaves blank fall back to placeholders so the persisted
  /// snapshot stays usable; the raw blocks are always kept in full.
  static ControllerIdentity identityFromBlocks(
      Map<int, List<int>> blocks, String bindingId) {
    String text(int block, String name) {
      final data = blocks[block];
      if (data == null) return '';
      final def = FardriverParamCatalog.byName(name, block: block);
      return FardriverDecoder.decode(def, data).value.trim();
    }

    String raw(int block, String name) {
      final data = blocks[block];
      if (data == null) return '';
      return FardriverDecoder.decode(
              FardriverParamCatalog.byName(name, block: block), data)
          .raw;
    }

    String orUnknown(String v) => v.isEmpty ? 'unknown' : v;
    final model = '${text(0xA0, 'ModelName')}${text(0xA6, 'ModelName')}';
    return ControllerIdentity(
      model: orUnknown(model),
      hardwareVersion: orUnknown(text(0x82, 'HardwareVersion')),
      firmwareVersion: orUnknown('${text(0x82, 'SoftwareVersionMajor')}'
          '.${raw(0x82, 'SoftwareVersionMinor')}'),
      functionCode: orUnknown(raw(0x69, 'ParaIndex')),
      extensionCode: orUnknown(raw(0x69, 'SpecialCode')),
      bindingId: orUnknown(bindingId),
    );
  }

  /// Converts a persisted snapshot into an exportable dump.
  static ParameterDump toDump(PersistedParameterSnapshot snapshot) =>
      ParameterDump(
        source: ParameterDumpSource.live,
        sourceLabel: snapshot.source,
        blocks: snapshot.rawBlocks,
        requiredBlocks: (snapshot.requiredAddresses
            .where((b) => !optionalBlocks.contains(b))
            .toList()
          ..sort()),
        optionalBlocks: FardriverParamCatalog.optionalBlocks,
        controllerId: (snapshot.metadata['controllerId'] as String?) ?? '',
        capturedAt: snapshot.capturedAt,
        appVersion: (snapshot.metadata['appVersion'] as String?) ?? '',
      );
}
