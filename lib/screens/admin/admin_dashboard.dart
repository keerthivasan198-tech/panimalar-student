import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
import '../../models/bus_sim_state.dart';
import '../../config/routes_config.dart';
import '../../widgets/custom_charts.dart';

class AdminDashboard extends StatefulWidget {
  final VoidCallback onSwitchRole;
  const AdminDashboard({super.key, required this.onSwitchRole});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Navigation & tabs
  int _currentTab = 0;

  // Firebase pickup requests queue
  List<Map<String, dynamic>> _requests = [];
  bool _isLoadingRequests = true;
  StreamSubscription? _requestsSub;

  // Persistence State Lists
  List<DriverEntry> _drivers = [];
  List<RouteEntry> _routes = [];
  List<LogEntry> _logs = [];
  List<AlertEntry> _alerts = [];
  List<UploadEntry> _uploads = [];

  // Admin STT Intercom State
  Map<String, List<Map<String, dynamic>>> _adminIntercomMessages = {};
  StreamSubscription? _adminIntercomSub;
  bool _isAdminSttListening = false;
  String _selectedAdminSttLang = 'en';
  final TextEditingController _adminChatInputCtrl = TextEditingController();

  // Live Bus Locations
  Map<String, Map<String, dynamic>> _liveBuses = {};
  StreamSubscription? _liveLocationsSub;

  // Map Controllers
  final MapController _mapController = MapController();

  // Registry sub-toggle
  int _registryViewMode = 0; // 0 = Drivers, 1 = Routes

  // Logs Filter
  String _selectedLogDate = DateTime.now().toIso8601String().substring(0, 10);

  // Stop Capture State
  bool _allowDriversToAddStops = false;
  StreamSubscription? _adminSettingsSub;
  List<Map<String, dynamic>> _newStops = [];
  StreamSubscription? _newStopsSub;

  // Constants & Static Caches
  final LatLng _campusCoord = const LatLng(13.0489049, 80.0754642);

  final List<String> _routeColors = [
    '#2563EB', '#22C55E', '#F97316', '#DB2777', '#8B5CF6', '#06B6D4', '#EF4444', '#84CC16', '#F59E0B', '#10B981'
  ];

  // Cached route geometries (interpolated paths)
  final Map<String, List<LatLng>> _routeGeometries = {};

  @override
  void initState() {
    super.initState();
    _loadPersistedData();
    _listenForRequests();
    _listenForAdminIntercomMessages();
    _listenForLiveLocations();
    _listenForAdminSettings();
    _listenForNewStops();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _liveLocationsSub?.cancel();
    _adminIntercomSub?.cancel();
    _adminSettingsSub?.cancel();
    _newStopsSub?.cancel();
    _adminChatInputCtrl.dispose();
    super.dispose();
  }

  // ─── PERSISTENCE DATA LOAD/SAVE ─────────────────────────────────
  void _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Drivers
    final driversStr = prefs.getString('ptAdmin_drivers');
    if (driversStr != null) {
      try {
        final List decoded = json.decode(driversStr);
        _drivers = decoded.map((e) => DriverEntry.fromJson(e)).toList();
      } catch (e) {
        _drivers = _getDefaultDrivers();
      }
    } else {
      _drivers = _getDefaultDrivers();
    }

    // Routes
    final routesStr = prefs.getString('ptAdmin_routes');
    if (routesStr != null) {
      try {
        final List decoded = json.decode(routesStr);
        _routes = decoded.map((e) => RouteEntry.fromJson(e)).toList();
      } catch (e) {
        _routes = _getDefaultRoutes();
      }
    } else {
      _routes = _getDefaultRoutes();
    }

    // Logs
    final logsStr = prefs.getString('ptAdmin_logs');
    if (logsStr != null) {
      try {
        final List decoded = json.decode(logsStr);
        _logs = decoded.map((e) => LogEntry.fromJson(e)).toList();
      } catch (e) {
        _logs = _getDefaultLogs();
      }
    } else {
      _logs = _getDefaultLogs();
    }

