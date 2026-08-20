import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:marquee/marquee.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:marquee/marquee.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:translator/translator.dart';


import 'package:flutter_tts/flutter_tts.dart';

import '../../models/campus_point.dart';
import '../../models/log_entry.dart';
import '../../models/alert_entry.dart';
import '../../config/routes_config.dart';
import '../../config/lang_config.dart';
import '../../config/app_config.dart';
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
  const MainShell({
    super.key,
    required this.onSwitchRole,
    required this.currentLang,
    required this.onLanguageChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  bool _isLoggedIn = false;
  bool _showCreateProfile = false;
  String _studentRollNo = "";
  bool _isFacultyLogin = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentRollNo = prefs.getString("studentRollNo") ?? "";
      _isFacultyLogin = prefs.getBool("isFacultyLogin") ?? false;
      _isLoggedIn = _studentRollNo.isNotEmpty;
    });
  }

  void _login(String rollNo, bool isFaculty) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("studentRollNo", rollNo);
    await prefs.setBool("isFacultyLogin", isFaculty);
    setState(() {
      _studentRollNo = rollNo;
      _isFacultyLogin = isFaculty;
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
    await prefs.remove('studentSelectedRoute');
    await prefs.remove('studentSavedStop');

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {}

    setState(() {
      _studentRollNo = "";
      _isLoggedIn = false;
      _showCreateProfile = false;
      _isFacultyLogin = false;
    });

    widget.onSwitchRole();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn && !_showCreateProfile) {
      return StudentLoginScreen(
        onLogin: _login,
        currentLang: widget.currentLang,
        onLanguageChanged: widget.onLanguageChanged,
        onSwitchRole: widget.onSwitchRole,
        onCreateProfile: (bool isFaculty) {
          setState(() {
            _showCreateProfile = true;
            _isFacultyLogin = isFaculty;
          });
        },
      );
    }

    return StudentDashboard(
      studentRollNo: _studentRollNo,
      isFirstTimeSignup: _showCreateProfile,
      isFaculty: _isFacultyLogin,
      onFirstTimeSave: (savedRollNo) {
        setState(() {
          _showCreateProfile = false;
        });
      },
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
  final bool isFaculty;
  final Function(String)? onFirstTimeSave;
  final VoidCallback onLogout;
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const StudentDashboard({
    super.key,
    required this.studentRollNo,
    this.isFirstTimeSignup = false,
    this.isFaculty = false,
    this.onFirstTimeSave,
    required this.onLogout,
    required this.onSwitchRole,
    required this.currentLang,
    required this.onLanguageChanged,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with TickerProviderStateMixin {
  String t(String key) {
    return appLang[widget.currentLang]?[key] ?? appLang['en']?[key] ?? key;
  }

  String translateDynamic(String text) {
    if (widget.currentLang == 'en') return text;
    String translated = text;
    final keys = [
      'Bus ', 'Breakdown', 'Ready', 'Replacement Bus ', 'is dispatched. Stay at your stop.',
      'The bus is now starts the journey.', 'Vehicle Breakdown Alert', 'Live',
      'breakdown reported. Replacement Bus dispatch is pending. Stay at your stop.',
      'breakdown. Replacement Bus ', ' dispatched. Stay at your stop.'
    ];
    for (final k in keys) {
      if (translated.contains(k)) {
        translated = translated.replaceAll(k, t(k));
      }
    }
    return translated;
  }

  String _formatStopName(String stop, {int index = -1}) {
    if (stop.contains("(Lat:") && stop.contains("Lng:")) {
      return stop.split("(Lat:")[0].trim();
    } else if (stop.startsWith("Lat: ")) {
      return index >= 0 ? "Stop ${index + 1}" : "Custom Stop";
    }
    return stop;
  }  int _currentIndex = 0;
  bool _isLoading = true;

  // ─── STT & Translator Variables ───
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListeningSTT = false;
  String _recognizedEnglishText = "";
  String _translatedTamilReason = "";
  final GoogleTranslator _translator = GoogleTranslator();

  // ─── DATA VARIABLES ───
  // --- DYNAMIC ROUTES CONFIG ---
  Map<String, String> _dynamicRouteLabels = {};
  Map<String, List<String>> _dynamicRouteStops = {};
  Map<String, String> _dynamicRouteColors = {};

  bool _isEditingProfile = false;
  String _profilePicUrl = "";
  MemoryImage? _cachedProfileImage; // cached to prevent blinking

  bool _busIsOnline = false;
  final bool _busIsParked = false;
  bool _isFollowingBus = true;
  double? _busLat;
  double? _busLng;
  double? _busAccuracy;
  String _busUpdatedAt = "--:--";
  String _busStatus = "offline";

  double? _renderLat;
  double? _renderLng;
  Timer? _lerpTimer;

  String _savedStop = "";
  String _studentName = "";
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
  bool _hasAlertedTripCompleted = false;
  bool _wasBusOnline = false;
  String _busDirection = 'To College';
  final double _alertRadiusMeters = 1000.0;

  bool _showNotification = false;
  String _notifTitle = "";
  String _notifBody = "";
  String _notifIcon = "";
  double _notifProgress = 1.0;
  Timer? _notifTimer;
  Timer? _notifProgressTimer;

  bool _breakdownActive = false;
  bool _breakdownDismissed = false;
  String _replacementBus = "";
  DateTime? _lastBreakdownClearTime;
  StreamSubscription? _breakdownSub;
  StreamSubscription? _locationSub;

  // Firebase Student Profile & Intercom
  StreamSubscription? _studentProfileSub;
  StreamSubscription? _driverBusRouteSub;


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
  String _selectedRoute = ""; 
  List<String> _routeStops = [];
  Map<String, LatLng> _coords = {};

  String _extractBusNumber(String input) {
    if (input.isEmpty) return '';
    final match = RegExp(r'(?:[Rr]oute|[Bb]us)?\s*[-_]?\s*(\d+)').firstMatch(input);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '')
        .replaceAll(RegExp(r'^[Rr]oute_?'), '')
        .split(RegExp(r'[-_\s]'))[0]
        .trim();
  }

  bool _isUploadTimeAllowed() {
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime nowIst = nowUtc.add(const Duration(hours: 5, minutes: 30));
    final double timeAsDouble = nowIst.hour + (nowIst.minute / 60.0);
    return timeAsDouble >= 13.5 && timeAsDouble <= 14.0;
  }
  String _busFirebaseId = "";
  String get _displayBusId {
    if (_breakdownActive &&
        _replacementBus.isNotEmpty &&
        _replacementBus != 'Unknown') {
      return _replacementBus;
    }
    if (_busFirebaseId.isNotEmpty) {
      return _busFirebaseId;
    }
    final num = _extractBusNumber(_selectedRoute);
    if (num.isNotEmpty) return num;
    return _selectedRoute;
  }

  String get _effectiveRouteKey {
    if (_breakdownActive && _replacementBus.isNotEmpty && _replacementBus != 'Unknown') {
      final repNum = _extractBusNumber(_replacementBus);
      final cleanRep = _replacementBus.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();

      for (final entry in _driverBusToRouteMap.entries) {
        final cleanBus = entry.key.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').trim();
        final busNum = _extractBusNumber(entry.key);
        if ((cleanBus == cleanRep || (repNum.isNotEmpty && busNum == repNum)) && entry.value.isNotEmpty) {
          return entry.value;
        }
      }
      for (final key in _dynamicRouteLabels.keys) {
        final cleanKey = key.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
        final keyNum = _extractBusNumber(key);
        if (cleanKey == cleanRep || (repNum.isNotEmpty && keyNum == repNum)) return key;
      }
      for (final key in _dynamicRouteStops.keys) {
        final cleanKey = key.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
        final keyNum = _extractBusNumber(key);
        if (cleanKey == cleanRep || (repNum.isNotEmpty && keyNum == repNum)) return key;
      }
      return 'route_$cleanRep';
    }
    return _selectedRoute;
  }

  String get _effectiveRouteLabel {
    final activeKey = _effectiveRouteKey;
    if (_dynamicRouteLabels.containsKey(activeKey)) {
      return _dynamicRouteLabels[activeKey]!;
    }
    final cleanKey = activeKey.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
    for (final entry in _dynamicRouteLabels.entries) {
      final k = entry.key.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
      if (k == cleanKey) {
        return entry.value;
      }
    }
    if (_breakdownActive && _replacementBus.isNotEmpty && _replacementBus != 'Unknown') {
      final repNum = _extractBusNumber(_replacementBus);
      final displayRep = repNum.isNotEmpty ? repNum : _replacementBus;
      return "Bus $displayRep";
    }
    return _dynamicRouteLabels[_selectedRoute] ?? "No Route Selected";
  }

  List<String> get _effectiveDisplayStops {
    final activeKey = _effectiveRouteKey;
    List<String> stops = List<String>.from(_dynamicRouteStops[activeKey] ?? []);
    if (stops.isEmpty) {
      final cleanKey = activeKey.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
      for (final entry in _dynamicRouteStops.entries) {
        final k = entry.key.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
        if (k == cleanKey) {
          stops = List<String>.from(entry.value);
          break;
        }
      }
    }
    if (!_breakdownActive && stops.isEmpty) {
      stops = List<String>.from(_routeStops);
    }
    if (stops.isNotEmpty && stops.last != "COLLEGE" && stops.last != "Panimalar Engineering College") {
      stops.add("COLLEGE");
    } else if (stops.isEmpty && _breakdownActive) {
      stops = ["COLLEGE"];
    }
    if (_busDirection.trim().toLowerCase() == 'to home' ||
        _busDirection.trim().toLowerCase() == 'home') {
      return stops.reversed.toList();
    }
    return stops;
  }
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
  bool _routeLoading = false; // true while OSRM fetch is in progress
  double _routeDistanceM = 0; // actual road distance from OSRM (metres)
  int _routeWalkMinutes = 0; // estimated walk time from OSRM (minutes)
  double _routeRemainingM = 0; // remaining distance to destination (metres)
  String _routeError = ''; // last routing error message for UI display
  List<Map<String, dynamic>> _navSteps = []; // turn-by-turn steps (future use)

  // Bus perfectly routed points
  List<LatLng> _busRoutePoints = [];
  bool _busRouteLoading = false;

  // Route cache — prevents unnecessary API calls
  String _cachedRouteDestName =
      ''; // name of destination when route was last fetched
  double? _cachedFromLat; // origin lat when route was last fetched
  double? _cachedFromLng; // origin lng when route was last fetched
  static const double _rerouteThresholdM =
      30.0; // reroute only after moving 30 m

  // Student's own GPS location (for campus navigation)
  double? _studentLat;
  double? _studentLng;
  StreamSubscription<Position>? _studentLocationSub;
  bool _studentLocationDenied = false;

  // ── Profile tab controllers — declared at state level so they survive rebuilds
  late final TextEditingController _profileRollNoCtrl;
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _profileBusCtrl; // bus number input
  String _profileTempYear = ''; // tracks dropdown selection before saving

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
        final snap = await FirebaseDatabase.instance.ref('drivers').get();
        if (snap.exists) {
          String? foundRoute;
          for (final child in snap.children) {
            final val = child.value;
            if (val is Map) {
              final b = (val['bus']?.toString() ?? '').trim().toUpperCase();
              if (b == bus) {
                foundRoute = val['route'] as String?;
                break;
              }
            }
          }
          if (mounted) {
            setState(() {
              _fetchedRouteKey = foundRoute;
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

  void _processCoordinatesForCurrentRoute() {
    _coords.clear();
    final activeStops = _effectiveDisplayStops;
    for (var stop in activeStops) {
      final match = RegExp(r'Lat:\s*([-\d.]+)\s*,\s*Lng:\s*([-\d.]+)').firstMatch(stop);
      if (match != null) {
        try {
          final lat = double.parse(match.group(1)!);
          final lng = double.parse(match.group(2)!);
          _coords[stop] = LatLng(lat, lng);
        } catch (_) {}
      } else if (coordsConfig.containsKey(stop)) {
        _coords[stop] = coordsConfig[stop]!;
      }
    }
  }

  /// Returns the stops list for the bus number the student typed, or empty.
  List<String> get _profileBusStops {
    final busNo = _profileBusCtrl.text.trim();
    if (busNo.isEmpty) return [];

    final key = _fetchedRouteKey;
    if (key == null) return [];
    
    final stops = List<String>.from(_dynamicRouteStops[key] ?? []);
    if (stops.isNotEmpty && stops.last != "COLLEGE" && stops.last != "Panimalar Engineering College") {
      stops.add("COLLEGE");
    }
    return stops;
  }

  List<Map<String, dynamic>> _adminNotifications = [];
  List<Map<String, dynamic>> _specialBuses = [];
  StreamSubscription? _specialBusesSub;

  List<Map<String, dynamic>> get _filteredNotifications {
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return _adminNotifications.where((n) {
      if (_hiddenNotifIds.contains(n['id'].toString())) return false;
      
      final idDouble = double.tryParse(n['id'].toString()) ?? 0.0;
      if (idDouble > 0) {
        final notifTimeIst = DateTime.fromMillisecondsSinceEpoch(idDouble.toInt()).toUtc().add(const Duration(hours: 5, minutes: 30));
        if (notifTimeIst.year != nowIst.year || notifTimeIst.month != nowIst.month || notifTimeIst.day != nowIst.day) {
          return false;
        }
      }

      final target = n['bus']?.toString().toLowerCase().trim() ?? 'all';
      if (target == 'all') return true;

      final originalBusNum = _extractBusNumber(_selectedRoute);
      final displayBusNum = _extractBusNumber(_displayBusId);
      final replacementNum = _breakdownActive ? _extractBusNumber(_replacementBus) : "";
      final targetNum = _extractBusNumber(target);

      if (targetNum.isNotEmpty) {
        if (originalBusNum.isNotEmpty && targetNum == originalBusNum) return true;
        if (displayBusNum.isNotEmpty && targetNum == displayBusNum) return true;
        if (replacementNum.isNotEmpty && targetNum == replacementNum) return true;
      }

      final myRouteClean = _selectedRoute.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
      final targetClean = target.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();

      if (myRouteClean.isNotEmpty && targetClean.isNotEmpty && (myRouteClean == targetClean || targetClean.contains(myRouteClean) || myRouteClean.contains(targetClean))) {
        return true;
      }

      return false;
    }).toList();
  }

  final List<String> _hiddenNotifIds = [];
  int _unreadNotifCount = 0;
  double _lastSeenNotifId = 0;

  StreamSubscription? _notifSub;

  // Real-time bus arrivals log feed
  List<LogEntry> _arrivalLogs = [];
  StreamSubscription? _logsSub;

  Map<String, Map<String, dynamic>> _allBusesLocations = {};
  StreamSubscription? _allBusesSub;
  StreamSubscription? _announcementSub;

  final MapController _mapController = MapController();
  final MapController _campusMapController = MapController();
  static const LatLng _homeScanCenter = LatLng(13.04890, 80.07546);
  static const bool _showNearbyCircle = false;



  Map<String, dynamic>? _latestAnnouncement;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _listenForAnnouncements();
    _listenForDynamicRoutes();
    // Profile controllers — empty initially; populated after prefs load
    _profileRollNoCtrl = TextEditingController();
    _profileNameCtrl = TextEditingController();

    if (widget.isFirstTimeSignup) {
      _currentIndex = 3;
      _isEditingProfile = true;
    }
    _profileBusCtrl = TextEditingController();
    _profileTempYear = '';
    _startLerpLoop();
    _listenForArrivalLogs();
    _listenToAllBuses();
    _startStudentLocationTracking();
    _listenForAdminNotifications();
  }

  void _listenForDynamicRoutes() {
    if (Firebase.apps.isEmpty) return;
    
    FirebaseDatabase.instance.ref('routes').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        Map<String, String> newLabels = {};
        Map<String, List<String>> newStops = {};
        Map<String, String> newColors = {};
        
        void processRoute(String fallbackKey, Map val) {
          if (val['deleted'] == true || val['isDeleted'] == true || val['status'] == 'deleted') return;
          final key = (val['key'] != null && val['key'].toString().isNotEmpty)
              ? val['key'].toString()
              : fallbackKey;
          if (key.isEmpty) return;
          
          if (val['name'] != null) {
            newLabels[key] = val['name'].toString();
            newLabels[fallbackKey] = val['name'].toString();
          }
          if (val['color'] != null) {
            newColors[key] = val['color'].toString();
            newColors[fallbackKey] = val['color'].toString();
          }
          if (val['stops'] != null && val['stops'] is List) {
            final stops = List<String>.from(val['stops'].map((e) => e.toString()));
            newStops[key] = stops;
            newStops[fallbackKey] = stops;
          }
        }

        for (final child in event.snapshot.children) {
          final childKey = child.key?.toString() ?? '';
          final val = child.value;
          if (val is Map) processRoute(childKey, val);
        }
        
        if (mounted) {
          setState(() {
            _dynamicRouteLabels = newLabels;
            _dynamicRouteStops = newStops;
            _dynamicRouteColors = newColors;

            // If student's currently selected route was deleted by admin, switch to first active route or clear
            if (_selectedRoute.isNotEmpty && !newLabels.containsKey(_selectedRoute)) {
              if (newLabels.isNotEmpty) {
                _selectedRoute = newLabels.keys.first;
              } else {
                _selectedRoute = '';
              }
            }

            // Also need to re-evaluate current active route stops
            if (_selectedRoute.isNotEmpty && newLabels.containsKey(_selectedRoute)) {
               _updateRouteDetails(_selectedRoute, startListener: false);
            } else if (_fetchedRouteKey != null && newLabels.containsKey(_fetchedRouteKey)) {
               _updateRouteDetails(_fetchedRouteKey!, startListener: false);
            } else {
               _routeStops = [];
            }
          });
        }
      }
    });
  }

  void _listenForAnnouncements() {
    _announcementSub = FirebaseDatabase.instance
        .ref('announcements/active')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map?;
      setState(() {
        if (data != null) {
          _latestAnnouncement = Map<String, dynamic>.from(data);
        } else {
          _latestAnnouncement = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _lerpTimer?.cancel();
    _notifTimer?.cancel();
    _notifProgressTimer?.cancel();
    _breakdownSub?.cancel();
    _locationSub?.cancel();
    _pickupRequestSub?.cancel();
    _studentProfileSub?.cancel();
    _studentIntercomSub?.cancel();
    _studentLocationSub?.cancel();
    _specialBusesSub?.cancel();
    _notifSub?.cancel();
    _logsSub?.cancel();
    _allBusesSub?.cancel();
    _announcementSub?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _profileRollNoCtrl.dispose();
    _profileNameCtrl.dispose();
    _profileBusCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _driverBusToRouteMap = {};

  void _listenToDriverRoute() {
    _driverBusRouteSub?.cancel();
    if (Firebase.apps.isNotEmpty) {
      _driverBusRouteSub = FirebaseDatabase.instance.ref('drivers').onValue.listen((event) {
        if (!mounted) return;
        if (event.snapshot.exists && event.snapshot.value != null) {
          String? foundRoute;
          Map<String, String> newDriverMap = {};
          final cleanStudentB = _studentBusNo.trim().toUpperCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').trim();
          for (final child in event.snapshot.children) {
            final val = child.value;
            if (val is Map) {
              final b = (val['bus']?.toString() ?? '').trim().toUpperCase();
              final cleanB = b.replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').trim();
              final r = val['route']?.toString();
              if (b.isNotEmpty && r != null && r.isNotEmpty) {
                newDriverMap[b] = r;
                newDriverMap[cleanB] = r;
              }
              if (_studentBusNo.isNotEmpty && (b == _studentBusNo.trim().toUpperCase() || (cleanB.isNotEmpty && cleanB == cleanStudentB))) {
                foundRoute = r;
              }
            }
          }
          setState(() {
            _driverBusToRouteMap = newDriverMap;
            if (foundRoute != null && !_breakdownActive) {
              _selectedRoute = foundRoute;
              _updateRouteDetails(_selectedRoute, startListener: true);
            }
          });
          if (foundRoute != null) {
            SharedPreferences.getInstance().then(
              (p) => p.setString('studentSelectedRoute', foundRoute!),
            );
          }
        }
      });
    }
  }

  void _listenToAllBuses() {
    if (Firebase.apps.isEmpty) return;
    try {
      _allBusesSub = FirebaseDatabase.instance.ref('liveLocations').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data == null) return;
        if (!mounted) return;
        final Map<String, Map<String, dynamic>> updatedBuses = {};
        data.forEach((key, value) {
          if (value is Map) {
            final dir = value['direction']?.toString() ?? value['tripType']?.toString() ?? 'To College';
            updatedBuses[key.toString()] = {
              'lat': value['lat'],
              'lng': value['lng'],
              'status': value['status'],
              'updatedAt': value['updatedAt'],
              'busId': key.toString(),
              'direction': dir,
            };
          }
        });
        setState(() {
          _allBusesLocations = updatedBuses;
          if (_studentBusNo.isNotEmpty && updatedBuses.containsKey(_studentBusNo)) {
            final dir = updatedBuses[_studentBusNo]?['direction']?.toString();
            if (dir != null && dir.isNotEmpty) {
              _busDirection = dir;
            }
          }
        });
      });
    } catch (e) {
      debugPrint("Error listening to all buses: $e");
    }
  }

  /// Requests GPS permission and starts a continuous location stream.
  /// Updates [_studentLat]/[_studentLng] on every significant movement.
  /// Only triggers a new OSRM route fetch when the user moves > [_rerouteThresholdM].
  void _startStudentLocationTracking() async {
    try {
      // ── 1. Check service enabled ──────────────────────────────────────────
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _studentLocationDenied = true;
            _routeError = 'GPS is disabled. Enable location in Settings.';
          });
        }
        return;
      }

      // ── 2. Request permission ─────────────────────────────────────────────
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _studentLocationDenied = true;
            _routeError = permission == LocationPermission.deniedForever
                ? 'Location permission permanently denied. Enable in app settings.'
                : 'Location permission denied.';
          });
        }
        return;
      }

      // ── 3. Get immediate first fix ────────────────────────────────────────
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
          ),
        );
        if (mounted) {
          setState(() {
            _studentLat = pos.latitude;
            _studentLng = pos.longitude;
            _routeError = '';
          });
        }
      } catch (_) {
        /* first fix failed — stream will recover */
      }

      // ── 4. Continuous stream (update every 3 m for smooth dot movement) ──
      _studentLocationSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0, // continuous update
            ),
          ).listen(
            (pos) {
              if (!mounted) return;
              final newLat = pos.latitude;
              final newLng = pos.longitude;

              // Only reroute when user has moved > threshold AND a destination is set
              bool needsReroute = false;
              if (_selectedNavPointName.isNotEmpty &&
                  _cachedFromLat != null &&
                  _cachedFromLng != null) {
                final movedM = _haversineM(
                  _cachedFromLat!,
                  _cachedFromLng!,
                  newLat,
                  newLng,
                );
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
                    final dest = _campusPointsList.firstWhere(
                      (p) => p.name == _selectedNavPointName,
                    );
                    _routeRemainingM = _haversineM(
                      newLat,
                      newLng,
                      dest.coords.latitude,
                      dest.coords.longitude,
                    );
                  } catch (_) {}
                }
              });

              if (needsReroute) _updateCampusRoute();
            },
            onError: (e) {
              if (mounted) {
                setState(() => _routeError = 'Location stream error: $e');
              }
            },
          );
    } catch (e) {
      debugPrint("Student location error: $e");
      if (mounted) {
        setState(() {
          _studentLocationDenied = true;
          _routeError = 'Could not start location tracking.';
        });
      }
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
      dest = _campusPointsList.firstWhere(
        (p) => p.name == _selectedNavPointName,
      );
    } catch (_) {
      setState(() {
        _campusRoute = null;
        _routeError = 'Invalid destination.';
      });
      return;
    }
    if (_studentLat == null || _studentLng == null) {
      setState(() {
        _campusRoute = null;
        _routeError = 'Waiting for GPS fix…';
      });
      return;
    }

    // Cache check
    if (_cachedRouteDestName == _selectedNavPointName &&
        _cachedFromLat != null &&
        _cachedFromLng != null) {
      final movedM = _haversineM(
        _cachedFromLat!,
        _cachedFromLng!,
        _studentLat!,
        _studentLng!,
      );
      if (movedM < _rerouteThresholdM) return;
    }

    setState(() {
      _routeLoading = true;
      _routeError = '';
    });

    // Straight-line fallback values
    List<LatLng> points = [LatLng(_studentLat!, _studentLng!), dest.coords];
    double distM = _haversineM(
      _studentLat!,
      _studentLng!,
      dest.coords.latitude,
      dest.coords.longitude,
    );
    int walkMin = max(1, (distM / 70).ceil());

    // Use the custom local graph for strictly internal campus paths
    final origin = LatLng(_studentLat!, _studentLng!);
    final graph = CampusPathGraph(); // Instantiate fresh for hot-reload safety
    points = graph.shortestPath(origin, dest.coords, destName: dest.name);
    distM = graph.pathDistanceM(points);
    walkMin = max(1, (distM / 70).ceil());

    if (!mounted) return;
    setState(() => _routeError = '');

    _cachedRouteDestName = _selectedNavPointName;
    _cachedFromLat = _studentLat;
    _cachedFromLng = _studentLng;

    setState(() {
      _campusRoute = Polyline(
        points: points,
        color: const Color(0xFF2563EB),
        strokeWidth: 4.0,
      );
      _routeDistanceM = distM;
      _routeWalkMinutes = walkMin;
      _routeRemainingM = _haversineM(
        _studentLat!,
        _studentLng!,
        dest.coords.latitude,
        dest.coords.longitude,
      );
      _navSteps = [];
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
    final a =
        sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Straight-line distance (metres) from student GPS to a [CampusPoint].
  double _distanceTo(CampusPoint cp) {
    if (_studentLat == null || _studentLng == null) return 0.0;
    return _haversineM(
      _studentLat!,
      _studentLng!,
      cp.coords.latitude,
      cp.coords.longitude,
    );
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
              _unreadNotifCount = _filteredNotifications
                  .where((n) => n['read'] != true)
                  .length;
            });

            // Show popup for new notifications relevant to this student
            if (_filteredNotifications.isNotEmpty) {
              final latest = _filteredNotifications.first;
              final double latestId = double.tryParse(latest['id']) ?? 0.0;
              if (_lastSeenNotifId == 0) {
                _lastSeenNotifId = latestId;
              } else if (latestId > _lastSeenNotifId) {
                _lastSeenNotifId = latestId;
                _showInAppNotification(
                  latest['title'] ?? 'New Notification',
                  latest['msg'] ?? '',
                  '🔔',
                  durationMs: 4000,
                );
              }
            }
          });

      _specialBusesSub = FirebaseDatabase.instance
          .ref('special_buses')
          .onValue
          .listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> loaded = [];
        if (data != null) {
          data.forEach((k, v) {
            if (v is Map) {
              loaded.add({...Map<String, dynamic>.from(v), 'id': k});
            }
          });
        }
        if (!mounted) return;
        setState(() {
          _specialBuses = loaded;
        });
      });
    } catch (e) {
      debugPrint("Notification listener error: $e");
    }
  }

  void _markAllNotificationsRead() {
    if (Firebase.apps.isEmpty) return;
    for (final n in _filteredNotifications) {
      if (n['read'] != true) {
        FirebaseDatabase.instance
            .ref('student_notifications/${n['id']}/read')
            .set(true);
      }
    }
    setState(() {
      for (final n in _filteredNotifications) {
        n['read'] = true;
      }
      _unreadNotifCount = 0;
    });
  }

  void _showNotificationsPanel() {
    _markAllNotificationsRead();
    _showNotificationsSheet(context);
  }

  void _showNotificationsSheet(BuildContext context) {
    final cleanBusNo = _displayBusId.replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
    final bool isBus39 = _displayBusId.contains('39') ||
        _busFirebaseId.contains('39') ||
        _studentBusNo.contains('39') ||
        _selectedRoute.contains('39') ||
        cleanBusNo.startsWith('39');
    final bool isBus84 = _displayBusId.contains('84') ||
        _busFirebaseId.contains('84') ||
        _studentBusNo.contains('84') ||
        _selectedRoute.contains('84') ||
        cleanBusNo.startsWith('84');
    final bool isBus111 = _displayBusId.contains('111') ||
        _busFirebaseId.contains('111') ||
        _studentBusNo.contains('111') ||
        _selectedRoute.contains('111') ||
        cleanBusNo.startsWith('111');
    final bool isBus138 = _displayBusId.contains('138') ||
        _busFirebaseId.contains('138') ||
        _studentBusNo.contains('138') ||
        _selectedRoute.contains('138') ||
        cleanBusNo.startsWith('138');
    final bool isBus104 = _displayBusId.contains('104') ||
        _busFirebaseId.contains('104') ||
        _studentBusNo.contains('104') ||
        _selectedRoute.contains('104') ||
        cleanBusNo.startsWith('104');
    final bool hasGroupQR = isBus39 || isBus84 || isBus111 || isBus138 || isBus104;
    final String activeBusId = isBus104 ? '104' : (isBus138 ? '138' : (isBus111 ? '111' : (isBus84 ? '84' : '39')));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
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
                      if (hasGroupQR)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx); // Close the sheet
                            _showQRScannerDialog(context, activeBusId);
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text("Join Group"),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                          ),
                        ),
                      if (_filteredNotifications.isNotEmpty)
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "Close",
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),
                // Notifications list
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      if (hasGroupQR) _buildJoinGroupNotifTile(ctx, activeBusId),
                      if (_breakdownActive && !_breakdownDismissed) ...[
                        _buildStudentBreakdownNotifTile(ctx),
                        const SizedBox(height: 8),
                      ],
                      ..._filteredNotifications.map(
                        (n) => Dismissible(
                          key: Key(n['id'].toString()),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            setState(() {
                              _hiddenNotifIds.add(n['id'].toString());
                            });
                            setModalState(() {});
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red.shade400,
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildNotifTile(n, setModalState),
                              const Divider(height: 1, indent: 56),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinGroupNotifTile(BuildContext ctx, String busId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Bus $busId Official Group",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Tap to view QR Code & join group",
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showQRScannerDialog(context, busId);
            },
            icon: const Icon(Icons.qr_code_scanner, size: 14),
            label: const Text("Join", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  void _showQRScannerDialog(BuildContext context, String busId) {
    final cleanId = busId.replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
    final bool is104 = cleanId.contains('104') || busId.contains('104');
    final bool is138 = cleanId.contains('138') || busId.contains('138');
    final bool is111 = cleanId.contains('111') || busId.contains('111');
    final bool is84 = cleanId.contains('84') || busId.contains('84');

    final String groupLink = is104
        ? 'https://t.me/+pgoiVH2g1Yg3OWM1'
        : (is138
            ? 'https://t.me/+teQTSm1J4tk5MzY1'
            : (is111
                ? 'https://t.me/+Am-vc2hoeKw4MTU9'
                : (is84 ? 'https://t.me/+5KzeX6aQCdsyY2Y1' : 'https://t.me/+hZmjz3T65PNkOGE1')));

    final String imageAsset = is104
        ? 'assets/images/bus104_qr.png'
        : (is138
            ? 'assets/images/bus138_qr.png'
            : (is111
                ? 'assets/images/bus111_qr.png'
                : (is84 ? 'assets/images/bus84_qr.png' : 'assets/images/bus39_qr.png')));

    final String targetBusNo = is104 ? '104' : (is138 ? '138' : (is111 ? '111' : (is84 ? '84' : '39')));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Join Bus $targetBusNo Group', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Show this QR code to others, or tap the QR code / 'Join Group' button to join the Telegram group.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                final Uri url = Uri.parse(groupLink);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: Image.asset(
                  imageAsset,
                  width: 240,
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.qr_code_2_rounded, size: 80, color: Color(0xFF2563EB)),
                          const SizedBox(height: 12),
                          Text(
                            "Bus $targetBusNo Official Group",
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Tap to join Telegram Group",
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "BUS $targetBusNo",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final Uri url = Uri.parse(groupLink);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.group_add),
            label: const Text('Join Group'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
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
                    Expanded(
                      child: Text(
                        translateDynamic("Vehicle Breakdown Alert"),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    Text(
                      translateDynamic("Live"),
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
                  translateDynamic(msg),
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
              setState(() {
                _breakdownDismissed = true;
              });
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
        border: Border.all(
          color: (config['color'] as Color).withValues(alpha: 0.3),
        ),
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

  Widget _buildNotifTile(Map<String, dynamic> n, StateSetter setModalState) {
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
                        translateDynamic(n['title'] as String),
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
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
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
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  translateDynamic(n['msg'] as String),
                  style: TextStyle(
                    fontSize: 12,
                    color: n['msg'].toString().contains("started the journey from the breakdown") 
                        ? const Color(0xFF16A34A) // Green color
                        : (n['msg'].toString().toLowerCase().contains("breakdown reported") || n['msg'].toString().toLowerCase().contains("replacement bus"))
                            ? const Color(0xFFEF4444) // Red color for breakdowns
                            : const Color(0xFF475569),
                    fontWeight: (n['msg'].toString().contains("started the journey from the breakdown") || n['msg'].toString().toLowerCase().contains("breakdown"))
                        ? FontWeight.w700
                        : FontWeight.w500,
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
            icon: const Icon(Icons.close, color: Colors.grey, size: 18),
            onPressed: () async {
              setModalState(() {
                _hiddenNotifIds.add(n['id'].toString());
              });
              setState(() {});
              final prefs = await SharedPreferences.getInstance();
              prefs.setStringList(
                'hidden_notifs_$_busFirebaseId',
                _hiddenNotifIds,
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _notifTypeConfig(String type) {
    switch (type) {
      case 'delay':
        return {
          'icon': '🚌',
          'color': const Color(0xFFF59E0B),
          'bg': const Color(0xFFFFFBEB),
        };
      case 'emergency':
        return {
          'icon': '🚨',
          'color': const Color(0xFFDC2626),
          'bg': const Color(0xFFFEF2F2),
        };
      case 'route_change':
        return {
          'icon': '🔀',
          'color': const Color(0xFF7C3AED),
          'bg': const Color(0xFFF5F3FF),
        };
      case 'arrival':
        return {
          'icon': '🛎️',
          'color': const Color(0xFF16A34A),
          'bg': const Color(0xFFF0FDF4),
        };
      case 'breakdown':
        return {
          'icon': '🔧',
          'color': const Color(0xFFEA580C),
          'bg': const Color(0xFFFFF7ED),
        };
      default:
        return {
          'icon': '🔔',
          'color': const Color(0xFF2563EB),
          'bg': const Color(0xFFEFF6FF),
        };
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
    final isNewUser = widget.isFirstTimeSignup || prefs.getString('studentRollNo') != widget.studentRollNo;
    
    setState(() {
      _studentName = isNewUser ? "" : (prefs.getString('studentName') ?? "");
      _studentYear = isNewUser ? "" : (prefs.getString('studentYear') ?? "3rd Year");
      _studentDept = isNewUser ? "" : (prefs.getString('studentDept') ?? "Computer Science (CSE)");
      _profilePicUrl = isNewUser ? "" : (prefs.getString('profilePicUrl') ?? "");
      _studentBusNo = isNewUser ? "" : (prefs.getString('studentBusNo') ?? "");
      _savedStop = isNewUser ? "" : (prefs.getString('studentSavedStop') ?? "");
      _studentId = isNewUser ? "" : widget.studentRollNo;
      // Pre-fill all edit controllers with existing values
      _profileRollNoCtrl.text = isNewUser ? "" : widget.studentRollNo;
      _profileNameCtrl.text = _studentName;
      _profileTempYear = _studentYear;
      _profileBusCtrl.text = _studentBusNo;
      if (_profilePicUrl.startsWith('base64:')) {
        try {
          _cachedProfileImage = MemoryImage(
            base64Decode(_profilePicUrl.substring(7)),
          );
        } catch (_) {
          _cachedProfileImage = null;
        }
      }
    });

    try {
      if (Firebase.apps.isNotEmpty && widget.studentRollNo.isNotEmpty) {
        final node = widget.isFaculty ? 'faculty' : 'students';
        final snapshot = await FirebaseDatabase.instance
            .ref('$node/${widget.studentRollNo}')
            .get();
        if (snapshot.exists && snapshot.value != null) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          if (mounted) {
            setState(() {
              _studentName = data['name'] ?? _studentName;
              _studentYear = data['year'] ?? _studentYear;
              _studentDept = data['department'] ?? _studentDept;
              _profileBusCtrl.text = data['busNo'] ?? _profileBusCtrl.text;
              _studentBusNo = data['busNo'] ?? _studentBusNo;
              _savedStop = data['boardingStop'] ?? _savedStop;
              // Keep edit controllers in sync with latest fetched values
              _profileNameCtrl.text = _studentName;
              _profileTempYear = _studentYear;
              if (data['profilePicBase64'] != null &&
                  data['profilePicBase64'].toString().isNotEmpty) {
                _profilePicUrl = data['profilePicBase64'];
                if (_profilePicUrl.startsWith('base64:')) {
                  try {
                    _cachedProfileImage = MemoryImage(
                      base64Decode(_profilePicUrl.substring(7)),
                    );
                  } catch (_) {
                    _cachedProfileImage = null;
                  }
                }
              }
              
              // Save fetched details to SharedPreferences to prevent placeholders on next app launch
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('studentName', _studentName);
                prefs.setString('studentYear', _studentYear);
                prefs.setString('studentDept', _studentDept);
                prefs.setString('profilePicUrl', _profilePicUrl);
                prefs.setString('studentBusNo', _studentBusNo);
              });
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isEditingProfile = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch profile from Firebase: $e");
    }
    // Check if the student has previously selected a route manually
    final savedRoute = prefs.getString('studentSelectedRoute');
    final isGuest = widget.studentRollNo.toLowerCase() == 'guest';

    if (savedRoute != null && savedRoute.isNotEmpty) {
      // User manually selected a route before — use it directly
      setState(() {
        _selectedRoute = savedRoute;
      });
      _updateRouteDetails(_selectedRoute, startListener: true);
    } else if (_studentBusNo.isNotEmpty && Firebase.apps.isNotEmpty) {
      // No saved route — listen dynamically to the drivers node for this bus
      _listenToDriverRoute();
      _updateRouteDetails(_selectedRoute, startListener: true);
    } else if (isGuest) {
      setState(() {
        _selectedRoute = "";
      });
      _updateRouteDetails(_selectedRoute, startListener: true);
    } else {
      _updateRouteDetails(_selectedRoute, startListener: true);
    }

    _startPickupRequestListener();
    _listenForStudentIntercomMessages();
  }

  void _updateRouteDetails(String routeKey, {bool startListener = true}) {
    _routeStops = List<String>.from(_dynamicRouteStops[routeKey] ?? []);
    if (_routeStops.isNotEmpty && _routeStops.last != "COLLEGE" && _routeStops.last != "Panimalar Engineering College") {
      _routeStops.add("COLLEGE");
    }
    if (_savedStop.isNotEmpty && !_routeStops.contains(_savedStop)) {
      _savedStop = "";
    }
    _processCoordinatesForCurrentRoute();

    final match = RegExp(r'route_(\d+)').firstMatch(routeKey);
    if (match != null) {
      _busFirebaseId = match.group(1)!;
    } else {
      _busFirebaseId = routeKey;
    }

    _routeColor = const Color(0xFF2563EB);
    try {
      if (_dynamicRouteColors.containsKey(routeKey)) {
        _routeColor = Color(
          int.parse(_dynamicRouteColors[routeKey]!.replaceFirst('#', '0xFF')),
        );
      }
    } catch (_) {}

    if (startListener) {
      _startFirebaseListener();
    }

    _fetchBusOsrmRoute();
  }

  Future<void> _fetchBusOsrmRoute() async {
    // The user explicitly requested NO connecting lines on the live tracker map.
    // We skip the slow OSRM HTTP fetch entirely to make the map load instantly.
    if (mounted) {
      setState(() {
        _busRoutePoints = [];
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
        'boardingStop': '',
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentSelectedRoute', routeKey);
    await prefs.setString('studentSavedStop', '');
    _showSnackBar("Route switched to ${_dynamicRouteLabels[routeKey]}");
  }

  void _saveStop(String stopName) async {
    setState(() {
      _savedStop = stopName;
      _hasAlertedApproaching = false;
      _hasAlertedArrived = false;
    });
    if (Firebase.apps.isNotEmpty) {
      await FirebaseDatabase.instance.ref('students/$_studentId').update({
        'boardingStop': stopName,
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentSavedStop', stopName);
    _showSnackBar("⭐ Boarding stop saved: ${_formatStopName(stopName)}");
  }

  String _deptToShortForm(String dept) {
    if (dept.contains('(AIML)')) return 'AIML';
    if (dept.contains('(CSE)')) return 'CSE';
    if (dept.contains('(AIDS)')) return 'AIDS';
    if (dept.contains('(CSBS)')) return 'CSBS';
    if (dept.contains('(ECE)')) return 'ECE';
    if (dept.contains('(EEE)')) return 'EEE';
    if (dept.contains('(IT)')) return 'IT';
    if (dept.contains('(MECH)')) return 'MECH';
    if (dept.contains('(CIVIL)')) return 'CIVIL';
    if (dept == 'MBA') return 'MBA';
    if (dept == 'Nursing') return 'NURSING';
    if (dept == 'Medical') return 'MEDICAL';
    if (dept == 'Allied Science') return 'ALLIED';
    if (dept == 'H&S') return 'HS';
    return dept.substring(0, min(3, dept.length)).toUpperCase();
  }

  void _saveProfile(
    String name,
    String year,
    String dept, {
    String busNo = '',
    String boardingStop = '',
    String rollNo = '',
  }) async {
    String actualRollNo = (rollNo.isNotEmpty ? rollNo : widget.studentRollNo).trim().toUpperCase();

    if (widget.isFaculty && widget.isFirstTimeSignup) {
      if (Firebase.apps.isNotEmpty) {
        final shortDept = _deptToShortForm(dept);
        final snapshot = await FirebaseDatabase.instance.ref('faculty').get();
        int maxId = 0;
        if (snapshot.exists && snapshot.value != null) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          for (final key in data.keys) {
            final keyStr = key.toString();
            if (keyStr.startsWith(shortDept)) {
              final numStr = keyStr.substring(shortDept.length);
              final idInt = int.tryParse(numStr) ?? 0;
              if (idInt > maxId) maxId = idInt;
            }
          }
        }
        maxId++;
        final generatedIdStr = maxId.toString().padLeft(3, '0');
        actualRollNo = '$shortDept$generatedIdStr';
        
        // Show an alert dialog to tell the faculty their ID
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              bool copied = false;
              return StatefulBuilder(
                builder: (context, setStateSB) {
                  return Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 10,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.badge_rounded,
                              color: Color(0xFF15803D),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Profile Created 🎉',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Please copy your ID or take a screenshot of this page for future logins.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.screenshot_rounded, size: 16, color: Color(0xFFDC2626)),
                                SizedBox(width: 6),
                                Text(
                                  "Please take a screenshot!",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'GENERATED FACULTY ID',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  actualRollNo,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2563EB),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "⚠️ You can log in only with this Faculty ID in the future.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: copied ? const Color(0xFF15803D) : const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              minimumSize: const Size(double.infinity, 44),
                            ),
                            icon: Icon(copied ? Icons.check : Icons.copy_rounded, size: 16),
                            label: Text(
                              copied ? 'Copied to Clipboard!' : 'Copy Faculty ID',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: actualRollNo));
                              setStateSB(() {
                                copied = true;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              foregroundColor: const Color(0xFF475569),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                            },
                            child: const Text(
                              'Got it, Proceed',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        }
      }
    }

    if (actualRollNo.trim().isEmpty) {
      _showSnackBar(widget.isFaculty ? "Faculty ID generation failed" : "Roll No is required");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentName', name);
    await prefs.setString('studentYear', year);
    await prefs.setString('studentDept', dept);
    await prefs.setString('profilePicUrl', _profilePicUrl);
    await prefs.setString('studentBusNo', busNo);
    await prefs.setString('studentSavedStop', boardingStop);
    // Always persist the roll number — covers first-time signup AND edits
    await prefs.setString('studentRollNo', actualRollNo);

    setState(() {
      _studentName = name;
      _studentYear = year;
      _studentDept = dept;
      
      bool busChanged = _studentBusNo != busNo;
      _studentBusNo = busNo;
      _savedStop = boardingStop;
      _studentId = actualRollNo;
      
      if (busChanged) {
        _listenToDriverRoute();
      }
    });

    try {
      if (Firebase.apps.isNotEmpty) {
        final node = widget.isFaculty ? 'faculty' : 'students';
        await FirebaseDatabase.instance.ref('$node/$actualRollNo').update({
          'name': name,
          'year': widget.isFaculty ? '' : year,
          'department': dept,
          'busNo': busNo,
          'boardingStop': boardingStop,
          'profilePicBase64': _profilePicUrl.startsWith('base64:')
              ? _profilePicUrl
              : '',
        });
      }
    } catch (e) {
      _showSnackBar("Warning: Network error saving to Firebase");
    }

    setState(() {
      if (busNo.isNotEmpty) {
        if (_fetchedRouteKey != null) {
          _selectedRoute = _fetchedRouteKey!;
          _updateRouteDetails(_selectedRoute, startListener: true);
        } else {
          _updateRouteDetails(_selectedRoute, startListener: true);
        }
      } else {
        SharedPreferences.getInstance().then(
          (p) => p.setString('studentSelectedRoute', ''),
        );
      }

      if (widget.isFirstTimeSignup) {
        _currentIndex = 0;
      }
      _isEditingProfile = false;
    });

    // Notify parent shell of the (possibly new) roll number so auto-login is always in sync
    if (widget.onFirstTimeSave != null) {
      widget.onFirstTimeSave!(actualRollNo);
    }

    _showSnackBar("✅ Profile saved successfully");
  }

  Future<void> _uploadProfilePhoto() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
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
              _profilePicUrl = 'base64:$base64String';
              try {
                _cachedProfileImage = MemoryImage(imageBytes!);
              } catch (_) {
                _cachedProfileImage = null;
              }
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
      _studentIntercomSub = FirebaseDatabase.instance
          .ref('voice_messages/student_$_studentId')
          .onValue
          .listen((event) {
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
      await FirebaseDatabase.instance
          .ref('voice_messages/student_$_studentId/$msgId')
          .set({
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

        final String apiUrl = kIsWeb
            ? 'https://panimalr-bus.onrender.com/api/voice'
            : 'https://panimalr-bus.onrender.com/api/voice';

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
          await FirebaseDatabase.instance
              .ref('voice_messages/student_$_studentId/$msgId')
              .set({
                'sender': 'student',
                'senderName': _studentName,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'msg':
                    '[Voice Message - 0:${duration.toString().padLeft(2, '0')}] "$mongoId"',
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
        final String apiUrl = kIsWeb
            ? 'https://panimalr-bus.onrender.com/api/voice/$mongoId'
            : 'https://panimalr-bus.onrender.com/api/voice/$mongoId';
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
      _pickupRequestSub = FirebaseDatabase.instance
          .ref('pickup_requests/$_studentId')
          .onValue
          .listen((event) {
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
      _logsSub = FirebaseDatabase.instance
          .ref('arrival_logs/$today')
          .onValue
          .listen((event) {
            final data = event.snapshot.value as Map?;
            final List<LogEntry> temp = [];
            if (data != null) {
              data.forEach((key, val) {
                if (val is Map) {
                  temp.add(
                    LogEntry(
                      id:
                          (val['timestamp'] as num?)?.toDouble() ??
                          DateTime.now().millisecondsSinceEpoch.toDouble(),
                      bus: val['bus'] ?? key,
                      driver: val['driver'] ?? 'Unknown',
                      route: val['route'] ?? 'Unknown',
                      date: val['date'] ?? today,
                      arrived: val['arrived'],
                      departed: val['departed'],
                      status: val['status'] ?? 'arrived',
                    ),
                  );
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
      bool isInitialSnapshot = true;

      final cleanTarget = targetBusId.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
      final numTarget = _extractBusNumber(targetBusId);

      _locationSub = FirebaseDatabase.instance
          .ref('liveLocations')
          .onValue
          .listen(
            (event) {
              if (!mounted) return;

              Map? data;
              final rootMap = event.snapshot.value as Map?;
              if (rootMap != null) {
                // 1. Direct match on key
                if (rootMap.containsKey(targetBusId) && rootMap[targetBusId] is Map) {
                  data = rootMap[targetBusId] as Map;
                } else if (numTarget.isNotEmpty && rootMap.containsKey(numTarget) && rootMap[numTarget] is Map) {
                  data = rootMap[numTarget] as Map;
                } else if (cleanTarget.isNotEmpty && rootMap.containsKey(cleanTarget) && rootMap[cleanTarget] is Map) {
                  data = rootMap[cleanTarget] as Map;
                } else {
                  // 2. Flexible search across all liveLocations keys and nested driver properties
                  Map? bestMatch;
                  for (final entry in rootMap.entries) {
                    final kStr = entry.key.toString();
                    final kClean = kStr.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();
                    final kNum = _extractBusNumber(kStr);

                    bool matches = false;

                    if (numTarget.isNotEmpty && kNum.isNotEmpty && numTarget == kNum) {
                      matches = true;
                    } else if (cleanTarget.isNotEmpty && (kClean == cleanTarget || kStr.toLowerCase().contains(cleanTarget))) {
                      matches = true;
                    }

                    if (!matches && entry.value is Map) {
                      final candidateMap = entry.value as Map;
                      final bBus = candidateMap['bus']?.toString() ?? '';
                      final bRoute = candidateMap['route']?.toString() ?? '';
                      final bBusNum = _extractBusNumber(bBus);
                      final bRouteNum = _extractBusNumber(bRoute);

                      if (numTarget.isNotEmpty && (bBusNum == numTarget || bRouteNum == numTarget)) {
                        matches = true;
                      } else if (cleanTarget.isNotEmpty && (bRoute.toLowerCase().contains(cleanTarget) || bBus.toLowerCase().contains(cleanTarget))) {
                        matches = true;
                      }
                    }

                    if (matches && entry.value is Map) {
                      final candidateMap = entry.value as Map;
                      final st = (candidateMap['status'] as String? ?? 'offline').toLowerCase().trim();
                      if (st == 'tracking' || st == 'online' || st == 'broken' || st == 'active') {
                        bestMatch = candidateMap;
                        break;
                      } else {
                        bestMatch ??= candidateMap;
                      }
                    }
                  }
                  data = bestMatch;
                }
              }

              final rawStatus = (data?['status'] as String? ?? 'offline').toLowerCase().trim();
              final rawUpdatedAt = data?['updatedAt']?.toString() ?? '';

              bool isStale = false;
              if (rawUpdatedAt.isNotEmpty) {
                try {
                  final parsedTime = DateTime.tryParse(rawUpdatedAt);
                  if (parsedTime != null) {
                    final ageSeconds = DateTime.now().difference(parsedTime.toLocal()).inSeconds;
                    if (ageSeconds > 300) { // 5 minutes stale threshold
                      isStale = true;
                    }
                  }
                } catch (_) {}
              }

              final repNum = _extractBusNumber(_replacementBus);
              final isTrackingReplacement = _breakdownActive && repNum.isNotEmpty && numTarget.isNotEmpty && numTarget == repNum;

              final bool isBroken = (rawStatus == 'broken' || (_breakdownActive && !isTrackingReplacement)) && _replacementBus.isEmpty;
              final bool isLive = (rawStatus == 'tracking' || rawStatus == 'online' || rawStatus == 'active') && !isStale;
              final bool isCompleted = (rawStatus == 'completed' || rawStatus == 'arrived');

              final bool justCameOnline = !isInitialSnapshot && !_wasBusOnline && isLive;
              final bool justCompleted = !isInitialSnapshot && _wasBusOnline && isCompleted;

              if (isLive) {
                _hasAlertedTripCompleted = false;
              }

              if (isInitialSnapshot) {
                isInitialSnapshot = false;
                _hasAlertedTripCompleted = true;
              }

              if (data == null || (!isLive && !isCompleted)) {
                if (mounted) {
                  setState(() {
                    _wasBusOnline = false;
                    _busIsOnline = false;
                    _busStatus = isBroken ? "broken" : (isCompleted ? "completed" : "offline");
                    _hasAlertedApproachingRadius = false;
                  });
                }
                
                if (justCompleted && !_hasAlertedTripCompleted) {
                  _hasAlertedTripCompleted = true;
                  _showInAppNotification(
                    "🏁 Trip Completed",
                    "Bus $_displayBusId has completed its trip.",
                    "🏁",
                    durationMs: 8000,
                  );
                }
                return;
              }

              if (mounted) {
                setState(() {
                  _busIsOnline = isLive;
                  _wasBusOnline = isLive;
                  final rawLat = (data?['lat'] as num?)?.toDouble() ?? 0.0;
                  final rawLng = (data?['lng'] as num?)?.toDouble() ?? 0.0;

                  if (rawLat != 0.0 || rawLng != 0.0) {
                    _busLat = rawLat;
                    _busLng = rawLng;
                  }

                  _busAccuracy =
                      (data?['acc'] as num?)?.toDouble() ??
                      (data?['accuracy'] as num?)?.toDouble() ??
                      10.0;
                  _busStatus = rawStatus;
                  _busDirection = data?['direction'] as String? ?? data?['tripType'] as String? ?? "To College";

                  final rawUpdatedAt = data?['updatedAt'] as String?;
                  if (rawUpdatedAt != null) {
                    try {
                      final dt = DateTime.parse(rawUpdatedAt).toLocal();
                      _busUpdatedAt =
                          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
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
              }

              bool ignoreTripStart = false;
              if (justCameOnline && _lastBreakdownClearTime != null) {
                if (DateTime.now().difference(_lastBreakdownClearTime!).inMinutes < 2) {
                  ignoreTripStart = true;
                }
              }

              if (justCameOnline && !ignoreTripStart) {
                _showInAppNotification(
                  "🚌 Bus Started",
                  "Bus $_displayBusId has started tracking. Live GPS is now active.",
                  "✅",
                  durationMs: 10000,
                );
                if (mounted) {
                  setState(() {
                    _isFollowingBus = true;
                  });
                }
                // Auto-pan to bus location when it comes online
                if (_busLat != null && _busLng != null) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      _mapController.move(LatLng(_busLat!, _busLng!), 14.0);
                    }
                  });
                }
              } else if (justCompleted && !_hasAlertedTripCompleted) {
                _hasAlertedTripCompleted = true;
                _showInAppNotification(
                  "🏁 Trip Completed",
                  "Bus $_displayBusId has completed its trip.",
                  "🏁",
                  durationMs: 8000,
                );
              }

              if (_isFollowingBus &&
                  !justCameOnline &&
                  _busLat != null &&
                  _busLng != null) {
                try {
                  if (mounted) {
                    _mapController.move(
                      LatLng(_busLat!, _busLng!),
                      _mapController.camera.zoom,
                    );
                  }
                } catch (_) {}
              }

              if (_savedStop.isNotEmpty && _busLat != null && _busLng != null && _routeStops.isNotEmpty) {
                final nearestIdx = _getNearestStopIndex(_busLat!, _busLng!);
                final displayStops = _effectiveDisplayStops;
                final myStopIdx = displayStops.indexOf(_savedStop);
                final logicalNearestIdx = displayStops.indexOf(
                  displayStops[nearestIdx < displayStops.length ? nearestIdx : 0],
                );

                if (logicalNearestIdx == 0) {
                  _hasAlertedApproaching = false;
                  _hasAlertedArrived = false;
                }

                if (myStopIdx != -1) {
                  if (logicalNearestIdx == myStopIdx - 1 &&
                      !_hasAlertedApproaching) {
                    _hasAlertedApproaching = true;
                    _showInAppNotification(
                      "Bus $targetBusId is approaching!",
                      "Bus $targetBusId is at ${_formatStopName(displayStops[logicalNearestIdx])}, which is 1 stop away from ${_formatStopName(_savedStop)}.",
                      "🔔",
                    );
                  } else if (logicalNearestIdx == myStopIdx &&
                      !_hasAlertedArrived) {
                    _hasAlertedArrived = true;
                    _showInAppNotification(
                      "Bus $targetBusId has arrived!",
                      "Bus $targetBusId is now at your boarding stop: ${_formatStopName(_savedStop)}. Get ready to board!",
                      "🚏",
                    );
                  }
                }

                // Proximity Radius Alert
                final stopCoords = _coords[_savedStop];
                if (stopCoords != null) {
                  double distanceMeters = _haversineM(
                    _busLat!,
                    _busLng!,
                    stopCoords.latitude,
                    stopCoords.longitude,
                  );
                  if (distanceMeters <= _alertRadiusMeters &&
                      !_hasAlertedApproachingRadius) {
                    _hasAlertedApproachingRadius = true;
                    _showInAppNotification(
                      "Bus is approaching!",
                      "The bus is within ${(_alertRadiusMeters / 1000).toStringAsFixed(1)}km of your stop. Be ready!",
                      "🔔",
                    );
                  } else if (distanceMeters > _alertRadiusMeters) {
                    _hasAlertedApproachingRadius = false;
                  }
                }
              }
            },
            onError: (e) {
              debugPrint("Database listen error: $e");
            },
          );
    }

    try {
      startLocationTracker(_selectedRoute.isNotEmpty ? _selectedRoute : _busFirebaseId);

      _breakdownSub = FirebaseDatabase.instance
          .ref('breakdowns')
          .onValue
          .listen(
            (event) {
              if (!mounted) return;
              final rootMap = event.snapshot.value as Map?;

              // Always use original selected route / bus ID to query breakdown status (NOT replacement bus ID)
              final targetBusNum = _extractBusNumber(_selectedRoute.isNotEmpty ? _selectedRoute : _busFirebaseId);
              final targetClean = _selectedRoute.toLowerCase().replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '').replaceAll('route_', '').trim();

              Map? data;
              if (rootMap != null) {
                // 1. Direct key match
                if (_busFirebaseId.isNotEmpty && rootMap.containsKey(_busFirebaseId) && rootMap[_busFirebaseId] is Map) {
                  data = rootMap[_busFirebaseId] as Map;
                } else if (targetBusNum.isNotEmpty && rootMap.containsKey(targetBusNum) && rootMap[targetBusNum] is Map) {
                  data = rootMap[targetBusNum] as Map;
                } else {
                  // 2. Flexible search across keys and nested objects
                  for (final entry in rootMap.entries) {
                    final kStr = entry.key.toString();
                    final kNum = _extractBusNumber(kStr);
                    if (entry.value is Map) {
                      final valMap = entry.value as Map;
                      final busVal = valMap['busId']?.toString() ?? valMap['bus']?.toString() ?? kStr;
                      final busNum = _extractBusNumber(busVal);
                      if ((targetBusNum.isNotEmpty && (kNum == targetBusNum || busNum == targetBusNum)) ||
                          (targetClean.isNotEmpty && kStr.toLowerCase().contains(targetClean))) {
                        data = valMap;
                        break;
                      }
                    }
                  }
                }
              }

              if (data == null) {
                if (_breakdownActive) {
                  _lastBreakdownClearTime = DateTime.now();
                }
                setState(() {
                  _breakdownActive = false;
                  _replacementBus = "";
                  _processCoordinatesForCurrentRoute();
                });
                startLocationTracker(_selectedRoute.isNotEmpty ? _selectedRoute : _busFirebaseId);
                return;
              }

              final timestamp = (data['timestamp'] as num?)?.toInt() ?? 0;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - timestamp > 12 * 60 * 60 * 1000) {
                // Old breakdown from yesterday, ignore it
                setState(() {
                  _breakdownActive = false;
                  _replacementBus = "";
                  _processCoordinatesForCurrentRoute();
                });
                startLocationTracker(_selectedRoute.isNotEmpty ? _selectedRoute : _busFirebaseId);
                return;
              }

              final isNew = !_breakdownActive;
              final repBus = data['replacement'] as String? ?? "Unknown";
              setState(() {
                _breakdownActive = true;
                if (isNew) _breakdownDismissed = false;
                _replacementBus = repBus;
                _processCoordinatesForCurrentRoute();
              });

              if (isNew) {
                _showInAppNotification(
                  "⚠️ Bus Breakdown Alert",
                  repBus != "Unknown" && repBus.isNotEmpty
                      ? "Bus $targetBusNum breakdown reported. Replacement Bus $repBus dispatched to pick you up!"
                      : "Bus $targetBusNum breakdown reported. Please wait for replacement bus update.",
                  "⚠️",
                  durationMs: 8000,
                );
              }

              if (_replacementBus.isNotEmpty && _replacementBus != "Unknown") {
                startLocationTracker(_replacementBus);
              } else {
                startLocationTracker(_selectedRoute.isNotEmpty ? _selectedRoute : _busFirebaseId);
              }
            },
            onError: (e) {
              debugPrint("Breakdown database listen error: $e");
            },
          );
    } catch (e) {
      debugPrint("Error starting database listener: $e");
    }
  }

  void _showInAppNotification(
    String title,
    String body,
    String icon, {
    int durationMs = 5000,
  }) {
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
      if (_busLat == null ||
          _busLng == null ||
          _renderLat == null ||
          _renderLng == null) {
        return;
      }
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
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  int _getNearestStopIndex(double lat, double lng) {
    final displayStops = _effectiveDisplayStops;
    if (displayStops.isEmpty) return 0;
    if (displayStops.length == 1) return 0;

    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < displayStops.length; i++) {
      final coord = _coords[displayStops[i]];
      if (coord == null) continue;
      final dist = _haversineKm(lat, lng, coord.latitude, coord.longitude);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    int nextIdx = closestIdx;
    if (closestIdx < displayStops.length - 1) {
      final cCurr = _coords[displayStops[closestIdx]];
      final cNext = _coords[displayStops[closestIdx + 1]];
      if (cCurr != null && cNext != null) {
        double vX = cNext.longitude - cCurr.longitude;
        double vY = cNext.latitude - cCurr.latitude;
        double uX = lng - cCurr.longitude;
        double uY = lat - cCurr.latitude;
        double dot = uX * vX + uY * vY;
        if (dot > 0) {
          nextIdx = closestIdx + 1;
        }
      }
    }

    final nextStopName = displayStops[nextIdx];
    final originalIdx = _effectiveDisplayStops.indexOf(nextStopName);
    return originalIdx != -1 ? originalIdx : 0;
  }

  int? _calculateEtaMinutes(int nearestIdx) {
    if (_effectiveDisplayStops.isEmpty ||
        !_busIsOnline ||
        _busLat == null ||
        _busLng == null ||
        _savedStop.isEmpty) {
      return null;
    }
    if (_busLat == 0.0 && _busLng == 0.0) return null;

    final displayStops = _effectiveDisplayStops;
    final myStopIdx = displayStops.indexOf(_savedStop);
    final logicalNearestIdx = displayStops.indexOf(_effectiveDisplayStops[nearestIdx < _effectiveDisplayStops.length ? nearestIdx : 0]);

    if (myStopIdx == -1 || logicalNearestIdx > myStopIdx) return null;

    double totalDist = 0.0;
    double currentLat = _busLat!;
    double currentLng = _busLng!;

    for (int i = logicalNearestIdx; i <= myStopIdx; i++) {
      final stopName = displayStops[i];
      final stopCoord = _coords[stopName];
      if (stopCoord != null) {
        totalDist += _haversineKm(
          currentLat,
          currentLng,
          stopCoord.latitude,
          stopCoord.longitude,
        );
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
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
    final int nearestIdx = (_busLat != null && _busLng != null)
        ? _getNearestStopIndex(_busLat!, _busLng!)
        : 0;
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
                  _effectiveDisplayStops.isEmpty ? "Coming Soon" : (_savedStop.isEmpty ? "Not set" : _formatStopName(_savedStop)),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _effectiveDisplayStops.isEmpty ? null : () {
                    setState(() {
                      _savedStop = "";
                    });
                    if (Firebase.apps.isNotEmpty) {
                      FirebaseDatabase.instance
                          .ref('students/$_studentId')
                          .update({'savedStop': ''});
                    }
                    _showSnackBar("⭐ Boarding stop cleared");
                  },
                  child: Text(
                    _effectiveDisplayStops.isEmpty ? "--" : "Change stop",
                    style: const TextStyle(
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
                _effectiveDisplayStops.isEmpty ? "-" : (_busIsOnline ? (eta != null ? "$eta" : "Passed") : "-"),
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
    return Dismissible(
      key: const Key('in_app_notification'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() {
          _showNotification = false;
        });
      },
      child: Material(
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
                Text(_notifIcon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayBusId.isNotEmpty ? "PANIMALAR TRANSIT — BUS $_displayBusId" : "PANIMALAR TRANSIT",
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
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGuest = widget.studentRollNo.toLowerCase() == 'guest';
    final List<Widget> pages = [
      _buildHomeTab(),
      _buildTrackTab(),
      _buildCampusNavTab(),
      if (!isGuest) _buildProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            TweenAnimationBuilder(
              duration: const Duration(milliseconds: 800),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              curve: Curves.elasticOut,
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/panimalar_logo.png',
                    height: 36,
                    width: 36,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Panimalar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                Text(
                  'SMART TRANSIT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF3B82F6),
                    letterSpacing: 1.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Notification button with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_rounded,
                  color: Colors.black54,
                ),
                onPressed: _showNotificationsPanel,
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.blue, // Updated to blue
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
          if (isGuest)
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.black54),
              onPressed: widget.onLogout,
              tooltip: 'Exit Guest Mode',
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_savedStop.isNotEmpty) _buildGlobalMyStopBanner(),
              if (_latestAnnouncement != null) _buildAnnouncementTicker(),
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
      bottomNavigationBar: widget.isFirstTimeSignup ? const SizedBox.shrink() : Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: MaterialStateProperty.all(
              const TextStyle(fontSize: 10, overflow: TextOverflow.ellipsis),
            ),
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
            NavigationDestination(
              icon: const Icon(Icons.home_outlined, color: Color(0xFF64748B)),
              selectedIcon: const Icon(Icons.home, color: Color(0xFF2563EB)),
              label: t('student_home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined, color: Color(0xFF64748B)),
              selectedIcon: const Icon(Icons.map, color: Color(0xFF2563EB)),
              label: t('student_live_track'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.domain_outlined, color: Color(0xFF64748B)),
              selectedIcon: const Icon(Icons.domain, color: Color(0xFF2563EB)),
              label: t('student_campus_map'),
            ),
            if (!isGuest)
              NavigationDestination(
                icon: const Icon(Icons.person_outline, color: Color(0xFF64748B)),
                selectedIcon: const Icon(Icons.person, color: Color(0xFF2563EB)),
                label: t('student_profile'),
              ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final int nearestIdx = (_busLat != null && _busLng != null)
        ? _getNearestStopIndex(_busLat!, _busLng!)
        : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_breakdownActive && !_breakdownDismissed) _buildBreakdownBanner(),
          _buildSpecialBusBanner(),
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
                if (_selectedRoute.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF64748B)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Please complete your profile and select a route to view bus details and trip status.",
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: (_busStatus == 'broken' || _breakdownActive)
                          ? const Color(0xFFFEF2F2)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (_busStatus == 'broken' || _breakdownActive)
                            ? const Color(0xFFFCA5A5)
                            : (_busIsOnline
                                ? const Color(0xFFBBF7D0)
                                : const Color(0xFFE2E8F0)),
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
                            color: (_busStatus == 'broken' || _breakdownActive)
                                ? const Color(0xFFFEE2E2)
                                : (_busIsOnline
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            (_busStatus == 'broken' || _breakdownActive)
                                ? Icons.warning_amber_rounded
                                : Icons.directions_bus_rounded,
                            color: (_busStatus == 'broken' || _breakdownActive)
                                ? const Color(0xFFDC2626)
                                : (_busIsOnline
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF94A3B8)),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_busStatus == 'broken' || _breakdownActive)
                                    ? (_replacementBus.isNotEmpty && _replacementBus != 'Unknown'
                                          ? "Replacement Bus ${_extractBusNumber(_replacementBus)} assigned"
                                          : "Bus $_displayBusId Breakdown Reported")
                                    : (_busIsOnline
                                          ? "Bus $_displayBusId is online"
                                          : "Bus $_displayBusId is offline"),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: (_busStatus == 'broken' || _breakdownActive)
                                      ? const Color(0xFFDC2626)
                                      : (_busIsOnline
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFF64748B)),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (_busStatus == 'broken' || _breakdownActive)
                                    ? (_replacementBus.isNotEmpty && _replacementBus != 'Unknown'
                                          ? "Tracking Replacement Bus ${_extractBusNumber(_replacementBus)} for your route"
                                          : "Replacement bus dispatch pending • Stay at your stop")
                                    : (_busIsOnline
                                          ? "Active • Updated $_busUpdatedAt"
                                          : (_busStatus == 'completed'
                                                ? "Trip is completed"
                                                : "Trip not started")),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (_busStatus == 'broken' || _breakdownActive)
                                      ? const Color(0xFF991B1B)
                                      : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: (_busStatus == 'broken' || _breakdownActive)
                                ? const Color(0xFFEF4444)
                                : (_busIsOnline
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFCBD5E1)),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                if (_savedStop.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2563EB,
                          ).withValues(alpha: 0.05),
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
                                _effectiveDisplayStops.isEmpty ? "--" : (_savedStop.isEmpty ? "Not set" : _formatStopName(_savedStop)),
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
                                onTap: _routeStops.isEmpty ? null : () {
                                  setState(() => _savedStop = "");
                                  if (Firebase.apps.isNotEmpty) {
                                    FirebaseDatabase.instance
                                        .ref('students/$_studentId')
                                        .update({'savedStop': ''});
                                  }
                                },
                                child: Text(
                                  _routeStops.isEmpty ? "--" : "Change stop",
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
                              _busIsOnline
                                  ? (eta != null ? "$eta" : "🏁")
                                  : "—",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _busIsOnline
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              _routeStops.isEmpty 
                                  ? "--"
                                  : (_busIsOnline
                                      ? (eta != null ? "min away" : "Passed")
                                      : "offline"),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
                    border: Border.all(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _routeSearchCtrl,
                    onChanged: (val) => setState(() => _routeSearchQuery = val),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      hintText: "Search bus stop or route no...",
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: Color(0xFF2563EB),
                        ),
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
                        final matches = _dynamicRouteLabels.keys.where((key) {
                          final label =
                              _dynamicRouteLabels[key]?.toLowerCase() ?? '';
                          final stops = _dynamicRouteStops[key] ?? [];
                          final stopsMatch = stops.any(
                            (s) => s.toLowerCase().contains(query),
                          );
                          return label.contains(query) || stopsMatch;
                        }).toList();
                        if (matches.isEmpty) {
                          return const Center(
                            child: Text(
                              "No routes found",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final key = matches[idx];
                            final label = _dynamicRouteLabels[key] ?? key;
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: _selectedRoute == key
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () {
                                  _changeSelectedRoute(key);
                                  _routeSearchCtrl.clear();
                                  setState(() => _routeSearchQuery = "");
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                if (_routeSearchQuery.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.directions_bus,
                          size: 18,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Selected: $_effectiveRouteLabel",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                  child: Builder(
                    builder: (context) {
                      final displayStops = _effectiveDisplayStops;
                      String? closestStopToBus;
                      if (_allBusesLocations.containsKey(_displayBusId)) {
                        final busData = _allBusesLocations[_displayBusId];
                        if (busData != null && busData['lat'] != null && busData['lng'] != null) {
                          double minDistance = double.infinity;
                          for (String stop in displayStops) {
                            if (_coords.containsKey(stop)) {
                              double dist = _haversineM(
                                busData['lat'],
                                busData['lng'],
                                _coords[stop]!.latitude,
                                _coords[stop]!.longitude,
                              );
                              if (dist < minDistance) {
                                minDistance = dist;
                                closestStopToBus = stop;
                              }
                            }
                          }
                        }
                      }
                      return Column(
                        children: [
                          for (int i = 0; i < displayStops.length; i++) ...[
                            _buildStopRow(
                              displayStops[i],
                              index: i,
                              isFirst: i == 0,
                              isLast: i == displayStops.length - 1,
                              isMyStop: _savedStop == displayStops[i],
                              isBusHere: closestStopToBus == displayStops[i],
                            ),
                            if (i < displayStops.length - 1) _buildStopConnector(),
                          ],
                        ],
                      );
                    }
                  ),
                ),
                const SizedBox(height: 6),
                if (_effectiveDisplayStops.isNotEmpty)
                  Center(
                    child: Text(
                      "Showing ${_effectiveDisplayStops.length} of ${_effectiveDisplayStops.length} stops",
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Center(
                      child: Text(
                        "Route stops coming soon...",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.redAccent,
                        ),
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

  Widget _buildStopRow(
    String stopName, {
    int index = -1,
    bool isFirst = false,
    bool isLast = false,
    bool isMyStop = false,
    bool isBusHere = false,
  }) {
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
          child: isBusHere
              ? const _BlinkingBusIcon()
              : Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: isMyStop
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: isMyStop
                        ? const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                        : null,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _formatStopName(stopName, index: index),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: fWeight,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
        if (!isLast && !isMyStop)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 20),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _saveStop(stopName),
            child: const Text(
              "Set My Stop",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        if (isMyStop)
          const Text(
            "⭐ Boarding",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2563EB),
            ),
          ),
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

  Map<String, dynamic>? _getLiveBusData(Map<String, dynamic> b) {
    final possibleKeys = [
      b['id']?.toString().toLowerCase().trim(),
      b['id']?.toString().replaceAll(RegExp(r'^[Bb]'), '').toLowerCase().trim(),
      b['bus']?.toString().toLowerCase().trim(),
      b['bus']?.toString().replaceAll(RegExp(r'^[Bb]us\s+'), '').toLowerCase().trim(),
      b['route']?.toString().toLowerCase().trim(),
      b['route']?.toString().replaceAll('route_', '').toLowerCase().trim(),
    ];

    for (final key in possibleKeys) {
      if (key != null) {
        for (final entryKey in _allBusesLocations.keys) {
          if (entryKey.toLowerCase().trim() == key) {
            final liveData = _allBusesLocations[entryKey]!;
            final liveStatus = liveData['status'] as String? ?? 'offline';
            final rawUpdatedAt = liveData['updatedAt'] as String?;
            bool isStale = false;
            if (rawUpdatedAt != null) {
              try {
                final dt = DateTime.parse(rawUpdatedAt).toLocal();
                if (DateTime.now().difference(dt).inMinutes > 5) {
                  isStale = true;
                }
              } catch (_) {}
            }

            if (liveStatus != 'offline' && !isStale) {
              if (liveData['lat'] != null && liveData['lng'] != null) {
                return liveData;
              }
            }
          }
        }
      }
    }
    return null;
  }



  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 10,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownBanner() {
    final breakdownBusId = _busFirebaseId;
    final text = _replacementBus.isEmpty || _replacementBus == 'Unknown'
        ? "⚠️ Bus $breakdownBusId breakdown. Replacement Bus dispatch is pending. Stay at your stop."
        : "⚠️ Bus $breakdownBusId breakdown. Replacement Bus $_replacementBus dispatched. Stay at your stop.";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialBusBanner() {
    if (_specialBuses.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: _specialBuses.map((sb) {
          final List<dynamic> busesList = sb['buses'] ?? [];
          List<String> displayBuses = [];
          for (var b in busesList) {
            if (b is String) {
              displayBuses.add(b); // Legacy fallback
            } else if (b is Map) {
              String place = b['place']?.toString() ?? '';
              place = place.replaceAll(RegExp(r'^Route\s+.*?-\s*', caseSensitive: false), '');
              displayBuses.add('${b['bus']} ($place)');
            }
          }
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_bus, color: Color(0xFFD97706), size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SPECIAL BUS SCHEDULE - ${sb['time']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Color(0xFF92400E),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Operating Buses: ${displayBuses.join(", ")}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
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
                    "${_effectiveRouteLabel} • Live Tracker",
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
    final int nearestIdx = (_busLat != null && _busLng != null)
        ? _getNearestStopIndex(_busLat!, _busLng!)
        : 0;
    final int? eta = _calculateEtaMinutes(nearestIdx);

    final List<Marker> markers = [];

    // --- Nearby active online bus markers (if circle active on home) ---
    if (_showNearbyCircle) {
      final List<Map<String, dynamic>> combinedBuses = [];
      _allBusesLocations.forEach((busKey, liveData) {
        final liveStatus = liveData['status'] as String? ?? 'offline';
        if (liveStatus == 'offline') return;

        final cleanKey = busKey.toLowerCase()
            .replaceAll(RegExp(r'^[Bb]us\s*|^[Bb]'), '')
            .replaceAll('route_', '')
            .trim();

        final alreadyExists = combinedBuses.any((b) {
          final bClean = (b['id'] as String).toLowerCase()
              .replaceAll(RegExp(r'^[Bb]'), '')
              .trim();
          return bClean == cleanKey;
        });

        if (!alreadyExists) {
          String matchedRouteKey = 'route_$cleanKey';
          for (final rKey in _dynamicRouteLabels.keys) {
            final cleanRKey = rKey.replaceAll('route_', '');
            if (cleanRKey == cleanKey) {
              matchedRouteKey = rKey;
              break;
            }
          }
          final routeName = _dynamicRouteLabels[matchedRouteKey] ?? 'Route $cleanKey';

          combinedBuses.add({
            'id': 'B$cleanKey',
            'bus': 'Bus $cleanKey',
            'driver': 'College Driver',
            'contact': 'N/A',
            'route': matchedRouteKey,
            'routeName': routeName,
            'lat': (liveData['lat'] as num?)?.toDouble() ?? 13.04890,
            'lng': (liveData['lng'] as num?)?.toDouble() ?? 80.07546,
          });
        }
      });

      for (final b in combinedBuses) {
        final liveData = _getLiveBusData(b);
        if (liveData == null) continue;

        final lat = (liveData['lat'] as num).toDouble();
        final lng = (liveData['lng'] as num).toDouble();

        final distMeters = Geolocator.distanceBetween(
          _homeScanCenter.latitude,
          _homeScanCenter.longitude,
          lat,
          lng,
        );

        if (distMeters <= 1000.0) {
          markers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF22C55E),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "🚌",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Add center scan pin marker on Live Track map if dragged away from user loc
      final userLoc = (_studentLat != null && _studentLng != null)
          ? LatLng(_studentLat!, _studentLng!)
          : (_coords[_savedStop] ?? const LatLng(13.04890, 80.07546));
      
      if ((_homeScanCenter.latitude - userLoc.latitude).abs() > 0.001 ||
          (_homeScanCenter.longitude - userLoc.longitude).abs() > 0.001) {
        markers.add(
          Marker(
            point: _homeScanCenter,
            width: 32,
            height: 32,
            child: const Icon(
              Icons.location_on,
              color: Colors.red,
              size: 32,
            ),
          ),
        );
      }
    }

    // --- All Route Stop Markers (always visible) ---
    bool collegeAdded = false;
    for (var stopName in _effectiveDisplayStops) {
      final coord = _coords[stopName];
      if (coord == null) continue;

      final isCollege =
          stopName == "COLLEGE" || stopName == "Panimalar Engineering College";
      
      if (isCollege) collegeAdded = true;

      markers.add(
        Marker(
          point: coord,
          width: isCollege ? 40 : 30,
          height: isCollege ? 40 : 30,
          alignment: Alignment.center,
          child: Tooltip(
            message: _formatStopName(stopName),
            child: Container(
              decoration: BoxDecoration(
                color: isCollege ? const Color(0xFF1B5E20) : _routeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: isCollege
                    ? const Text("🏫", style: TextStyle(fontSize: 16))
                    : const Icon(
                        Icons.location_pin,
                        color: Colors.white,
                        size: 16,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    if (!collegeAdded) {
      markers.add(
        Marker(
          point: const LatLng(13.04890, 80.07546), // College default coordinate
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Tooltip(
            message: "COLLEGE",
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Text("🏫", style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
      );
    }

    // --- Live Bus Icon (only when bus is online and has location) ---
    if (_busLat != null && _busLng != null) {
      final currentLat = _renderLat ?? _busLat!;
      final currentLng = _renderLng ?? _busLng!;
      markers.add(
        Marker(
          point: LatLng(currentLat, currentLng),
          width: 80,
          height: 75,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  "Bus $_displayBusId",
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text("🚌", style: TextStyle(fontSize: 30)),
            ],
          ),
        ),
      );
    }

    // --- Nearest Stop Label (when bus is live) ---
    if (_busIsOnline && _routeStops.isNotEmpty) {
      final displayStops = _effectiveDisplayStops;
      final safeIdx = nearestIdx < displayStops.length ? nearestIdx : 0;
      final nearStop = displayStops[safeIdx];
      final nearCoord = _coords[nearStop];
      if (nearCoord != null) {
        markers.add(
          Marker(
            point: nearCoord,
            width: 120,
            height: 22,
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1D4ED8),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Builder(
                builder: (context) {
                  int idx = _effectiveDisplayStops.indexOf(nearStop);
                  String displayName = _formatStopName(nearStop, index: idx);
                  return Text(
                    "Next: $displayName",
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ),
          ),
        );
      }
    }

    String nearestStopName = _busIsOnline ? "Searching…" : "--";
    if (_busIsOnline && _effectiveDisplayStops.isNotEmpty) {
      final displayStops = _effectiveDisplayStops;
      final safeIdx = nearestIdx < displayStops.length ? nearestIdx : 0;
      nearestStopName = displayStops[safeIdx];
      if (nearestStopName == displayStops.last && _busLat != null && _busLng != null) {
        final lastCoord = _coords[nearestStopName];
        if (lastCoord != null) {
          final dist = _haversineKm(_busLat!, _busLng!, lastCoord.latitude, lastCoord.longitude);
          if (dist < 0.15) { // within 150m of final stop
            nearestStopName = "Arrived at Destination";
          }
        }
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _coords.isNotEmpty
                ? _coords.values.first
                : const LatLng(13.047, 80.11),
            initialZoom: 12.0,
            maxZoom: 22.0,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(6.75, 68.16),
                const LatLng(35.5, 97.4),
              ),
            ),
            onPositionChanged: (position, hasGesture) {
              if (hasGesture && _isFollowingBus) {
                setState(() => _isFollowingBus = false);
              }
            },
          ),
          children: [
            // Map tiles
            TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.panimalar.bus',
              maxNativeZoom: 19,
              maxZoom: 22.0,
            ),

            // GPS accuracy circle around bus when live
            if (_busIsOnline &&
                _renderLat != null &&
                _renderLng != null &&
                _busAccuracy != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_renderLat!, _renderLng!),
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderColor: const Color(0xFF22C55E),
                    borderStrokeWidth: 1.5,
                    useRadiusInMeter: true,
                    radius: (_busAccuracy! < 50 ? _busAccuracy! : 50),
                  ),
                ],
              ),

            if (_showNearbyCircle)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _homeScanCenter,
                    radius: 1000.0,
                    useRadiusInMeter: true,
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderColor: const Color(0xFF2563EB),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),

            if (_effectiveDisplayStops.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _effectiveDisplayStops
                        .map((s) => _coords[s])
                        .where((c) => c != null)
                        .cast<LatLng>()
                        .toList(),
                    color: const Color(0xFF2563EB),
                    strokeWidth: 4.0,
                  ),
                ],
              ),

            // All markers: stops + live bus icon
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
                    setState(() {
                      _savedStop = "";
                    });
                    if (Firebase.apps.isNotEmpty) {
                      FirebaseDatabase.instance
                          .ref('students/$_studentId')
                          .update({'savedStop': ''});
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 6),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _busIsOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
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
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
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
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
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
                          _displayBusId.isNotEmpty ? "BUS $_displayBusId DETAILS" : "ROUTE DETAILS",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _routeColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _effectiveRouteLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.gps_fixed,
                        color: _isFollowingBus
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF2563EB),
                      ),
                      onPressed: () {
                        if (_busLat != null && _busLng != null) {
                          setState(() => _isFollowingBus = true);
                          _mapController.move(LatLng(_busLat!, _busLng!), 14.5);
                        } else {
                          _showSnackBar("Location signal not received yet");
                        }
                      },
                    ),
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
                          const Text(
                            "NEXT STOP",
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              if (_routeStops.isEmpty) {
                                return const Text(
                                  "--",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                  ),
                                );
                              }
                              int idx = _effectiveDisplayStops.indexOf(nearestStopName);
                              String displayName = _formatStopName(nearestStopName, index: idx);
                              return Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 30,
                      color: const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "ACCURACY SIGNAL",
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _busIsOnline && _busAccuracy != null
                                ? "${_busAccuracy!.toStringAsFixed(1)} meters"
                                : "No Signal",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_savedStop.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
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
                              const Text(
                                "ETA TO MY STOP",
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: Color(0xFF1E40AF),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _routeStops.isEmpty ? "--" : _formatStopName(_savedStop),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _effectiveDisplayStops.isEmpty 
                              ? "Coming Soon" 
                              : (_busIsOnline
                                  ? (eta != null ? "$eta min" : "Passed")
                                  : "offline"),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E40AF),
                          ),
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
      selectedPoint = _campusPointsList.firstWhere(
        (p) => p.name == _selectedNavPointName,
      );
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
                    final dest = _campusPointsList.firstWhere(
                      (p) => p.name == cp.name,
                    );
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
                        color: isSelected
                            ? const Color(0xFF2563EB).withValues(alpha: 0.4)
                            : Colors.black26,
                        blurRadius: isSelected ? 8 : 4,
                      ),
                    ],
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF2563EB),
                      width: 2,
                    ),
                  ),
                  child: Text(cp.icon, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
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
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                  ),
                ),
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
                  color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
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
                      color: const Color(0xFF2563EB).withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Parked buses markers on Campus Map
    _allBusesLocations.forEach((busId, data) {
      if (data['status'] == 'parked' && data['lat'] != null && data['lng'] != null) {
        markers.add(
          Marker(
            point: LatLng(data['lat'], data['lng']),
            width: 64,
            height: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.directions_bus, color: Colors.white, size: 20),
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
                    "Bus $busId",
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });

    final filteredPoints = _campusPointsList
        .where(
          (p) => p.name.toLowerCase().contains(_searchFilter.toLowerCase()),
        )
        .toList();

    // Use OSRM-computed distance/time if available, else straight-line estimate
    final distanceM = _routeDistanceM > 0
        ? _routeDistanceM
        : (selectedPoint != null ? _distanceTo(selectedPoint) : 0.0);
    final walkMinutes = _routeWalkMinutes > 0
        ? _routeWalkMinutes
        : max(1, (distanceM / 83).ceil());

    return Stack(
      children: [
        FlutterMap(
          mapController: _campusMapController,
          options: MapOptions(
            initialCenter: const LatLng(13.049, 80.075),
            initialZoom: 16.5,
            maxZoom: 22.0,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(13.035, 80.060),
                const LatLng(13.062, 80.090),
              ),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.panimalar.bus',
              maxNativeZoom: 20,
              maxZoom: 22.0,
            ),
            if (_campusRoute != null) PolylineLayer(polylines: [_campusRoute!]),
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
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
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
                    .where(
                      (p) => p.name.toLowerCase().contains(val.toLowerCase()),
                    )
                    .toList();
                final newDest = matches.length == 1 ? matches.first.name : '';
                final destChanged =
                    newDest != _selectedNavPointName && newDest.isNotEmpty;
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
                        final dest = _campusPointsList.firstWhere(
                          (p) => p.name == _selectedNavPointName,
                        );
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
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _routeError.isNotEmpty
                          ? _routeError
                          : 'Location permission denied — enable in Settings',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Navigation info card — shown when a route is active ─────────────
        if (selectedPoint != null && _campusRoute != null && !_routeLoading)
          Positioned(
            top: _studentLocationDenied || _routeError.isNotEmpty ? 100 : 64,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navInfoCell(Icons.straighten, 'Dist', distanceM < 1000 ? '${distanceM.round()}m' : '${(distanceM / 1000).toStringAsFixed(1)}km', const Color(0xFF2563EB)),
                  _navDivider(),
                  _navInfoCell(Icons.near_me, 'Left', _routeRemainingM < 1000 ? '${_routeRemainingM.round()}m' : '${(_routeRemainingM / 1000).toStringAsFixed(1)}km', const Color(0xFF16A34A)),
                  _navDivider(),
                  _navInfoCell(Icons.directions_walk, 'Time', '$walkMinutes min', const Color(0xFFF59E0B)),
                ],
              ),
            ),
          ),

        // Bottom Detail Card — when a destination is selected
        if (selectedPoint != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white.withValues(alpha: 0.95),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
                      child: Center(child: Text(selectedPoint.icon, style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(selectedPoint.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                          if (_studentLat != null)
                            Text("Walking: $walkMinutes min (${distanceM.round()} m)", style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _clearRouteCache();
                        setState(() {
                          _selectedNavPointName = "";
                          _campusRoute = null;
                          _searchCtrl.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Search results list — shown when searching but no point selected yet
        if (filteredPoints.isNotEmpty && _searchFilter.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10),
                ],
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
          ),
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
  Widget _navDivider() =>
      Container(width: 1, height: 32, color: const Color(0xFFE2E8F0));

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
  static const double _campusRadiusMetres =
      600.0; // ~600 m covers the whole campus

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
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
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
                      backgroundImage: _cachedProfileImage,
                      child: _cachedProfileImage == null
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
                          child: const Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _studentName.isEmpty ? (widget.isFaculty ? "Faculty Name" : "Student Name") : _studentName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _studentName.isEmpty
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _studentId.isEmpty
                      ? "Panimalar Smart Transit Account"
                      : _studentId,
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
                Text(
                  widget.isFaculty ? "FACULTY DETAILS" : "STUDENT DETAILS",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                if (_isEditingProfile) ...[
                  if (_isEditingProfile && !(widget.isFaculty && widget.isFirstTimeSignup)) ...[
                    Text(
                      widget.isFaculty ? "FACULTY ID" : "ROLL NO",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _profileRollNoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: widget.isFaculty ? "Enter your Faculty ID" : "Enter your Roll No",
                        hintStyle: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
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
                      hintText: "Enter your full name", // placeholder
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1), // light colour
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!widget.isFaculty) ...[
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
                    initialValue: _profileTempYear.isNotEmpty
                        ? _profileTempYear
                        : null,
                    hint: const Text(
                      "Select year of study",
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "1st Year",
                        child: Text("1st Year"),
                      ),
                      DropdownMenuItem(
                        value: "2nd Year",
                        child: Text("2nd Year"),
                      ),
                      DropdownMenuItem(
                        value: "3rd Year",
                        child: Text("3rd Year"),
                      ),
                      DropdownMenuItem(
                        value: "4th Year",
                        child: Text("4th Year"),
                      ),
                    ],
                      onChanged: (val) {
                        if (val != null) setState(() => _profileTempYear = val);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

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
                    initialValue: _deptDropdownValue(),
                    hint: const Text(
                      "Select your department",
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                    ),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: "AI & Machine Learning (AIML)",
                        child: Text("AI & Machine Learning (AIML)"),
                      ),
                      DropdownMenuItem(
                        value: "Computer Science (CSE)",
                        child: Text("Computer Science (CSE)"),
                      ),
                      DropdownMenuItem(
                        value: "Information Technology (IT)",
                        child: Text("Information Technology (IT)"),
                      ),
                      DropdownMenuItem(
                        value: "Artificial Intelligence & DS (AIDS)",
                        child: Text("AI & Data Science (AIDS)"),
                      ),
                      DropdownMenuItem(
                        value: "Computer Science & BS (CSBS)",
                        child: Text("CS & Business Systems (CSBS)"),
                      ),
                      DropdownMenuItem(
                        value: "Electrical & Electronics (EEE)",
                        child: Text("Electrical & Electronics (EEE)"),
                      ),
                      DropdownMenuItem(
                        value: "Mechanical Engineering (MECH)",
                        child: Text("Mechanical Engineering (MECH)"),
                      ),
                      DropdownMenuItem(
                        value: "Nursing",
                        child: Text("Nursing"),
                      ),
                      DropdownMenuItem(
                        value: "Medical",
                        child: Text("Medical"),
                      ),
                      DropdownMenuItem(
                        value: "Electronics & Communication (ECE)",
                        child: Text("Electronics & Communication (ECE)"),
                      ),
                      DropdownMenuItem(
                        value: "Allied Science",
                        child: Text("Allied Science"),
                      ),
                      DropdownMenuItem(
                        value: "H&S",
                        child: Text("H&S"),
                      ),
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
                      if (_debounceTimer?.isActive ?? false) {
                        _debounceTimer!.cancel();
                      }
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 500),
                        () {
                          _fetchRouteForBus(val);
                        },
                      );
                    },
                    decoration: InputDecoration(
                      hintText: "e.g. 1, 3, 6, 23, 65",
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Icon(
                        Icons.directions_bus_rounded,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                      suffixIcon: _isFetchingRoute
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 2,
                        ),
                      ),
                      // Show route label as helper text when bus is recognised
                      helperText: () {
                        if (_isFetchingRoute) return 'Checking bus number...';
                        final key = _fetchedRouteKey;
                        if (key == null) return null;
                        return '✓  ${_dynamicRouteLabels[key] ?? ''}';
                      }(),
                      helperStyle: TextStyle(
                        color: _isFetchingRoute
                            ? const Color(0xFF64748B)
                            : const Color(0xFF16A34A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      errorText:
                          _profileBusCtrl.text.trim().isNotEmpty &&
                              !_isFetchingRoute &&
                              _fetchedRouteKey == null
                          ? 'Unknown bus number'
                          : null,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
                      initialValue: _profileBusStops.contains(_savedStop)
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
                        prefixIcon: const Icon(
                          Icons.location_on_outlined,
                          color: Color(0xFF2563EB),
                          size: 18,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 2,
                          ),
                        ),
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                      ),
                      isExpanded: true,
                      items: _profileBusStops
                          .asMap()
                          .entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.value,
                              child: Text(_formatStopName(entry.value, index: entry.key)),
                            ),
                          )
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
                        borderRadius: BorderRadius.circular(30),
                      ),
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
                        name,
                        year,
                        _studentDept,
                        busNo: _profileBusCtrl.text.trim().toUpperCase(),
                        boardingStop: _savedStop,
                        rollNo: _profileRollNoCtrl.text.trim().toUpperCase(),
                      );
                    },
                    child: const Text(
                      "💾  Save Profile",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ] else ...[
                  // ── View Mode ──────────────────────────────────────────────
                  _buildProfileRow("FULL NAME", _studentName),
                  const SizedBox(height: 12),
                  if (!widget.isFaculty) ...[
                    _buildProfileRow("YEAR OF STUDY", _studentYear),
                    const SizedBox(height: 12),
                  ],
                  _buildProfileRow("DEPARTMENT", _studentDept),
                  const SizedBox(height: 12),
                  _buildProfileRow(
                    widget.isFaculty ? "FACULTY ID" : "ROLL NO",
                    widget.studentRollNo.isEmpty ? "-" : widget.studentRollNo,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileRow(
                    "BUS NUMBER",
                    _studentBusNo.isEmpty ? "-" : _studentBusNo,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileRow(
                    "BOARDING STOP",
                    _savedStop.isEmpty ? "-" : _formatStopName(_savedStop),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditingProfile = true;
                      });
                    },
                    icon: const Icon(
                      Icons.edit,
                      color: Color(0xFF2563EB),
                      size: 18,
                    ),
                    label: const Text(
                      "Edit Profile",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                  if (widget.studentRollNo.toLowerCase() != 'guest' && !widget.isFaculty) ...[
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
                  ],
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                      color: Color(0xFFDC2626),
                    ), // Red for logout
                    foregroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
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
      "AI & Machine Learning (AIML)",
      "Computer Science (CSE)",
      "Information Technology (IT)",
      "Artificial Intelligence & DS (AIDS)",
      "Computer Science & BS (CSBS)",
      "Electrical & Electronics (EEE)",
      "Mechanical Engineering (MECH)",
      "Nursing",
      "Medical",
      "Electronics & Communication (ECE)",
      "Allied Science",
      "H&S",
    ];
    return valid.contains(_studentDept) ? _studentDept : null;
  }

  Widget _buildPickupRequestCard() {
    final bool isAllowed = _isUploadTimeAllowed();

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
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.access_time_filled, size: 14, color: Color(0xFFDC2626)),
                SizedBox(width: 6),
                Text(
                  "Allowed Timing: 1:30 PM - 2:00 PM IST only",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isAllowed ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: isAllowed ? _pickAndUploadFile : null,
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(
                isAllowed ? "Select & Upload Letter" : "Upload Closed (Allowed 1:30 PM - 2:00 PM)",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
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
          ),
        ],
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Attached Document",
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (_pickupRequestDocUrl.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.visibility, color: Color(0xFF2563EB)),
                  onPressed: () => _viewUploadedLetter(
                    _pickupRequestDoc,
                    _pickupRequestDocUrl,
                  ),
                ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          if (_pickupRequestStatus == "rejected" ||
              _pickupRequestStatus == "confirmed") ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time_filled, size: 12, color: Color(0xFF64748B)),
                SizedBox(width: 4),
                Text(
                  "Allowed Timing: 1:30 PM - 2:00 PM IST only",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                side: BorderSide(color: isAllowed ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: isAllowed ? _pickAndUploadFile : null,
              child: Text(
                isAllowed ? "Upload Another Document" : "Upload Closed (Allowed 1:30 PM - 2:00 PM)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: isAllowed ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    if (!_isUploadTimeAllowed()) {
      _showSnackBar("❌ Document upload is only allowed between 1:30 PM and 2:00 PM IST.");
      return;
    }
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
        _showVoiceReasonDialog(file);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("❌ Could not open file picker: $e");
      }
    }
  }

  Future<void> _showVoiceReasonDialog(PlatformFile file) async {
    final TextEditingController _documentDescCtrl = TextEditingController();
    
    setState(() {
      _isListeningSTT = false;
      _recognizedEnglishText = "";
      _translatedTamilReason = "";
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            void toggleListening() async {
              if (!_isListeningSTT) {
                bool available = await _speech.initialize(
                  onStatus: (val) => debugPrint('onStatus: $val'),
                  onError: (val) => debugPrint('onError: $val'),
                );
                if (available) {
                  setStateSB(() => _isListeningSTT = true);
                  _speech.listen(
                    onResult: (val) async {
                      setStateSB(() {
                        _recognizedEnglishText = val.recognizedWords;
                      });
                      if (_recognizedEnglishText.isNotEmpty) {
                        try {
                          var translation = await _translator.translate(_recognizedEnglishText, from: 'en', to: 'ta');
                          setStateSB(() {
                            _translatedTamilReason = translation.text;
                          });
                        } catch (e) {
                          debugPrint("Translation error: $e");
                        }
                      }
                    },
                  );
                } else {
                  _showSnackBar("Microphone permission denied.");
                }
              } else {
                setStateSB(() => _isListeningSTT = false);
                _speech.stop();
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Add a Description & Voice Reason", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 16),
                    TextField(
                      controller: _documentDescCtrl,
                      decoration: InputDecoration(
                        labelText: "Short Description (Required)",
                        hintText: "E.g., Medical Certificate for sick leave",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    SizedBox(height: 16),
                    GestureDetector(
                      onTap: toggleListening,
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: _isListeningSTT ? Colors.red : Color(0xFF2563EB),
                        child: Icon(_isListeningSTT ? Icons.mic : Icons.mic_none, color: Colors.white, size: 30),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(_isListeningSTT ? "Listening..." : "Tap to speak in English (Optional)", style: TextStyle(color: Colors.grey)),
                    if (_recognizedEnglishText.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Text("English: $_recognizedEnglishText", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      SizedBox(height: 8),
                      Text("Tamil: $_translatedTamilReason", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            if (_documentDescCtrl.text.trim().isEmpty) {
                              _showSnackBar("⚠️ Please provide a short description.");
                              return;
                            }
                            _speech.stop();
                            _translatedTamilReason = ""; // explicitly clear
                            _recognizedEnglishText = "";
                            Navigator.pop(ctx);
                            _uploadPickedFile(file, _documentDescCtrl.text.trim()); // proceed without reason
                          },
                          child: Text("Skip Voice"),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (_documentDescCtrl.text.trim().isEmpty) {
                              _showSnackBar("⚠️ Please provide a short description.");
                              return;
                            }
                            _speech.stop();
                            if (_recognizedEnglishText.isEmpty) {
                              // Proceed without voice reason if empty
                              Navigator.pop(ctx);
                              _uploadPickedFile(file, _documentDescCtrl.text.trim());
                              return;
                            }
                            
                            // Ensure translation is complete
                            if (_translatedTamilReason.isEmpty && _recognizedEnglishText.isNotEmpty) {
                              try {
                                var translation = await _translator.translate(_recognizedEnglishText, from: 'en', to: 'ta');
                                _translatedTamilReason = translation.text;
                              } catch (e) {
                                debugPrint("Translation error at confirm: $e");
                                _translatedTamilReason = _recognizedEnglishText; // fallback
                              }
                            }
                            
                            Navigator.pop(ctx);
                            _uploadPickedFile(file, _documentDescCtrl.text.trim()); // proceed with reason
                          },
                          child: Text("Confirm & Upload"),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _uploadPickedFile(PlatformFile file, String description) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  "Uploading file...",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      String base64Data = "";
      if (file.bytes != null) {
        base64Data = base64Encode(file.bytes!);
      } else if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        base64Data = base64Encode(bytes);
      }

      if (base64Data.isEmpty) {
        throw Exception("Failed to read file data.");
      }

      String mimeType = "application/octet-stream";
      if (file.name.toLowerCase().endsWith(".pdf")) {
        mimeType = "application/pdf";
      } else if (file.name.toLowerCase().endsWith(".png")) mimeType = "image/png";
      else if (file.name.toLowerCase().endsWith(".jpg") || file.name.toLowerCase().endsWith(".jpeg")) mimeType = "image/jpeg";

      final docRef = FirebaseDatabase.instance.ref('documents').push();
      final docId = docRef.key;

      if (docId == null) {
        throw Exception("Failed to generate document ID from Firebase.");
      }

      await docRef.set({
        'fileName': file.name,
        'mimeType': mimeType,
        'fileBase64': base64Data,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // No downloadUrl needed if we fetch from RTDB directly, but we can store the ID
      String downloadUrl = docId;

      if (mounted) {
        Navigator.pop(context); // Close dialog
        _sendRequestToAdmin(file.name, downloadUrl, description);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        _showSnackBar("❌ Upload failed: $e");
      }
    }
  }

  void _sendRequestToAdmin(String fileName, String downloadUrl, String description) async {
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
        'documentName': description.isNotEmpty ? description : fileName,
        'documentUrl': downloadUrl,
        'voiceReasonTamil': _translatedTamilReason, // Added translated reason
        'profilePicBase64': _profilePicUrl.startsWith('base64:') ? _profilePicUrl : '', // Pass profile pic
        'status': 'pending',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'savedStop': _savedStop.isNotEmpty ? _formatStopName(_savedStop) : "Not Selected",
      });
      _showSnackBar("📨 Request sent to Admin successfully!");
      setState(() {
        _translatedTamilReason = "";
        _recognizedEnglishText = "";
      });
    } catch (e) {
      _showSnackBar("❌ Error sending request: $e");
    }
  }

  void _viewUploadedLetter(String docName, String docUrl) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<DatabaseEvent>(
                  future: FirebaseDatabase.instance.ref('documents/$docUrl').once(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData || snapshot.data?.snapshot.value == null) {
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        ),
                      );
                    }
                    
                    final docData = snapshot.data!.snapshot.value as Map;
                    final base64String = docData['fileBase64'] as String?;
                    
                    if (base64String == null || base64String.isEmpty) {
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        ),
                      );
                    }
                    
                    final mimeType = docData['mimeType'] as String? ?? '';
                    final isImage = mimeType.startsWith('image/');
                    final isPdf = mimeType == 'application/pdf';
                    
                    if (isImage) {
                      return GestureDetector(
                        onTap: () {
                          // Full screen image on tap
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(12),
                              child: InteractiveViewer(
                                child: Image.memory(base64Decode(base64String)),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.memory(
                              base64Decode(base64String),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    } else {
                      return Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                size: 40,
                                color: isPdf ? Colors.red : Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text(
                                  docName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Close Preview",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
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
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        subtitle: const Text(
          "Send direct transcripts & voice notes to admin",
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
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
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
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
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            width: isVoice ? 220 : null,
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: Radius.circular(isMe ? 14 : 2),
                                bottomRight: Radius.circular(isMe ? 2 : 14),
                              ),
                              border: Border.all(
                                color: isMe
                                    ? const Color(0xFFBFDBFE)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isMe
                                      ? "You"
                                      : (msg['senderName'] ?? "Sender"),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: isMe
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFF64748B),
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
                                              ? Icons
                                                    .pause_circle_filled_rounded
                                              : Icons
                                                    .play_circle_filled_rounded,
                                          color: isMe
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF1E293B),
                                          size: 28,
                                        ),
                                        onPressed: () {
                                          _playVoiceMessage(
                                            msg['id'],
                                            msg['msg'] ?? '',
                                            msg['voiceDuration'] ?? 3,
                                          );
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                value:
                                                    _playingMsgId == msg['id']
                                                    ? _playbackProgress
                                                    : 0.0,
                                                backgroundColor: isMe
                                                    ? const Color(0xFFDBEAFE)
                                                    : const Color(0xFFE2E8F0),
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(
                                                      isMe
                                                          ? const Color(
                                                              0xFF2563EB,
                                                            )
                                                          : const Color(
                                                              0xFF64748B,
                                                            ),
                                                    ),
                                                minHeight: 3,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  "0:${(msg['voiceDuration'] as int? ?? 3).toString().padLeft(2, '0')}",
                                                  style: const TextStyle(
                                                    fontSize: 8,
                                                    color: Color(0xFF64748B),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons.volume_up,
                                                  size: 8,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? const Color(
                                              0xFFDBEAFE,
                                            ).withValues(alpha: 0.3)
                                          : const Color(
                                              0xFFE2E8F0,
                                            ).withValues(alpha: 0.5),
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
                                    t(msg['msg'] ?? ''),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
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
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF991B1B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: List.generate(8, (idx) {
                                  final height =
                                      3.0 +
                                      (idx % 2 == 0 ? 8.0 : 4.0) +
                                      (Random().nextDouble() * 5.0);
                                  return Container(
                                    width: 2,
                                    height: height,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
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
                          icon: const Icon(
                            Icons.cancel,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                          onPressed: _cancelRecordingVoice,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.check_circle,
                            color: Color(0xFF16A34A),
                            size: 20,
                          ),
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
                            hintStyle: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
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
                          child: const Icon(
                            Icons.mic,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAnnouncementTicker() {
    return GestureDetector(
      onTap: () {
        if (_latestAnnouncement?['attachmentBase64'] != null) {
          _showAttachmentDialog();
        }
      },
      child: Container(
        width: double.infinity,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.redAccent,
              alignment: Alignment.center,
              child: const Text(
                'UPDATE',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Marquee(
                  text: '${_latestAnnouncement?['title'] ?? ''}: ${_latestAnnouncement?['message'] ?? ''}${_latestAnnouncement?['attachmentBase64'] != null ? '   📎 Tap to view' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  blankSpace: 300.0,
                  velocity: 40.0,
                  startPadding: 10.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentDialog() {
    final String type = _latestAnnouncement?['attachmentType'] ?? 'image';
    final String base64Str = _latestAnnouncement?['attachmentBase64'] ?? '';
    if (base64Str.isEmpty) return;

    // Use base64Decode from dart:convert
    final bytes = base64Decode(base64Str);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(_latestAnnouncement?['title'] ?? 'Attachment', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Expanded(
                  child: type == 'pdf' 
                      ? SfPdfViewer.memory(bytes)
                      : InteractiveViewer(
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                ),
              ],
            ),
          ),
        );
      },
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

class _BlinkingBusIcon extends StatefulWidget {
  const _BlinkingBusIcon();

  @override
  State<_BlinkingBusIcon> createState() => _BlinkingBusIconState();
}

class _BlinkingBusIconState extends State<_BlinkingBusIcon> {
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
      opacity: _visible ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 300),
      child: const Text(
        "🚌",
        style: TextStyle(fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }
}
