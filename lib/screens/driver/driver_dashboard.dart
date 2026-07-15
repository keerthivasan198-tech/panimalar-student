import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/routes_config.dart';

class DriverDashboard extends StatefulWidget {
  final String driverBus;
  final String currentLang;
  final VoidCallback onLogout;
  final Function(String) onLanguageChanged;
  final VoidCallback onSwitchRole;

  const DriverDashboard({
    super.key,
    required this.driverBus,
    required this.currentLang,
    required this.onLogout,
    required this.onLanguageChanged,
    required this.onSwitchRole,
  });

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isTracking = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;

  String _appStatus = "Offline";
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _accuracy = 0.0;
  String _updatedAt = "--";
  String _gpsStatus = "Offline";
  String _replacementBus = "";
  Map<String, bool> _selectedNotifyBuses = {};

  bool _firebaseConnected = false;
  StreamSubscription? _connectedSubscription;
  String _syncStatusText = "Firebase sync ready";
  String _syncTimestamp = "--";
  bool _isSyncing = false;

  String _nextStop = "COLLEGE";
  String _eta = "--";

  int _attendanceCount = 0;
  final int _attendanceCapacity = 14;

  bool _breakdownActive = false;
  final TextEditingController _replacementController = TextEditingController();
  String _routeNotifyStatus = "";

  bool _showBusReadyBanner = false;
  int _busReadyCountdown = 10;
  Timer? _busReadyTimer;
  Timer? _busReadyCountdownTimer;

  final MapController _mapController = MapController();

  // Speech monitor details
  bool _smActive = false;
  int _totalSpeakingSeconds = 0;
  int _sessionsCount = 0;
  int _longestSessionSeconds = 0;
  double _speechUsagePercentage = 0.0;
  List<Map<String, String>> _speechLog = [];
  bool _showSpeechAlert = false;
  Timer? _smSimulationTimer;
  int _driveSeconds = 0;
  bool _isSpeaking = false;
  int _currentSpeechSessionSecs = 0;
  List<double> _waveValues = List.filled(15, 2.0);
  Timer? _waveTimer;

  List<Map<String, dynamic>> _confirmedPickups = [];
  StreamSubscription? _confirmedSub;
  
  // Intercom Messages
  List<Map<String, dynamic>> _intercomMessages = [];
  StreamSubscription? _intercomSub;
  final TextEditingController _driverChatInputCtrl = TextEditingController();

  // Route Simulation State
  bool _simulateRoute = false;
  List<LatLng> _simulatedPath = [];
  int _simRouteIndex = 0;
  Timer? _simTimer;

  // Safety Warnings State
  bool _onPhoneCall = false;
  bool _connectedToEarpods = false;
  Timer? _safetyTimer;
  int _callSecondsCounter = 0;

  // Intercom Playback & Recording State
  bool _isRecordingVoice = false;
  int _recordingDurationSecs = 0;
  Timer? _recordingTimer;
  List<double> _recordingWaveforms = [];
  String? _playingMsgId;
  double _playbackProgress = 0.0;
  Timer? _playbackTimer;

  final double _warnThresholdPct = 20.0;

  List<Map<String, dynamic>> _routeStops = [];
  String _routeKey = "route_15";

  bool _allowLocationCapture = false;
  StreamSubscription? _adminSettingsSub;

  @override
  void initState() {
    super.initState();
    _loadRouteDetails();
    _startFirebaseConnectedListener();
    _listenForConfirmedPickups();
    _listenForIntercomMessages();
    _listenForAdminSettings();
  }