    // Alerts
    final alertsStr = prefs.getString('ptAdmin_alerts');
    if (alertsStr != null) {
      try {
        final List decoded = json.decode(alertsStr);
        _alerts = decoded.map((e) => AlertEntry.fromJson(e)).toList();
      } catch (e) {
        _alerts = _getDefaultAlerts();
      }
    } else {
      _alerts = _getDefaultAlerts();
    }

    // Uploads
    final uploadsStr = prefs.getString('ptAdmin_uploads');
    if (uploadsStr != null) {
      try {
        final List decoded = json.decode(uploadsStr);
        _uploads = decoded.map((e) => UploadEntry.fromJson(e)).toList();
      } catch (e) {
        _uploads = [];
      }
    }
    if (mounted) setState(() {});
  }

  void _saveDrivers() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ptAdmin_drivers', json.encode(_drivers.map((e) => e.toJson()).toList()));
    
    // Also sync to Firebase Realtime Database
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
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ptAdmin_routes', json.encode(_routes.map((e) => e.toJson()).toList()));
  }

  void _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ptAdmin_logs', json.encode(_logs.map((e) => e.toJson()).toList()));
  }

  void _saveAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ptAdmin_alerts', json.encode(_alerts.map((e) => e.toJson()).toList()));
  }

  void _saveUploads() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('ptAdmin_uploads', json.encode(_uploads.map((e) => e.toJson()).toList()));
  }

  // ─── DEFAULT METRICS ──────────────────────────────────────────────
  List<DriverEntry> _getDefaultDrivers() {
    return [
      DriverEntry(id: 1, bus: 'B101', driver: 'Rajan Kumar', contact: '9876543210', route: 'route_15', type: 'combined', password: '1234'),
      DriverEntry(id: 2, bus: 'B202', driver: 'Selvam P', contact: '9876543211', route: 'route_52', type: 'combined', password: '1234'),
      DriverEntry(id: 3, bus: 'B303', driver: 'Murugan S', contact: '9876543212', route: 'route_137', type: 'combined', password: '1234'),
    ];
  }

  List<RouteEntry> _getDefaultRoutes() {
    return [
      RouteEntry(id: 1, key: 'route_15', name: 'Route 15 - Manali 2', stops: routeStopsConfig['route_15']!, color: '#2563EB'),
      RouteEntry(id: 2, key: 'route_52', name: 'Route 52 - Padappai', stops: routeStopsConfig['route_52']!, color: '#22C55E'),
      RouteEntry(id: 3, key: 'route_137', name: 'Route 137 - Porur', stops: routeStopsConfig['route_137']!, color: '#F97316'),
    ];
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
    return [
      AlertEntry(id: 1, type: 'breakdown', bus: 'B303', msg: 'Bus B303 has broken down near Koyambedu. Alternate arrangements being made.', time: '08:15'),
      AlertEntry(id: 2, type: 'delay', bus: 'B101', msg: 'Bus B101 is delayed by 20 minutes due to traffic near Porur.', time: '07:45'),
    ];
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
          data.forEach((busId, msgs) {
            if (msgs is Map) {
              final List<Map<String, dynamic>> busMsgs = [];
              msgs.forEach((k, v) {
                if (v is Map) {
                  busMsgs.add({
                    'id': k,
                    'sender': v['sender'] ?? 'unknown',
                    'senderName': v['senderName'] ?? '',
                    'timestamp': v['timestamp'] ?? 0,
                    'msg': v['msg'] ?? '',
                  });
                }
              });
              busMsgs.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
              temp[busId.toString()] = busMsgs;
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

  void _sendAdminTextMessage(String busId, String text) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseDatabase.instance.ref('voice_messages/$busId/$msgId').set({
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

  List<LatLng> _getRoutePointsCached(String routeKey) {
    if (_routeGeometries.containsKey(routeKey)) {
      return _routeGeometries[routeKey]!;
    }
    final points = _getLinearRoutePoints(routeKey);
    _routeGeometries[routeKey] = points;
    return points;
  }

  List<LatLng> _getLinearRoutePoints(String routeKey) {
    final route = _routes.firstWhere((r) => r.key == routeKey, orElse: () => _getDefaultRoutes()[0]);
    final stops = route.stops;
    final List<LatLng> pts = [];
    for (int i = 0; i < stops.length; i++) {
      final name = stops[i];
      final coord = coordsConfig[name];
      if (coord == null) continue;
      if (i == 0) {
        pts.add(coord);
        continue;
      }
      final prevName = stops[i - 1];
      final prevCoord = coordsConfig[prevName];
      if (prevCoord == null) continue;
      
      for (int s = 1; s <= 40; s++) {
        double t = s / 40.0;
        double lat = prevCoord.latitude + (coord.latitude - prevCoord.latitude) * t;
        double lng = prevCoord.longitude + (coord.longitude - prevCoord.longitude) * t;
        pts.add(LatLng(lat, lng));
      }
    }
    return pts;
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Add Driver & Bus Entry", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Add College Transit Route", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
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
    final typeCtrl = TextEditingController(text: "delay");
    final busCtrl = TextEditingController(text: "B101");
    final msgCtrl = TextEditingController();

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
                const Text("Broadcast Alert Notice", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E3A8A))),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: typeCtrl.text,
                  decoration: const InputDecoration(labelText: "Alert Category"),
                  items: const [
                    DropdownMenuItem(value: "delay", child: Text("Traffic Delay")),
                    DropdownMenuItem(value: "breakdown", child: Text("Mechanical Breakdown")),
                    DropdownMenuItem(value: "route", child: Text("Route Change")),
                  ],
                  onChanged: (val) => setSheetState(() => typeCtrl.text = val!),
                ),
                const SizedBox(height: 8),
                TextField(controller: busCtrl, decoration: const InputDecoration(labelText: "Affected Bus (or 'all')")),
                const SizedBox(height: 8),
                TextField(controller: msgCtrl, decoration: const InputDecoration(labelText: "Notice Message description")),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                  onPressed: () {
                    final t = typeCtrl.text;
                    final b = busCtrl.text.trim().toUpperCase();
                    final m = msgCtrl.text.trim();
                    if (m.isEmpty) {
                      _showAppSnackBar("Please enter alert message.");
                      return;
                    }
                    setState(() {
                      final timeNow = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
                      final newAlert = AlertEntry(
                        id: DateTime.now().millisecondsSinceEpoch.toDouble(),
                        type: t,
                        bus: b.isNotEmpty ? b : "all",
                        msg: m,
                        time: timeNow,
                      );
                      _alerts.add(newAlert);
                      _saveAlerts();

                      // Also publish alert to Firebase RTDB for real-time notifications
                      if (Firebase.apps.isNotEmpty) {
                        FirebaseDatabase.instance.ref('routeAlerts/${newAlert.id.round()}').set(newAlert.toJson());
                      }
                    });
                    Navigator.pop(context);
                    _showAppSnackBar("Notice broadcasted to all channels.");
                  },
                  child: const Text("Broadcast Alert Notice", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
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
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Smart Transit Console", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                Text("College Administration System", style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
        actions: [
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
          destinations: const [
            NavigationDestination(icon: Icon(Icons.analytics_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.analytics, color: Color(0xFF2563EB)), label: "Overview"),
            NavigationDestination(icon: Icon(Icons.map_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.map, color: Color(0xFF2563EB)), label: "Live Tracker"),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.chat_bubble, color: Color(0xFF2563EB)), label: "Intercom"),
            NavigationDestination(icon: Icon(Icons.checklist_rtl_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.checklist_rtl, color: Color(0xFF2563EB)), label: "Approvals"),
            NavigationDestination(icon: Icon(Icons.app_registration_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.app_registration, color: Color(0xFF2563EB)), label: "Registry"),
          ],
        ),
      ),
    );
  }

  // ─── TABS IMPLEMENTATION ──────────────────────────────────────────
  Widget _buildOverviewTab() {
    int activeBuses = _liveBuses.values.where((v) => v['status'] != 'offline').length;
    int pendingReqs = _requests.where((r) => r['status'] == 'pending').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildStatCard("🚌", "$activeBuses online", "Live Active Fleet", const Color(0xFF2563EB))),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard("🎫", "$pendingReqs pending", "Pickup Letters Queue", const Color(0xFFEAB308))),
            ],
          ),
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
                    title: const Text("Allow Drivers to Add Stops", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    subtitle: const Text("Enable to let drivers submit their current location as a new bus stop.", style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
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
                    const Text("Suggested stops by Drivers (Grouped by Bus Card):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155))),
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
                        label: const Text("Broadcast Notice", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
    final List<Polyline> polylines = [];

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

    // Draw route polylines
    for (var r in _routes) {
      final points = _getRoutePointsCached(r.key);
      Color c = const Color(0xFF2563EB);
      try {
        c = Color(int.parse(r.color.replaceFirst('#', '0xFF')));
      } catch (_) {}

      if (points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: points,
            color: c.withValues(alpha: 0.8),
            strokeWidth: 3.5,
          ),
        );
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
            width: 40,
            height: 40,
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

    return FlutterMap(
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
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildSTTIntercomTab() {
    final List<String> activeBusIds = _adminIntercomMessages.keys.toList();

    return Row(
      children: [
        // Left Column - Bus list
        Container(
          width: 140,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("ACTIVE BUSES", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              ),
              const Divider(height: 1),
              Expanded(
                child: activeBusIds.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text("No driver text channel active", style: TextStyle(fontSize: 10, color: Colors.grey))))
                    : ListView.builder(
                        itemCount: activeBusIds.length,
                        itemBuilder: (ctx, idx) {
                          final bus = activeBusIds[idx];
                          return ListTile(
                            dense: true,
                            title: Text("Bus $bus", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            trailing: const Icon(Icons.circle, size: 8, color: Colors.green),
                            onTap: () {
                              setState(() {
                                _adminChatInputCtrl.text = ""; // clear input
                              });
                            },
                          );
                        },
                      ),
              )
            ],
          ),
        ),

        // Right Column - Intercom chat panels
        Expanded(
          child: activeBusIds.isEmpty
              ? const Center(child: Text("Select an active bus to send notices.", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: activeBusIds.length,
                        itemBuilder: (ctx, idx) {
                          final bus = activeBusIds[idx];
                          final msgs = _adminIntercomMessages[bus] ?? [];
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.white,
                            elevation: 0,
                            borderOnForeground: true,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Channel Bus $bus", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF1E3A8A))),
                                      const Icon(Icons.circle, size: 8, color: Colors.green),
                                    ],
                                  ),
                                  const Divider(),
                                  const SizedBox(height: 6),
                                  Column(
                                    children: msgs.map((m) {
                                      final isMe = m['sender'] == 'admin';
                                      return Align(
                                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 2),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text("${isMe ? 'You' : 'Driver'}: ${m['msg']}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          decoration: const InputDecoration(
                                            hintText: "Type note details...",
                                            hintStyle: TextStyle(fontSize: 10),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                                          ),
                                          style: const TextStyle(fontSize: 11),
                                          onSubmitted: (val) {
                                            if (val.trim().isNotEmpty) {
                                              _sendAdminTextMessage(bus, val.trim());
                                            }
                                          },
                                        ),
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
        )
      ],
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
                        Text("Category: ${d.type.toUpperCase()} • Pass: ${d.password ?? 'None'}", style: const TextStyle(fontSize: 9.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _routes.length,
        itemBuilder: (ctx, idx) {
          final r = _routes[idx];
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        onPressed: _openRouteAddBottomSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}
