import 'dart:async';
import 'dart:convert';
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
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../models/campus_point.dart';
import '../../models/log_entry.dart';
import '../../models/alert_entry.dart';
import '../../config/routes_config.dart';
import '../../config/lang_config.dart';
import '../../widgets/marquee_notice_bar.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/legend_item.dart';
import '../../services/campus_path_graph.dart';
import 'student_login_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class MainShell extends StatefulWidget {
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const MainShell({super.key, required this.onSwitchRole, required this.currentLang, required this.onLanguageChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  bool _isLoggedIn = false;
  bool _showCreateProfile = false;
  String _studentRollNo = "";

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentRollNo = prefs.getString("studentRollNo") ?? "";
      _isLoggedIn = _studentRollNo.isNotEmpty;
    });
  }

  void _login(String rollNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("studentRollNo", rollNo);
    setState(() {
      _studentRollNo = rollNo;
      _isLoggedIn = true;
    });
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('studentName');
    await prefs.remove('studentYear');
    await prefs.remove('studentRollNo');
    await prefs.remove('profilePicUrl');
    await prefs.remove('studentBusNo');
    
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {}

    setState(() {
      _studentRollNo = "";
      _isLoggedIn = false;
      _showCreateProfile = false;
    });
    
    widget.onSwitchRole();
  }

  @override
  Widget build(BuildContext context) {
    // Always go directly to student dashboard without requiring login
    return StudentDashboard(
      studentRollNo: _studentRollNo,
      onLogout: _logout,
      currentLang: widget.currentLang,
      onLanguageChanged: widget.onLanguageChanged,
      onSwitchRole: widget.onSwitchRole,
    );
  }
}

class StudentDashboard extends StatefulWidget {
  final String studentRollNo;
  final bool isFirstTimeSignup;
  final Function(String)? onFirstTimeSave;
  final VoidCallback onLogout;
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const StudentDashboard({
    super.key,
    required this.studentRollNo,
    this.isFirstTimeSignup = false,
    this.onFirstTimeSave,
    required this.onLogout,
    required this.onSwitchRole,
    required this.currentLang,
    required this.onLanguageChanged,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with TickerProviderStateMixin {
  String t(String key) {
    return appLang[widget.currentLang]?[key] ?? appLang['en']?[key] ?? key;
  }

  int _currentIndex = 0;
  bool _isEditingProfile = false;
  String _profilePicUrl = "";

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
  bool _hasAlertedApproachingRadius = false;
  bool _wasBusOnline = false;
  String _busDirection = 'To College';
  double _alertRadiusMeters = 1000.0;

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

  // Firebase Student Profile & Intercom
  StreamSubscription? _studentProfileSub;
  List<Map<String, dynamic>> _studentIntercomMessages = [];
  StreamSubscription? _studentIntercomSub;
  bool _isRecordingVoice = false;
  int _recordingDurationSecs = 0;
  Timer? _recordingTimer;
  List<double> _recordingWaveforms = [];
  String? _playingMsgId;
  double _playbackProgress = 0.0;
  Timer? _playbackTimer;
  final FlutterTts _flutterTts = FlutterTts();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordPath;

  // Dynamic Route selections
  String _selectedRoute = "route_1"; // default
  List<String> _routeStops = [];
  Map<String, LatLng> _coords = {};

  String _busFirebaseId = '1';
  String get _displayBusId => (_breakdownActive && _replacementBus.isNotEmpty && _replacementBus != 'Unknown') ? _replacementBus : _busFirebaseId;
  Color _routeColor = const Color(0xFF2563EB);
  String _studentBusNo = "";

  // Campus points for navigation
  final List<CampusPoint> _campusPointsList = campusPoints;

  // Campus points search filter
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchFilter = "";
  
  // Route search filter
  final TextEditingController _routeSearchCtrl = TextEditingController();
  String _routeSearchQuery = "";
  String _selectedNavPointName = "";
  Polyline? _campusRoute;
  bool _routeLoading = false;        // true while OSRM fetch is in progress
  double _routeDistanceM = 0;        // actual road distance from OSRM (metres)
  int _routeWalkMinutes = 0;         // estimated walk time from OSRM (minutes)
  double _routeRemainingM = 0;       // remaining distance to destination (metres)
  String _routeError = '';           // last routing error message for UI display
  List<Map<String, dynamic>> _navSteps = []; // turn-by-turn steps (future use)

  // Bus perfectly routed points
  List<LatLng> _busRoutePoints = [];
  bool _busRouteLoading = false;

  // Route cache — prevents unnecessary API calls
  String _cachedRouteDestName = '';  // name of destination when route was last fetched
  double? _cachedFromLat;            // origin lat when route was last fetched
  double? _cachedFromLng;            // origin lng when route was last fetched
  static const double _rerouteThresholdM = 30.0; // reroute only after moving 30 m

  // Student's own GPS location (for campus navigation)
  double? _studentLat;
  double? _studentLng;
  StreamSubscription<Position>? _studentLocationSub;
  bool _studentLocationDenied = false;

  // ── Profile tab controllers — declared at state level so they survive rebuilds
  late final TextEditingController _profileRollNoCtrl;
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _profileBusCtrl;   // bus number input
  String _profileTempYear = '';   // tracks dropdown selection before saving

  // --- Dynamic Route Fetching State ---
  String? _fetchedRouteKey;
  bool _isFetchingRoute = false;
  Timer? _debounceTimer;

  void _fetchRouteForBus(String busNumber) async {
    final bus = busNumber.trim().toUpperCase();
    if (bus.isEmpty) {
      setState(() {
        _fetchedRouteKey = null;
        _isFetchingRoute = false;
      });
      return;
    }

    setState(() {
      _isFetchingRoute = true;
      _fetchedRouteKey = null;
    });

    try {
      if (Firebase.apps.isNotEmpty) {
        final snap = await FirebaseDatabase.instance
            .ref('drivers')
            .orderByChild('bus')
            .equalTo(bus)
            .get();
        if (snap.exists) {
          final data = snap.value as Map<dynamic, dynamic>;
          final firstDriver = data.values.first as Map<dynamic, dynamic>;
          final route = firstDriver['route'] as String?;
          if (mounted) {
            setState(() {
              _fetchedRouteKey = route;
              _isFetchingRoute = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _fetchedRouteKey = null;
              _isFetchingRoute = false;
            });
          }
        }
      } else {
        if (mounted) setState(() => _isFetchingRoute = false);
      }
    } catch (e) {
      debugPrint("Error fetching route for bus $bus: $e");
      if (mounted) setState(() => _isFetchingRoute = false);
    }
  }

  /// Returns the stops list for the bus number the student typed, or empty.
  List<String> get _profileBusStops {
    final key = _fetchedRouteKey;
    if (key == null) return [];
    return List<String>.from(routeStopsConfig[key] ?? []);
  }
  List<Map<String, dynamic>> _adminNotifications = [];
  int _unreadNotifCount = 0;
  StreamSubscription? _notifSub;

  // Real-time bus arrivals log feed
  List<LogEntry> _arrivalLogs = [];
  StreamSubscription? _logsSub;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Profile controllers — empty initially; populated after prefs load
    _profileRollNoCtrl = TextEditingController();
    _profileNameCtrl = TextEditingController();
    
    if (widget.isFirstTimeSignup) {
      _currentIndex = 3;
      _isEditingProfile = true;
    }
    _profileBusCtrl  = TextEditingController();
    _profileTempYear = '';
    _loadPreferences();
    _startLerpLoop();
    _listenForArrivalLogs();
    _startStudentLocationTracking();
    _listenForAdminNotifications();
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
    _studentLocationSub?.cancel();
    _notifSub?.cancel();
    _studentProfileSub?.cancel();
    _studentIntercomSub?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _profileRollNoCtrl.dispose();
    _profileNameCtrl.dispose();
    _profileBusCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Requests GPS permission and starts a continuous location stream.
  /// Updates [_studentLat]/[_studentLng] on every significant movement.
  /// Only triggers a new OSRM route fetch when the user moves > [_rerouteThresholdM].
  void _startStudentLocationTracking() async {
    try {
      // ── 1. Check service enabled ──────────────────────────────────────────
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() {
          _studentLocationDenied = true;
          _routeError = 'GPS is disabled. Enable location in Settings.';
        });
        return;
      }

      // ── 2. Request permission ─────────────────────────────────────────────
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() {
          _studentLocationDenied = true;
          _routeError = permission == LocationPermission.deniedForever
              ? 'Location permission permanently denied. Enable in app settings.'
              : 'Location permission denied.';
        });
        return;
      }

      // ── 3. Get immediate first fix ────────────────────────────────────────
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (mounted) {
          setState(() {
            _studentLat = pos.latitude;
            _studentLng = pos.longitude;
            _routeError = '';
          });
        }
      } catch (_) { /* first fix failed — stream will recover */ }

