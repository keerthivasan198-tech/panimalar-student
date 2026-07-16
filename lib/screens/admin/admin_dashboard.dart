import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/driver_entry.dart';
import '../../models/route_entry.dart';
import '../../models/log_entry.dart';
import '../../models/alert_entry.dart';
import '../../models/upload_entry.dart';
import '../../config/routes_config.dart';
import '../../config/lang_config.dart';
import '../../widgets/custom_charts.dart';

class AdminDashboard extends StatefulWidget {
  final VoidCallback onSwitchRole;
  final String currentLang;
  const AdminDashboard({super.key, required this.onSwitchRole, required this.currentLang});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String t(String key) {
    return appLang[widget.currentLang]?[key] ?? appLang['en']?[key] ?? key;
  }

  // Navigation & tabs
  int _currentTab = 0;

  // Firebase pickup requests queue
  List<Map<String, dynamic>> _requests = [];
  bool _isLoadingRequests = true;
  StreamSubscription? _requestsSub;

  // Persistence State Lists
  // Persistence State Lists
  List<DriverEntry> _drivers = [];
  List<RouteEntry> _routes = [];
  List<LogEntry> _logs = [];
  List<AlertEntry> _alerts = [];
  List<UploadEntry> _uploads = [];

  // Safety Warnings
  Map<String, dynamic> _safetyAlerts = {};
  StreamSubscription? _safetyAlertsSub;

  // Segmented Intercom State
  int _intercomViewMode = 0; // 0 = Drivers, 1 = Students
  String? _selectedChatId; // e.g. driver_B101 or student_STD123
  Map<String, dynamic> _adminStudentsList = {};
  StreamSubscription? _adminStudentsSub;

  // Voice recording & playback states
  bool _isRecordingVoice = false;
  int _recordingDurationSecs = 0;
  Timer? _recordingTimer;
  List<double> _recordingWaveforms = [];

  // Admin STT Intercom State
  Map<String, List<Map<String, dynamic>>> _adminIntercomMessages = {};
  StreamSubscription? _adminIntercomSub;
  final TextEditingController _adminChatInputCtrl = TextEditingController();
  
  // WhatsApp Style Intercom UI State
  String? _selectedIntercomBus;
  final TextEditingController _intercomSearchCtrl = TextEditingController();
  String _intercomSearchQuery = "";
  int _intercomSegment = 0; // 0 = Drivers, 1 = Students
  List<Map<String, dynamic>> _studentsList = [];
  StreamSubscription? _studentsSub;
  bool _isAdminRecording = false;
  int _adminRecordingDuration = 0;
  Timer? _adminRecordingTimer;
  String? _playingMsgId;
  double _playbackProgress = 0.0;
  Timer? _playbackTimer;
  final FlutterTts _flutterTts = FlutterTts();

  // Live Bus Locations
  Map<String, Map<String, dynamic>> _liveBuses = {};
  StreamSubscription? _liveLocationsSub;
  Map<String, Map<String, dynamic>> _firebaseBreakdowns = {};
  StreamSubscription? _breakdownListenerSub;
  Map<String, Map<String, dynamic>> _driversAlerts = {};
  StreamSubscription? _driversAlertsSub;

  // Map Controllers
  final MapController _mapController = MapController();

  // Registry sub-toggle
  int _registryViewMode = 0; // 0 = Drivers, 1 = Routes
  final TextEditingController _adminRouteSearchCtrl = TextEditingController();
  String _adminRouteSearchQuery = "";

  // Live map search
  final TextEditingController _liveMapSearchCtrl = TextEditingController();
  String _liveMapSearchQuery = "";
  RouteEntry? _selectedLiveRoute;

  // Stop Capture State
  bool _allowDriversToAddStops = false;
  StreamSubscription? _adminSettingsSub;
  List<Map<String, dynamic>> _newStops = [];
  StreamSubscription? _newStopsSub;

  // Constants & Static Caches
  final LatLng _campusCoord = const LatLng(13.0489049, 80.0754642);

  @override
  void initState() {
    super.initState();
    _loadPersistedData();
    _listenForRequests();
    _listenForAdminIntercomMessages();
    _listenForStudents();
    _listenForLiveLocations();
    _listenForDriversAlerts();
    _listenForAdminSettings();
    _listenForNewStops();
    _listenForSafetyAlerts();
    _listenForAdminStudents();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _liveLocationsSub?.cancel();
    _driversAlertsSub?.cancel();
    _adminIntercomSub?.cancel();
    _studentsSub?.cancel();
    _adminSettingsSub?.cancel();
    _newStopsSub?.cancel();
    _adminRecordingTimer?.cancel();
    _playbackTimer?.cancel();
    _adminChatInputCtrl.dispose();
    super.dispose();
  }

  // ─── PERSISTENCE DATA LOAD/SAVE ─────────────────────────────────
  void _loadPersistedData() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        // Drivers
        final driversSnap = await FirebaseDatabase.instance.ref('drivers').get();
        if (driversSnap.exists && driversSnap.value != null) {
          final data = driversSnap.value;
          List driversList = [];
          if (data is List) {
            driversList = data;
          } else if (data is Map) {
            driversList = data.values.toList();
          }
          _drivers = driversList.map((e) {
            return DriverEntry.fromJson(Map<String, dynamic>.from(e as Map));
          }).toList();
        } else {
          _drivers = _getDefaultDrivers();
          await FirebaseDatabase.instance.ref('drivers').set(_drivers.map((e) => e.toJson()).toList());
        }

        // Routes
        final routesSnap = await FirebaseDatabase.instance.ref('routes').get();
        if (routesSnap.exists && routesSnap.value != null) {
          final data = routesSnap.value;
          List routesList = [];
          if (data is List) {
            routesList = data;
          } else if (data is Map) {
            routesList = data.values.toList();
          }
          _routes = routesList.map((e) {
            return RouteEntry.fromJson(Map<String, dynamic>.from(e as Map));
          }).toList();
        } else {
          _routes = _getDefaultRoutes();
          await FirebaseDatabase.instance.ref('routes').set(_routes.map((e) => e.toJson()).toList());
        }

        // Logs
        final logsSnap = await FirebaseDatabase.instance.ref('logs').get();
        if (logsSnap.exists && logsSnap.value != null) {
          final data = logsSnap.value;
          List logsList = [];
          if (data is List) {
            logsList = data;
          } else if (data is Map) {
            logsList = data.values.toList();
          }
          _logs = logsList.map((e) {
            return LogEntry.fromJson(Map<String, dynamic>.from(e as Map));
          }).toList();
        } else {
          _logs = _getDefaultLogs();
          await FirebaseDatabase.instance.ref('logs').set(_logs.map((e) => e.toJson()).toList());
        }

        // Alerts
        final alertsSnap = await FirebaseDatabase.instance.ref('alerts').get();
        if (alertsSnap.exists && alertsSnap.value != null) {
          final data = alertsSnap.value;
          List alertsList = [];
          if (data is List) {
            alertsList = data;
          } else if (data is Map) {
            alertsList = data.values.toList();
          }
          _alerts = alertsList.map((e) {
            return AlertEntry.fromJson(Map<String, dynamic>.from(e as Map));
          }).toList();
        } else {
          _alerts = _getDefaultAlerts();
          await FirebaseDatabase.instance.ref('alerts').set(_alerts.map((e) => e.toJson()).toList());
        }

