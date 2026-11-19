import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 通知を有効にした結果
class PushRegistration {
  const PushRegistration({required this.granted, required this.platform, required this.token});

  final bool granted;

  /// サーバーに登録する端末の種類（ios / ios-simulator / android）
  final String platform;

  /// 端末トークン。シミュレーターなどで APNs のトークンが取れない場合は試作用の ID
  final String token;
}

/// iOS のネイティブ側（AppDelegate.swift の VamosPushPlugin）とつなぐ。
///
/// 本番では Firebase Cloud Messaging に置き換える想定。
abstract final class PushService {
  static const _channel = MethodChannel('vamos/push');

  /// 通知タップを受け取れるようにし、起動前にタップされた通知があれば開く。
  static Future<void> init({required void Function(String link) onOpenLink}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap' && call.arguments is String) {
        onOpenLink(call.arguments as String);
      }
    });
    try {
      final pending = await _channel.invokeMethod<String>('ready');
      if (pending != null) onOpenLink(pending);
    } on MissingPluginException {
      // ネイティブ側の実装がない環境（Android の試作など）
    } on PlatformException catch (error) {
      debugPrint('通知の初期化に失敗しました: $error');
    }
  }

  /// 通知の許可を求め、通知先として登録する情報を返す。
  static Future<PushRegistration> enable() async {
    if (!Platform.isIOS) {
      throw UnsupportedError('試作版の通知は iOS のみ対応しています（Android は Firebase で対応予定）');
    }
    final result = await _channel.invokeMapMethod<String, Object?>('requestPermission') ?? const {};
    final granted = result['granted'] == true;
    final simulator = result['simulator'] == true;
    final token = result['token'] as String? ?? 'simulator-${Random().nextInt(1 << 32).toRadixString(16)}';
    return PushRegistration(
      granted: granted,
      platform: simulator ? 'ios-simulator' : 'ios',
      token: token,
    );
  }

  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
