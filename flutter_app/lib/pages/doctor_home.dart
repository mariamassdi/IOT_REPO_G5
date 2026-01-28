import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/backend_api.dart';
import '../services/push_service.dart';

class DoctorHome extends StatefulWidget {
  final String patientId;
  const DoctorHome({super.key, required this.patientId});

  @override
  State<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends State<DoctorHome> {
  late final BackendApi api;
  late final PushService push;

  @override
  void initState() {
    super.initState();
    api = BackendApi();
    push = PushService(api);
    push.initAndRegister(patientId: widget.patientId, role: 'doctor');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Doctor Menu (${widget.patientId})')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MenuButton(
              icon: Icons.monitor_heart,
              title: "CURRENT",
              color: Colors.blue.shade100,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DoctorCurrentSession(patientId: widget.patientId)),
              ),
            ),
            const SizedBox(height: 24),
            _MenuButton(
              icon: Icons.calendar_month,
              title: "DAILY SESSIONS",
              color: Colors.orange.shade100,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DoctorDailySessions(patientId: widget.patientId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({required this.icon, required this.title, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.black87),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class SessionFallsHistory extends StatelessWidget {
  final String patientId;
  final String sessionId;

  const SessionFallsHistory({super.key, required this.patientId, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Session Falls History")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('patients/$patientId/alerts')
            .where('sessionId', isEqualTo: sessionId)
            .where('type', isEqualTo: 'fall_alert')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                  SizedBox(height: 10),
                  Text("No falls recorded in this session.", style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (c, i) => const Divider(),
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final ts = (d['timestamp'] as Timestamp?)?.toDate();
              final timeStr = ts != null
                  ? "${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}"
                  : "Unknown Time";
              final handled = (d['handled'] ?? false) == true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
                ),
                title: Text("Fall Detected at $timeStr", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Status: ${handled ? 'Handled' : 'Pending'}"),
              );
            },
          );
        },
      ),
    );
  }
}

class DoctorCurrentSession extends StatefulWidget {
  final String patientId;
  const DoctorCurrentSession({super.key, required this.patientId});

  @override
  State<DoctorCurrentSession> createState() => _DoctorCurrentSessionState();
}

