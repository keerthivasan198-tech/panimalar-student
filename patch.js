const fs = require('fs');

const filePath = 'lib/screens/student/student_shell.dart';
let content = fs.readFileSync(filePath, 'utf8');

// 1. Imports
content = content.replace(
  "import '../../services/campus_path_graph.dart';",
  "import '../../services/campus_path_graph.dart';\nimport 'student_login_screen.dart';\nimport 'dart:convert';\nimport 'package:http/http.dart' as http;\nimport 'dart:io';\nimport 'dart:typed_data';\nimport 'package:file_picker/file_picker.dart';"
);

// 2. MainShell Wrapper
content = content.replace(
  "class _MainShellState extends State<MainShell> with TickerProviderStateMixin {\n  String t(String key) {\n    return appLang[widget.currentLang]?[key] ?? appLang['en']?[key] ?? key;\n  }\n\n  int _currentIndex = 0;\n  final FlutterTts _flutterTts = FlutterTts();",
  `class _MainShellState extends State<MainShell> {
  bool _isLoggedIn = false;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return StudentLoginScreen(
        currentLang: widget.currentLang,
        onLogin: _login,
        onLanguageChanged: widget.onLanguageChanged,
        onSwitchRole: widget.onSwitchRole,
      );
    } else {
      return StudentDashboard(
        studentRollNo: _studentRollNo,
        onLogout: _logout,
        currentLang: widget.currentLang,
        onLanguageChanged: widget.onLanguageChanged,
        onSwitchRole: widget.onSwitchRole,
      );
    }
  }
}

class StudentDashboard extends StatefulWidget {
  final String studentRollNo;
  final VoidCallback onLogout;
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const StudentDashboard({
    super.key,
    required this.studentRollNo,
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

  String _profilePicUrl = "";
  bool _isEditingProfile = false;
  int _currentIndex = 0;
  final FlutterTts _flutterTts = FlutterTts();`
);

// 3. _loadPreferences update
content = content.replace(
  `  void _loadPreferences() async {
    try {
      final auth = FirebaseAuth.instance;
      User? currentUser = auth.currentUser;
      if (currentUser == null) {
        final userCredential = await auth.signInAnonymously();
        currentUser = userCredential.user;
      }
    } catch (e) {
      debugPrint("Anonymous auth error: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _studentName = prefs.getString("studentName") ?? "Student Name";
      _studentYear = prefs.getString("studentYear") ?? "3rd Year";
      _studentDept = prefs.getString("studentDept") ?? "Computer Science (CSE)";
      _studentId = prefs.getString("studentId") ?? "";
      _savedStop = prefs.getString("studentSavedStop") ?? "";
      
      final savedName = prefs.getString("studentName") ?? "";
      final savedYear = prefs.getString("studentYear") ?? "";
      
      _profileNameCtrl.text = savedName; 
      _profileTempYear = savedYear;
      
      final savedBus = prefs.getString("studentBusNo") ?? "";
      _profileBusCtrl.text = savedBus;
      _studentBusNo = savedBus;
    });

    _updateRouteDetails(_selectedRoute, startListener: false);
    _startPickupRequestListener();
    _startFirebaseListener();
    _listenForStudentIntercomMessages();
  }`,
  `  void _loadPreferences() async {
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
      _profileBusCtrl.text = _studentBusNo;
    });

    try {
      final response = await http.get(Uri.parse('http://localhost:5000/api/students/\${widget.studentRollNo}'));
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
  }`
);