  void _loadRouteDetails() async {
    // 1. Initial quick guess based on bus number
    _routeKey = _getRouteKeyForBus(widget.driverBus);
    _updateStopsFromKey();

    // 2. Fetch the true route from Firebase Driver Registry
    if (Firebase.apps.isNotEmpty) {
      try {
        final snap = await FirebaseDatabase.instance.ref('drivers').get();
        if (snap.exists && snap.value != null) {
          final data = snap.value;
          List driversList = [];
          if (data is List) {
            driversList = data;
          } else if (data is Map) {
            driversList = data.values.toList();
          }

          final bus = widget.driverBus.toUpperCase();
          for (var item in driversList) {
            if (item is Map) {
              final dbBus = item['bus']?.toString().toUpperCase();
              if (dbBus == bus && item['route'] != null) {
                final String dbRoute = item['route'].toString();
                if (mounted && dbRoute != _routeKey) {
                  setState(() {
                    _routeKey = dbRoute;
                  });
                  _updateStopsFromKey();
                }
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching driver route: $e");
      }
    }
  }

  void _updateStopsFromKey() {
    final stops = routeStopsConfig[_routeKey] ?? [];
    setState(() {
      _routeStops = stops.map((name) {
        final coord = coordsConfig[name] ?? const LatLng(13.0489049, 80.0754642);
        return {
          'name': name,
          'lat': coord.latitude,
          'lng': coord.longitude,
        };
      }).toList();
      if (_routeStops.isNotEmpty) {
        _nextStop = _routeStops[0]['name'];
      }
    });
  }

  String _getRouteKeyForBus(String busId) {
    final bus = busId.toUpperCase();
    if (bus == 'B101' || bus == 'BUS101') return 'route_15';
    if (bus == 'B202' || bus == 'BUS102') return 'route_52';
    if (bus == 'B303') return 'route_137';
    if (RegExp(r'^\d+$').hasMatch(busId)) {
      if (routeLabelsConfig.containsKey('route_$busId')) return 'route_$busId';
    }
    return 'route_15'; // default fallback
  }

  String _getRouteLabelForBus(String busId) {
    return routeLabelsConfig[_routeKey] ?? "College Route";
  }

  String t(String key) {
    return driverLang[widget.currentLang]?[key] ?? key;
  }

  void _listenForAdminSettings() {
    if (Firebase.apps.isEmpty) return;
    try {
      _adminSettingsSub = FirebaseDatabase.instance.ref('adminSettings/allowDriversToAddStops').onValue.listen((event) {
        final val = event.snapshot.value;
        if (mounted) {
          setState(() {
            _allowLocationCapture = val == true;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening to admin settings: $e");
    }
  }

  void _fetchAndSendLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("Location services are disabled.");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar("Location permissions are denied");
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _showSnackBar("Location permissions are permanently denied.");
      return;
    }

    _showSnackBar("Fetching location...");
    
    try {
      Position position = await Geolocator.getCurrentPosition();
      final data = {
        'driverBus': widget.driverBus,
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'new_stop_suggested'
      };
      await FirebaseDatabase.instance.ref('new_stops/${widget.driverBus}_${DateTime.now().millisecondsSinceEpoch}').set(data);
      _showSnackBar("✅ Location sent to Admin");
    } catch (e) {
      _showSnackBar("Failed to get location: $e");
    }
  }

  void _listenForConfirmedPickups() {
    if (Firebase.apps.isEmpty) return;
    try {
      _confirmedSub = FirebaseDatabase.instance.ref('pickup_requests').onValue.listen((event) {
        final data = event.snapshot.value as Map?;
        final List<Map<String, dynamic>> temp = [];
        if (data != null) {
          data.forEach((key, val) {
            if (val is Map && val['status'] == 'confirmed') {
              temp.add({
                'studentName': val['studentName'] ?? "Unknown Student",
                'savedStop': val['savedStop'] ?? "Not Selected",
                'documentName': val['documentName'] ?? "No Document",
                'studentDept': val['studentDept'] ?? "N/A",
              });
            }
          });
        }
        setState(() {
          _confirmedPickups = temp;
        });
      });
    } catch (e) {
      debugPrint("Error listening to driver pickups: $e");
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _connectedSubscription?.cancel();
    _confirmedSub?.cancel();
    _adminSettingsSub?.cancel();
    _smSimulationTimer?.cancel();
    _waveTimer?.cancel();
    _busReadyTimer?.cancel();
    _busReadyCountdownTimer?.cancel();
    _simTimer?.cancel();
    _safetyTimer?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _replacementController.dispose();
    _intercomSub?.cancel();
    _driverChatInputCtrl.dispose();
    super.dispose();
  }

  void _listenForIntercomMessages() {
    if (Firebase.apps.isEmpty) return;
    try {
      _intercomSub = FirebaseDatabase.instance.ref('voice_messages/driver_${widget.driverBus}').onValue.listen((event) {
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
            _intercomMessages = temp;
          });
        }
      });
    } catch (e) {
      debugPrint("Error listening for intercom messages: $e");
    }
  }

  void _sendTextMessage(String text) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseDatabase.instance.ref('voice_messages/driver_${widget.driverBus}/$msgId').set({
        'sender': 'driver',
        'senderName': 'Driver ${widget.driverBus}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'msg': text,
      });
    } catch (e) {
      debugPrint("Error sending text message: $e");
    }
  }

  void _startRecordingVoice() {
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

  void _stopAndSendRecordingVoice() async {
    _recordingTimer?.cancel();
    if (!_isRecordingVoice) return;
    final duration = _recordingDurationSecs == 0 ? 3 : _recordingDurationSecs;
    setState(() {
      _isRecordingVoice = false;
    });

    if (Firebase.apps.isEmpty) return;

    final transcripts = [
      "Hello admin, route 15 bus starting from Manali.",
      "Hi admin, reached rettri roundna just now.",
      "Driver B101 here, heavy traffic near gate. ETA 15 mins.",
      "Reporting minor delay for passenger boarding.",
      "Admin, breakdown occurred near Tambaram depot, need assistance.",
    ];
    final randomTranscript = transcripts[Random().nextInt(transcripts.length)];

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await FirebaseDatabase.instance.ref('voice_messages/driver_${widget.driverBus}/$msgId').set({
        'sender': 'driver',
        'senderName': 'Driver ${widget.driverBus}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'msg': '[Voice Message - 0:${duration.toString().padLeft(2, '0')}] "$randomTranscript"',
        'isVoice': true,
        'voiceDuration': duration,
        'transcript': randomTranscript,
      });
    } catch (e) {
      debugPrint("Error sending voice message: $e");
    }
  }

  void _cancelRecordingVoice() {
    _recordingTimer?.cancel();
    setState(() {
      _isRecordingVoice = false;
      _recordingDurationSecs = 0;
    });
    _showSnackBar("Recording cancelled.");
  }

  void _playVoiceMessage(String msgId, int durationSecs) {
    if (_playingMsgId == msgId) {
      _playbackTimer?.cancel();
      setState(() {
        _playingMsgId = null;
      });
      return;
    }
    _playbackTimer?.cancel();
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

  void _showDriverPredefinedMessages() {
    const List<String> driverMessages = [
      "🚌 Bus is on the way. Please be ready at your stop.",
      "⏱️ Slight delay due to traffic. ETA 10 minutes.",
      "✅ Bus has arrived at campus safely.",
      "🛣️ Route is clear, proceeding as scheduled.",
      "⚠️ Emergency: Bus breakdown. Sending help.",
      "🔁 Bus is returning after drop-off.",
      "⛽ Fuel stop needed. 5-minute halt.",
      "🌧️ Slow speed due to rain. Be patient.",
      "🚫 Bus is full. Cannot board more students.",
      "📍 Arriving at first stop in 5 minutes.",
      "🚧 Road block ahead. Taking alternate route.",
      "🛑 Bus stopped for a quick headcount.",
      "🎓 All students safely dropped at campus.",
      "📞 Please call admin for urgent matters.",
      "🔧 Minor mechanical issue. Will resume shortly.",
      "🅿️ Parked at designated bus bay.",
      "👨‍🎓 Students boarding at current stop.",
      "🚦 Waiting at traffic signal. On schedule.",
      "🏫 Reached college gate. Please exit safely.",
      "✔️ Trip completed. Bus returning to depot.",
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Color(0xFFCBD5E1), borderRadius: BorderRadius.all(Radius.circular(2)))),
              ),
              const SizedBox(height: 16),
              const Text(
                "Select Predefined Intercom Message",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1E3A8A)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: driverMessages.length,
                  itemBuilder: (context, index) {
                    final msg = driverMessages[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      borderOnForeground: true,
                      child: ListTile(
                        title: Text(msg, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                        trailing: const Icon(Icons.send_rounded, color: Color(0xFF2563EB), size: 18),
                        onTap: () {
                          _sendTextMessage(msg);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startFirebaseConnectedListener() {
    if (Firebase.apps.isEmpty) return;
    _connectedSubscription = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value == true;
      if (mounted) {
        setState(() {
          _firebaseConnected = connected;
          if (connected) {
            _syncStatusText = "Connected to Firebase Realtime Database";
            _syncTimestamp = _formattedTimeNow();
          } else {
            _syncStatusText = "Sync paused — offline mode active";
          }
        });
      }
    });
  }

  String _formattedTimeNow() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }

  Future<void> _fbUpdateLocationRaw(double lat, double lng, double acc) async {
    if (Firebase.apps.isEmpty) return;
    setState(() {
      _isSyncing = true;
      _syncStatusText = "Syncing…";
    });

    final data = {
      'lat': lat,
      'lng': lng,
      'acc': acc,
      'status': _isTracking ? (_breakdownActive ? 'broken' : 'tracking') : 'offline',
      'updatedAt': DateTime.now().toIso8601String()
    };

    try {
      await FirebaseDatabase.instance.ref('liveLocations/${widget.driverBus}').set(data);
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = "✅ Synced to Firebase";
          _syncTimestamp = _formattedTimeNow();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = "❌ Sync failed — check connection";
        });
      }
    }
  }

  Future<void> _fbUpdateLocation(Position pos) async {
    await _fbUpdateLocationRaw(pos.latitude, pos.longitude, pos.accuracy);
  }

  void _startSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isTracking) return;
      
      if (_onPhoneCall) {
        _callSecondsCounter++;
        if (_callSecondsCounter >= 60) {
          await _sendSafetyAlert("phoneCall", "Driver is using phone (on call) for ${_callSecondsCounter}s while driving!");
        }
      } else {
        _callSecondsCounter = 0;
        await _clearSafetyAlert("phoneCall");
      }

      if (_connectedToEarpods) {
        await _sendSafetyAlert("earpods", "Driver phone is connected to earpods/headphones!");
      } else {
        await _clearSafetyAlert("earpods");
      }
    });
  }

  void _stopSafetyTimer() async {
    _safetyTimer?.cancel();
    _safetyTimer = null;
    _callSecondsCounter = 0;
    await _clearSafetyAlert("phoneCall");
    await _clearSafetyAlert("earpods");
  }

  Future<void> _sendSafetyAlert(String type, String message) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('drivers_alerts/${widget.driverBus}/$type').set({
        'active': true,
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint("Error sending safety alert: $e");
    }
  }

  Future<void> _clearSafetyAlert(String type) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('drivers_alerts/${widget.driverBus}/$type').remove();
    } catch (e) {
      debugPrint("Error clearing safety alert: $e");
    }
  }

  Future<void> _fbSetOffline() async {
    if (Firebase.apps.isEmpty) return;
    setState(() {
      _isSyncing = true;
    });

    final data = {
      'lat': _currentPosition?.latitude ?? 13.0486,
      'lng': _currentPosition?.longitude ?? 80.0753,
      'acc': _currentPosition?.accuracy ?? 10.0,
      'status': 'offline',
      'updatedAt': DateTime.now().toIso8601String()
    };

    try {
      await FirebaseDatabase.instance.ref('liveLocations/${widget.driverBus}').set(data);
      setState(() {
        _isSyncing = false;
        _syncStatusText = "☁️ Offline status saved";
      });
    } catch (_) {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  List<LatLng> _interpolatePoints(List<Map<String, dynamic>> stops) {
    List<LatLng> path = [];
    if (stops.isEmpty) return path;
    for (int i = 0; i < stops.length - 1; i++) {
      final start = LatLng(stops[i]['lat'] as double, stops[i]['lng'] as double);
      final end = LatLng(stops[i + 1]['lat'] as double, stops[i + 1]['lng'] as double);
      int steps = 15;
      for (int s = 0; s < steps; s++) {
        double t = s / steps;
        double lat = start.latitude + (end.latitude - start.latitude) * t;
        double lng = start.longitude + (end.longitude - start.longitude) * t;
        path.add(LatLng(lat, lng));
      }
    }
    final last = stops.last;
    path.add(LatLng(last['lat'] as double, last['lng'] as double));
    return path;
  }

  void _startTracking() async {
    setState(() {
      _isTracking = true;
      _appStatus = "Online";
      _syncStatusText = "Starting GPS stream...";
    });

    _showBusReadyNotification();
    _startSpeechMonitor();
    _startSafetyTimer();

    if (_simulateRoute) {
      _simulatedPath = _interpolatePoints(_routeStops);
      _simRouteIndex = 0;
      if (_simulatedPath.isNotEmpty) {
        final firstPt = _simulatedPath[0];
        setState(() {
          _latitude = firstPt.latitude;
          _longitude = firstPt.longitude;
          _accuracy = 5.0;
          _updatedAt = _formattedTimeNow();
          _gpsStatus = "Simulated";
        });
        await _fbUpdateLocationRaw(_latitude, _longitude, _accuracy);
        _mapController.move(firstPt, _mapController.camera.zoom);
      }

      _simTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_simulatedPath.isEmpty || !_isTracking) {
          timer.cancel();
          return;
        }
        _simRouteIndex = (_simRouteIndex + 1) % _simulatedPath.length;
        final pt = _simulatedPath[_simRouteIndex];
        setState(() {
          _latitude = pt.latitude;
          _longitude = pt.longitude;
          _accuracy = 5.0;
          _updatedAt = _formattedTimeNow();
        });
        _fbUpdateLocationRaw(_latitude, _longitude, _accuracy);
        _mapController.move(pt, _mapController.camera.zoom);
        
        final mockPos = Position(
          latitude: pt.latitude,
          longitude: pt.longitude,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 10.0,
          speedAccuracy: 0.0,
        );
        _checkGeofences(mockPos);
        _checkCollegeArrival(mockPos);
      });
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _showDialog("Permission Required", "GPS Location permissions are required to start vehicle tracking.");
          return;
        }
      }

      Position initialPos = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = initialPos;
        _latitude = initialPos.latitude;
        _longitude = initialPos.longitude;
        _accuracy = initialPos.accuracy;
        _updatedAt = _formattedTimeNow();
        _gpsStatus = "Active";
      });
      await _fbUpdateLocationRaw(_latitude, _longitude, _accuracy);
      _mapController.move(LatLng(initialPos.latitude, initialPos.longitude), _mapController.camera.zoom);

      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Panimalar Smart Transit is tracking location in background",
            notificationTitle: "Live GPS Active",
          ),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        );
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        setState(() {
          _currentPosition = position;
          _latitude = position.latitude;
          _longitude = position.longitude;
          _accuracy = position.accuracy;
          _updatedAt = _formattedTimeNow();
          _mapController.move(LatLng(position.latitude, position.longitude), _mapController.camera.zoom);
        });
        _fbUpdateLocationRaw(position.latitude, position.longitude, position.accuracy);
        _checkGeofences(position);
        _checkCollegeArrival(position);
      });
    }
  }

  void _stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _simTimer?.cancel();
    _simTimer = null;
    _stopSafetyTimer();

    setState(() {
      _isTracking = false;
      _appStatus = "Offline";
      _gpsStatus = "Offline";
    });

    await _fbSetOffline();
    _stopSpeechMonitor();
  }

  void _checkGeofences(Position pos) {
    double minDistance = double.maxFinite;
    String closestStopName = _nextStop;

    for (var stop in _routeStops) {
      double dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        stop['lat'] as double,
        stop['lng'] as double,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestStopName = stop['name'] as String;
      }
    }

    setState(() {
      if (minDistance < 100) {
        _nextStop = closestStopName;
        _eta = "Arrived";
      } else {
        _nextStop = closestStopName;
        int estMinutes = (minDistance / 250).ceil();
        _eta = "$estMinutes min";
      }
    });
  }

  void _checkCollegeArrival(Position pos) async {
    if (!_isTracking) return;

    // College entrance Gate coords
    double distToCollege = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      13.0489049,
      80.0754642,
    );

    // If inside 150m of college gate, automatically update arrival logs on Firebase!
    if (distToCollege < 150) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final timeNow = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";

      if (Firebase.apps.isNotEmpty) {
        try {
          final logRef = FirebaseDatabase.instance.ref('arrival_logs/$today/${widget.driverBus}');
          final snap = await logRef.get();
          if (!snap.exists) {
            await logRef.set({
              'bus': widget.driverBus,
              'driver': 'Driver ${widget.driverBus}',
              'route': _getRouteLabelForBus(widget.driverBus),
              'date': today,
              'arrived': timeNow,
              'status': 'arrived',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
            _showSnackBar("🏫 Reached campus! Arrival logged automatically.");
          }
        } catch (e) {
          debugPrint("Failed to write automated arrival log: $e");
        }
      }
    }
  }

  void _reportBreakdown() {
    if (!_isTracking) return;
    setState(() {
      _breakdownActive = true;
      _appStatus = "Broken Down";
    });

    if (_currentPosition != null) {
      _fbUpdateLocation(_currentPosition!);
    }
  }

  Future<void> _sendBreakdownAlert() async {
    final repBus = _replacementController.text.trim().toUpperCase();
    if (repBus.isEmpty) {
      _showDialog("Error", t('replacementErrorEmpty'));
      return;
    }

    final data = {
      'busId': widget.driverBus,
      'replacement': repBus,
      'lat': _latitude,
      'lng': _longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    };

    try {
      await FirebaseDatabase.instance.ref('breakdowns/${widget.driverBus}').set(data);
      _showDialog("Success", "Breakdown Alert Sent! Replacement bus: $repBus");
      setState(() {
        _replacementBus = repBus;
      });
    } catch (e) {
      _showDialog("Error", "Failed to send alert: $e");
    }
  }

  void _sendBreakdownToRouteBuses() async {
    final selectedBuses = _selectedNotifyBuses.entries.where((e) => e.value).map((e) => e.key).join(", ");
    setState(() {
      _routeNotifyStatus = "Notifying other buses on same route…";
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _routeNotifyStatus = "✅ Notified buses $selectedBuses to pick up stranded students.";
    });
    _showSnackBar("Notifications dispatched successfully.");
  }

  void _logBoarding() {
    if (_attendanceCount < _attendanceCapacity) {
      setState(() {
        _attendanceCount++;
      });
      _showSnackBar(t('boardingLogged'));
    } else {
      _showSnackBar(t('allBoarded'));
    }
  }

  void _startSpeechMonitor() {
    _waveTimer?.cancel();
    _smSimulationTimer?.cancel();
    
    setState(() {
      _smActive = true;
      _totalSpeakingSeconds = 0;
      _sessionsCount = 0;
      _longestSessionSeconds = 0;
      _speechUsagePercentage = 0.0;
      _speechLog = [];
      _showSpeechAlert = false;
      _driveSeconds = 0;
      _isSpeaking = false;
      _currentSpeechSessionSecs = 0;
    });

    _smSimulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _driveSeconds++;
      final random = Random();
      
      if (!_isSpeaking && random.nextDouble() < 0.15) {
        // Start speaking
        _isSpeaking = true;
        _sessionsCount++;
        _currentSpeechSessionSecs = 0;
      } else if (_isSpeaking && random.nextDouble() < 0.25) {
        // Stop speaking
        _isSpeaking = false;
        if (_currentSpeechSessionSecs > _longestSessionSeconds) {
          _longestSessionSeconds = _currentSpeechSessionSecs;
        }
      }

      if (_isSpeaking) {
        _totalSpeakingSeconds++;
        _currentSpeechSessionSecs++;
        if (_currentSpeechSessionSecs % 5 == 0) {
          final now = DateTime.now();
          final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
          
          final val = random.nextDouble() < 0.3
              ? "Asking passengers to step behind yellow line"
              : "Talking to co-driver about traffic block";
              
          final bool isWarn = _speechUsagePercentage > _warnThresholdPct;

          _speechLog.insert(0, {
            'time': timeStr,
            'text': val,
            'isWarn': isWarn.toString(),
          });
        }
      }

      _speechUsagePercentage = (_totalSpeakingSeconds / _driveSeconds) * 100;

      if (_speechUsagePercentage > _warnThresholdPct) {
        _showSpeechAlert = true;
      } else {
        _showSpeechAlert = false;
      }
    });

    _waveTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      final random = Random();
      setState(() {
        if (_isSpeaking) {
          _waveValues = List.generate(15, (index) => 5.0 + random.nextDouble() * 25.0);
        } else {
          _waveValues = List.generate(15, (index) => 2.0 + random.nextDouble() * 3.0);
        }
      });
    });
  }

  void _stopSpeechMonitor() {
    _waveTimer?.cancel();
    _smSimulationTimer?.cancel();
    setState(() {
      _smActive = false;
      _isSpeaking = false;
    });
  }

  void _showBusReadyNotification() {
    setState(() {
      _showBusReadyBanner = true;
      _busReadyCountdown = 10;
    });

    _busReadyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_busReadyCountdown > 0) {
          _busReadyCountdown--;
        } else {
          timer.cancel();
        }
      });
    });

    _busReadyTimer = Timer(const Duration(seconds: 10), () {
      setState(() {
        _showBusReadyBanner = false;
      });
    });
  }

  void _showDialog(String title, String m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF1E3A8A),
      ),
    );
  }

  String _formatDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Widget _buildFieldTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildSmTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 8.5, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF78350F))),
        ],
      ),
    );
  }

  Widget _buildRouteBusItem(String bus, String details, {bool isDiffRoute = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_bus, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bus $bus", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF991B1B))),
                Text(details, style: const TextStyle(fontSize: 9.5, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Switch(
            value: _selectedNotifyBuses[bus] ?? false,
            activeColor: const Color(0xFFDC2626),
            onChanged: isDiffRoute ? null : (val) {
              setState(() {
                _selectedNotifyBuses[bus] = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextMessageBubble(Map<String, dynamic> msg, bool isMe) {
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
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          border: Border.all(color: isMe ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg['senderName'] ?? '',
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
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
                      _playVoiceMessage(msg['id'], msg['voiceDuration'] ?? 3);
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
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorizedPickupsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text("🎫", style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                "Authorized Pickup Letters (${_confirmedPickups.length})",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_confirmedPickups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text("No pickup requests approved yet for today.", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _confirmedPickups.length,
              itemBuilder: (ctx, idx) {
                final pickup = _confirmedPickups[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFDCFCE7),
                        radius: 12,
                        child: Icon(Icons.check, size: 12, color: Color(0xFF15803D)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pickup['studentName'], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            Text("${pickup['studentDept']} • Stop: ${pickup['savedStop']}", style: const TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                        child: const Text("APPROVED", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                      )
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
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
                      points: _routeStops.map((s) => LatLng(s['lat'] as double, s['lng'] as double)).toList(),
                      color: const Color(0xFF2563EB),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
                if (_isTracking && _currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_latitude, _longitude),
                        width: 40,
                        height: 40,
                        child: const Text("🚌", style: TextStyle(fontSize: 24)),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                onPressed: () {
                  if (_currentPosition != null) {
                    _mapController.move(LatLng(_latitude, _longitude), 14.0);
                  }
                },
                backgroundColor: Colors.white,
                child: const Icon(Icons.gps_fixed, color: Color(0xFF2563EB)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _appStatus == "Offline"
        ? const Color(0xFF64748B)
        : (_appStatus == "Broken Down" ? const Color(0xFFDC2626) : const Color(0xFF2563EB));

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2FF),
      floatingActionButton: _allowLocationCapture
          ? FloatingActionButton.extended(
              onPressed: _fetchAndSendLocation,
              label: const Text("Capture Stop"),
              icon: const Icon(Icons.add_location_alt),
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            )
          : null,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(child: Text("🚌", style: TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('appTitle'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                ),
                Text(
                  t('appSubtitle'),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                ),
              ],
            )
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _firebaseConnected ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _firebaseConnected ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _firebaseConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _firebaseConnected ? "SYNC ACTIVE" : "OFFLINE",
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: _firebaseConnected ? const Color(0xFF166534) : const Color(0xFF991B1B),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('dashboardLabel'),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Bus ${widget.driverBus}",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getRouteLabelForBus(widget.driverBus),
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _appStatus.toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      t('gpsLabel'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.2,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildFieldTile(t('latLabel'), _isTracking ? _latitude.toStringAsFixed(6) : "--"),
                        _buildFieldTile(t('lngLabel'), _isTracking ? _longitude.toStringAsFixed(6) : "--"),
                        _buildFieldTile(t('accLabel'), _isTracking ? "${_accuracy.toStringAsFixed(1)} m" : "--"),
                        _buildFieldTile(t('updatedLabel'), _isTracking ? _updatedAt : "--"),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Simulate Route Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                      subtitle: const Text("Interpolates path and broadcasts movement automatically", style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      value: _simulateRoute,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: _isTracking ? null : (val) {
                        setState(() {
                          _simulateRoute = val;
                        });
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFEDD5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "🚨 DRIVER SAFETY SIMULATOR CONSOLE",
                            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFFC2410C), letterSpacing: 0.5),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text("Speaking on Call", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF451A03))),
                                  value: _onPhoneCall,
                                  activeColor: const Color(0xFFC2410C),
                                  onChanged: (val) {
                                    setState(() {
                                      _onPhoneCall = val ?? false;
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text("Earpods Connected", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF451A03))),
                                  value: _connectedToEarpods,
                                  activeColor: const Color(0xFFC2410C),
                                  onChanged: (val) {
                                    setState(() {
                                      _connectedToEarpods = val ?? false;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('highlightTitle'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('highlightText'),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.4, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            ),
                            onPressed: _isTracking ? null : _startTracking,
                            child: Text(t('startTracking'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFDBE2F8)),
                              foregroundColor: const Color(0xFF1E293B),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: _isTracking ? _stopTracking : null,
                            child: Text(t('stopTracking'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: _isTracking && !_breakdownActive ? _reportBreakdown : null,
                      icon: const Icon(Icons.warning_amber, size: 16),
                      label: Text(t('reportBreakdown'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Speech Monitor Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFDF5), Color(0xFFFEF3C7)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDE68A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: const Text("🎙️", style: TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('speechTitle'),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                              ),
                              Text(
                                _smActive ? t('speechActive') : t('speechWaiting'),
                                style: const TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _smActive ? const Color(0xFFDCFCE7) : const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _smActive ? (_isSpeaking ? Colors.red : Colors.green) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _smActive ? (_isSpeaking ? "SPEAKING" : "LIVE") : "OFF",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: _smActive ? (_isSpeaking ? Colors.red : const Color(0xFF166534)) : Colors.grey,
                                ),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (!_smActive)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2), width: 1),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          "🔒 Monitoring activates automatically when tracking starts.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.bold),
                        ),
                      ),

                    if (_smActive) ...[
                      Center(
                        child: SizedBox(
                          height: 36,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: _waveValues.map((h) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 3.5,
                                height: h,
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(
                                  color: _isSpeaking ? const Color(0xFFEFF6FF) : const Color(0xFFD97706),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.1,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildSmTile(t('speakingTime'), _formatDuration(_totalSpeakingSeconds)),
                          _buildSmTile(t('sessions'), _sessionsCount.toString()),
                          _buildSmTile(t('longest'), _formatDuration(_longestSessionSeconds)),
                          _buildSmTile(t('pctDrive'), "${_speechUsagePercentage.toStringAsFixed(0)}%"),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('speechUsage'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                              Text("${_speechUsagePercentage.toStringAsFixed(0)}% / 20%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: (_speechUsagePercentage / 100).clamp(0.0, 1.0),
                              backgroundColor: const Color(0xFFFDE68A),
                              color: _speechUsagePercentage > _warnThresholdPct ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),

                      if (_showSpeechAlert) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Text("⚠️", style: TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t('speechTooMuch'),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B), fontWeight: FontWeight.w900),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],

                      if (_speechLog.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(t('sessionLog'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 90),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(8),
                            itemCount: _speechLog.length > 5 ? 5 : _speechLog.length,
                            itemBuilder: (context, idx) {
                              final item = _speechLog[idx];
                              final isWarn = item['isWarn'] == "true";
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: isWarn ? Colors.red : const Color(0xFFF59E0B), width: 3)),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      item['time'] ?? "",
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item['text'] ?? "",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isWarn ? Colors.red : const Color(0xFF78350F),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                      ]
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Live Fleet Dashboard (ETA, Health, Boarding count)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('fleetLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFDBE2F8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text("On route", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                                ),
                                const SizedBox(height: 8),
                                Text(t('etaTitle'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                const SizedBox(height: 2),
                                Text("${t('nextStopLabel')} $_nextStop", style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(_eta, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFDBE2F8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text("Maintenance", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                                ),
                                const SizedBox(height: 8),
                                Text(t('healthTitle'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                                const SizedBox(height: 6),
                                const Text("Next service in 4 days", style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600, height: 1.4)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDBE2F8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('boardingTitle'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                              const SizedBox(height: 4),
                              Text("$_attendanceCount / $_attendanceCapacity boarded", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                            ],
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Color(0xFFDBE2F8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: _logBoarding,
                            child: Text(t('logBoarding'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildAuthorizedPickupsCard(),
              const SizedBox(height: 16),

              _buildMapCard(),
              const SizedBox(height: 16),

              // Breakdown alerts
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('breakdownSection'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                    const SizedBox(height: 14),
                    Text(t('replacementBus'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _replacementController,
                      decoration: InputDecoration(
                        hintText: "e.g. B202",
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t('detectedLocation'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        Text(
                          _isTracking ? "${_latitude.toStringAsFixed(4)}, ${_longitude.toStringAsFixed(4)}" : t('locationUnavailable'),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                        )
                      ],
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: _sendBreakdownAlert,
                      child: Text(t('sendAlert'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text("🚌", style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('notifyRoute'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF991B1B))),
                            Text(t('autoAlertNearby'), style: const TextStyle(fontSize: 9, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('notifyExpl'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF78350F), height: 1.4, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Column(
                      children: [
                        _buildRouteBusItem("B202", "Route 52 · Behind you ~2.4 km"),
                        _buildRouteBusItem("B303", "Route 137 · Ahead ~1.1 km"),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: _selectedNotifyBuses.containsValue(true) ? _sendBreakdownToRouteBuses : null,
                      child: Text(t('sendBreakdownBuses'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                    if (_routeNotifyStatus.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _routeNotifyStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDBE2F8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('langLabelDash'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
                        const SizedBox(height: 6),
                        DropdownButton<String>(
                          value: widget.currentLang,
                          underline: const SizedBox(),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB), fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'en', child: Text('English')),
                            DropdownMenuItem(value: 'ta', child: Text('தமிழ்')),
                            DropdownMenuItem(value: 'te', child: Text('తెలుగు')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              widget.onLanguageChanged(val);
                            }
                          },
                        )
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: widget.onLogout,
                      child: Text(t('logout'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Intercom messaging
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDBE2F8), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Text("💬", style: TextStyle(fontSize: 16)),
                            SizedBox(width: 8),
                            Text(
                              "Intercom Messenger",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Online",
                            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (_intercomMessages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
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
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _intercomMessages.length,
                          itemBuilder: (ctx, idx) {
                            final msg = _intercomMessages[idx];
                            final isMe = msg['sender'] == 'driver';
                            return _buildTextMessageBubble(msg, isMe);
                          },
                        ),
                      ),
                      
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
                              controller: _driverChatInputCtrl,
                              decoration: InputDecoration(
                                hintText: "Type message or hold mic...",
                                hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                                fillColor: const Color(0xFFF8FAFC),
                                filled: true,
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.flash_on, color: Color(0xFF2563EB)),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFEFF6FF),
                              padding: const EdgeInsets.all(10),
                            ),
                            onPressed: _showDriverPredefinedMessages,
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.all(10),
                            ),
                            onPressed: () {
                              final text = _driverChatInputCtrl.text.trim();
                              if (text.isNotEmpty) {
                                _sendTextMessage(text);
                                _driverChatInputCtrl.clear();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
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
                  ],
                ),
              ),
              const SizedBox(height: 24),

              TextButton(
                onPressed: widget.onSwitchRole,
                child: const Text(
                  "🎓 Switch to Student Mode",
                  style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 8),

              Center(
                child: Text(
                  t('bottomInfo'),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
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