class _DoctorCurrentSessionState extends State<DoctorCurrentSession> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curRef = FirebaseFirestore.instance.doc('patients/${widget.patientId}/tracking/currentSession');

    return Scaffold(
      appBar: AppBar(title: const Text("Current Session Status")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: curRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final rawData = snap.data!.data();
          final d = (rawData is Map) ? rawData : {};

          final active = (d['active'] ?? false) == true;
          final sessionId = d['sessionId']?.toString() ?? "";

          if (!active) {
            return const Center(
              child: Text("NO CURRENT SESSION", style: TextStyle(fontSize: 24, color: Colors.grey)),
            );
          }

          final lastAtTimestamp = d['lastAt'] as Timestamp?;
          bool isDisconnected = true;
          String statusText = "WAITING FOR SIGNAL...";
          Color statusColor = Colors.orange;

          if (lastAtTimestamp != null) {
            final lastDate = lastAtTimestamp.toDate();
            final diff = DateTime.now().difference(lastDate).inSeconds;
            if (diff > 25) {
              isDisconnected = true;
              statusText = "⚠️ PATIENT DISCONNECTED";
              statusColor = Colors.red;
            } else {
              isDisconnected = false;
              statusText = "🟢 ONLINE";
              statusColor = Colors.green;
            }
          }

          final live = (d['live'] is Map) ? d['live'] as Map : {};
          final last = (d['last'] is Map) ? d['last'] as Map : {};

          final steps = live['steps'] ?? 0;
          final stairsCount = live['stairsCount'] ?? 0;
          final fallsCount = live['fallsCount'] ?? 0;
          final isFallActive = (last['isFallActive'] ?? false) == true;
          final immobility = (last['type'] == 'long_immobility');

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      border: Border.all(color: statusColor, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isDisconnected ? Icons.wifi_off : Icons.wifi, color: statusColor),
                        const SizedBox(width: 10),
                        Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 18)
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Live Metrics", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const Divider(),
                          const SizedBox(height: 10),

                          _InfoRow(label: "STEPS", value: "$steps"),
                          _InfoRow(label: "STAIRS", value: "$stairsCount"),
                          _InfoRow(
                            label: "FALLS",
                            value: "$fallsCount",
                            isHighlight: fallsCount > 0,
                            onTap: (fallsCount > 0 && sessionId.isNotEmpty)
                                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionFallsHistory(patientId: widget.patientId, sessionId: sessionId)))
                                : null,
                          ),
                          _InfoRow(label: "IMMOBILITY", value: immobility ? "YES" : "NO", isHighlight: immobility),

                          const SizedBox(height: 20),
                          if (isFallActive)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8)
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning, color: Colors.red, size: 30),
                                    SizedBox(width: 10),
                                    Text("FALL DETECTED NOW", style: TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;
  final VoidCallback? onTap;

  const _InfoRow({required this.label, required this.value, this.isHighlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, color: Colors.black54)),
            Row(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isHighlight ? Colors.red : Colors.black,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DoctorDailySessions extends StatefulWidget {
  final String patientId;
  const DoctorDailySessions({super.key, required this.patientId});

  @override
  State<DoctorDailySessions> createState() => _DoctorDailySessionsState();
}

class _DoctorDailySessionsState extends State<DoctorDailySessions> {
  DateTime _selectedDate = DateTime.now();
  bool _isNavigating = false;

  String get _dateKey {
    return "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickDate() async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (newDate != null) {
      setState(() => _selectedDate = newDate);
    }
  }

  Future<void> _safeNavigateToSession(Map<String, dynamic> sessionData) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoctorSessionDetails(
            patientId: widget.patientId,
            sessionData: sessionData,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryRef = FirebaseFirestore.instance.doc('patients/${widget.patientId}/daily/$_dateKey');
    final sessionsQuery = FirebaseFirestore.instance
        .collection('patients/${widget.patientId}/sessions')
        .where('dateKey', isEqualTo: _dateKey)
        .orderBy('startTime', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text("Daily Sessions")),
      body: Column(
        children: [
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Selected: $_dateKey", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                FilledButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text("Change Date"),
                )
              ],
            ),
          ),

          StreamBuilder<DocumentSnapshot>(
            stream: summaryRef.snapshots(),
            builder: (context, snap) {
              if (snap.hasData && snap.data!.exists) {
                final d = snap.data!.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.indigo.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text("Daily Summary", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatCol(label: "Steps", val: "${d['totalSteps'] ?? 0}"),
                            _StatCol(label: "Stairs", val: "${d['stairsCount'] ?? 0}"),
                            _StatCol(label: "Falls", val: "${d['fallsCount'] ?? 0}", isBad: (d['fallsCount']??0) > 0),
                            _StatCol(label: "Alerts", val: "${d['alertsCount'] ?? 0}", isBad: (d['alertsCount']??0) > 0),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: sessionsQuery.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.red)));
                }
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("NO SESSIONS AT THIS DAY", style: TextStyle(fontSize: 18, color: Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final s = docs[i].data() as Map<String, dynamic>;
                    final startTime = (s['startTime'] as Timestamp?)?.toDate();
                    final endTime = (s['endTime'] as Timestamp?)?.toDate();
                    final startStr = startTime != null
                        ? "${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}"
                        : "??:??";
                    final endStr = endTime != null
                        ? "${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}"
                        : "Active";

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.timer_outlined, color: Colors.blue),
                        title: Text("Session Time: $startStr - $endStr"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _safeNavigateToSession(s);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DoctorSessionDetails extends StatelessWidget {
  final String patientId;
  final Map<String, dynamic> sessionData;

  const DoctorSessionDetails({super.key, required this.patientId, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    final startTime = (sessionData['startTime'] as Timestamp?)?.toDate();
    final endTime = (sessionData['endTime'] as Timestamp?)?.toDate();
    final sessionId = sessionData['sessionId'] as String? ?? "";

    int durationMinutes = 0;
    if (startTime != null && endTime != null) {
      durationMinutes = endTime.difference(startTime).inMinutes;
    }
    if (durationMinutes < 1) durationMinutes = 1;

    final totalSteps = (sessionData['totalSteps'] as num? ?? 0).toInt();
    final totalStairs = (sessionData['stairsCount'] as num? ?? 0).toInt();
    final totalFalls = (sessionData['fallsCount'] as num? ?? 0).toInt();
    final totalAlerts = (sessionData['alertsCount'] as num? ?? 0).toInt();

    final stepsPerMinute = (totalSteps / durationMinutes).toStringAsFixed(1);
    final stairsPerMinute = (totalStairs / durationMinutes).toStringAsFixed(1);

    final startStr = startTime != null
        ? "${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}"
        : "--:--";
    final endStr = endTime != null
        ? "${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}"
        : "Active";

    return Scaffold(
      appBar: AppBar(title: const Text("Session Details")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.access_time, size: 32, color: Colors.blue),
                title: Text("Time: $startStr - $endStr", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Duration: ~$durationMinutes min"),
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.3,
              children: [
                _DetailCard(
                  title: "Steps Pace",
                  value: stepsPerMinute,
                  unit: "steps/min",
                  icon: Icons.speed,
                  color: Colors.blue,
                ),
                _DetailCard(
                  title: "Stairs Pace",
                  value: stairsPerMinute,
                  unit: "stairs/min",
                  icon: Icons.show_chart,
                  color: Colors.orange,
                ),
                _DetailCard(
                  title: "Total Steps",
                  value: "$totalSteps",
                  unit: "count",
                  icon: Icons.directions_walk,
                  color: Colors.green,
                ),
                _DetailCard(
                  title: "Total Stairs",
                  value: "$totalStairs",
                  unit: "count",
                  icon: Icons.stairs,
                  color: Colors.purple,
                ),
                _DetailCard(
                  title: "Falls",
                  value: "$totalFalls",
                  unit: "events",
                  icon: Icons.warning,
                  color: Colors.red,
                  isBad: totalFalls > 0,
                  onTap: (totalFalls > 0 && sessionId.isNotEmpty)
                      ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionFallsHistory(patientId: patientId, sessionId: sessionId)))
                      : null,
                ),
                _DetailCard(
                  title: "All Alerts",
                  value: "$totalAlerts",
                  unit: "events",
                  icon: Icons.notifications_active,
                  color: Colors.deepOrange,
                  isBad: totalAlerts > 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final bool isBad;
  final VoidCallback? onTap;

  const _DetailCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.isBad = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBad ? const BorderSide(color: Colors.red, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 4),

              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                ),
              ),

              Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 2),

              Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)
              ),
              if (onTap != null)
                const Icon(Icons.touch_app, size: 16, color: Colors.grey)
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String val;
  final bool isBad;
  const _StatCol({required this.label, required this.val, this.isBad = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isBad ? Colors.red : Colors.indigo)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}