class MacroDroidContract {
  static const action = 'com.arcdash.arcdash.APPLY_STREET_LEGAL';

  const MacroDroidContract();

  MacroDroidRequest? parse(
      {required String actionName, Map<String, Object?> extras = const {}}) {
    if (actionName != action || extras.isNotEmpty) return null;
    return const MacroDroidRequest();
  }
}

class MacroDroidRequest {
  const MacroDroidRequest();
}
