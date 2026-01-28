import 'package:flutter/material.dart';
import 'pages/patient_home.dart';
import 'pages/caregiver_home.dart';
import 'pages/doctor_home.dart';

class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    const patientId = 'p1';

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Role')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _RoleButton(
              title: 'Patient',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientHome(patientId: patientId),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _RoleButton(
              title: 'Caregiver',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CaregiverHome(patientId: patientId),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _RoleButton(
              title: 'Doctor',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorHome(patientId: patientId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _RoleButton({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(title, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}