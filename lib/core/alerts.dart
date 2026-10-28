import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shop bell + phone notification for new orders.
/// Works while the app is open or in the background (not fully closed —
/// that needs Firebase push, planned for Phase 5).
class Alerts {
  Alerts._();

  static final _notes = FlutterLocalNotificationsPlugin();
  static AudioPlayer? _player;
  static bool _ready = false;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Call once on the shopkeeper side. Asks for notification permission (Android 13+).
  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    if (!_android) return;
    try {
      await _notes.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _notes
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  static Future<void> newOrder({required int orderNo, required String title, required String body}) async {
    unawaited(HapticFeedback.heavyImpact());
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource('sounds/new_order.wav'));
    } catch (e) {
      debugPrint('sound failed: $e'); // e.g. browser blocked autoplay before the first tap
    }
    if (!_android) return;
    try {
      await _notes.show(
        id: orderNo,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'new_orders',
            'New orders',
            channelDescription: 'Rings when a customer places an order',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
        ),
      );
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }
}