      // ── 4. Continuous stream (update every 3 m for smooth dot movement) ──
      _studentLocationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // dot moves every 3 m
        ),
      ).listen((pos) {
        if (!mounted) return;
        final newLat = pos.latitude;
        final newLng = pos.longitude;

        // Only reroute when user has moved > threshold AND a destination is set
        bool needsReroute = false;
        if (_selectedNavPointName.isNotEmpty &&
            _cachedFromLat != null && _cachedFromLng != null) {
          final movedM = _haversineM(
              _cachedFromLat!, _cachedFromLng!, newLat, newLng);
          needsReroute = movedM > _rerouteThresholdM;
        } else if (_selectedNavPointName.isNotEmpty) {
          // No cached origin yet — fetch immediately
          needsReroute = true;
        }

        setState(() {
          _studentLat = newLat;
          _studentLng = newLng;
          _routeError = '';
          // Update remaining distance from current position
          if (_selectedNavPointName.isNotEmpty) {
            try {
              final dest = _campusPointsList
                  .firstWhere((p) => p.name == _selectedNavPointName);
              _routeRemainingM = _haversineM(
                  newLat, newLng,
                  dest.coords.latitude, dest.coords.longitude);
            } catch (_) {}
          }
        });

        if (needsReroute) _updateCampusRoute();
      }, onError: (e) {
        if (mounted) setState(() => _routeError = 'Location stream error: $e');
      });
    } catch (e) {
      debugPrint("Student location error: $e");
      if (mounted) setState(() {
        _studentLocationDenied = true;
        _routeError = 'Could not start location tracking.';
      });
    }
  }

  /// Fetches the exact road-following route from OSRM using the device's internet.
  /// OSRM foot-profile uses OSM road data — the same roads visible on the map tile.
  /// Falls back to the local graph if the network call fails.
  Future<void> _updateCampusRoute() async {
    if (_selectedNavPointName.isEmpty) {
      setState(() => _campusRoute = null);
      return;
    }
    CampusPoint dest;
    try {
      dest = _campusPointsList.firstWhere((p) => p.name == _selectedNavPointName);
    } catch (_) {
      setState(() { _campusRoute = null; _routeError = 'Invalid destination.'; });
      return;
    }
    if (_studentLat == null || _studentLng == null) {
      setState(() { _campusRoute = null; _routeError = 'Waiting for GPS fix…'; });
      return;
    }

    // Cache check
    if (_cachedRouteDestName == _selectedNavPointName &&
        _cachedFromLat != null && _cachedFromLng != null) {
      final movedM = _haversineM(
          _cachedFromLat!, _cachedFromLng!, _studentLat!, _studentLng!);
      if (movedM < _rerouteThresholdM) return;
    }

    setState(() { _routeLoading = true; _routeError = ''; });

    // Straight-line fallback values
    List<LatLng> points = [LatLng(_studentLat!, _studentLng!), dest.coords];
    double distM = _haversineM(_studentLat!, _studentLng!,
        dest.coords.latitude, dest.coords.longitude);
    int walkMin = max(1, (distM / 70).ceil());

    try {
      // OSRM public foot-profile — runs on device, reaches internet fine
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/'
        '${_studentLng!},${_studentLat!};'
        '${dest.coords.longitude},${dest.coords.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok') {
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final route = routes[0] as Map<String, dynamic>;
            final allCoords = (route['geometry']['coordinates'] as List)
                .map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();

            // ── Keep only waypoints inside the campus boundary ─────────────
            // Campus bounding box (with small margin):
            // lat: 13.0468 – 13.0552, lng: 80.0722 – 80.0772
            const minLat = 13.0468, maxLat = 13.0552;
            const minLng = 80.0722, maxLng = 80.0772;

            bool inCampus(LatLng p) =>
                p.latitude  >= minLat && p.latitude  <= maxLat &&
                p.longitude >= minLng && p.longitude <= maxLng;

            // Find the longest contiguous sub-sequence inside campus
            // that connects origin side to destination side.
            final inside = allCoords.where(inCampus).toList();

            // Always include real origin and destination endpoints
            final clipped = <LatLng>[LatLng(_studentLat!, _studentLng!)];
            clipped.addAll(inside);
            clipped.add(dest.coords);

            if (clipped.length >= 2) {
              points  = clipped;
              // Recompute distance along clipped path
              distM = 0;
              for (int i = 0; i < clipped.length - 1; i++) {
                distM += _haversineM(clipped[i].latitude, clipped[i].longitude,
                    clipped[i+1].latitude, clipped[i+1].longitude);
              }
              final dur = ((route['duration'] as num?)?.toDouble()) ?? 0;
              walkMin = dur > 0 ? max(1, (dur / 60).ceil())
                                : max(1, (distM / 70).ceil());
            }
          }
        }
      }
    } catch (_) {
      // Network unavailable — fall back to local graph
      final origin = LatLng(_studentLat!, _studentLng!);
      points = campusPathGraph.shortestPath(origin, dest.coords, destName: dest.name);
      distM  = campusPathGraph.pathDistanceM(points);
      walkMin = max(1, (distM / 70).ceil());
      setState(() => _routeError = 'Offline — using campus road estimate');
    }

    _cachedRouteDestName = _selectedNavPointName;
    _cachedFromLat = _studentLat;
    _cachedFromLng = _studentLng;

    setState(() {
      _campusRoute = Polyline(
        points: points,
        color: const Color(0xFF2563EB),
        strokeWidth: 5.0,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        borderColor: Colors.white,
        borderStrokeWidth: 2.0,
      );
      _routeDistanceM   = distM;
      _routeWalkMinutes = walkMin;
      _routeRemainingM  = _haversineM(_studentLat!, _studentLng!,
          dest.coords.latitude, dest.coords.longitude);
      _navSteps    = [];
      _routeLoading = false;
    });
  }

  /// Haversine distance in metres between two lat/lng pairs.
  double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final phi1 = lat1 * (pi / 180);
    final phi2 = lat2 * (pi / 180);
    final dPhi = (lat2 - lat1) * (pi / 180);
    final dLambda = (lng2 - lng1) * (pi / 180);
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Straight-line distance (metres) from student GPS to a [CampusPoint].
  double _distanceTo(CampusPoint cp) {
    if (_studentLat == null || _studentLng == null) return 0.0;
    return _haversineM(
        _studentLat!, _studentLng!, cp.coords.latitude, cp.coords.longitude);
  }

  /// Clears cached route — called when destination changes so a fresh fetch runs.
  void _clearRouteCache() {
    _cachedRouteDestName = '';
    _cachedFromLat = null;
    _cachedFromLng = null;
  }

  void _listenForAdminNotifications() {
    _notifSub?.cancel();
    if (Firebase.apps.isEmpty) return;
    try {
      _notifSub = FirebaseDatabase.instance
          .ref('student_notifications')
          .onValue
          .listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> loaded = [];
        if (data != null) {
          data.forEach((key, val) {
            if (val is Map) {
              loaded.add({
                'id': key.toString(),
                'type': val['type']?.toString() ?? 'info',
                'title': val['title']?.toString() ?? '',
                'msg': val['msg']?.toString() ?? '',
                'bus': val['bus']?.toString() ?? 'all',
                'time': val['time']?.toString() ?? '',
                'read': val['read'] == true,
              });
            }
          });
        }
        // Sort newest first
        loaded.sort((a, b) => b['id'].compareTo(a['id']));
        if (!mounted) return;
        setState(() {
          _adminNotifications = loaded;
          _unreadNotifCount = loaded.where((n) => n['read'] != true).length;
        });
      });
    } catch (e) {
      debugPrint("Notification listener error: $e");
    }
  }

  void _markAllNotificationsRead() {
    if (Firebase.apps.isEmpty) return;
    for (final n in _adminNotifications) {
      if (n['read'] != true) {
        FirebaseDatabase.instance
            .ref('student_notifications/${n['id']}/read')
            .set(true);
      }
    }
    setState(() {
      for (final n in _adminNotifications) {
        n['read'] = true;
      }
      _unreadNotifCount = 0;
    });
  }

  void _showNotificationsPanel() {
    _markAllNotificationsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_rounded,
                        color: Color(0xFF2563EB), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Notifications",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (_adminNotifications.isNotEmpty)
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Close",
                            style: TextStyle(color: Color(0xFF64748B))),
                      ),
                  ],
                ),
              ),
              // Category legend chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _notifChip("🚌", "Delay", "delay"),
                    _notifChip("⚠️", "Emergency", "emergency"),
                    _notifChip("🔀", "Route Change", "route_change"),
                    _notifChip("🛎️", "Arrival", "arrival"),
                    _notifChip("🔧", "Breakdown", "breakdown"),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Notifications list
               Expanded(
                child: (!_breakdownActive && _adminNotifications.isEmpty)
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("🔔", style: TextStyle(fontSize: 48)),
                            SizedBox(height: 12),
                            Text(
                              "No notifications yet",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Admin alerts will appear here",
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          if (_breakdownActive) ...[
                            _buildStudentBreakdownNotifTile(ctx),
                            const SizedBox(height: 8),
                          ],
                          ..._adminNotifications.map((n) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildNotifTile(n),
                              const Divider(height: 1, indent: 56),
                            ],
                          )),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentBreakdownNotifTile(BuildContext sheetCtx) {
    final breakdownBusId = _busFirebaseId;
    final msg = _replacementBus == "Pending"
        ? "Bus $breakdownBusId breakdown reported. Replacement Bus dispatch is pending. Stay at your stop."
        : "Bus $breakdownBusId breakdown. Replacement Bus $_replacementBus dispatched. Stay at your stop.";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text("🔧", style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Vehicle Breakdown Alert",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    Text(
                      "Live",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  msg,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7F1D1D),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, color: Color(0xFF991B1B), size: 18),
            onPressed: () {
              if (Firebase.apps.isNotEmpty) {
                FirebaseDatabase.instance.ref('breakdowns/$breakdownBusId').remove();
              }
              Navigator.pop(sheetCtx);
              _showSnackBar("Breakdown alert dismissed.");
            },
          ),
        ],
      ),
    );
  }

  Widget _notifChip(String emoji, String label, String type) {
    final config = _notifTypeConfig(type);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: config['bg'] as Color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (config['color'] as Color).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: config['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifTile(Map<String, dynamic> n) {
    final config = _notifTypeConfig(n['type'] as String);
    final isUnread = n['read'] != true;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isUnread
            ? (config['bg'] as Color).withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: config['bg'] as Color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                config['icon'] as String,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n['title'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Text(
                      n['time'] as String,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF94A3B8)),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: config['color'] as Color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ]
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  n['msg'] as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                if ((n['bus'] as String) != 'all') ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Bus ${n['bus']}",
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _notifTypeConfig(String type) {
    switch (type) {
      case 'delay':
        return {'icon': '🚌', 'color': const Color(0xFFF59E0B), 'bg': const Color(0xFFFFFBEB)};
      case 'emergency':
        return {'icon': '🚨', 'color': const Color(0xFFDC2626), 'bg': const Color(0xFFFEF2F2)};
      case 'route_change':
        return {'icon': '🔀', 'color': const Color(0xFF7C3AED), 'bg': const Color(0xFFF5F3FF)};
      case 'arrival':
        return {'icon': '🛎️', 'color': const Color(0xFF16A34A), 'bg': const Color(0xFFF0FDF4)};
      case 'breakdown':
        return {'icon': '🔧', 'color': const Color(0xFFEA580C), 'bg': const Color(0xFFFFF7ED)};
      default:
        return {'icon': '🔔', 'color': const Color(0xFF2563EB), 'bg': const Color(0xFFEFF6FF)};
    }
  }

  void _loadPreferences() async {
    try {
      final auth = FirebaseAuth.instance;
      User? currentUser = auth.currentUser;
      if (currentUser == null) {
        final userCredential = await auth.signInAnonymously();
        currentUser = userCredential.user;
      }
    } catch (e) {
      debugPrint("Error with firebase auth: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('studentName') ?? "Student Name";
      _studentYear = prefs.getString('studentYear') ?? "3rd Year";
      _studentDept = prefs.getString('studentDept') ?? "Computer Science (CSE)";
      _profilePicUrl = prefs.getString('profilePicUrl') ?? "";
      _studentBusNo = prefs.getString('studentBusNo') ?? "";
      _savedStop = prefs.getString('studentSavedStop') ?? "";
      _studentId = widget.studentRollNo;
      _profileNameCtrl.text = _studentName;
      _profileTempYear = _studentYear;
      _profileBusCtrl.text = _studentBusNo;
    });

    try {
      final response = await http.get(Uri.parse('https://panimalr-bus.onrender.com/api/students/${widget.studentRollNo}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _studentName = data['name'] ?? _studentName;
            _studentYear = data['year'] ?? _studentYear;
            _studentDept = data['department'] ?? _studentDept;
            _profileBusCtrl.text = data['busNo'] ?? _profileBusCtrl.text;
            _studentBusNo = data['busNo'] ?? _studentBusNo;
            _savedStop = data['boardingStop'] ?? _savedStop;
            if (data['profilePicBase64'] != null && data['profilePicBase64'].isNotEmpty) {
              _profilePicUrl = data['profilePicBase64'];
            }
          });
        }
      } else {
         if (mounted) setState(() { _isEditingProfile = true; });
      }
    } catch (e) {
      debugPrint("Failed to fetch profile from MongoDB: $e");
    }

    _updateRouteDetails(_selectedRoute, startListener: false);
    _startPickupRequestListener();
    _startFirebaseListener();
    _listenForStudentIntercomMessages();
  }

  void _updateRouteDetails(String routeKey, {bool startListener = true}) {
    _routeStops = routeStopsConfig[routeKey] ?? [];
    _coords = {};
    for (var stop in _routeStops) {
      if (coordsConfig.containsKey(stop)) {
        _coords[stop] = coordsConfig[stop]!;
      }
    }

    final match = RegExp(r'route_(\d+)').firstMatch(routeKey);
    if (match != null) {
      _busFirebaseId = match.group(1)!;
    } else {
      _busFirebaseId = routeKey;
    }

    _routeColor = const Color(0xFF2563EB);
    try {
      if (routeColorsConfig.containsKey(routeKey)) {
         _routeColor = Color(int.parse(routeColorsConfig[routeKey]!.replaceFirst('#', '0xFF')));
      }
    } catch (_) {}

    if (startListener) {
      _startFirebaseListener();
    }
    
    _fetchBusOsrmRoute();
  }

  Future<void> _fetchBusOsrmRoute() async {
    if (_routeStops.length < 2) {
      setState(() => _busRoutePoints = []);
      return;
    }
    if (!mounted) return;
    setState(() => _busRouteLoading = true);

    try {
      final coordsList = <String>[];
      for (var stop in _routeStops) {
        final coord = _coords[stop];
        if (coord != null) {
          coordsList.add('${coord.longitude.toStringAsFixed(6)},${coord.latitude.toStringAsFixed(6)}');
        }
      }

      if (coordsList.length < 2) {
        setState(() => _busRouteLoading = false);
        return;
      }

      final coords = coordsList.join(';');
      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/$coords'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = json['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List?;
          if (coordinates != null) {
            final points = coordinates.map((c) {
              final lng = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();
            if (mounted) {
              setState(() {
                _busRoutePoints = points;
                _busRouteLoading = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM bus route fetch error: $e');
    }

    if (mounted) {
      setState(() {
        _busRoutePoints = _routeStops.map((s) => _coords[s]).whereType<LatLng>().toList();
        _busRouteLoading = false;
      });
    }
  }

  void _changeSelectedRoute(String routeKey) async {
    setState(() {
      _selectedRoute = routeKey;
      _savedStop = "";
      _updateRouteDetails(routeKey, startListener: true);
      _hasAlertedApproaching = false;
      _hasAlertedArrived = false;
    });
    if (Firebase.apps.isNotEmpty) {
      await FirebaseDatabase.instance.ref('students/$_studentId').update({
        'selectedRoute': routeKey,
        'savedStop': '',
      });
    }
    _showSnackBar("Route switched to ${routeLabelsConfig[routeKey]}");
  }

  void _saveStop(String stopName) async {
    setState(() {
      _savedStop = stopName;
      _hasAlertedApproaching = false;
      _hasAlertedArrived = false;
    });
    if (Firebase.apps.isNotEmpty) {
      await FirebaseDatabase.instance.ref('students/$_studentId').update({
        'savedStop': stopName,
      });
    }
    _showSnackBar("⭐ Boarding stop saved: $stopName");
  }

  void _saveProfile(String name, String year, String dept,
      {String busNo = '', String boardingStop = '', String rollNo = ''}) async {
      
    final actualRollNo = rollNo.isNotEmpty ? rollNo : widget.studentRollNo;
    if (actualRollNo.trim().isEmpty) {
      _showSnackBar("Roll No is required");
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentName', name);
    await prefs.setString('studentYear', year);
    await prefs.setString('studentDept', dept);
    await prefs.setString('profilePicUrl', _profilePicUrl);
    await prefs.setString('studentBusNo', busNo);
    await prefs.setString('studentSavedStop', boardingStop);
    
    try {
      final response = await http.post(
        Uri.parse('https://panimalr-bus.onrender.com/api/students/${actualRollNo}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'year': year,
          'department': dept,
          'busNo': busNo,
          'boardingStop': boardingStop,
          'profilePicBase64': _profilePicUrl.startsWith('base64:') ? _profilePicUrl : '',
        }),
      );
      if (response.statusCode != 200) {
        _showSnackBar("Warning: Failed to save to MongoDB");
      }
    } catch (e) {
      _showSnackBar("Warning: Network error saving to MongoDB");
    }

    setState(() {
      _studentName = name;
      _studentYear = year;
      _studentDept = dept;
      _studentBusNo = busNo;
      _savedStop = boardingStop;
      
      
      if (busNo.isNotEmpty) {
        // Fetch the route async and update later if needed, but since we are saving,
        // _fetchedRouteKey should have been fetched already.
        if (_fetchedRouteKey != null) {
          _selectedRoute = _fetchedRouteKey!;
          _updateRouteDetails(_selectedRoute, startListener: true);
        } else {
          // If for some reason it's not fetched but we save, just fallback to query
          if (Firebase.apps.isNotEmpty) {
            FirebaseDatabase.instance.ref('drivers').orderByChild('bus').equalTo(busNo.trim().toUpperCase()).get().then((snap) {
               if (snap.exists) {
                  final data = snap.value as Map<dynamic, dynamic>;
                  final route = data.values.first['route'] as String?;
                  if (route != null && mounted) {
                     setState(() {
                        _selectedRoute = route;
                        _updateRouteDetails(_selectedRoute, startListener: true);
                     });
                  }
               }
            });
          }
        }
      }
      
      if (widget.isFirstTimeSignup) {
         _currentIndex = 0;
      }
      _isEditingProfile = false;
    });
    
    if (widget.isFirstTimeSignup && widget.onFirstTimeSave != null) {
      widget.onFirstTimeSave!(actualRollNo);
    }
    
    _showSnackBar("✅ Profile saved successfully");
  }

  Future<void> _uploadProfilePhoto() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null) {
        final file = result.files.single;
        if (file.bytes != null || file.path != null) {
          _showSnackBar("Processing profile photo...");
          
          Uint8List? imageBytes = file.bytes;
          if (imageBytes == null && file.path != null) {
            imageBytes = await File(file.path!).readAsBytes();
          }
          
          if (imageBytes != null) {
            final base64String = base64Encode(imageBytes);
            setState(() {
              _profilePicUrl = 'base64:' + base64String;
            });
            _showSnackBar("Profile photo attached! Don't forget to save!");
          }
        }
      }
    } catch (e) {
      _showSnackBar("Failed to pick/process image: $e");
    }
  }

  void _listenForStudentIntercomMessages() {
    _studentIntercomSub?.cancel();
    if (Firebase.apps.isEmpty || _studentId.isEmpty) return;
    try {
      _studentIntercomSub = FirebaseDatabase.instance.ref('voice_messages/student_$_studentId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> temp = [];
        if (data != null) {
          data.forEach((key, val) {
            if (val is Map) {
              temp.add({
                'id': key.toString(),
                'sender': val['sender'] ?? 'unknown',
                'timestamp': val['timestamp'] ?? 0,
                'msg': val['msg'] ?? '',
                'senderName': val['senderName'] ?? '',
                'isVoice': val['isVoice'] ?? false,
                'voiceDuration': val['voiceDuration'] ?? 0,
                'transcript': val['transcript'] ?? '',
              });
            }
          });
          temp.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
        }
        if (mounted) {
          setState(() {
            _studentIntercomMessages = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to intercom: $e");
    }
  }

  void _sendStudentTextMessage(String text) async {
    if (Firebase.apps.isEmpty || _studentId.isEmpty) return;
    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseDatabase.instance.ref('voice_messages/student_$_studentId/$msgId').set({
        'sender': 'student',
        'senderName': _studentName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'msg': text,
      });
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  void _startRecordingVoice() async {
    if (await _audioRecorder.hasPermission()) {
      if (kIsWeb) {
        await _audioRecorder.start(const RecordConfig(), path: '');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        _recordPath = '${dir.path}/voice_message.m4a';
        await _audioRecorder.start(const RecordConfig(), path: _recordPath!);
      }
      setState(() {
        _isRecordingVoice = true;
        _recordingDurationSecs = 0;
        _recordingWaveforms = [];
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDurationSecs++;
            final rand = Random();
            _recordingWaveforms.add(5.0 + rand.nextDouble() * 30.0);
          });
        }
      });
    }
  }

  void _stopAndSendRecordingVoice() async {
    _recordingTimer?.cancel();
    if (!_isRecordingVoice) return;
    
    final path = await _audioRecorder.stop();
    final duration = _recordingDurationSecs == 0 ? 3 : _recordingDurationSecs;
    setState(() {
      _isRecordingVoice = false;
    });

    if (path != null && Firebase.apps.isNotEmpty && _studentId.isNotEmpty) {
      try {
        Uint8List bytes;
        if (kIsWeb) {
          final res = await http.get(Uri.parse(path));
          bytes = res.bodyBytes;
        } else {
          bytes = await File(path).readAsBytes();
        }
        final base64Audio = base64Encode(bytes);
        
        final String apiUrl = kIsWeb ? 'https://panimalr-bus.onrender.com/api/voice' : 'https://panimalr-bus.onrender.com/api/voice';
        
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sender': 'student_$_studentId',
            'receiver': 'admin',
            'audioBase64': base64Audio,
            'duration': duration,
          }),
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final mongoId = data['id'];
          
          final msgId = DateTime.now().millisecondsSinceEpoch.toString();
          await FirebaseDatabase.instance.ref('voice_messages/student_$_studentId/$msgId').set({
            'sender': 'student',
            'senderName': _studentName,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'msg': '[Voice Message - 0:${duration.toString().padLeft(2, '0')}] "$mongoId"',
            'isVoice': true,
            'voiceDuration': duration,
            'mongoId': mongoId,
          });
        }
      } catch (e) {
        debugPrint("Error sending voice message: $e");
      }
    }
  }

  void _cancelRecordingVoice() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _isRecordingVoice = false;
      _recordingDurationSecs = 0;
    });
    _showSnackBar("Recording cancelled.");
  }

  void _playVoiceMessage(String msgId, String text, int durationSecs) async {
    if (_playingMsgId == msgId) {
      _playbackTimer?.cancel();
      await _audioPlayer.stop();
      setState(() {
        _playingMsgId = null;
      });
      return;
    }
    _playbackTimer?.cancel();
    await _audioPlayer.stop();

    String mongoId = "";
    if (text.startsWith('[Voice Message')) {
      final index = text.indexOf(']');
      if (index != -1 && index + 1 < text.length) {
        mongoId = text.substring(index + 1).replaceAll('"', '').trim();
      }
    }
    
    if (mongoId.isNotEmpty) {
      try {
        final String apiUrl = kIsWeb ? 'https://panimalr-bus.onrender.com/api/voice/$mongoId' : 'https://panimalr-bus.onrender.com/api/voice/$mongoId';
        final response = await http.get(Uri.parse(apiUrl));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final audioBytes = base64Decode(data['audioBase64']);
          await _audioPlayer.play(BytesSource(audioBytes));
        }
      } catch (e) {
        debugPrint("Error playing audio: $e");
      }
    }

    setState(() {
      _playingMsgId = msgId;
      _playbackProgress = 0.0;
    });
    
    final int totalSteps = durationSecs * 10;
    int currentStep = 0;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      currentStep++;
      if (mounted) {
        setState(() {
          _playbackProgress = currentStep / totalSteps;
        });
      }
      if (currentStep >= totalSteps) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _playingMsgId = null;
            _playbackProgress = 0.0;
          });
        }
      }
    });
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
    
    void startLocationTracker(String targetBusId) {
      _locationSub?.cancel();
      _locationSub = FirebaseDatabase.instance.ref('liveLocations/$targetBusId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data == null || data['status'] == 'offline') {
          setState(() {
            _wasBusOnline = false;
            _busIsOnline = false;
            _busStatus = "offline";
            _hasAlertedApproachingRadius = false;
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
          _busDirection = data['direction'] as String? ?? "To College";

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
            "🚌 Bus $targetBusId is Ready!",
            "The bus has started its route. Live GPS tracking is now active. Get ready to board!",
            "✅",
            durationMs: 10000,
          );
        }

        if (_savedStop.isNotEmpty && _busLat != null && _busLng != null) {
          final nearestIdx = _getNearestStopIndex(_busLat!, _busLng!);
          final displayStops = _busDirection == 'To Home' ? _routeStops.reversed.toList() : _routeStops;
          final myStopIdx = displayStops.indexOf(_savedStop);
          final logicalNearestIdx = displayStops.indexOf(_routeStops[nearestIdx]);

          if (logicalNearestIdx == 0) {
            _hasAlertedApproaching = false;
            _hasAlertedArrived = false;
          }

          if (myStopIdx != -1) {
            if (logicalNearestIdx == myStopIdx - 1 && !_hasAlertedApproaching) {
              _hasAlertedApproaching = true;
              _showInAppNotification(
                "Bus $targetBusId is approaching!",
                "Bus $targetBusId is at ${displayStops[logicalNearestIdx]}, which is 1 stop away from $_savedStop.",
                "🔔",
              );
            } else if (logicalNearestIdx == myStopIdx && !_hasAlertedArrived) {
              _hasAlertedArrived = true;
              _showInAppNotification(
                "Bus $targetBusId has arrived!",
                "Bus $targetBusId is now at your boarding stop: $_savedStop. Get ready to board!",
                "🚏",
              );
            }
          }

          // Proximity Radius Alert
          final stopCoords = _coords[_savedStop];
          if (stopCoords != null) {
            double distanceMeters = _haversineM(_busLat!, _busLng!, stopCoords.latitude, stopCoords.longitude);
            if (distanceMeters <= _alertRadiusMeters && !_hasAlertedApproachingRadius) {
              _hasAlertedApproachingRadius = true;
              _showInAppNotification(
                "Bus is approaching!",
                "The bus is within ${(_alertRadiusMeters/1000).toStringAsFixed(1)}km of your stop. Be ready!",
                "🔔",
              );
            } else if (distanceMeters > _alertRadiusMeters) {
              _hasAlertedApproachingRadius = false;
            }
          }
        }
      }, onError: (e) {
        debugPrint("Database listen error: $e");
      });
    }

    try {
      startLocationTracker(_busFirebaseId);

      _breakdownSub = FirebaseDatabase.instance.ref('breakdowns/$_busFirebaseId').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data == null) {
          setState(() {
            _breakdownActive = false;
            _replacementBus = "";
          });
          startLocationTracker(_busFirebaseId);
          return;
        }
        setState(() {
          _breakdownActive = true;
          _replacementBus = data['replacement'] as String? ?? "Unknown";
        });
        
        if (_replacementBus.isNotEmpty && _replacementBus != "Unknown") {
          startLocationTracker(_replacementBus);
        } else {
          startLocationTracker(_busFirebaseId);
        }
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
    
    final displayStops = _busDirection == 'To Home' ? _routeStops.reversed.toList() : _routeStops;
    final myStopIdx = displayStops.indexOf(_savedStop);
    final logicalNearestIdx = displayStops.indexOf(_routeStops[nearestIdx]);

    if (myStopIdx == -1 || logicalNearestIdx > myStopIdx) return null;

    double totalDist = 0.0;
    double currentLat = _busLat!;
    double currentLng = _busLng!;

    for (int i = logicalNearestIdx; i <= myStopIdx; i++) {
      final stopName = displayStops[i];
      final stopCoord = _coords[stopName];
      if (stopCoord != null) {
        totalDist += _haversineKm(currentLat, currentLng, stopCoord.latitude, stopCoord.longitude);
        currentLat = stopCoord.latitude;
        currentLng = stopCoord.longitude;
      }
    }

    final intermediateStops = myStopIdx - logicalNearestIdx;
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
    // Only show when bus GPS is actively connected — hide completely otherwise
    if (!_busIsOnline) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFFF0FDF4),
        border: Border(bottom: BorderSide(color: Color(0xFFE8EDF8))),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF15803D),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Firebase connected — live GPS data",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF15803D),
              ),
            ),
          ),
          Text(
            _busUpdatedAt,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF15803D),
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
                    if (Firebase.apps.isNotEmpty) {
                      FirebaseDatabase.instance.ref('students/$_studentId').update({'savedStop': ''});
                    }
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
                        "PANIMALAR TRANSIT — BUS $_displayBusId",
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
        title: Text(t('Panimalar Transit'), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Exit/Home button - returns to role selection screen
          Tooltip(
            message: 'Go to Home',
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Row(
                      children: [
                        Icon(Icons.home_rounded, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Text('Go to Home', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ],
                    ),
                    content: const Text(
                      'Are you sure you want to exit the student portal and go back to the home screen?',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onSwitchRole();
                        },
                        child: const Text('Yes, Go Home'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
              ),
            ),
          ),
          // Notification button with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_rounded, color: Colors.black54),
                onPressed: _showNotificationsPanel,
              ),
              if (_unreadNotifCount > 0)
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
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      '$_unreadNotifCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
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
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.home, color: Color(0xFF2563EB)), label: t('student_home')),
            NavigationDestination(icon: const Icon(Icons.map_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.map, color: Color(0xFF2563EB)), label: t('student_live_track')),
            NavigationDestination(icon: const Icon(Icons.domain_outlined, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.domain, color: Color(0xFF2563EB)), label: t('student_campus_map')),
            NavigationDestination(icon: const Icon(Icons.person_outline, color: Color(0xFF64748B)), selectedIcon: const Icon(Icons.person, color: Color(0xFF2563EB)), label: t('student_profile')),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final int nearestIdx = (_busLat != null && _busLng != null) ? _getNearestStopIndex(_busLat!, _busLng!) : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);
    final displayStops = _busDirection == 'To Home' ? _routeStops.reversed.toList() : _routeStops;

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                              _busIsOnline ? "Bus $_displayBusId is online" : "Bus $_displayBusId is offline",
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
                _buildVoiceIntercomCard(),
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
                                  if (Firebase.apps.isNotEmpty) {
                                    FirebaseDatabase.instance.ref('students/$_studentId').update({'savedStop': ''});
                                  }
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
                  // Boarding stop set via Profile tab — nothing to show here
                ],
                const SizedBox(height: 20),

                // Dynamic Route select list
                const Text(
                  "Find Your Bus & Route",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 12),
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
                    controller: _routeSearchCtrl,
                    onChanged: (val) => setState(() => _routeSearchQuery = val),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      hintText: "Search bus stop or route no...",
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                      border: InputBorder.none,
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
                const SizedBox(height: 12),
                if (_routeSearchQuery.isNotEmpty)
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Builder(
                      builder: (context) {
                        final query = _routeSearchQuery.toLowerCase();
                        final matches = routeLabelsConfig.keys.where((key) {
                          final label = routeLabelsConfig[key]?.toLowerCase() ?? '';
                          final stops = routeStopsConfig[key] ?? [];
                          final stopsMatch = stops.any((s) => s.toLowerCase().contains(query));
                          return label.contains(query) || stopsMatch;
                        }).toList();
                        if (matches.isEmpty) {
                          return const Center(child: Text("No routes found", style: TextStyle(fontSize: 12, color: Colors.grey)));
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: matches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final key = matches[idx];
                            final label = routeLabelsConfig[key] ?? key;
                            return ListTile(
                              dense: true,
                              title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              trailing: _selectedRoute == key ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : null,
                              onTap: () {
                                _changeSelectedRoute(key);
                                _routeSearchCtrl.clear();
                                setState(() => _routeSearchQuery = "");
                              },
                            );
                          },
                        );
                      }
                    ),
                  ),
                if (_routeSearchQuery.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_bus, size: 18, color: Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Expanded(child: Text("Selected: ${routeLabelsConfig[_selectedRoute] ?? _selectedRoute}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)))),
                      ],
                    ),
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
                      for (int i = 0; i < displayStops.length; i++) ...[
                        _buildStopRow(
                          displayStops[i],
                          isFirst: i == 0,
                          isLast: i == displayStops.length - 1,
                          isMyStop: _savedStop == displayStops[i],
                        ),
                        if (i < displayStops.length - 1) _buildStopConnector(),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    "Showing ${displayStops.length} of ${displayStops.length} stops",
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
            // Background bus image
            Positioned.fill(
              child: Image.asset(
                'assets/images/panimalar_bus2.jpeg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
            // Blue gradient overlay
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
            // ── LIVE badge — top-right, visible only when driver is tracking
            if (_busIsOnline)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Text content overlay
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Firebase connected chip — shown when GPS is active
                  if (_busIsOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            "Firebase connected — live GPS data",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _busUpdatedAt,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // BUS number chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "BUS $_displayBusId",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    t('appTitle'),
                    style: const TextStyle(
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
    // Draw all route stops as dots instead of lines
    for (var stopName in _routeStops) {
      final coord = _coords[stopName];
      if (coord != null && stopName != "COLLEGE" && stopName != "Panimalar Engineering College") {
        markers.add(
          Marker(
            point: coord,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                color: _routeColor.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.location_on, color: Colors.white, size: 14),
            ),
          ),
        );
      }
    }

    if (_busLat != null && _busLng != null) {
      markers.add(
        Marker(
          point: LatLng(_busLat!, _busLng!),
          width: 80,
          height: 80,
          alignment: Alignment.center,
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
                  "Bus $_displayBusId",
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
            
            if (_busRoutePoints.isNotEmpty)
              PolylineLayer(
                polylines: <Polyline<Object>>[
                  Polyline<Object>(
                    points: _busRoutePoints,
                    strokeWidth: 4.0,
                    color: _routeColor.withValues(alpha: 0.7),
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
                    if (Firebase.apps.isNotEmpty) {
                      FirebaseDatabase.instance.ref('students/$_studentId').update({'savedStop': ''});
                    }
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
                          "BUS $_displayBusId DETAILS",
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

    // Campus location markers
    for (var cp in _campusPointsList) {
      final isSelected = cp.name == _selectedNavPointName;
      markers.add(
        Marker(
          point: cp.coords,
          width: 64,
          height: 64,
          child: GestureDetector(
            onTap: () {
              _clearRouteCache(); // destination changed — force fresh fetch
              setState(() {
                _selectedNavPointName = cp.name;
                _searchCtrl.clear();
                _searchFilter = "";
                _routeDistanceM = 0;
                _routeWalkMinutes = 0;
                _routeRemainingM = 0;
                _routeError = '';
              });
              _updateCampusRoute().then((_) {
                if (mounted) {
                  try {
                    final dest = _campusPointsList.firstWhere((p) => p.name == cp.name);
                    _fitMapToRoute(dest);
                  } catch (_) {}
                }
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isSelected ? const Color(0xFF2563EB).withOpacity(0.4) : Colors.black26,
                        blurRadius: isSelected ? 8 : 4,
                      )
                    ],
                    border: Border.all(color: isSelected ? Colors.white : const Color(0xFF2563EB), width: 2),
                  ),
                  child: Text(cp.icon, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300, width: 0.5),
                  ),
                  child: Text(
                    cp.name,
                    style: TextStyle(
                      fontSize: 6,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }

    // Student location marker — blue pulsing dot
    if (_studentLat != null && _studentLng != null) {
      markers.add(
        Marker(
          point: LatLng(_studentLat!, _studentLng!),
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3), width: 1.5),
                ),
              ),
              // Inner solid dot
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.5),
                      blurRadius: 6,
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filteredPoints = _campusPointsList
        .where((p) => p.name.toLowerCase().contains(_searchFilter.toLowerCase()))
        .toList();

    // Use OSRM-computed distance/time if available, else straight-line estimate
    final distanceM = _routeDistanceM > 0 ? _routeDistanceM : (selectedPoint != null ? _distanceTo(selectedPoint) : 0.0);
    final walkMinutes = _routeWalkMinutes > 0 ? _routeWalkMinutes : max(1, (distanceM / 83).ceil());

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
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
                          _clearRouteCache();
                          setState(() {
                            _searchFilter = "";
                            _selectedNavPointName = "";
                            _campusRoute = null;
                            _routeDistanceM = 0;
                            _routeWalkMinutes = 0;
                            _routeRemainingM = 0;
                            _routeError = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) {
                final matches = _campusPointsList
                    .where((p) => p.name.toLowerCase().contains(val.toLowerCase()))
                    .toList();
                final newDest = matches.length == 1 ? matches.first.name : '';
                final destChanged = newDest != _selectedNavPointName && newDest.isNotEmpty;
                if (destChanged) _clearRouteCache();
                setState(() {
                  _searchFilter = val;
                  if (newDest.isNotEmpty) {
                    _selectedNavPointName = newDest;
                    _routeDistanceM = 0;
                    _routeWalkMinutes = 0;
                    _routeRemainingM = 0;
                    _routeError = '';
                  }
                });
                if (_selectedNavPointName.isNotEmpty && destChanged) {
                  _updateCampusRoute().then((_) {
                    if (mounted) {
                      try {
                        final dest = _campusPointsList
                            .firstWhere((p) => p.name == _selectedNavPointName);
                        _fitMapToRoute(dest);
                      } catch (_) {}
                    }
                  });
                }
              },
            ),
          ),
        ),

        // No-location warning chip
        if (_studentLocationDenied || _routeError.isNotEmpty)
          Positioned(
            top: 68,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _routeError.isNotEmpty
                          ? _routeError
                          : 'Location permission denied — enable in Settings',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Navigation info card — shown when a route is active ─────────────
        if (selectedPoint != null && _campusRoute != null && !_routeLoading)
          Positioned(
            top: _studentLocationDenied || _routeError.isNotEmpty ? 116 : 68,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Row(
                children: [
                  // Total distance
                  _navInfoCell(
                    Icons.straighten,
                    'Total',
                    distanceM < 1000
                        ? '${distanceM.round()} m'
                        : '${(distanceM / 1000).toStringAsFixed(1)} km',
                    const Color(0xFF2563EB),
                  ),
                  _navDivider(),
                  // Remaining distance
                  _navInfoCell(
                    Icons.near_me,
                    'Remaining',
                    _routeRemainingM < 1000
                        ? '${_routeRemainingM.round()} m'
                        : '${(_routeRemainingM / 1000).toStringAsFixed(1)} km',
                    const Color(0xFF16A34A),
                  ),
                  _navDivider(),
                  // Walk time
                  _navInfoCell(
                    Icons.directions_walk,
                    'ETA',
                    '$walkMinutes min',
                    const Color(0xFFF59E0B),
                  ),
                  // Steps count (future voice nav indicator)
                  if (_navSteps.isNotEmpty) ...[
                    _navDivider(),
                    _navInfoCell(
                      Icons.turn_right,
                      'Turns',
                      '${_navSteps.length}',
                      const Color(0xFF7C3AED),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Bottom Detail Card — when a destination is selected
        if (selectedPoint != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white,
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3), width: 1.5),
                          ),
                          child: Center(
                            child: Text(selectedPoint.icon, style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedPoint.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              const Text(
                                "Panimalar Engineering College Campus",
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _clearRouteCache();
                            setState(() {
                              _selectedNavPointName = "";
                              _campusRoute = null;
                              _routeDistanceM = 0;
                              _routeWalkMinutes = 0;
                              _routeRemainingM = 0;
                              _routeError = '';
                              _searchCtrl.clear();
                              _searchFilter = "";
                            });
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 14, color: Color(0xFF2563EB)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Coords: ${selectedPoint.coords.latitude.toStringAsFixed(6)}, ${selectedPoint.coords.longitude.toStringAsFixed(6)}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_studentLat != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Walk time badge — shows OSRM data or loading
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
                            ),
                            child: _routeLoading
                                ? const SizedBox(
                                    width: 60,
                                    height: 14,
                                    child: LinearProgressIndicator(
                                      backgroundColor: Color(0xFFBFDBFE),
                                      color: Color(0xFF2563EB),
                                    ),
                                  )
                                : Text(
                                    "$walkMinutes min · ${distanceM < 1000 ? '${distanceM.round()} m' : '${(distanceM / 1000).toStringAsFixed(1)} km'}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                  ),
                          ),
                          const Spacer(),
                          // Navigate button — fully in-app via OSRM
                          TextButton.icon(
                            onPressed: _routeLoading
                                ? null
                                : () => _handleNavigationTap(selectedPoint!),
                            style: TextButton.styleFrom(
                              backgroundColor: _routeLoading
                                  ? Colors.grey.shade300
                                  : const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            icon: _routeLoading
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.directions_walk, size: 14),
                            label: Text(
                              _routeLoading ? "Routing…" : "Navigate →",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                     ] else ...[
                       const SizedBox(height: 10),
                       const Row(
                         children: [
                           Icon(Icons.info_outline, size: 12, color: Colors.grey),
                           SizedBox(width: 4),
                           Text(
                             "Enable location to see distance & walking time",
                             style: TextStyle(fontSize: 10, color: Colors.grey),
                           ),
                         ],
                       ),
                     ],
                  ],
                ),
              ),
            ),
          )
        // Search results list — shown when searching but no point selected yet
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
                      _clearRouteCache();
                      setState(() {
                        _selectedNavPointName = cp.name;
                        _searchCtrl.clear();
                        _searchFilter = "";
                        _routeDistanceM = 0;
                        _routeWalkMinutes = 0;
                        _routeRemainingM = 0;
                        _routeError = '';
                      });
                      _updateCampusRoute().then((_) {
                        if (mounted) _fitMapToRoute(cp);
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
                          Text(
                            cp.name,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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

  /// Small info cell used in the navigation info card.
  Widget _navInfoCell(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  /// Thin vertical divider for the nav info card.
  Widget _navDivider() => Container(
        width: 1,
        height: 32,
        color: const Color(0xFFE2E8F0),
      );

  /// Fits the map camera to show both the student's position and the destination.
  void _fitMapToRoute(CampusPoint dest) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_studentLat != null && _studentLng != null) {
        final minLat = min(_studentLat!, dest.coords.latitude);
        final maxLat = max(_studentLat!, dest.coords.latitude);
        final minLng = min(_studentLng!, dest.coords.longitude);
        final maxLng = max(_studentLng!, dest.coords.longitude);
        // Fit with padding
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(minLat - 0.0004, minLng - 0.0004),
              LatLng(maxLat + 0.0004, maxLng + 0.0004),
            ),
            padding: const EdgeInsets.fromLTRB(40, 80, 40, 200),
          ),
        );
      } else {
        _mapController.move(dest.coords, 17.5);
      }
    });
  }

  // Campus centre coordinate — used to decide if student is inside campus.
  static const LatLng _campusCentre = LatLng(13.0508, 80.0754);
  static const double _campusRadiusMetres = 600.0; // ~600 m covers the whole campus

  /// Returns true if the student's current GPS fix is inside the campus boundary.
  bool get _isInsideCampus {
    if (_studentLat == null || _studentLng == null) return false;
    final lat1 = _studentLat! * (pi / 180);
    final lng1 = _studentLng! * (pi / 180);
    final lat2 = _campusCentre.latitude * (pi / 180);
    final lng2 = _campusCentre.longitude * (pi / 180);
    const r = 6371000.0;
    final dLat = lat2 - lat1;
    final dLng = lng2 - lng1;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final dist = r * 2 * atan2(sqrt(a), sqrt(1 - a));
    return dist <= _campusRadiusMetres;
  }

  /// Handles tapping the "Navigate" button — stays fully in-app.
  /// Fetches the OSRM route and fits the map camera to show the full path.
  void _handleNavigationTap(CampusPoint dest) {
    _updateCampusRoute().then((_) {
      if (mounted) _fitMapToRoute(dest);
    });
  }


    Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Avatar + display name ────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFFE2E8F0),
                      backgroundImage: _profilePicUrl.startsWith('base64:')
                          ? MemoryImage(base64Decode(_profilePicUrl.substring(7)))
                          : null,
                      child: _profilePicUrl.isEmpty
                          ? const Text("🎓", style: TextStyle(fontSize: 54))
                          : null,
                    ),
                    if (_isEditingProfile)
                      GestureDetector(
                        onTap: _uploadProfilePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 18, color: Colors.white),
                        ),
                      )
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _studentName.isEmpty || _studentName == "Student Name" ? "Your Name" : _studentName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _studentName.isEmpty || _studentName == "Student Name"
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.studentRollNo.isEmpty ? "Panimalar Smart Transit Account" : widget.studentRollNo,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Student Details card ─────────────────────────────────────────
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
                const Text(
                  "STUDENT DETAILS",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                if (_isEditingProfile) ...[
                  if (_isEditingProfile) ...[
                    const Text(
                      "ROLL NO",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _profileRollNoCtrl,
                      decoration: InputDecoration(
                        hintText: "Enter your Roll No (e.g. 2024PECAI424)",
                        hintStyle: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ── Full Name ──────────────────────────────────────────────
                  const Text(
                    "FULL NAME",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _profileNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: "Enter your full name",          // placeholder
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),               // light colour
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 2),
                      ),
                    ),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),

                  // ── Year of Study ──────────────────────────────────────────
                  const Text(
                    "YEAR OF STUDY",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _profileTempYear.isNotEmpty ? _profileTempYear : null,
                    hint: const Text(
                      "Select year of study",
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                      ),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 2),
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                    ),
                    items: const [
                      DropdownMenuItem(value: "1st Year", child: Text("1st Year")),
                      DropdownMenuItem(value: "2nd Year", child: Text("2nd Year")),
                      DropdownMenuItem(value: "3rd Year", child: Text("3rd Year")),
                      DropdownMenuItem(value: "4th Year", child: Text("4th Year")),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _profileTempYear = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Department dropdown (not free-text) ────────────────────
                  const Text(
                    "DEPARTMENT",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _deptDropdownValue(),
                    hint: const Text(
                      "Select your department",
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                      ),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 2),
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                    ),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: "Computer Science (CSE)",            child: Text("Computer Science (CSE)")),
                      DropdownMenuItem(value: "Artificial Intelligence & DS (AIDS)", child: Text("AI & Data Science (AIDS)")),
                      DropdownMenuItem(value: "Computer Science & BS (CSBS)",      child: Text("CS & Business Systems (CSBS)")),
                      DropdownMenuItem(value: "Electronics & Communication (ECE)", child: Text("Electronics & Communication (ECE)")),
                      DropdownMenuItem(value: "Electrical & Electronics (EEE)",    child: Text("Electrical & Electronics (EEE)")),
                      DropdownMenuItem(value: "Information Technology (IT)",       child: Text("Information Technology (IT)")),
                      DropdownMenuItem(value: "Mechanical Engineering (MECH)",     child: Text("Mechanical Engineering (MECH)")),
                      DropdownMenuItem(value: "Civil Engineering (CIVIL)",         child: Text("Civil Engineering (CIVIL)")),
                      DropdownMenuItem(value: "MBA",                               child: Text("MBA")),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _studentDept = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Bus Number ─────────────────────────────────────────────
                  const Text(
                    "BUS NUMBER",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _profileBusCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (val) {
                      setState(() {});
                      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                        _fetchRouteForBus(val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: "e.g. 1, 3, 6, 23, 65",
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Icon(Icons.directions_bus_rounded,
                          color: Color(0xFF2563EB), size: 18),
                      suffixIcon: _isFetchingRoute
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                                ),
                              ),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                            color: Color(0xFF2563EB), width: 2),
                      ),
                      // Show route label as helper text when bus is recognised
                      helperText: () {
                        if (_isFetchingRoute) return 'Checking bus number...';
                        final key = _fetchedRouteKey;
                        if (key == null) return null;
                        return '✓  ' + (routeLabelsConfig[key] ?? '');
                      }(),
                      helperStyle: TextStyle(
                        color: _isFetchingRoute ? const Color(0xFF64748B) : const Color(0xFF16A34A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      errorText: _profileBusCtrl.text.trim().isNotEmpty &&
                              !_isFetchingRoute &&
                              _fetchedRouteKey == null
                          ? 'Unknown bus number'
                          : null,
                    ),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),

                  // ── Boarding Stop — shown only when bus number is valid ─────
                  if (_profileBusStops.isNotEmpty) ...[
                    const Text(
                      "BOARDING STOP",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _profileBusStops.contains(_savedStop)
                          ? _savedStop
                          : null,
                      hint: const Text(
                        "Select your boarding stop",
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                        ),
                      ),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.location_on_outlined,
                            color: Color(0xFF2563EB), size: 18),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                              color: Color(0xFF2563EB), width: 2),
                        ),
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                      ),
                      isExpanded: true,
                      items: _profileBusStops
                          .map((stop) => DropdownMenuItem(
                                value: stop,
                                child: Text(stop),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _savedStop = val);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 8),

                  // ── Save button ────────────────────────────────────────────
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {
                      final name = _profileNameCtrl.text.trim();
                      final year = _profileTempYear.isNotEmpty
                          ? _profileTempYear
                          : _studentYear;
                      if (name.isEmpty) {
                        _showSnackBar("Please enter your full name");
                        return;
                      }
                      _saveProfile(
                        name, year, _studentDept,
                        busNo: _profileBusCtrl.text.trim().toUpperCase(),
                        boardingStop: _savedStop,
                        rollNo: _profileRollNoCtrl.text.trim(),
                      );
                    },
                    child: const Text(
                      "💾  Save Profile",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ] else ...[
                  // ── View Mode ──────────────────────────────────────────────
                  _buildProfileRow("FULL NAME", _studentName),
                  const SizedBox(height: 12),
                  _buildProfileRow("YEAR OF STUDY", _studentYear),
                  const SizedBox(height: 12),
                  _buildProfileRow("DEPARTMENT", _studentDept),
                  const SizedBox(height: 12),
                  _buildProfileRow("ROLL NO", widget.studentRollNo.isEmpty ? "-" : widget.studentRollNo),
                  const SizedBox(height: 12),
                  _buildProfileRow("BUS NUMBER", _studentBusNo.isEmpty ? "-" : _studentBusNo),
                  const SizedBox(height: 12),
                  _buildProfileRow("BOARDING STOP", _savedStop.isEmpty ? "-" : _savedStop),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditingProfile = true;
                      });
                    },
                    icon: const Icon(Icons.edit, color: Color(0xFF2563EB), size: 18),
                    label: const Text(
                      "Edit Profile",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF2563EB)),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  "BUS PICKUP AUTHORIZATION",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                _buildPickupRequestCard(),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFDC2626)), // Red for logout
                    foregroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: widget.onLogout,
                  child: const Text(
                    "🔄  Logout",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  /// Returns the current department value only if it matches one of the
  String? _deptDropdownValue() {
    const valid = [
      "Computer Science (CSE)",
      "Artificial Intelligence & DS (AIDS)",
      "Computer Science & BS (CSBS)",
      "Electronics & Communication (ECE)",
      "Electrical & Electronics (EEE)",
      "Information Technology (IT)",
      "Mechanical Engineering (MECH)",
      "Civil Engineering (CIVIL)",
      "MBA",
    ];
    return valid.contains(_studentDept) ? _studentDept : null;
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
        withData: true,
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

      if (downloadUrl.isEmpty) {
        throw Exception("Failed to get document URL. Are you running on web without a hard restart?");
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
        'studentBus': _profileBusCtrl.text.trim().toUpperCase(),
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

  Widget _buildVoiceIntercomCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      shadowColor: Colors.black12,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Row(
          children: [
            Icon(Icons.mic, color: Color(0xFF2563EB), size: 18),
            SizedBox(width: 8),
            Text(
              "Admin STT Voice Intercom",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF1E293B)),
            ),
          ],
        ),
        subtitle: const Text(
          "Send direct transcripts & voice notes to admin",
          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_studentIntercomMessages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        "No messages yet. Tap Mic to dictate a message.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _studentIntercomMessages.length,
                      itemBuilder: (ctx, idx) {
                        final msg = _studentIntercomMessages[idx];
                        final isMe = msg['sender'] == 'student';
                        final isVoice = msg['isVoice'] == true;
                        
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            width: isVoice ? 220 : null,
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: Radius.circular(isMe ? 14 : 2),
                                bottomRight: Radius.circular(isMe ? 2 : 14),
                              ),
                              border: Border.all(color: isMe ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isMe ? "You" : (msg['senderName'] ?? "Sender"),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: isMe ? const Color(0xFF2563EB) : const Color(0xFF64748B),
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
                                          _playingMsgId == msg['id']
                                              ? Icons.pause_circle_filled_rounded
                                              : Icons.play_circle_filled_rounded,
                                          color: isMe ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                                          size: 28,
                                        ),
                                        onPressed: () {
                                          _playVoiceMessage(msg['id'], msg['msg'] ?? '', msg['voiceDuration'] ?? 3);
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                value: _playingMsgId == msg['id'] ? _playbackProgress : 0.0,
                                                backgroundColor: isMe ? const Color(0xFFDBEAFE) : const Color(0xFFE2E8F0),
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  isMe ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                                ),
                                                minHeight: 3,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  "0:${(msg['voiceDuration'] as int? ?? 3).toString().padLeft(2, '0')}",
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
                                      color: isMe ? const Color(0xFFDBEAFE).withValues(alpha: 0.3) : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "Transcript: \"${msg['transcript'] ?? ''}\"",
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    msg['msg'] ?? '',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                if (_isRecordingVoice)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Recording... 0:${_recordingDurationSecs.toString().padLeft(2, '0')}",
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: List.generate(8, (idx) {
                                  final height = 3.0 + (idx % 2 == 0 ? 8.0 : 4.0) + (Random().nextDouble() * 5.0);
                                  return Container(
                                    width: 2,
                                    height: height,
                                    margin: const EdgeInsets.symmetric(horizontal: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 20),
                          onPressed: _cancelRecordingVoice,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                          onPressed: _stopAndSendRecordingVoice,
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: "Type note or hold mic...",
                            hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                            fillColor: const Color(0xFFF8FAFC),
                            filled: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              _sendStudentTextMessage(val.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onLongPressStart: (_) {
                          _startRecordingVoice();
                          _showSnackBar("Recording... Release to send.");
                        },
                        onLongPressEnd: (_) {
                          _stopAndSendRecordingVoice();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mic, color: Color(0xFF2563EB), size: 20),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
          )
        ],
      ),
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
