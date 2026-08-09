import 'package:arcdash/services/macrodroid_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts exactly the local Street-Legal action', () {
    final request = const MacroDroidContract().parse(
      actionName: MacroDroidContract.action,
    );
    expect(request, isNotNull);
  });

  test('rejects arbitrary actions and parameter extras', () {
    const contract = MacroDroidContract();
    expect(contract.parse(actionName: 'other'), isNull);
    expect(
      contract.parse(
        actionName: MacroDroidContract.action,
        extras: const {'profile': 'Full Send'},
      ),
      isNull,
    );
  });
}
