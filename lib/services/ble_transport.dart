import 'bluetooth_service.dart';

abstract interface class BleTransport {
  Stream<DongleConnectionState> get connectionStateStream;
  Stream<List<int>> get rawDataStream;
  Stream<List<DiscoveredDongle>> get scanResultsStream;
  DongleConnectionState get state;

  Future<bool> isBluetoothOn();
  Future<void> startScan({Duration timeout});
  Future<void> stopScan();
  Future<bool> connect(DiscoveredDongle dongle);
  Future<bool> write(List<int> data);
  Future<void> disconnect();
  void dispose();
}