// 4. _saveProfile and _uploadProfilePhoto
content = content.replace(
  `  void _saveProfile(String name, String year, String dept,
      {String busNo = '', String boardingStop = ''}) async {
    final updateData = {
      'name': name,
      'year': year,
      'department': dept,
    };
    
    String finalStop = _savedStop;
    String finalRoute = _selectedRoute;

    if (boardingStop.isNotEmpty) {
      finalStop = boardingStop;
      updateData['savedStop'] = boardingStop;
      
      final routeKey = _busToRouteKey[busNo.toUpperCase()];
      if (routeKey != null) {
        finalRoute = routeKey;
        updateData['selectedRoute'] = routeKey;
      }
    }

    if (Firebase.apps.isNotEmpty) {
      await FirebaseDatabase.instance.ref('students/$_studentId').update(updateData);
    }

    setState(() {
      _studentName = name;
      _studentYear = year;
      _studentDept = dept;
      if (busNo.isNotEmpty) {
        _studentBusNo = busNo;
      }
      if (boardingStop.isNotEmpty) {
        _savedStop = finalStop;
        _selectedRoute = finalRoute;
        _updateRouteDetails(finalRoute, startListener: true);
      }
    });
    _showSnackBar("✅ Profile saved successfully");
  }`,
  `  void _saveProfile(String name, String year, String dept, {required String busNo, required String boardingStop}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentName', name);
    await prefs.setString('studentYear', year);
    await prefs.setString('studentDept', dept);
    await prefs.setString('profilePicUrl', _profilePicUrl);
    await prefs.setString('studentBusNo', busNo);
    await prefs.setString('studentSavedStop', boardingStop);
    
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5000/api/students/\${widget.studentRollNo}'),
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
      
      if (busNo.isNotEmpty && _busToRouteKey.containsKey(busNo)) {
         _selectedRoute = _busToRouteKey[busNo]!;
         _updateRouteDetails(_selectedRoute, startListener: true);
      }
      _isEditingProfile = false;
    });
    
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
  }`
);


// 5. Update UI profile tab
const oldProfileTabStr = `                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF2563EB), width: 3),
                  ),
                  child: const Center(
                    child: Text("🎓", style: TextStyle(fontSize: 54)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _studentName == "Student Name" ? "Your Name" : _studentName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _studentName == "Student Name"
                        ? const Color(0xFFCBD5E1) // light grey when default
                        : const Color(0xFF0F172A),
                  ),
                ),
                const Text(
                  "Panimalar Smart Transit Account",
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),`;

const newProfileTabStr = `                Stack(
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
                  widget.studentRollNo.isEmpty ? "Roll Number" : widget.studentRollNo,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),`;

content = content.replace(oldProfileTabStr, newProfileTabStr);

// 6. View Mode vs Edit mode
const oldFieldsStr = `                // ── Full Name ──────────────────────────────────────────────
                const Text(
                  "FULL NAME",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                  ),
                ),`;

const newFieldsStr = `                if (_isEditingProfile) ...[
                  // ── Full Name ──────────────────────────────────────────────
                  const Text(
                    "FULL NAME",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),`;

content = content.replace(oldFieldsStr, newFieldsStr);

const oldSaveBtnStr = `                // ── Save button ────────────────────────────────────────────
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
                    );
                  },
                  child: const Text(
                    "💾  Save Profile",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),`;

const newSaveBtnStr = `                // ── Save button ────────────────────────────────────────────
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
                ],`;

content = content.replace(oldSaveBtnStr, newSaveBtnStr);


const endOfBuildStr = `  Widget _buildPickupRequestCard() {`;

const newBuildProfileRowStr = `  Widget _buildProfileRow(String label, String value) {
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

  Widget _buildPickupRequestCard() {`;

content = content.replace(endOfBuildStr, newBuildProfileRowStr);

// 7. AppBar Actions - add Logout
const oldAppBarStr = `      appBar: AppBar(
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
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.notifications_rounded,
                    color: Color(0xFF2563EB),
                    size: 26,
                  ),
                  onPressed: _showNotificationsPanel,
                ),
                if (_unreadNotifCount > 0 || _breakdownActive)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          ((_unreadNotifCount + (_breakdownActive ? 1 : 0)) > 9)
                              ? '9+'
                              : '\${_unreadNotifCount + (_breakdownActive ? 1 : 0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),`;

const newAppBarStr = `      appBar: AppBar(
        title: Text(t('Panimalar Transit'), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            onPressed: widget.onLogout,
            tooltip: "Logout",
          ),
          IconButton(
            icon: const Icon(Icons.language, color: Colors.black54),
            onPressed: () {
              widget.onLanguageChanged(widget.currentLang == 'en' ? 'ta' : 'en');
            },
            tooltip: t('Switch Language'),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.black54),
            onPressed: widget.onSwitchRole,
            tooltip: t('Switch Role'),
          )
        ],
      ),`;

content = content.replace(oldAppBarStr, newAppBarStr);

fs.writeFileSync(filePath, content);
console.log('Patched student_shell.dart successfully.');
