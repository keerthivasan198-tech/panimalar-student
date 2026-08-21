import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class StudentLoginScreen extends StatefulWidget {
  final Function(String, bool) onLogin;
  final String currentLang;
  final Function(String) onLanguageChanged;
  final VoidCallback onSwitchRole;
  final Function(bool) onCreateProfile;

  const StudentLoginScreen({
    super.key,
    required this.onLogin,
    required this.currentLang,
    required this.onLanguageChanged,
    required this.onSwitchRole,
    required this.onCreateProfile,
  });

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen>
    with SingleTickerProviderStateMixin {
  final _rollNoController = TextEditingController();
  bool _isLoading = false;
  bool _isFacultyLogin = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _rollNoController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final rollNo = _rollNoController.text.trim().toUpperCase();
    if (rollNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFacultyLogin
                ? 'Please enter your Faculty ID'
                : 'Please enter your Roll Number',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    if (rollNo.toLowerCase() == 'guest') {
      widget.onLogin(rollNo, false);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        final node = _isFacultyLogin ? 'faculty' : 'students';
        final snapshot = await FirebaseDatabase.instance
            .ref('$node/$rollNo')
            .get();
        if (snapshot.exists && snapshot.value != null) {
          // Profile exists, log in
          widget.onLogin(rollNo, _isFacultyLogin);
        } else {
          // Profile not found, show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isFacultyLogin
                      ? 'faculty id is not registered'
                      : 'student rollno is not registered',
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      } else {
        // Fallback if Firebase isn't initialized
        widget.onLogin(rollNo, _isFacultyLogin);
      }
    } catch (e) {
      debugPrint("Firebase check failed: $e");
      widget.onLogin(rollNo, _isFacultyLogin); // Fallback on error
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showGuestBusDialog() {
    final TextEditingController searchCtrl = TextEditingController();
    List<_GuestBusRouteInfo> allBusRoutes = [];
    List<String> allStops = [];
    bool isFetching = true;
    String selectedStop = '';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Load routes & drivers data once when dialog opens
            if (isFetching && allBusRoutes.isEmpty) {
              Future.microtask(() async {
                try {
                  final Map<String, String> routeLabels = {};
                  final Map<String, List<String>> routeStopsMap = {};
                  final Map<String, _GuestBusRouteInfo> busMap = {};

                  if (Firebase.apps.isNotEmpty) {
                    final routesSnap = await FirebaseDatabase.instance.ref('routes').get();
                    if (routesSnap.exists && routesSnap.value != null) {
                      for (final child in routesSnap.children) {
                        final childKey = child.key?.toString() ?? '';
                        final val = child.value;
                        if (val is Map) {
                          if (val['deleted'] == true || val['isDeleted'] == true || val['status'] == 'deleted') continue;
                          final key = (val['key'] != null && val['key'].toString().isNotEmpty)
                              ? val['key'].toString()
                              : childKey;
                          if (key.isEmpty) continue;
                          
                          final name = val['name']?.toString() ?? key;
                          routeLabels[key] = name;
                          routeLabels[childKey] = name;
                          
                          List<String> stops = [];
                          if (val['stops'] != null && val['stops'] is List) {
                            stops = List<String>.from(val['stops'].map((e) => e.toString()));
                            routeStopsMap[key] = stops;
                            routeStopsMap[childKey] = stops;
                          }
                          
                          busMap[key] = _GuestBusRouteInfo(
                            busNo: name,
                            routeKey: key,
                            routeName: name,
                            stops: stops,
                          );
                        }
                      }
                    }

                    final Map<String, String> routeToBusNoMap = {};
                    final driversSnap = await FirebaseDatabase.instance.ref('drivers').get();
                    if (driversSnap.exists && driversSnap.value != null) {
                      for (final child in driversSnap.children) {
                        final val = child.value;
                        if (val is Map) {
                          final busNo = (val['bus']?.toString() ?? '').trim().toUpperCase();
                          final routeKey = (val['route']?.toString() ?? '').trim();
                          if (busNo.isNotEmpty && routeKey.isNotEmpty) {
                            routeToBusNoMap[routeKey] = busNo;
                          }
                        }
                      }
                    }

                    final List<_GuestBusRouteInfo> canonicalRoutes = [];
                    for (final routeKey in busMap.keys) {
                      final originalInfo = busMap[routeKey]!;
                      final activeBusNo = routeToBusNoMap[routeKey];
                      if (activeBusNo != null) {
                        final updatedInfo = _GuestBusRouteInfo(
                          busNo: activeBusNo,
                          routeKey: routeKey,
                          routeName: originalInfo.routeName,
                          stops: originalInfo.stops,
                        );
                        canonicalRoutes.add(updatedInfo);
                      } else {
                        canonicalRoutes.add(originalInfo);
                      }
                    }

                    allBusRoutes = canonicalRoutes;
                    
                    allBusRoutes.sort((a, b) {
                      final nA = int.tryParse(a.busNo) ?? 999;
                      final nB = int.tryParse(b.busNo) ?? 999;
                      if (nA != 999 && nB != 999) return nA.compareTo(nB);
                      return a.busNo.compareTo(b.busNo);
                    });

                      String cleanStopName(String rawStop) {
                        var name = rawStop.trim();
                        if (name.contains('(Lat:')) {
                          name = name.split('(Lat:')[0];
                        } else if (name.contains('(lat:')) {
                          name = name.split('(lat:')[0];
                        } else if (name.contains('(')) {
                          final idx = name.indexOf('(');
                          final inside = name.substring(idx);
                          if (inside.contains('Lat') || inside.contains('Lng') || inside.contains('lat') || inside.contains('lng') || inside.contains('.')) {
                            name = name.substring(0, idx);
                          }
                        }
                        return name.trim();
                      }

                      final Set<String> uniqueStops = {};
                      for (final b in allBusRoutes) {
                        for (final s in b.stops) {
                          final clean = cleanStopName(s);
                          if (clean.isNotEmpty &&
                              clean.toUpperCase() != 'COLLEGE' &&
                              clean.toUpperCase() != 'PANIMALAR ENGINEERING COLLEGE') {
                            uniqueStops.add(clean);
                          }
                        }
                      }
                      allStops = uniqueStops.toList()..sort();
                    }
                } catch (e) {
                  debugPrint("Guest dialog route fetch error: $e");
                } finally {
                  if (context.mounted) {
                    setDialogState(() {
                      isFetching = false;
                    });
                  }
                }
              });
            }

            String cleanStopName(String rawStop) {
              var name = rawStop.trim();
              if (name.contains('(Lat:')) {
                name = name.split('(Lat:')[0];
              } else if (name.contains('(lat:')) {
                name = name.split('(lat:')[0];
              } else if (name.contains('(')) {
                final idx = name.indexOf('(');
                final inside = name.substring(idx);
                if (inside.contains('Lat') || inside.contains('Lng') || inside.contains('lat') || inside.contains('lng') || inside.contains('.')) {
                  name = name.substring(0, idx);
                }
              }
              return name.trim();
            }

            final query = searchCtrl.text.trim().toLowerCase();

            // Filter matching stops ONLY when query is NOT empty
            final matchingStops = query.isEmpty
                ? <String>[]
                : allStops.where((s) => s.toLowerCase().contains(query)).toList();

            // Filter matching buses for query
            final queryMatchingBuses = query.isEmpty
                ? <_GuestBusRouteInfo>[]
                : allBusRoutes.where((b) {
                    return b.busNo.toLowerCase().contains(query) ||
                        b.routeName.toLowerCase().contains(query);
                  }).toList();

            // Buses serving selectedStop
            final stopServingBuses = selectedStop.isEmpty
                ? <_GuestBusRouteInfo>[]
                : allBusRoutes.where((b) {
                    return b.stops.any((s) => cleanStopName(s).toLowerCase() == selectedStop.toLowerCase());
                  }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              title: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.pin_drop_rounded, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Guest Login',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          'Enter your stop to find available buses',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Search Bar
                    TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Enter your stop (e.g. Tambaram)',
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF2563EB)),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setDialogState(() {
                                    selectedStop = '';
                                  });
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (isFetching)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (selectedStop.isNotEmpty) ...[
                      // Banner showing selected stop
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Stop: $selectedStop',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E40AF),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedStop = '';
                                });
                              },
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Select Bus Route serving this stop:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (stopServingBuses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No buses found passing through $selectedStop.',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: stopServingBuses.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final b = stopServingBuses[index];
                              return Card(
                                elevation: 0,
                                color: const Color(0xFFF1F5F9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF2563EB),
                                    child: Text(
                                      b.busNo,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    'Bus ${b.busNo} — ${b.routeName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Passes through $selectedStop',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF2563EB)),
                                  onTap: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('studentBusNo', b.busNo);
                                    await prefs.setString('studentSavedStop', selectedStop);
                                    await prefs.remove('studentSelectedRoute');
                                    if (mounted) {
                                      Navigator.pop(context);
                                      widget.onLogin('Guest', false);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ] else ...[
                      // Search List: Matching Stops
                      if (matchingStops.isNotEmpty) ...[
                        Text(
                          query.isEmpty
                              ? 'Popular & Registered Stops:'
                              : 'Stops matching "$query":',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: matchingStops.length,
                            itemBuilder: (context, index) {
                              final stop = matchingStops[index];
                              final servingBuses = allBusRoutes
                                  .where((b) => b.stops.any((s) => s.trim().toLowerCase() == stop.toLowerCase()))
                                  .toList();
                              final busLabelText = servingBuses.map((b) => "Bus ${b.busNo}").join(", ");
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                leading: const Icon(Icons.location_on_outlined, size: 20, color: Color(0xFF2563EB)),
                                title: Text(
                                  stop,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: Text(
                                  busLabelText.isEmpty ? 'Available' : 'Served by $busLabelText',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF2563EB)),
                                onTap: () {
                                  setDialogState(() {
                                    selectedStop = stop;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],

                      // Bus matching query (if user typed bus number e.g. "52")
                      if (queryMatchingBuses.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Buses matching "$query":',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 140),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: queryMatchingBuses.length,
                            itemBuilder: (context, index) {
                              final b = queryMatchingBuses[index];
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: const Icon(Icons.directions_bus_rounded, size: 18, color: Color(0xFF2563EB)),
                                title: Text(
                                  'Bus ${b.busNo} — ${b.routeName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: b.stops.isNotEmpty
                                    ? Text(
                                        b.stops.join(' ➔ '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      )
                                    : null,
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () async {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('studentBusNo', b.busNo);
                                  await prefs.remove('studentSavedStop');
                                  await prefs.remove('studentSelectedRoute');
                                  if (mounted) {
                                    Navigator.pop(context);
                                    widget.onLogin('Guest', false);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],

                      if (query.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_rounded, size: 36, color: Color(0xFFCBD5E1)),
                                SizedBox(height: 8),
                                Text(
                                  'Type your stop name to see matching stops',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (query.isNotEmpty && matchingStops.isEmpty && queryMatchingBuses.isEmpty) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.location_off_rounded, size: 24, color: Color(0xFFDC2626)),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Bus stop not available.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Please enter a correct registered bus stop.',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF7F1D1D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('studentBusNo', 'Guest');
                    await prefs.setString('studentSavedStop', '');
                    await prefs.remove('studentSelectedRoute');
                    if (mounted) {
                      Navigator.pop(context);
                      widget.onLogin('Guest', false);
                    }
                  },
                  child: const Text(
                    'Skip & Proceed',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: widget.onSwitchRole,
        ),
      ),
      body: Stack(
        children: [
          // Background Image
          Container(
            height: size.height,
            width: size.width,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/red_bus_bg.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Dark Overlay for better text readability
          Container(
            height: size.height,
            width: size.width,
            color: Colors.black.withValues(alpha: 0.15),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
                          padding: const EdgeInsets.all(32.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 30,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Logo/Icon
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  size: 64,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Toggle for Student / Faculty
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _isFacultyLogin = false,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: !_isFacultyLogin
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'Student',
                                            style: TextStyle(
                                              color: !_isFacultyLogin
                                                  ? const Color(0xFF1E3A8A)
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _isFacultyLogin = true,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isFacultyLogin
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'Faculty',
                                            style: TextStyle(
                                              color: _isFacultyLogin
                                                  ? const Color(0xFF1E3A8A)
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _isFacultyLogin
                                    ? 'Faculty Portal'
                                    : 'Student Portal',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isFacultyLogin
                                    ? 'Enter your Faculty ID (e.g. CSE001)'
                                    : 'Enter your Roll Number to continue',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 40),

                              // Input Field
                              TextField(
                                controller: _rollNoController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                cursorColor: Colors.white,
                                decoration: InputDecoration(
                                  labelText: _isFacultyLogin
                                      ? 'Faculty ID'
                                      : 'Roll Number',
                                  labelStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.badge_outlined,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              const SizedBox(height: 32),

                              // Login Button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF1E3A8A),
                                    elevation: 5,
                                    shadowColor: Colors.black.withValues(
                                      alpha: 0.3,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF1E3A8A),
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const Text(
                                          'Login',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Create Profile
                              TextButton(
                                onPressed: () =>
                                    widget.onCreateProfile(_isFacultyLogin),
                                child: const Text(
                                  'Create new profile',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Guest Login
                              TextButton(
                                onPressed: _showGuestBusDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Continue as Guest',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ), // closes Column
                        ), // closes Container
                      ), // closes ConstrainedBox
                    ), // closes BackdropFilter
                  ), // closes ClipRRect
                ), // closes SlideTransition
              ), // closes FadeTransition
            ), // closes SingleChildScrollView
          ), // closes Center
        ], // closes Stack children
      ), // closes Stack
    ); // closes Scaffold
  }
}

class _GuestBusRouteInfo {
  final String busNo;
  final String routeKey;
  final String routeName;
  final List<String> stops;

  _GuestBusRouteInfo({
    required this.busNo,
    required this.routeKey,
    required this.routeName,
    required this.stops,
  });
}
