import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/backend_api.dart';
import '../services/push_service.dart';

class PatientHome extends StatefulWidget {
  final String patientId;
  const PatientHome({super.key, required this.patientId});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  late final BackendApi api;
  late final PushService push;

  bool busy = false;
  String msg = '';

  bool _pendingStart = false;
  bool _pendingStop = false;

  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    api = BackendApi();
    push = PushService(api);
    push.initAndRegister(patientId: widget.patientId, role: 'patient');

    _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!busy) {
        if (_pendingStart) _attemptStartSession();
        if (_pendingStop) _attemptStopSession();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _attemptStartSession() async {
    setState(() => busy = true);
    try {
      await api.startSession(patientId: widget.patientId);
      if (mounted) {
        setState(() {
          msg = '✅ Session Started';
          _pendingStart = false;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingStart = true;
          msg = '⏳ No Internet. Waiting to START...';
          busy = false;
        });
      }
    }
  }

  Future<void> _attemptStopSession() async {
    setState(() => busy = true);
    try {
      bool hasInternet = false;
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          hasInternet = true;
        }
      } catch (_) {
        hasInternet = false;
      }

      if (hasInternet) {
        setState(() => msg = 'Finalizing Session...');
        await api.stopSession(patientId: widget.patientId);

        if (mounted) {
          setState(() {
            msg = '✅ Session Saved Successfully!';
            _pendingStop = false;
            busy = false;
          });
        }
      } else {
        for (int i = 15; i > 0; i--) {
          if (!mounted) return;
          try {
            await api.client.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 1));
            break;
          } catch (e) {
            setState(() => msg = 'No Internet. Waiting... ($i)');
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        setState(() => msg = 'Finalizing Session...');
        await api.stopSession(patientId: widget.patientId);

        if (mounted) {
          setState(() {
            msg = '✅ Session Saved (Offline Mode)!';
            _pendingStop = false;
            busy = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingStop = true;
          msg = '⏳ Offline. Waiting for internet to SAVE...';
          busy = false;
        });
      }
    }
  }

  Future<void> _do(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      msg = 'Sending...';
    });
    try {
      await action();
      if (mounted) setState(() => msg = '✅ Done');
    } catch (e) {
      if (mounted) {
        setState(() => msg = '⚠️ Network Error. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionRef = FirebaseFirestore.instance
        .doc('patients/${widget.patientId}/tracking/currentSession');

    return Scaffold(
      appBar: AppBar(title: Text('Patient (${widget.patientId})')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: sessionRef.snapshots(),
        builder: (context, snapshot) {
          bool okPending = false;
          bool sessionActive = false;

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            okPending = (data['okPending'] ?? false) == true;
            sessionActive = (data['active'] ?? false) == true;
          }

          bool canStart = !sessionActive && !_pendingStart && !_pendingStop;
          bool canStop = (sessionActive || _pendingStart) && !_pendingStop;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      icon: _pendingStart
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow),
                      label: Text(
                          _pendingStart ? 'SYNCING START...' : 'SESSION START',
                          style: const TextStyle(fontSize: 18)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingStart ? Colors.orange.shade100 : Colors.green.shade100,
                        foregroundColor: Colors.green.shade900,
                      ),
                      onPressed: (busy || !canStart)
                          ? null
                          : () {
                        setState(() {
                          _pendingStart = true;
                          msg = "Starting...";
                        });
                        _attemptStartSession();
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      icon: _pendingStop
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.stop),
                      label: Text(
                          _pendingStop ? 'WAITING TO SAVE...' : 'SESSION STOP',
                          style: const TextStyle(fontSize: 18)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingStop ? Colors.orange.shade100 : Colors.red.shade100,
                        foregroundColor: Colors.red.shade900,
                      ),
                      onPressed: (busy || !canStop)
                          ? null
                          : () {
                        setState(() {
                          _pendingStop = true;
                          msg = "Pending Stop...";
                        });
                        _attemptStopSession();
                      },
                    ),
                  ),

                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 40),

                  if (okPending) ...[
                    const Text(
                      "Alert Active! Are you OK?",
                      style: TextStyle(fontSize: 22, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 80,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: busy
                            ? null
                            : () => _do(() => api.imOk(patientId: widget.patientId)),
                        child: const Text('I’M OK', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.security, size: 60, color: Colors.blueGrey),
                    const SizedBox(height: 10),
                    const Text("Status: Normal", style: TextStyle(color: Colors.grey, fontSize: 18)),
                  ],

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                        msg,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: msg.contains('✅') ? Colors.green
                                : (msg.contains('Wait') || msg.contains('Syncing') ? Colors.orange[800]
                                : Colors.red)
                        )
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