import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'role_select_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const PatientMonitoringApp());
}

class PatientMonitoringApp extends StatelessWidget {
  const PatientMonitoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient Monitoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RoleSelectPage(),
    );
  }
}