        // Uploads
        final uploadsSnap = await FirebaseDatabase.instance.ref('uploads').get();
        if (uploadsSnap.exists && uploadsSnap.value != null) {
          final data = uploadsSnap.value;
          List uploadsList = [];
          if (data is List) {
            uploadsList = data;
          } else if (data is Map) {
            uploadsList = data.values.toList();
          }
          _uploads = uploadsList.map((e) {
            return UploadEntry.fromJson(Map<String, dynamic>.from(e as Map));
          }).toList();
        } else {
          _uploads = [];
          await FirebaseDatabase.instance.ref('uploads').set(_uploads.map((e) => e.toJson()).toList());
        }

        if (mounted) setState(() {});
      } catch (e) {
        debugPrint("Error loading data from Firebase: $e");
      }
    }
  }

  void _saveDrivers() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseDatabase.instance.ref('drivers').set(
          _drivers.map((e) => e.toJson()).toList()
        );
      } catch (e) {
        debugPrint("Error syncing drivers to Firebase: $e");
      }
    }
  }

  void _saveRoutes() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseDatabase.instance.ref('routes').set(
          _routes.map((e) => e.toJson()).toList()
        );
      } catch (e) {
        debugPrint("Error syncing routes to Firebase: $e");
      }
    }
  }

  void _saveLogs() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseDatabase.instance.ref('logs').set(
          _logs.map((e) => e.toJson()).toList()
        );
      } catch (e) {
        debugPrint("Error syncing logs to Firebase: $e");
      }
    }
  }

  void _saveAlerts() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseDatabase.instance.ref('alerts').set(
          _alerts.map((e) => e.toJson()).toList()
        );
      } catch (e) {
        debugPrint("Error syncing alerts to Firebase: $e");
      }
    }
  }

  void _saveUploads() async {
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseDatabase.instance.ref('uploads').set(
          _uploads.map((e) => e.toJson()).toList()
        );
      } catch (e) {
        debugPrint("Error syncing uploads to Firebase: $e");
      }
    }
  }

  List<DriverEntry> _getDefaultDrivers() {
    return [];
  }

  List<RouteEntry> _getDefaultRoutes() {
    int id = 1;
    final List<RouteEntry> routes = [];
    for (var key in routeLabelsConfig.keys) {
      routes.add(RouteEntry(
        id: (id++).toDouble(),
        key: key,
        name: routeLabelsConfig[key]!,
        stops: routeStopsConfig[key] ?? [],
        color: routeColorsConfig[key] ?? '#2563EB',
      ));
    }
    return routes;
  }

  List<LogEntry> _getDefaultLogs() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final list = _getDefaultDrivers();
    return List.generate(list.length, (i) {
      final d = list[i];
      return LogEntry(
        id: (i + 1).toDouble(),
        bus: d.bus,
        driver: d.driver,
        route: routeLabelsConfig[d.route] ?? d.route,
        date: today,
        arrived: i < 5 ? "0${7 + i}:${(i * 5) < 10 ? '0' : ''}${i * 5}" : null,
        departed: i < 3 ? "1${6 + i}:${(i * 5) < 10 ? '0' : ''}${i * 5}" : null,
        status: i < 5 ? (i == 2 ? 'delayed' : 'arrived') : 'on-route',
      );
    });
  }

  List<AlertEntry> _getDefaultAlerts() {
    return [];
  }

  // ─── FIREBASE LISTENER (STUDENT LETTERS) ─────────────────────────
  void _listenForRequests() {
    if (Firebase.apps.isEmpty) return;
    try {
      _requestsSub = FirebaseDatabase.instance.ref('pickup_requests').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> temp = [];
        if (data != null) {
          data.forEach((key, val) {
            if (val is Map) {
              temp.add({
                'studentId': key,
                'studentName': val['studentName'] ?? "Unknown Student",
                'studentYear': val['studentYear'] ?? "N/A",
                'studentDept': val['studentDept'] ?? "N/A",
                'documentName': val['documentName'] ?? "No Document",
                'documentUrl': val['documentUrl'] ?? "",
                'status': val['status'] ?? "pending",
                'savedStop': val['savedStop'] ?? "Not Selected",
                'timestamp': val['timestamp'] ?? 0,
              });
            }
          });
          temp.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
        }
        if (mounted) {
          setState(() {
            _requests = temp;
            _isLoadingRequests = false;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to admin requests: $e");
      if (mounted) {
        setState(() {
          _isLoadingRequests = false;
        });
      }
    }
  }

  void _updateRequestStatus(String studentId, String status) async {
    try {
      await FirebaseDatabase.instance.ref('pickup_requests/$studentId/status').set(status);
      _showAppSnackBar("Request status set to $status");
    } catch (e) {
      _showAppSnackBar("Failed to update status: $e");
    }
  }

  // ─── FIREBASE INTERCOM MESSAGES ──────────────────────────────────
  void _listenForAdminIntercomMessages() {
    if (Firebase.apps.isEmpty) return;
    try {
      _adminIntercomSub = FirebaseDatabase.instance.ref('voice_messages').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final Map<String, List<Map<String, dynamic>>> temp = {};
        if (data != null) {
          data.forEach((channelId, msgs) {
            if (msgs is Map) {
              final List<Map<String, dynamic>> channelMsgs = [];
              msgs.forEach((k, v) {
                if (v is Map) {
                  channelMsgs.add({
                    'id': k.toString(),
                    'sender': v['sender'] ?? 'unknown',
                    'senderName': v['senderName'] ?? '',
                    'timestamp': v['timestamp'] ?? 0,
                    'msg': v['msg'] ?? '',
                    'isVoice': v['isVoice'] ?? false,
                    'voiceDuration': v['voiceDuration'] ?? 0,
                    'transcript': v['transcript'] ?? '',
                  });
                }
              });
              channelMsgs.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
              temp[channelId.toString()] = channelMsgs;
            }
          });
        }
        if (mounted) {
          setState(() {
            _adminIntercomMessages = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error loading admin intercom: $e");
    }
  }

  void _listenForStudents() {
    _studentsSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _studentsSub = FirebaseDatabase.instance.ref('students').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> temp = [];
        if (data != null) {
          data.forEach((studentId, profileVal) {
            if (profileVal is Map) {
              temp.add({
                'id': studentId.toString(),
                'name': profileVal['name'] ?? 'Student Name',
                'year': profileVal['year'] ?? '',
                'department': profileVal['department'] ?? '',
                'selectedRoute': profileVal['selectedRoute'] ?? '',
                'savedStop': profileVal['savedStop'] ?? '',
              });
            }
          });
        }
        if (mounted) {
          setState(() {
            _studentsList = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to students list: $e");
    }
  }

  void _sendAdminTextMessage(String channelId, String text) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseDatabase.instance.ref('voice_messages/$channelId/$msgId').set({
        'sender': 'admin',
        'senderName': 'College Admin',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'msg': text,
      });
      _adminChatInputCtrl.clear();
    } catch (e) {
      _showAppSnackBar("Error sending intercom message: $e");
    }
  }

  void _startAdminRecordingVoice() {
    setState(() {
      _isAdminRecording = true;
      _adminRecordingDuration = 0;
    });
    _adminRecordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _adminRecordingDuration++;
        });
      }
    });
  }

  void _stopAndSendAdminRecordingVoice(String channelId) async {
    _adminRecordingTimer?.cancel();
    if (!_isAdminRecording) return;
    final duration = _adminRecordingDuration == 0 ? 3 : _adminRecordingDuration;
    setState(() {
      _isAdminRecording = false;
    });

    if (Firebase.apps.isEmpty) return;

    final transcripts = [
      "Admin here, route updates are approved.",
      "Copy that, please proceed with standard scheduling.",
      "Alert acknowledged, dispatching alternative transit.",
      "Acknowledged, please report back on arrival.",
      "Understood, notify when passengers are boarded.",
    ];
    final randomTranscript = transcripts.isNotEmpty ? transcripts[Random().nextInt(transcripts.length)] : '';

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await FirebaseDatabase.instance.ref('voice_messages/$channelId/$msgId').set({
        'sender': 'admin',
        'senderName': 'College Admin',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'msg': '[Voice Message - 0:${duration.toString().padLeft(2, '0')}] "$randomTranscript"',
        'isVoice': true,
        'voiceDuration': duration,
        'transcript': randomTranscript,
      });
    } catch (e) {
      debugPrint("Error sending admin voice message: $e");
    }
  }

  void _cancelAdminRecordingVoice() {
    _adminRecordingTimer?.cancel();
    setState(() {
      _isAdminRecording = false;
      _adminRecordingDuration = 0;
    });
    _showAppSnackBar("Recording cancelled.");
  }

  void _playAdminVoiceMessage(String msgId, String text, int durationSecs) {
    if (_playingMsgId == msgId) {
      _playbackTimer?.cancel();
      _flutterTts.stop();
      setState(() {
        _playingMsgId = null;
      });
      return;
    }
    _playbackTimer?.cancel();
    _flutterTts.stop();

    String speakText = text;
    if (text.startsWith('[Voice Message')) {
      final index = text.indexOf(']');
      if (index != -1 && index + 1 < text.length) {
        speakText = text.substring(index + 1).replaceAll('"', '').trim();
      }
    }
    _flutterTts.speak(speakText);

    setState(() {
      _playingMsgId = msgId;
      _playbackProgress = 0.0;
    });
    
    final int totalSteps = durationSecs * 10;
    int currentStep = 0;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      currentStep++;
      if (currentStep >= totalSteps) {
        timer.cancel();
        _flutterTts.stop();
        if (mounted) {
          setState(() {
            _playingMsgId = null;
            _playbackProgress = 1.0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _playbackProgress = currentStep / totalSteps;
          });
        }
      }
    });
  }

  // ─── FIREBASE LIVE LOCATIONS ──────────────────────────────────────
  void _listenForLiveLocations() {
    if (Firebase.apps.isEmpty) return;
    try {
      _liveLocationsSub = FirebaseDatabase.instance.ref('liveLocations').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final Map<String, Map<String, dynamic>> temp = {};
        if (data != null) {
          data.forEach((k, v) {
            if (v is Map) {
              temp[k.toString()] = Map<String, dynamic>.from(v);
            }
          });
        }
        if (mounted) {
          setState(() {
            _liveBuses = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to live locations: $e");
    }
  }

  void _listenForDriversAlerts() {
    _driversAlertsSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _driversAlertsSub = FirebaseDatabase.instance.ref('drivers_alerts').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final Map<String, Map<String, dynamic>> temp = {};
        if (data != null) {
          data.forEach((busId, alertsMap) {
            if (alertsMap is Map) {
              final Map<String, dynamic> alerts = {};
              alertsMap.forEach((alertType, alertVal) {
                if (alertVal is Map) {
                  alerts[alertType.toString()] = Map<String, dynamic>.from(alertVal);
                }
              });
              temp[busId.toString()] = alerts;
            }
          });
        }
        if (mounted) {
          setState(() {
            _driversAlerts = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to driver alerts: $e");
    }
  }

  // ─── DRIVER LOCATIONS SETTINGS & SUGGESTIONS ──────────────────────
  void _listenForAdminSettings() {
    if (Firebase.apps.isEmpty) return;
    try {
      _adminSettingsSub = FirebaseDatabase.instance.ref('adminSettings/allowDriversToAddStops').onValue.listen((event) {
        final val = event.snapshot.value;
        if (mounted) {
          setState(() {
            _allowDriversToAddStops = val == true;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to admin settings: $e");
    }
  }

  void _listenForNewStops() {
    if (Firebase.apps.isEmpty) return;
    try {
      _newStopsSub = FirebaseDatabase.instance.ref('new_stops').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> temp = [];
        if (data != null) {
          data.forEach((k, v) {
            if (v is Map) {
              temp.add(Map<String, dynamic>.from(v));
            }
          });
          temp.sort((a, b) => (b['timestamp'] as int? ?? 0).compareTo(a['timestamp'] as int? ?? 0));
          if (mounted) {
            setState(() {
              _newStops = temp;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _newStops = [];
            });
          }
        }
      });
    } catch (e) {
      debugPrint("Error listening to new stops: $e");
    }
  }

  void _listenForSafetyAlerts() {
    _safetyAlertsSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _safetyAlertsSub = FirebaseDatabase.instance.ref('safety_alerts').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final Map<String, dynamic> temp = {};
        if (data != null) {
          data.forEach((busId, alertsMap) {
            if (alertsMap is Map) {
              final Map<String, dynamic> alerts = {};
              alertsMap.forEach((alertType, alertVal) {
                if (alertVal is Map) {
                  alerts[alertType.toString()] = Map<String, dynamic>.from(alertVal);
                }
              });
              temp[busId.toString()] = alerts;
            }
          });
        }
        if (mounted) {
          setState(() {
            _safetyAlerts = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to safety alerts: $e");
    }
  }

  void _listenForAdminStudents() {
    _adminStudentsSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _adminStudentsSub = FirebaseDatabase.instance.ref('students').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final Map<String, dynamic> temp = {};
        if (data != null) {
          data.forEach((studentId, profileVal) {
            if (profileVal is Map) {
              temp[studentId.toString()] = Map<String, dynamic>.from(profileVal);
            }
          });
        }
        if (mounted) {
          setState(() {
            _adminStudentsList = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to admin students: $e");
    }
  }


  void _showAppSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF2563EB),
      ),
    );
  }

  // ─── ADMIN DIALOGS & FORMS ───────────────────────────────────────
  void _openDriverAddBottomSheet() {
    final busCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selRoute = _routes.isNotEmpty ? _routes[0].key : 'route_15';
    String selType = 'combined';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Add Driver & Bus Entry", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                TextField(controller: busCtrl, decoration: const InputDecoration(labelText: "Bus Number (e.g. B110)")),
                const SizedBox(height: 8),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Driver Name")),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Contact Phone")),
                const SizedBox(height: 8),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Driver Portal Password")),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selRoute,
                  decoration: const InputDecoration(labelText: "Assign Route"),
                  items: _routes.map((r) => DropdownMenuItem(value: r.key, child: Text(r.name))).toList(),
                  onChanged: (val) => setSheetState(() => selRoute = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selType,
                  decoration: const InputDecoration(labelText: "Bus Gender Category"),
                  items: const [
                    DropdownMenuItem(value: 'boys', child: Text("Boys Bus")),
                    DropdownMenuItem(value: 'girls', child: Text("Girls Bus")),
                    DropdownMenuItem(value: 'combined', child: Text("Combined")),
                  ],
                  onChanged: (val) => setSheetState(() => selType = val!),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                  onPressed: () {
                    final b = busCtrl.text.trim().toUpperCase();
                    final n = nameCtrl.text.trim();
                    final p = phoneCtrl.text.trim();
                    final pass = passCtrl.text.trim();
                    if (b.isEmpty || n.isEmpty || p.isEmpty || pass.isEmpty) {
                      _showAppSnackBar("Please fill all fields, including password.");
                      return;
                    }
                    setState(() {
                      _drivers.add(DriverEntry(
                        id: DateTime.now().millisecondsSinceEpoch.toDouble(),
                        bus: b,
                        driver: n,
                        contact: p,
                        route: selRoute,
                        type: selType,
                        password: pass,
                      ));
                      _saveDrivers();
                    });
                    Navigator.pop(ctx);
                    _showAppSnackBar("Driver registry created & synced to Firebase.");
                  },
                  child: const Text("Save Registry Entry", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  void _openDriverEditBottomSheet(DriverEntry entry) {
    final busCtrl = TextEditingController(text: entry.bus);
    final nameCtrl = TextEditingController(text: entry.driver);
    final phoneCtrl = TextEditingController(text: entry.contact);
    final passCtrl = TextEditingController(text: entry.password);
    String selRoute = entry.route;
    String selType = entry.type;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Edit Driver & Bus Entry", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                const SizedBox(height: 16),
                TextField(controller: busCtrl, decoration: const InputDecoration(labelText: "Bus Number")),
                const SizedBox(height: 8),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Driver Name")),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Contact Phone")),
                const SizedBox(height: 8),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Driver Portal Password")),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selRoute,
                  decoration: const InputDecoration(labelText: "Assign Route"),
                  items: _routes.map((r) => DropdownMenuItem(value: r.key, child: Text(r.name))).toList(),
                  onChanged: (val) => setSheetState(() => selRoute = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selType,
                  decoration: const InputDecoration(labelText: "Bus Gender Category"),
                  items: const [
                    DropdownMenuItem(value: 'boys', child: Text("Boys Bus")),
                    DropdownMenuItem(value: 'girls', child: Text("Girls Bus")),
                    DropdownMenuItem(value: 'combined', child: Text("Combined")),
                  ],
                  onChanged: (val) => setSheetState(() => selType = val!),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                  onPressed: () {
                    final b = busCtrl.text.trim().toUpperCase();
                    final n = nameCtrl.text.trim();
                    final p = phoneCtrl.text.trim();
                    final pass = passCtrl.text.trim();
                    if (b.isEmpty || n.isEmpty || p.isEmpty || pass.isEmpty) {
                      _showAppSnackBar("Please fill all fields.");
                      return;
                    }
                    setState(() {
                      final idx = _drivers.indexWhere((item) => item.id == entry.id);
                      if (idx != -1) {
                        _drivers[idx] = DriverEntry(
                          id: entry.id,
                          bus: b,
                          driver: n,
                          contact: p,
                          route: selRoute,
                          type: selType,
                          password: pass,
                        );
                      }
                      _saveDrivers();
                    });
                    Navigator.pop(ctx);
                    _showAppSnackBar("Driver registry updated.");
                  },
                  child: const Text("Save Registry Entry", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRouteAddBottomSheet() {
    final keyCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final stopsCtrl = TextEditingController();
    final colorCtrl = TextEditingController(text: "#2563EB");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Add College Transit Route", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: "Route Key (e.g. route_15)")),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Route Display Name")),
              const SizedBox(height: 8),
              TextField(controller: stopsCtrl, decoration: const InputDecoration(labelText: "Stops (comma separated)", hintText: "Porur, Poonamallee, College")),
              const SizedBox(height: 8),
              TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: "Hex Color", hintText: "#2563EB")),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                onPressed: () {
                  final k = keyCtrl.text.trim();
                  final n = nameCtrl.text.trim();
                  final s = stopsCtrl.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
                  final c = colorCtrl.text.trim();
                  if (k.isEmpty || n.isEmpty || s.isEmpty) {
                    _showAppSnackBar("Please fill route key, name, and stops.");
                    return;
                  }
                  setState(() {
                    _routes.add(RouteEntry(
                      id: DateTime.now().millisecondsSinceEpoch.toDouble(),
                      key: k,
                      name: n,
                      stops: s,
                      color: c.isNotEmpty ? c : "#2563EB",
                    ));
                    _saveRoutes();
                  });
                  Navigator.pop(context);
                  _showAppSnackBar("Route added.");
                },
                child: const Text("Create Route", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _openRouteEditBottomSheet(RouteEntry entry) {
    final keyCtrl = TextEditingController(text: entry.key);
    final nameCtrl = TextEditingController(text: entry.name);
    final stopsCtrl = TextEditingController(text: entry.stops.join(', '));
    final colorCtrl = TextEditingController(text: entry.color);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Edit Transit Route", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
              const SizedBox(height: 16),
              TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: "Route Key")),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Route Display Name")),
              const SizedBox(height: 8),
              TextField(controller: stopsCtrl, decoration: const InputDecoration(labelText: "Stops (comma separated)")),
              const SizedBox(height: 8),
              TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: "Hex Color")),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                onPressed: () {
                  final k = keyCtrl.text.trim();
                  final n = nameCtrl.text.trim();
                  final s = stopsCtrl.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
                  final c = colorCtrl.text.trim();
                  if (k.isEmpty || n.isEmpty || s.isEmpty) {
                    _showAppSnackBar("Please fill all details.");
                    return;
                  }
                  setState(() {
                    final idx = _routes.indexWhere((item) => item.id == entry.id);
                    if (idx != -1) {
                      _routes[idx] = RouteEntry(
                        id: entry.id,
                        key: k,
                        name: n,
                        stops: s,
                        color: c.isNotEmpty ? c : "#2563EB",
                      );
                    }
                    _saveRoutes();
                  });
                  Navigator.pop(context);
                  _showAppSnackBar("Route updated.");
                },
                child: const Text("Save Route Settings", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openAlertAddBottomSheet() {
    String selectedType = "delay";
    final busCtrl = TextEditingController(text: "B101");
    final msgCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    final types = [
      {'value': 'delay',        'label': '🚌  Delay Alert',      'hint': 'e.g. Bus B101 delayed 20 min due to traffic'},
      {'value': 'route_change', 'label': '🔀  Route Change',     'hint': 'e.g. Route 15 diverted via Ambattur today'},
      {'value': 'emergency',    'label': '🚨  Emergency Alert',  'hint': 'e.g. Bus breakdown, alternate arranged'},
      {'value': 'arrival',      'label': '🛎️  Arrival Notice',   'hint': 'e.g. Bus B202 arriving in 5 minutes'},
      {'value': 'breakdown',    'label': '🔧  Breakdown Notice', 'hint': 'e.g. Bus B303 broke down near Koyambedu'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) {
          final currentType = types.firstWhere((t) => t['value'] == selectedType, orElse: () => types[0]);
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Broadcast Alert Notice", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Type selector grid
                    const Text("NOTIFICATION TYPE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B), letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: types.map((t) {
                        final isSelected = selectedType == t['value'];
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            selectedType = t['value']!;
                            titleCtrl.text = _defaultNotifTitle(t['value']!);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              t['label']!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Title field
                    const Text("TITLE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        hintText: _defaultNotifTitle(selectedType),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    // Message field
                    const Text("MESSAGE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B), letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: msgCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: currentType['hint'],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    // Bus field
                    TextField(
                      controller: busCtrl,
                      decoration: InputDecoration(
                        labelText: "Affected Bus (or 'all')",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text("Send to All Students",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        final t = selectedType;
                        final b = busCtrl.text.trim().toUpperCase();
                        final m = msgCtrl.text.trim();
                        final title = titleCtrl.text.trim().isNotEmpty
                            ? titleCtrl.text.trim()
                            : _defaultNotifTitle(t);
                        if (m.isEmpty) {
                          _showAppSnackBar("Please enter notification message.");
                          return;
                        }

                        final timeNow =
                            "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
                        final id = DateTime.now().millisecondsSinceEpoch;

                        setState(() {
                          final newAlert = AlertEntry(
                            id: id.toDouble(),
                            type: t,
                            bus: b.isNotEmpty ? b : "all",
                            msg: m,
                            time: timeNow,
                          );
                          _alerts.add(newAlert);
                          _saveAlerts();
                        });

                        // Push to Firebase — student portals listen to student_notifications
                        if (Firebase.apps.isNotEmpty) {
                          FirebaseDatabase.instance
                              .ref('student_notifications/$id')
                              .set({
                            'type': t,
                            'title': title,
                            'msg': m,
                            'bus': b.isNotEmpty ? b : "all",
                            'time': timeNow,
                            'read': false,
                            'sentAt': DateTime.now().toIso8601String(),
                          });
                          // Also write to legacy routeAlerts path
                          FirebaseDatabase.instance
                              .ref('routeAlerts/$id')
                              .set({'type': t, 'bus': b, 'msg': m, 'time': timeNow});
                        }

                        Navigator.pop(context);
                        _showAppSnackBar("✅ Notification sent to all students!");
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _defaultNotifTitle(String type) {
    switch (type) {
      case 'delay':        return 'Bus Delay Alert';
      case 'route_change': return 'Route Change Notice';
      case 'emergency':    return 'Emergency Alert';
      case 'arrival':      return 'Bus Arrival Notice';
      case 'breakdown':    return 'Bus Breakdown Alert';
      default:             return 'Transit Notice';
    }
  }

  // Upgraded document viewing preview dialog
  void _viewUploadedLetter(String docName, String docUrl) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Document Preview",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: docUrl.isNotEmpty && (docName.toLowerCase().endsWith('.png') || docName.toLowerCase().endsWith('.jpg') || docName.toLowerCase().endsWith('.jpeg'))
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.network(
                            docUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey));
                            },
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                docName.toLowerCase().endsWith(".pdf") ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                size: 40,
                                color: docName.toLowerCase().endsWith(".pdf") ? Colors.red : Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text(
                                  docName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                if (docUrl.isNotEmpty) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse(docUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text("Open in Browser", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Close Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSimulatedDocumentView(String studentName, String docName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Document Preview ($studentName)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description, size: 48, color: Colors.blue),
            const SizedBox(height: 8),
            Text(docName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("[Simulated document content viewer: Permission is valid for today's date]", style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      _buildOverviewTab(),
      _buildLiveTrackTab(),
      _buildSTTIntercomTab(),
      _buildRequestsTab(),
      _buildRegistryTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Icon(Icons.admin_panel_settings, color: Color(0xFF2563EB), size: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('appTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                Text(t('admin_subtitle'), style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Color(0xFF64748B)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BreakdownNotificationsPage(
                        breakdowns: _firebaseBreakdowns,
                      ),
                    ),
                  );
                },
              ),
              if (_firebaseBreakdowns.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${_firebaseBreakdowns.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
            onPressed: widget.onSwitchRole,
          )
        ],
      ),
      body: tabs[_currentTab],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2))),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFEFF6FF),
          selectedIndex: _currentTab,
          onDestinationSelected: (idx) {
            setState(() {
              _currentTab = idx;
            });
          },
          destinations: [
            NavigationDestination(icon: const Icon(Icons.analytics_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.analytics, color: Color(0xFF2563EB)), label: t('admin_overview')),
            NavigationDestination(icon: const Icon(Icons.map_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.map, color: Color(0xFF2563EB)), label: t('admin_live_tracker')),
            NavigationDestination(icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.chat_bubble, color: Color(0xFF2563EB)), label: t('admin_intercom')),
            NavigationDestination(icon: const Icon(Icons.checklist_rtl_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.checklist_rtl, color: Color(0xFF2563EB)), label: t('admin_approvals')),
            NavigationDestination(icon: const Icon(Icons.app_registration_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.app_registration, color: Color(0xFF2563EB)), label: t('admin_registry')),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownNotificationBanner() {
    if (_firebaseBreakdowns.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text("🚨", style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                "ACTIVE VEHICLE BREAKDOWNS",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: Color(0xFF991B1B),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._firebaseBreakdowns.entries.map((entry) {
            final busId = entry.key;
            final replacement = entry.value['replacement'] ?? 'None';
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      "• Bus $busId breakdown alert sent! Replacement bus: $replacement.",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7F1D1D),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, color: Color(0xFF991B1B), size: 18),
                  onPressed: () {
                    if (Firebase.apps.isNotEmpty) {
                      FirebaseDatabase.instance.ref('breakdowns/$busId').remove();
                    }
                  },
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ─── TABS IMPLEMENTATION ──────────────────────────────────────────
  Widget _buildOverviewTab() {
    int activeBuses = _liveBuses.values.where((v) => v['status'] != 'offline').length;
    int pendingReqs = _requests.where((r) => r['status'] == 'pending').length;

    final List<Widget> alertBanners = [];
    _driversAlerts.forEach((busId, alerts) {
      alerts.forEach((type, alert) {
        if (alert['active'] == true) {
          alertBanners.add(
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
              ),
              child: Row(
                children: [
                  const _FlashingRedDot(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "SAFETY WARNING: BUS $busId",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF991B1B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alert['message'] ?? 'Critical safety violation detected.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7F1D1D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      });
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alertBanners.isNotEmpty) ...[
            ...alertBanners,
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: _buildStatCard("🚌", "$activeBuses online", "Live Active Fleet", const Color(0xFF2563EB))),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard("🎫", "$pendingReqs pending", "Pickup Letters Queue", const Color(0xFFEAB308))),
            ],
          ),
          _buildFlashingSafetyAlertsWidget(),
          const SizedBox(height: 16),

          // Suggest stops card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
            shadowColor: Colors.black12,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "📍 DRIVER LOCATION STOP CAPTURE CONSOLE",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF2563EB), letterSpacing: 1),
                  ),
                  SwitchListTile(
                    title: Text(t('admin_allow_stops'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    subtitle: Text(t('admin_enable_stops_desc'), style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    value: _allowDriversToAddStops,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (val) {
                      if (Firebase.apps.isNotEmpty) {
                        FirebaseDatabase.instance.ref('adminSettings/allowDriversToAddStops').set(val);
                      }
                    },
                  ),
                  if (_newStops.isNotEmpty) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(t('admin_suggested_stops'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
                    const SizedBox(height: 8),
                    _buildGroupedStopsWidget(),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: Text("No location stop check-ins received yet.", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Active Alerts List Preview
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
            shadowColor: Colors.black12,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "🔔 ACTIVE ALERTS PREVIEW",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF64748B), letterSpacing: 1),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 14),
                        label: Text(t('admin_broadcast_notice'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        onPressed: _openAlertAddBottomSheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_alerts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text("No active alerts. All systems normal.", style: TextStyle(fontSize: 12, color: Colors.grey))),
                    )
                  else
                    ..._alerts.take(3).map((a) => _buildAlertCard(a)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedStopsWidget() {
    // Group stops by driverBus
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var stop in _newStops) {
      final bus = stop['driverBus']?.toString() ?? 'Unknown Bus';
      grouped.putIfAbsent(bus, () => []).add(stop);
    }

    return Column(
      children: [
        for (var bus in grouped.keys) ...[
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.symmetric(vertical: 6),
            borderOnForeground: true,
            elevation: 0,
            color: const Color(0xFFF8FAFC),
            child: ExpansionTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFDBEAFE),
                child: Icon(Icons.directions_bus, color: Color(0xFF2563EB), size: 18),
              ),
              title: Text("Bus $bus", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
              subtitle: Text("${grouped[bus]!.length} stops check-ins", style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: grouped[bus]!.map((stop) {
                final ts = stop['timestamp'] as int?;
                final timeStr = ts != null ? DateTime.fromMillisecondsSinceEpoch(ts).toString().substring(0, 16) : "--";
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_location_alt, color: Color(0xFF2563EB), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Lat: ${stop['lat']}, Lng: ${stop['lng']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF0F172A))),
                            const SizedBox(height: 2),
                            Text("Captured: $timeStr", style: const TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () {
                          if (Firebase.apps.isNotEmpty) {
                            FirebaseDatabase.instance.ref('new_stops/${stop['driverBus']}_$ts').remove();
                          }
                        },
                      )
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildStatCard(String icon, String val, String title, Color color) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(val, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Text(title, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(AlertEntry a) {
    final isB = a.type == 'breakdown';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isB ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isB ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isB ? "🚨" : "⚠️", style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Notice (${a.bus == 'all' ? 'All Buses' : 'Bus ' + a.bus}) • ${a.time}", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: isB ? const Color(0xFF991B1B) : const Color(0xFF92400E))),
                const SizedBox(height: 4),
                Text(a.msg, style: TextStyle(fontSize: 11.5, color: isB ? const Color(0xFF7F1D1D) : const Color(0xFF78350F), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            onPressed: () {
              setState(() {
                _alerts.removeWhere((item) => item.id == a.id);
                _saveAlerts();
              });
              if (Firebase.apps.isNotEmpty) {
                FirebaseDatabase.instance.ref('routeAlerts/${a.id.round()}').remove();
              }
            },
          )
        ],
      ),
    );
  }

  Widget _buildLiveTrackTab() {
    final List<Marker> markers = [];

    // Add college campus pin
    markers.add(
      Marker(
        point: _campusCoord,
        width: 44,
        height: 44,
        child: Container(
          decoration: const BoxDecoration(color: Color(0xFF1E3A8A), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)]),
          alignment: Alignment.center,
          child: const Text(" PEC ", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      ),
    );

    // Draw route stops for selected route only
    if (_selectedLiveRoute != null) {
      Color c = const Color(0xFF2563EB);
      try {
        c = Color(int.parse(_selectedLiveRoute!.color.replaceFirst('#', '0xFF')));
      } catch (_) {}

      for (var stop in _selectedLiveRoute!.stops) {
        final coord = coordsConfig[stop];
        if (coord != null && stop != "COLLEGE" && stop != "Panimalar Engineering College") {
          markers.add(
            Marker(
              point: coord,
              width: 24,
              height: 24,
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.location_on, color: Colors.white, size: 14),
              ),
            ),
          );
        }
      }
    }

    // Add live bus pins
    _liveBuses.forEach((busId, data) {
      final status = data['status'] as String? ?? 'offline';
      if (status != 'offline') {
        final double lat = (data['lat'] as num).toDouble();
        final double lng = (data['lng'] as num).toDouble();
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 80,
            height: 80,
            alignment: Alignment.center,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)),
                  child: Text(busId, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const Text("🚌", style: TextStyle(fontSize: 22)),
              ],
            ),
          ),
        );
      }
    });

    final query = _liveMapSearchQuery.toLowerCase();
    final matches = _routes.where((r) {
      return r.name.toLowerCase().contains(query) || r.key.toLowerCase().contains(query) || r.stops.any((s) => s.toLowerCase().contains(query));
    }).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(13.047, 80.11),
            initialZoom: 12.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        
        // Search Bar Overlay
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3), width: 1.5),
                ),
                child: TextField(
                  controller: _liveMapSearchCtrl,
                  onChanged: (val) => setState(() => _liveMapSearchQuery = val),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: "Search route or bus stop...",
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                    border: InputBorder.none,
                    suffixIcon: _liveMapSearchQuery.isNotEmpty || _selectedLiveRoute != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _liveMapSearchCtrl.clear();
                                _liveMapSearchQuery = "";
                                _selectedLiveRoute = null;
                              });
                            },
                          )
                        : null,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
              ),
              
              if (_liveMapSearchQuery.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: matches.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text("No routes found", style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final r = matches[idx];
                            return ListTile(
                              leading: const Icon(Icons.directions_bus, color: Color(0xFF2563EB)),
                              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(r.stops.take(3).join(', ') + '...', style: const TextStyle(fontSize: 11)),
                              onTap: () {
                                setState(() {
                                  _selectedLiveRoute = r;
                                  _liveMapSearchQuery = "";
                                  _liveMapSearchCtrl.text = r.name;
                                  
                                  // Optional: Center map on first stop of the route
                                  if (r.stops.isNotEmpty && coordsConfig[r.stops[0]] != null) {
                                    _mapController.move(coordsConfig[r.stops[0]]!, 12.0);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSTTIntercomTab() {
    final query = _intercomSearchQuery.toLowerCase();
    
    final List<Map<String, dynamic>> chatList = [];
    if (_intercomSegment == 0) {
      for (final d in _drivers) {
        if (query.isEmpty || d.bus.toLowerCase().contains(query)) {
          final channelId = "driver_${d.bus}";
          final msgs = _adminIntercomMessages[channelId] ?? [];
          final lastMsg = msgs.isNotEmpty ? msgs.last['msg'] : 'No messages yet';
          chatList.add({
            'channelId': channelId,
            'title': "Driver - Bus ${d.bus}",
            'subtitle': d.driver,
            'lastMsg': lastMsg,
            'online': true,
          });
        }
      }
    } else {
      for (final s in _studentsList) {
        if (query.isEmpty || s['name'].toLowerCase().contains(query) || s['id'].toLowerCase().contains(query)) {
          final channelId = "student_${s['id']}";
          final msgs = _adminIntercomMessages[channelId] ?? [];
          final lastMsg = msgs.isNotEmpty ? msgs.last['msg'] : 'No messages yet';
          chatList.add({
            'channelId': channelId,
            'title': s['name'],
            'subtitle': "${s['year']} • ${s['department']}",
            'lastMsg': lastMsg,
            'online': true,
          });
        }
      }
    }

    return Container(
      color: const Color(0xFFF0F2F5),
      child: Row(
        children: [
          Container(
            width: 320,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xFFF0F2F5),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Drivers", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          selected: _intercomSegment == 0,
                          selectedColor: const Color(0xFF2563EB),
                          labelStyle: TextStyle(color: _intercomSegment == 0 ? Colors.white : Colors.black87),
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            setState(() {
                              _intercomSegment = 0;
                              _selectedIntercomBus = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Students", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          selected: _intercomSegment == 1,
                          selectedColor: const Color(0xFF2563EB),
                          labelStyle: TextStyle(color: _intercomSegment == 1 ? Colors.white : Colors.black87),
                          backgroundColor: Colors.white,
                          onSelected: (val) {
                            setState(() {
                              _intercomSegment = 1;
                              _selectedIntercomBus = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFFF0F2F5),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _intercomSearchCtrl,
                      onChanged: (val) => setState(() => _intercomSearchQuery = val),
                      decoration: const InputDecoration(
                        hintText: "Search chat room...",
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const Divider(height: 1),
                
                Expanded(
                  child: chatList.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No channels found.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))))
                      : ListView.separated(
                          itemCount: chatList.length,
                          separatorBuilder: (ctx, idx) => const Divider(height: 1, indent: 64),
                          itemBuilder: (ctx, idx) {
                            final chat = chatList[idx];
                            final isSelected = _selectedIntercomBus == chat['channelId'];
                            
                            return ListTile(
                              tileColor: isSelected ? const Color(0xFFF0F2F5) : Colors.white,
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFEFF6FF),
                                child: Text(_intercomSegment == 0 ? "🚌" : "🎓", style: const TextStyle(fontSize: 18)),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat['title'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                    ),
                                  ),
                                  const Icon(Icons.circle, size: 8, color: Color(0xFF25D366)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chat['subtitle'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    chat['lastMsg'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                  ),
                                ],
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedIntercomBus = chat['channelId'];
                                });
                              },
                            );
                          },
                        ),
                )
              ],
            ),
          ),

          Expanded(
            child: _selectedIntercomBus == null
                ? Container(
                    color: const Color(0xFFF0F2F5),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_chat_unread_outlined, size: 64, color: Colors.black26),
                          SizedBox(height: 16),
                          Text("Select a channel to view transcript & record voice alerts", style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        color: const Color(0xFFF0F2F5),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFEFF6FF),
                              child: Text(_intercomSegment == 0 ? "🚌" : "🎓", style: const TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_selectedIntercomBus!.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(t('admin_online'), style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE5DDD5),
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: (_adminIntercomMessages[_selectedIntercomBus] ?? []).length,
                            itemBuilder: (ctx, idx) {
                              final m = _adminIntercomMessages[_selectedIntercomBus!]![idx];
                              final isMe = m['sender'] == 'admin';
                              final isVoice = m['isVoice'] == true;
                              
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  width: isVoice ? 230 : null,
                                  decoration: BoxDecoration(
                                    color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                                    borderRadius: BorderRadius.circular(12).copyWith(
                                      topRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                                      topLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                                    ),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isMe ? "You" : (m['senderName'] ?? "Sender"),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: isMe ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (isVoice) ...[
                                        Row(
                                          children: [
                                            IconButton(
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                _playingMsgId == m['id']
                                                    ? Icons.pause_circle_filled_rounded
                                                    : Icons.play_circle_filled_rounded,
                                                color: isMe ? const Color(0xFF15803D) : const Color(0xFF1E293B),
                                                size: 26,
                                              ),
                                              onPressed: () {
                                                 _playAdminVoiceMessage(m['id'], m['msg'] ?? '', m['voiceDuration'] ?? 3);
                                               },
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(2),
                                                    child: LinearProgressIndicator(
                                                      value: _playingMsgId == m['id'] ? _playbackProgress : 0.0,
                                                      backgroundColor: isMe ? const Color(0xFFC5E1A5) : const Color(0xFFE2E8F0),
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        isMe ? const Color(0xFF33691E) : const Color(0xFF64748B),
                                                      ),
                                                      minHeight: 3,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        "0:${(m['voiceDuration'] as int? ?? 3).toString().padLeft(2, '0')}",
                                                        style: const TextStyle(fontSize: 8, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                                      ),
                                                      const Icon(Icons.volume_up, size: 8, color: Color(0xFF64748B)),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFFD4E157).withValues(alpha: 0.3) : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            "Transcript: \"${m['transcript'] ?? ''}\"",
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontStyle: FontStyle.italic,
                                              color: Color(0xFF374151),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          "${m['msg']}",
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      
                      Container(
                        color: const Color(0xFFF0F2F5),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: _isAdminRecording
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFFCA5A5)),
                                ),
                                child: Row(
                                  children: [
                                    const _FlashingRedDot(),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Recording alert... 0:${_adminRecordingDuration.toString().padLeft(2, '0')}",
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 22),
                                      onPressed: _cancelAdminRecordingVoice,
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 22),
                                      onPressed: () {
                                        _stopAndSendAdminRecordingVoice(_selectedIntercomBus!);
                                      },
                                    ),
                                  ],
                                ),
                              )
                            : Row(
                                children: [
                                  const Icon(Icons.emoji_emotions_outlined, color: Colors.grey, size: 26),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: TextField(
                                        controller: _adminChatInputCtrl,
                                        decoration: const InputDecoration(
                                          hintText: "Type a message or hold mic...",
                                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          border: InputBorder.none,
                                        ),
                                        style: const TextStyle(fontSize: 13),
                                        onSubmitted: (val) {
                                          if (val.trim().isNotEmpty) {
                                            _sendAdminTextMessage(_selectedIntercomBus!, val.trim());
                                            _adminChatInputCtrl.clear();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      final val = _adminChatInputCtrl.text;
                                      if (val.trim().isNotEmpty) {
                                        _sendAdminTextMessage(_selectedIntercomBus!, val.trim());
                                        _adminChatInputCtrl.clear();
                                      }
                                    },
                                    child: const CircleAvatar(
                                      backgroundColor: Color(0xFF00A884),
                                      radius: 18,
                                      child: Icon(Icons.send, color: Colors.white, size: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onLongPressStart: (_) {
                                      _startAdminRecordingVoice();
                                      _showAppSnackBar("Recording admin voice broadcast...");
                                    },
                                    onLongPressEnd: (_) {
                                      _stopAndSendAdminRecordingVoice(_selectedIntercomBus!);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEFF6FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.mic, color: Color(0xFF2563EB), size: 18),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    return _isLoadingRequests
        ? const Center(child: CircularProgressIndicator())
        : _requests.isEmpty
            ? const Center(child: Text("All pickup letter queues cleared for today.", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                itemBuilder: (ctx, idx) {
                  final req = _requests[idx];
                  final status = req['status'] as String? ?? "pending";
                  final docName = req['documentName'] as String? ?? "Attached_Document.png";
                  final timeStr = req['timestamp'] != 0
                      ? DateTime.fromMillisecondsSinceEpoch(req['timestamp']).toString().substring(0, 16)
                      : "--";

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.white,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                req['studentName'],
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1E3A8A)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: status == "confirmed"
                                      ? const Color(0xFFDCFCE7)
                                      : (status == "rejected" ? const Color(0xFFFEE2E2) : const Color(0xFFFEF9C3)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: status == "confirmed"
                                        ? const Color(0xFF16A34A)
                                        : (status == "rejected" ? const Color(0xFFDC2626) : const Color(0xFFA16207)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${req['studentDept']} • ${req['studentYear']} • Recd: $timeStr",
                            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Text(
                                "Boarding Stop: ${req['savedStop']}",
                                style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                docName.toLowerCase().endsWith(".png") || docName.toLowerCase().endsWith(".jpg")
                                    ? Icons.image
                                    : Icons.picture_as_pdf,
                                color: docName.toLowerCase().endsWith(".png") || docName.toLowerCase().endsWith(".jpg")
                                    ? Colors.orange
                                    : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  docName,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final docUrl = req['documentUrl'] as String?;
                                  if (docUrl != null && docUrl.isNotEmpty) {
                                    _viewUploadedLetter(docName, docUrl);
                                  } else {
                                    _showSimulatedDocumentView(req['studentName'], docName);
                                  }
                                },
                                child: const Text("View Document", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (status == "pending") ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF22C55E),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _updateRequestStatus(req['studentId'], "confirmed"),
                                    child: const Text("Confirm Request", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _updateRequestStatus(req['studentId'], "rejected"),
                                    child: const Text("Reject Request", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onPressed: () => _updateRequestStatus(req['studentId'], "pending"),
                              child: const Text("Reset status to Pending", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
  }

  Widget _buildRegistryTab() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text("Drivers Registry"),
                selected: _registryViewMode == 0,
                onSelected: (val) {
                  if (val) setState(() => _registryViewMode = 0);
                },
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text("Routes Registry"),
                selected: _registryViewMode == 1,
                onSelected: (val) {
                  if (val) setState(() => _registryViewMode = 1);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _registryViewMode == 0 ? _buildDriversRegistrySubTab() : _buildRoutesRegistrySubTab(),
        )
      ],
    );
  }

  Widget _buildDriversRegistrySubTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _drivers.length,
        itemBuilder: (ctx, idx) {
          final d = _drivers[idx];
          return Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFEEF2FF), width: 1.5)),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFEEF2FF),
                    child: Text("👔", style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.driver, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A))),
                        const SizedBox(height: 2),
                        Text("Bus: ${d.bus} • Route: ${routeLabelsConfig[d.route] ?? d.route}", style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        Text("Category: ${d.type.toUpperCase()} • Pass: ${d.password.isEmpty ? 'None' : d.password}", style: const TextStyle(fontSize: 9.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _openDriverEditBottomSheet(d),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (diag) => AlertDialog(
                          title: const Text("Confirm Delete"),
                          content: Text("Delete registry entry for ${d.driver}?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(diag), child: const Text("Cancel")),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _drivers.removeWhere((item) => item.id == d.id);
                                  _saveDrivers();
                                });
                                Navigator.pop(diag);
                                _showAppSnackBar("Driver removed.");
                              },
                              child: const Text("Delete", style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        onPressed: _openDriverAddBottomSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildRoutesRegistrySubTab() {
    final query = _adminRouteSearchQuery.toLowerCase();
    final displayedRoutes = _routes.where((r) {
      if (query.isEmpty) return true;
      final nameMatch = r.name.toLowerCase().contains(query);
      final stopMatch = r.stops.any((s) => s.toLowerCase().contains(query));
      return nameMatch || stopMatch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _adminRouteSearchCtrl,
                onChanged: (val) => setState(() => _adminRouteSearchQuery = val),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: "Search by route name or bus stop...",
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: displayedRoutes.length,
              itemBuilder: (ctx, idx) {
                final r = displayedRoutes[idx];
                Color c = const Color(0xFF2563EB);
                try {
                  c = Color(int.parse(r.color.replaceFirst('#', '0xFF')));
                } catch (_) {}
                return Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFEEF2FF), width: 1.5)),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("🛣️ ${r.name}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: c)),
                            Text("${r.stops.length} Stops", style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text("Path: ${r.stops.join(' ➔ ')}", style: const TextStyle(fontSize: 10, color: Color(0xFF475569), height: 1.3, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit, size: 14),
                              label: const Text("Edit", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              onPressed: () => _openRouteEditBottomSheet(r),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                              label: const Text("Delete", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (diag) => AlertDialog(
                                    title: const Text("Confirm Delete", style: TextStyle(fontWeight: FontWeight.bold)),
                                    content: Text("Are you sure you want to delete the ${r.name} Route?"),
                                    actions: [
                                     TextButton(onPressed: () => Navigator.pop(diag), child: const Text("Cancel")),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _routes.removeWhere((item) => item.id == r.id);
                                            _saveRoutes();
                                          });
                                          Navigator.pop(diag);
                                          _showAppSnackBar("Route deleted.");
                                        },
                                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        onPressed: _openRouteAddBottomSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFlashingSafetyAlertsWidget() {
    List<Widget> alertTiles = [];
    _safetyAlerts.forEach((busId, alertsMap) {
      if (alertsMap is Map) {
        alertsMap.forEach((alertType, alertData) {
          if (alertData is Map && alertData['active'] == true) {
            final msg = alertData['message'] ?? "";
            alertTiles.add(
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "CRITICAL SAFETY WARNING: BUS $busId",
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              color: Color(0xFF991B1B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            msg,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7F1D1D),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        });
      }
    });

    if (alertTiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: alertTiles,
    );
  }
}

class _FlashingRedDot extends StatefulWidget {
  const _FlashingRedDot();

  @override
  State<_FlashingRedDot> createState() => _FlashingRedDotState();
}

class _FlashingRedDotState extends State<_FlashingRedDot> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _visible = !_visible;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.2,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class BreakdownNotificationsPage extends StatelessWidget {
  final Map<String, Map<String, dynamic>> breakdowns;

  const BreakdownNotificationsPage({super.key, required this.breakdowns});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Vehicle Breakdowns",
          style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: breakdowns.isEmpty
          ? const Center(
              child: Text(
                "No active vehicle breakdowns.",
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: breakdowns.entries.map((entry) {
                final busId = entry.key;
                final replacement = entry.value['replacement'] ?? 'None';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("🚨", style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Bus $busId Breakdown",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              replacement == "Pending"
                                  ? "Bus $busId breakdown reported. Replacement Bus dispatch is pending."
                                  : "Bus $busId breakdown alert sent! Replacement bus: $replacement.",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7F1D1D),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF991B1B), size: 20),
                        onPressed: () {
                          if (Firebase.apps.isNotEmpty) {
                            FirebaseDatabase.instance.ref('breakdowns/$busId').remove();
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
