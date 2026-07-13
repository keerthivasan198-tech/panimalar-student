import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../../models/campus_point.dart';
import '../../models/log_entry.dart';
import '../../models/alert_entry.dart';
import '../../config/routes_config.dart';
import '../../widgets/marquee_notice_bar.dart';
import '../../widgets/legend_item.dart';

class MainShell extends StatefulWidget {
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const MainShell({super.key, required this.onSwitchRole, required this.currentLang, required this.onLanguageChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  bool _busIsOnline = false;
  double? _busLat;
  double? _busLng;
  double? _busAccuracy;
  String _busUpdatedAt = "--:--";
  String _busStatus = "offline";

  double? _renderLat;
  double? _renderLng;
  Timer? _lerpTimer;

  String _savedStop = "";
  String _studentName = "Student Name";
  String _studentYear = "3rd Year";
  String _studentDept = "Computer Science (CSE)";
  String _studentId = "";
  StreamSubscription? _pickupRequestSub;
  String _pickupRequestStatus = "none";
  String _pickupRequestDoc = "";
  String _pickupRequestDocUrl = "";

  bool _hasAlertedApproaching = false;
  bool _hasAlertedArrived = false;
  bool _wasBusOnline = false;

  bool _showNotification = false;
  String _notifTitle = "";
  String _notifBody = "";
  String _notifIcon = "";
  double _notifProgress = 1.0;
  Timer? _notifTimer;
  Timer? _notifProgressTimer;

  bool _breakdownActive = false;
  String _replacementBus = "";
  StreamSubscription? _breakdownSub;
  StreamSubscription? _locationSub;

  // Dynamic Route selections
  String _selectedRoute = "route_15"; // default
  List<String> _routeStops = [];
  Map<String, LatLng> _coords = {};
  Color _routeColor = const Color(0xFF2563EB);
  String _busFirebaseId = 'B101';

  // Campus points for navigation
  final List<CampusPoint> _campusPointsList = campusPoints;

  // Campus points search filter
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchFilter = "";
  String _selectedNavPointName = "";
  Polyline? _campusRoute;

  // Real-time bus arrivals log feed
  List<LogEntry> _arrivalLogs = [];
  StreamSubscription? _logsSub;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _startLerpLoop();
    _listenForArrivalLogs();
  }

  @override
  void dispose() {
    _lerpTimer?.cancel();
    _notifTimer?.cancel();
    _notifProgressTimer?.cancel();
    _breakdownSub?.cancel();
    _locationSub?.cancel();
    _pickupRequestSub?.cancel();
    _logsSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedRoute = prefs.getString("student_route") ?? "route_15";
      _savedStop = prefs.getString("savedStop") ?? "";
      _studentName = prefs.getString("studentName") ?? "Student Name";
      _studentYear = prefs.getString("studentYear") ?? "3rd Year";
      _studentDept = prefs.getString("studentDept") ?? "Computer Science (CSE)";
      _studentId = prefs.getString("studentId") ?? "";
      if (_studentId.isEmpty) {
        _studentId = "STD_${DateTime.now().millisecondsSinceEpoch}";
        prefs.setString("studentId", _studentId);
      }
      _updateRouteDetails(_selectedRoute, startListener: false);
    });
    _startPickupRequestListener();
    _startFirebaseListener();
  }

  void _updateRouteDetails(String routeKey, {bool startListener = true}) {
    _routeStops = routeStopsConfig[routeKey] ?? [];
    _coords = {};
    for (var stop in _routeStops) {
      if (coordsConfig.containsKey(stop)) {
        _coords[stop] = coordsConfig[stop]!;
      }
    }

    if (routeKey == 'route_15') {
      _busFirebaseId = 'B101';
      _routeColor = const Color(0xFF2563EB); // Blue
    } else if (routeKey == 'route_52') {
      _busFirebaseId = 'B202';
      _routeColor = const Color(0xFF22C55E); // Green
    } else if (routeKey == 'route_137') {
      _busFirebaseId = 'B303';
      _routeColor = const Color(0xFFF97316); // Orange
    } else {
      _busFirebaseId = 'B101';
      _routeColor = const Color(0xFF2563EB);
    }

    if (startListener) {
      _startFirebaseListener();
    }
  }

  void _changeSelectedRoute(String routeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("student_route", routeKey);
    setState(() {
      _selectedRoute = routeKey;
      _savedStop = ""; // reset boarding stop on route change
      _updateRouteDetails(routeKey, startListener: true);
      _hasAlertedApproaching = false;
      _hasAlertedArrived = false;
    });
    _showSnackBar("Route switched to ${routeLabelsConfig[routeKey]}");
  }

  void _saveStop(String stopName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("savedStop", stopName);
    setState(() {
      _savedStop = stopName;
      _hasAlertedApproaching = false;
      _hasAlertedArrived = false;
    });
    _showSnackBar("⭐ Boarding stop saved: $stopName");
  }

  void _saveProfile(String name, String year, String dept) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("studentName", name);
    await prefs.setString("studentYear", year);
    await prefs.setString("studentDept", dept);
    setState(() {
      _studentName = name;
      _studentYear = year;
      _studentDept = dept;
    });
    _showSnackBar("✅ Profile saved successfully");
  }

  void _startPickupRequestListener() {
    _pickupRequestSub?.cancel();
    if (Firebase.apps.isEmpty || _studentId.isEmpty) return;
    try {
      _pickupRequestSub = FirebaseDatabase.instance.ref('pickup_requests/$_studentId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          setState(() {
            _pickupRequestStatus = data['status'] as String? ?? "none";
            _pickupRequestDoc = data['documentName'] as String? ?? "";
            _pickupRequestDocUrl = data['documentUrl'] as String? ?? "";
          });
        } else {
          setState(() {
            _pickupRequestStatus = "none";
            _pickupRequestDoc = "";
            _pickupRequestDocUrl = "";
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to pickup request: $e");
    }
  }

  void _listenForArrivalLogs() {
    _logsSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      _logsSub = FirebaseDatabase.instance.ref('arrival_logs/$today').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<LogEntry> temp = [];
        if (data != null) {
          data.forEach((key, val) {
            if (val is Map) {
              temp.add(LogEntry(
                id: (val['timestamp'] as num?)?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
                bus: val['bus'] ?? key,
                driver: val['driver'] ?? 'Unknown',
                route: val['route'] ?? 'Unknown',
                date: val['date'] ?? today,
                arrived: val['arrived'],
                departed: val['departed'],
                status: val['status'] ?? 'arrived',
              ));
            }
          });
        }
        setState(() {
          _arrivalLogs = temp;
        });
      });
    } catch (e) {
      debugPrint("Error listening to arrival logs: $e");
    }
  }

  void _startFirebaseListener() {
    _locationSub?.cancel();
    _breakdownSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _locationSub = FirebaseDatabase.instance.ref('liveLocations/$_busFirebaseId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data == null || data['status'] == 'offline') {
          setState(() {
            _wasBusOnline = false;
            _busIsOnline = false;
            _busStatus = "offline";
          });
          return;
        }

        final bool justCameOnline = !_wasBusOnline;

        setState(() {
          _busIsOnline = true;
          _wasBusOnline = true;
          _busLat = (data['lat'] as num).toDouble();
          _busLng = (data['lng'] as num).toDouble();
          _busAccuracy = (data['acc'] as num?)?.toDouble() ?? (data['accuracy'] as num?)?.toDouble() ?? 10.0;
          _busStatus = data['status'] as String? ?? "tracking";

          final rawUpdatedAt = data['updatedAt'] as String?;
          if (rawUpdatedAt != null) {
            try {
              final dt = DateTime.parse(rawUpdatedAt).toLocal();
              _busUpdatedAt = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
            } catch (_) {
              _busUpdatedAt = "--:--";
            }
          } else {
            _busUpdatedAt = "--:--";
          }

          if (_renderLat == null || _renderLng == null) {
            _renderLat = _busLat;
            _renderLng = _busLng;
          }
        });

        if (justCameOnline) {
          _showInAppNotification(
            "🚌 Bus $_busFirebaseId is Ready!",
            "The bus has started its route. Live GPS tracking is now active. Get ready to board!",
            "✅",
            durationMs: 10000,
          );
        }

        if (_savedStop.isNotEmpty && _busLat != null && _busLng != null) {
          final myStopIdx = _routeStops.indexOf(_savedStop);
          final nearestIdx = _getNearestStopIndex(_busLat!, _busLng!);

          if (nearestIdx == 0) {
            _hasAlertedApproaching = false;
            _hasAlertedArrived = false;
          }

          if (myStopIdx != -1) {
            if (nearestIdx == myStopIdx - 1 && !_hasAlertedApproaching) {
              _hasAlertedApproaching = true;
              _showInAppNotification(
                "Bus $_busFirebaseId is approaching!",
                "Bus $_busFirebaseId is at ${_routeStops[nearestIdx]}, which is 1 stop away from $_savedStop.",
                "🔔",
              );
            } else if (nearestIdx == myStopIdx && !_hasAlertedArrived) {
              _hasAlertedArrived = true;
              _showInAppNotification(
                "Bus $_busFirebaseId has arrived!",
                "Bus $_busFirebaseId is now at your boarding stop: $_savedStop. Get ready to board!",
                "🚏",
              );
            }
          }
        }
      }, onError: (e) {
        debugPrint("Database listen error: $e");
      });

      _breakdownSub = FirebaseDatabase.instance.ref('breakdowns/$_busFirebaseId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data == null) {
          setState(() {
            _breakdownActive = false;
            _replacementBus = "";
          });
          return;
        }
        setState(() {
          _breakdownActive = true;
          _replacementBus = data['replacement'] as String? ?? "Unknown";
        });
      }, onError: (e) {
        debugPrint("Breakdown database listen error: $e");
      });
    } catch (e) {
      debugPrint("Error starting database listener: $e");
    }
  }

  void _showInAppNotification(String title, String body, String icon, {int durationMs = 5000}) {
    _notifTimer?.cancel();
    _notifProgressTimer?.cancel();

    HapticFeedback.vibrate();

    setState(() {
      _notifTitle = title;
      _notifBody = body;
      _notifIcon = icon;
      _showNotification = true;
      _notifProgress = 1.0;
    });

    final duration = Duration(milliseconds: durationMs);
    const steps = 100;
    final stepDuration = Duration(milliseconds: durationMs ~/ steps);

    int currentStep = 0;
    _notifProgressTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      if (currentStep >= steps) {
        timer.cancel();
      } else {
        setState(() {
          _notifProgress = 1.0 - (currentStep / steps);
        });
      }
    });

    _notifTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _showNotification = false;
        });
      }
    });
  }

  void _startLerpLoop() {
    _lerpTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_busLat == null || _busLng == null || _renderLat == null || _renderLng == null) return;
      const lerpSpeed = 0.08;
      setState(() {
        _renderLat = _renderLat! + (_busLat! - _renderLat!) * lerpSpeed;
        _renderLng = _renderLng! + (_busLng! - _renderLng!) * lerpSpeed;
      });
    });
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  int _getNearestStopIndex(double lat, double lng) {
    int idx = 0;
    double minD = double.infinity;
    for (int i = 0; i < _routeStops.length; i++) {
      final stopName = _routeStops[i];
      final stopCoord = _coords[stopName];
      if (stopCoord == null) continue;
      final d = _haversineKm(lat, lng, stopCoord.latitude, stopCoord.longitude);
      if (d < minD) {
        minD = d;
        idx = i;
      }
    }
    return idx;
  }

  int? _calculateEtaMinutes(int nearestIdx) {
    if (!_busIsOnline || _busLat == null || _busLng == null || _savedStop.isEmpty) return null;
    final myStopIdx = _routeStops.indexOf(_savedStop);
    if (myStopIdx == -1 || nearestIdx > myStopIdx) return null;

    double totalDist = 0.0;
    double currentLat = _busLat!;
    double currentLng = _busLng!;

    for (int i = nearestIdx; i <= myStopIdx; i++) {
      final stopName = _routeStops[i];
      final stopCoord = _coords[stopName];
      if (stopCoord != null) {
        totalDist += _haversineKm(currentLat, currentLng, stopCoord.latitude, stopCoord.longitude);
        currentLat = stopCoord.latitude;
        currentLng = stopCoord.longitude;
      }
    }

    final intermediateStops = myStopIdx - nearestIdx;
    int eta = (totalDist * 2.5 + intermediateStops).round();
    return eta < 1 ? 1 : eta;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF2563EB),
      ),
    );
  }

  Widget _buildFirebaseStatusStrip() {
    Color bgColor;
    Color textColor;
    String statusText;

    if (_busIsOnline) {
      bgColor = const Color(0xFFF0FDF4);
      textColor = const Color(0xFF15803D);
      statusText = "Firebase connected — live GPS data";
    } else if (_busStatus == "offline") {
      bgColor = const Color(0xFFFEF2F2);
      textColor = const Color(0xFFDC2626);
      statusText = "Bus $_busFirebaseId GPS offline — driver not tracking";
    } else {
      bgColor = const Color(0xFFFEFCE8);
      textColor = const Color(0xFF92400E);
      statusText = "Connecting to Firebase…";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        border: const Border(bottom: BorderSide(color: Color(0xFFE8EDF8))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          Text(
            _busUpdatedAt,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalMyStopBanner() {
    final int nearestIdx = (_busLat != null && _busLng != null) ? _getNearestStopIndex(_busLat!, _busLng!) : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "📍 MY STOP",
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF93C5FD),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _savedStop,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _savedStop = "";
                    });
                    SharedPreferences.getInstance().then((prefs) {
                      prefs.setString("savedStop", "");
                    });
                    _showSnackBar("⭐ Boarding stop cleared");
                  },
                  child: const Text(
                     "Change stop",
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF93C5FD),
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _busIsOnline ? (eta != null ? "$eta" : "Passed") : "—",
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _busIsOnline ? (eta != null ? "min away" : "") : "offline",
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF93C5FD),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInAppNotificationWidget() {
    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EDF8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _notifIcon,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PANIMALAR TRANSIT — BUS $_busFirebaseId",
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _notifTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _notifBody,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: _notifProgress,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeTab(),
      _buildTrackTab(),
      _buildCampusNavTab(),
      _buildProfileTab(),
    ];

    return Scaffold(
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                color: Color(0xFF2563EB),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Panimalar Transit",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "Student Portal",
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                    )
                  ],
                )
              ],
            )
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: () {
              _startFirebaseListener();
              _listenForArrivalLogs();
              _showSnackBar("Refreshed transit details");
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildFirebaseStatusStrip(),
              if (_savedStop.isNotEmpty) _buildGlobalMyStopBanner(),
              Expanded(child: pages[_currentIndex]),
            ],
          ),
          if (_showNotification)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildInAppNotificationWidget(),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFEFF6FF),
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) {
            setState(() {
              _currentIndex = idx;
            });
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.home, color: Color(0xFF2563EB)), label: "Home"),
            NavigationDestination(icon: Icon(Icons.map_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.map, color: Color(0xFF2563EB)), label: "Live Track"),
            NavigationDestination(icon: Icon(Icons.domain_outlined, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.domain, color: Color(0xFF2563EB)), label: "Campus Map"),
            NavigationDestination(icon: Icon(Icons.person_outline, color: Color(0xFF64748B)), selectedIcon: Icon(Icons.person, color: Color(0xFF2563EB)), label: "Profile"),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final int nearestIdx = (_busLat != null && _busLng != null) ? _getNearestStopIndex(_busLat!, _busLng!) : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_breakdownActive)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Text("⚠️", style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Bus $_busFirebaseId breakdown. Replacement Bus $_replacementBus dispatched. Stay at your stop.",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF991B1B),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          _buildHeroBanner(),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "WELCOME BACK,",
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _studentName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 20),

                // Selected Route Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _busIsOnline ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _busIsOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.directions_bus_rounded,
                          color: _busIsOnline ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _busIsOnline ? "Bus $_busFirebaseId is online" : "Bus $_busFirebaseId is offline",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _busIsOnline ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _busIsOnline ? "Active • Updated $_busUpdatedAt" : "Driver not broadcasting live location",
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _busIsOnline ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_savedStop.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "MY BOARDING STOP",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF94A3B8),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _savedStop,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _savedStop = "");
                                  SharedPreferences.getInstance().then((p) => p.setString("savedStop", ""));
                                },
                                child: const Text(
                                  "Change stop",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _busIsOnline ? (eta != null ? "$eta" : "🏁") : "—",
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _busIsOnline ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)),
                            ),
                            Text(
                              _busIsOnline ? (eta != null ? "min away" : "Passed") : "offline",
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  GestureDetector(
                    onTap: () => setState(() => _currentIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: Color(0xFF2563EB),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Set your boarding stop",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Get ETA alerts when bus is near",
                                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Dynamic Route select list
                const Text(
                  "Assigned College Route",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: routeLabelsConfig.keys.map((routeKey) {
                    final isSelected = _selectedRoute == routeKey;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _changeSelectedRoute(routeKey),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? _routeColor : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? _routeColor : const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            routeKey == 'route_15' ? "R15" : (routeKey == 'route_52' ? "R52" : "R137"),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.location_on_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: "Track Live",
                        onTap: () => setState(() => _currentIndex = 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.map_outlined,
                        iconColor: const Color(0xFF475569),
                        label: "Campus Map",
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Real-time Automated Arrivals Feed
                if (_arrivalLogs.isNotEmpty) ...[
                  const Text(
                    "Real-time Automated Arrivals (Today)",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: _arrivalLogs.map((log) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                                  const SizedBox(width: 6),
                                  Text("Bus ${log.bus} (${log.route})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                              Text("Arrived: ${log.arrived ?? '--:--'}", style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const Text(
                  "Route Stops Sequence",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < _routeStops.length; i++) ...[
                        _buildStopRow(
                          _routeStops[i],
                          isFirst: i == 0,
                          isLast: i == _routeStops.length - 1,
                          isMyStop: _savedStop == _routeStops[i],
                        ),
                        if (i < _routeStops.length - 1) _buildStopConnector(),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    "Showing ${_routeStops.length} of ${_routeStops.length} stops",
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopRow(String stopName, {bool isFirst = false, bool isLast = false, bool isMyStop = false}) {
    Color dotColor = const Color(0xFF94A3B8);
    double dotSize = 10.0;
    FontWeight fWeight = FontWeight.w600;

    if (isFirst || isLast) {
      dotColor = _routeColor;
      dotSize = 12.0;
      fWeight = FontWeight.w800;
    }
    if (isMyStop) {
      dotColor = const Color(0xFF2563EB);
      dotSize = 14.0;
      fWeight = FontWeight.w900;
    }

    return Row(
      children: [
        Container(
          width: 20,
          alignment: Alignment.center,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: isMyStop ? Border.all(color: Colors.white, width: 2) : null,
              boxShadow: isMyStop ? const [BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            stopName,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: fWeight,
              color: isMyStop ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
            ),
          ),
        ),
        if (!isFirst && !isLast && _savedStop.isEmpty)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 20), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => _saveStop(stopName),
            child: const Text("Set My Stop", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        if (isMyStop)
          const Text("⭐ Boarding", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
      ],
    );
  }

  Widget _buildStopConnector() {
    return Row(
      children: [
        Container(
          width: 20,
          alignment: Alignment.center,
          child: Container(
            width: 2,
            height: 18,
            color: const Color(0xFFCBD5E1),
          ),
        ),
        const SizedBox(width: 12),
        const Spacer(),
      ],
    );
  }

  Widget _buildActionTile({required IconData icon, required Color iconColor, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      height: 175,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/panimalar_bus2.jpeg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E40AF).withValues(alpha: 0.52),
                      const Color(0xFF2563EB).withValues(alpha: 0.25),
                      const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "BUS $_busFirebaseId",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    "Panimalar Smart Transit",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${routeLabelsConfig[_selectedRoute]} • Live Tracker",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
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

  Widget _buildTrackTab() {
    final int nearestIdx = (_busLat != null && _busLng != null) ? _getNearestStopIndex(_busLat!, _busLng!) : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);

    final List<Marker> markers = [];

    // Add user marker if we had one
    // Add bus marker
    if (_busLat != null && _busLng != null) {
      markers.add(
        Marker(
          point: LatLng(_busLat!, _busLng!),
          width: 50,
          height: 50,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(
                  "Bus $_busFirebaseId",
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              const Text("🚌", style: TextStyle(fontSize: 26)),
            ],
          ),
        ),
      );
    }

    if (_busIsOnline && _routeStops.isNotEmpty) {
      final nearStop = _routeStops[nearestIdx];
      final nearCoord = _coords[nearStop];
      if (nearCoord != null) {
        markers.add(
          Marker(
            point: nearCoord,
            width: 80,
            height: 30,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(
                  nearStop,
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      }
    }

    final String nearestStopName = _busIsOnline && _routeStops.isNotEmpty ? _routeStops[nearestIdx] : "Searching…";

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(13.047, 80.11),
            initialZoom: 13.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _routeStops.map((name) => _coords[name]).whereType<LatLng>().toList(),
                  color: _routeColor,
                  strokeWidth: 4.0,
                  borderColor: Colors.white,
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),
            if (_busIsOnline && _renderLat != null && _renderLng != null && _busAccuracy != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_renderLat!, _renderLng!),
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderColor: const Color(0xFF22C55E),
                    borderStrokeWidth: 1.2,
                    useRadiusInMeter: true,
                    radius: _busAccuracy!,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() { _savedStop = ""; });
                    SharedPreferences.getInstance().then((p) => p.setString("savedStop", ""));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF0F172A)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _busIsOnline ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _busIsOnline ? "LIVE GPS" : "OFFLINE",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4))],
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "BUS $_busFirebaseId DETAILS",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _routeColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          routeLabelsConfig[_selectedRoute] ?? "Manali Route",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.gps_fixed, color: Color(0xFF2563EB)),
                      onPressed: () {
                        if (_busLat != null && _busLng != null) {
                          _mapController.move(LatLng(_busLat!, _busLng!), 14.5);
                        } else {
                          _showSnackBar("Location signal not received yet");
                        }
                      },
                    )
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("NEAREST STOP", style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            nearestStopName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 30, color: const Color(0xFFCBD5E1)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("ACCURACY SIGNAL", style: TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _busIsOnline && _busAccuracy != null ? "${_busAccuracy!.toStringAsFixed(1)} meters" : "No Signal",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_savedStop.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("ETA TO MY STOP", style: TextStyle(fontSize: 8.5, color: Color(0xFF1E40AF), fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(_savedStop, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Text(
                          _busIsOnline ? (eta != null ? "$eta min" : "Passed") : "offline",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E40AF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCampusNavTab() {
    final List<Marker> markers = [];
    CampusPoint? selectedPoint;
    try {
      selectedPoint = _campusPointsList.firstWhere((p) => p.name == _selectedNavPointName);
    } catch (_) {}

    for (var cp in _campusPointsList) {
      final isSelected = cp.name == _selectedNavPointName;
      markers.add(
        Marker(
          point: cp.coords,
          width: 60,
          height: 60,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedNavPointName = cp.name;
                if (_busLat != null && _busLng != null) {
                  _campusRoute = Polyline(
                    points: [LatLng(_busLat!, _busLng!), cp.coords],
                    color: const Color(0xFFD97706),
                    strokeWidth: 3.5,
                  );
                }
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    border: Border.all(color: isSelected ? Colors.white : const Color(0xFF2563EB), width: 1.5),
                  ),
                  child: Text(cp.icon, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
                  child: Text(cp.name, style: TextStyle(fontSize: 6, fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F172A)), maxLines: 1),
                )
              ],
            ),
          ),
        ),
      );
    }

    final filteredPoints = _campusPointsList.where((p) => p.name.toLowerCase().contains(_searchFilter.toLowerCase())).toList();

    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(13.049, 80.075),
            initialZoom: 16.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            if (_campusRoute != null)
              PolylineLayer(
                polylines: [_campusRoute!],
              ),
            MarkerLayer(markers: markers),
          ],
        ),

        // Search Bar overlay
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search department, mess, or block...",
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchFilter = "";
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) {
                setState(() {
                  _searchFilter = val;
                });
              },
            ),
          ),
        ),

        // Bottom Detail Card
        if (selectedPoint != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white,
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(selectedPoint.icon, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(selectedPoint.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1E3A8A))),
                              const Text("Panimalar Engineering College Campus", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() {
                              _selectedNavPointName = "";
                              _campusRoute = null;
                            });
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 14, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          "Coords: ${selectedPoint.coords.latitude.toStringAsFixed(6)}, ${selectedPoint.coords.longitude.toStringAsFixed(6)}",
                          style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (filteredPoints.isNotEmpty && _searchFilter.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: filteredPoints.length,
                itemBuilder: (ctx, idx) {
                  final cp = filteredPoints[idx];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedNavPointName = cp.name;
                      });
                    },
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(cp.icon, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(cp.name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
      ],
    );
  }

  Widget _buildProfileTab() {
    final TextEditingController nameCtrl = TextEditingController(text: _studentName);
    final TextEditingController deptCtrl = TextEditingController(text: _studentDept);
    String tempYear = _studentYear;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF2563EB), width: 3),
                  ),
                  child: const Center(child: Text("🎓", style: TextStyle(fontSize: 54))),
                ),
                const SizedBox(height: 12),
                Text(
                  _studentName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Text(
                  "Panimalar Smart Transit Account",
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("STUDENT DETAILS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
                const SizedBox(height: 16),

                const Text("FULL NAME", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                const Text("YEAR OF STUDY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: tempYear,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: "1st Year", child: Text("1st Year")),
                    DropdownMenuItem(value: "2nd Year", child: Text("2nd Year")),
                    DropdownMenuItem(value: "3rd Year", child: Text("3rd Year")),
                    DropdownMenuItem(value: "4th Year", child: Text("4th Year")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      tempYear = val;
                    }
                  },
                ),
                const SizedBox(height: 16),

                const Text("DEPARTMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                TextField(
                  controller: deptCtrl,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () {
                    _saveProfile(nameCtrl.text.trim(), tempYear, deptCtrl.text.trim());
                  },
                  child: const Text("💾 Save Profile", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                const Text("BUS PICKUP AUTHORIZATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A), letterSpacing: 0.8)),
                const SizedBox(height: 10),
                _buildPickupRequestCard(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: widget.onSwitchRole,
                  child: const Text("🔄 Switch to Driver Mode", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPickupRequestCard() {
    if (_pickupRequestStatus == "none") {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "You need a confirmed letter request to board the bus. Please upload your permission letter (Image/PDF) for Admin approval.",
              style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _showSimulatedFilePicker,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text("Select & Upload Letter", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    Color badgeColor;
    Color textColor;
    String statusText;
    IconData statusIcon;

    if (_pickupRequestStatus == "confirmed") {
      badgeColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF15803D);
      statusText = "APPROVED / CONFIRMED";
      statusIcon = Icons.check_circle;
    } else if (_pickupRequestStatus == "rejected") {
      badgeColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFB91C1C);
      statusText = "REJECTED BY ADMIN";
      statusIcon = Icons.cancel;
    } else {
      badgeColor = const Color(0xFFFEF9C3);
      textColor = const Color(0xFFA16207);
      statusText = "PENDING ADMIN APPROVAL";
      statusIcon = Icons.hourglass_empty;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDBE2F8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.description, color: Color(0xFF64748B), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickupRequestDoc,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text("Attached Document", style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              if (_pickupRequestDocUrl.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.visibility, color: Color(0xFF2563EB)),
                  onPressed: () => _viewUploadedLetter(_pickupRequestDoc, _pickupRequestDocUrl),
                )
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(statusIcon, color: textColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: textColor),
                ),
              ],
            ),
          ),
          if (_pickupRequestStatus == "rejected" || _pickupRequestStatus == "confirmed") ...[
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: _showSimulatedFilePicker,
              child: const Text("Upload Another Document", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF475569))),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showSimulatedFilePicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!mounted) return;
        _uploadPickedFile(file);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("❌ Could not open file picker: $e");
      }
    }
  }

  Future<void> _uploadPickedFile(PlatformFile file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Uploading file...", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );

    try {
      final storageRef = FirebaseStorage.instance.ref().child('pickup_letters/$_studentId/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      
      String downloadUrl = "";
      if (file.path != null) {
        final uploadTask = storageRef.putFile(File(file.path!));
        final snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else if (file.bytes != null) {
        final uploadTask = storageRef.putData(file.bytes!);
        final snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      if (mounted) {
        Navigator.pop(context); // Close dialog
        _sendRequestToAdmin(file.name, downloadUrl);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        _showSnackBar("❌ Upload failed: $e");
      }
    }
  }

  void _sendRequestToAdmin(String fileName, String downloadUrl) async {
    if (Firebase.apps.isEmpty) {
      _showSnackBar("⚠️ Firebase not connected!");
      return;
    }

    try {
      await FirebaseDatabase.instance.ref('pickup_requests/$_studentId').set({
        'studentId': _studentId,
        'studentName': _studentName,
        'studentYear': _studentYear,
        'studentDept': _studentDept,
        'documentName': fileName,
        'documentUrl': downloadUrl,
        'status': 'pending',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'savedStop': _savedStop.isNotEmpty ? _savedStop : "Not Selected",
      });
      _showSnackBar("📨 Request sent to Admin successfully!");
    } catch (e) {
      _showSnackBar("❌ Error sending request: $e");
    }
  }

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
}
