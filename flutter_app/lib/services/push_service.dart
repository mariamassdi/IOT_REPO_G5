import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'backend_api.dart';

class PushService {
  PushService(this.api);
  final BackendApi api;

  Future<void> initAndRegister({
    required String patientId,
    required String role,
  }) async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (token == null) return;

    await api.registerToken(
      patientId: patientId,
      token: token,
      role: role,
      platform: Platform.isAndroid ? 'android' : 'ios',
    );
  }
}
