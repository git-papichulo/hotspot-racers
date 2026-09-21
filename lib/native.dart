import 'package:flutter/services.dart';

class Native {
  static const MethodChannel _ch = MethodChannel('hotspot_racers/native');

  static Future<bool> prepare({required bool bindWifi}) async {
    try {
      final r = await _ch.invokeMethod<bool>('prepare', <String, dynamic>{'bindWifi': bindWifi});
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> release() async {
    try {
      await _ch.invokeMethod<bool>('release');
    } catch (_) {}
  }

  static Future<String?> getPref(String k) async {
    try {
      return await _ch.invokeMethod<String>('getPref', <String, dynamic>{'k': k});
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPref(String k, String v) async {
    try {
      await _ch.invokeMethod<bool>('setPref', <String, dynamic>{'k': k, 'v': v});
    } catch (_) {}
  }
}
