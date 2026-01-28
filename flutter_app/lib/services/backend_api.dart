import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart'; // וודא שהייבוא הזה תקין לפי מבנה התיקיות שלך

class BackendApi {
  // שינוי 1: שימוש בכתובת הכללית מתוך קובץ הקונפיגורציה
  // אם הייבוא לא עובד, אתה יכול להדביק כאן את המחרוזת:
  // 'https://us-central1-pocg5-c30e6.cloudfunctions.net'
  final String baseUrl = AppConfig.functionsBaseUrl;

  final http.Client client = http.Client();

  // פונקציית עזר לביצוע בקשות כדי למנוע שכפול קוד וטעויות בכתובת
  Future<void> _post(String functionName, Map<String, dynamic> body) async {
    // שינוי 2: בניית ה-URL בצורה נכונה
    // התוצאה תהיה: https://us-central1-pocg5-c30e6.cloudfunctions.net/startSession
    final uri = Uri.parse('$baseUrl/$functionName');

    print('Calling: $uri with body: $body'); // לוג לדיבאג

    try {
      final res = await client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      print('Response (${res.statusCode}): ${res.body}');

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Error $functionName: ${res.statusCode} - ${res.body}');
      }
    } catch (e) {
      print('Network Error: $e');
      rethrow;
    }
  }

  // --- 1. Register Token ---
  Future<void> registerToken({
    required String patientId,
    required String token,
    required String role,
    required String platform,
  }) async {
    await _post('registerToken', {
      'patientId': patientId,
      'token': token,
      'role': role,
      'platform': platform,
    });
  }

  // --- 2. Start Session ---
  Future<void> startSession({required String patientId}) async {
    await _post('startSession', {'patientId': patientId});
  }

  // --- 3. Stop Session ---
  Future<void> stopSession({required String patientId}) async {
    await _post('stopSession', {'patientId': patientId});
  }

  // --- 4. I'm OK ---
  Future<void> imOk({required String patientId}) async {
    await _post('imOk', {'patientId': patientId});
  }

  // --- 5. Handle Alert (Caregiver) ---
  Future<void> caregiverHandleAlert({required String patientId, required String alertId}) async {
    await _post('caregiverHandleAlert', {
      'patientId': patientId,
      'alertId': alertId,
    });
  }
}