import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/backend_api.dart';
import '../services/push_service.dart';

class CaregiverHome extends StatefulWidget {
  final String patientId;
  const CaregiverHome({super.key, required this.patientId});

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  late final BackendApi api;
  late final PushService push;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    api = BackendApi();
    push = PushService(api);
    push.initAndRegister(patientId: widget.patientId, role: 'caregiver');
  }

  Future<void> _markAsHandled(String alertId) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.caregiverHandleAlert(patientId: widget.patientId, alertId: alertId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Alert marked as handled")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));

    final q = FirebaseFirestore.instance
        .collection('patients/${widget.patientId}/alerts')
        .where('timestamp', isGreaterThan: cutoff)
        .orderBy('timestamp', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: Text('Caregiver Alerts (${widget.patientId})')),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('No alerts in the last 24h', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final docId = docs[i].id;

              final rawType = d['type']?.toString() ?? 'ALERT';
              final typeDisplay = rawType.toUpperCase().replaceAll('_', ' ');

              final handled = (d['handled'] ?? false) == true;
              final handledBy = d['handledBy']?.toString() ?? '';
              final timestamp = (d['timestamp'] as Timestamp?)?.toDate();
              final timeStr = timestamp != null
                  ? "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}"
                  : '';

              Color cardColor;
              Color iconColor;
              IconData iconData;
              Widget statusWidget;

              if (!handled) {
                cardColor = rawType == 'long_immobility' ? Colors.orange.shade50 : Colors.red.shade50;
                iconColor = rawType == 'long_immobility' ? Colors.orange.shade900 : Colors.red.shade900;
                iconData = rawType == 'long_immobility' ? Icons.person_off : Icons.warning_rounded;

                statusWidget = ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rawType == 'long_immobility' ? Colors.orange.shade800 : Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text("MARK AS HANDLED"),
                  onPressed: busy ? null : () => _markAsHandled(docId),
                );
              } else {
                cardColor = Colors.white;
                iconColor = Colors.green;
                iconData = Icons.check_circle;

                String handledText = "Handled";
                Color chipColor = Colors.green.shade100;

                if (handledBy == 'patient') {
                  handledText = "THE PATIENT SENT OK";
                  chipColor = Colors.greenAccent.shade100;
                } else if (handledBy == 'caregiver') {
                  handledText = "HANDLED BY CAREGIVER";
                  chipColor = Colors.grey.shade300;
                }

                statusWidget = Chip(
                  label: Text(handledText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  backgroundColor: chipColor,
                );
              }

              return Card(
                color: cardColor,
                elevation: handled ? 1 : 4,
                shape: RoundedRectangleBorder(
                  side: !handled
                      ? BorderSide(color: iconColor, width: 2)
                      : BorderSide.none,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(iconData, color: iconColor, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  typeDisplay,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: !handled ? iconColor : Colors.black87
                                  ),
                                ),
                                Text(
                                  timestamp != null ? "$timeStr  (${timestamp.day}/${timestamp.month})" : "",
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (rawType == 'long_immobility' && d['payload'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "Duration: ${(d['payload']['immobilityMs'] / 1000).toStringAsFixed(1)} seconds",
                            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: statusWidget,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}