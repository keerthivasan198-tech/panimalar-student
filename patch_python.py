import os
import re

file_path = "lib/screens/student/student_shell.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Fix imports
content = content.replace(
    "import '../../services/campus_path_graph.dart';",
    "import '../../services/campus_path_graph.dart';\nimport 'student_login_screen.dart';\nimport 'dart:convert';\nimport 'package:http/http.dart' as http;\nimport 'dart:io';\nimport 'dart:typed_data';\nimport 'package:file_picker/file_picker.dart';"
)

# 2. Refactor MainShell to StudentDashboard wrapper
old_main_shell = """class MainShell extends StatefulWidget {
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const MainShell({super.key, required this.onSwitchRole, required this.currentLang, required this.onLanguageChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {"""

new_main_shell = """class MainShell extends StatefulWidget {
  final VoidCallback onSwitchRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  const MainShell({super.key, required this.onSwitchRole, required this.currentLang, required this.onLanguageChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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

class _StudentDashboardState extends State<StudentDashboard> with TickerProviderStateMixin {"""
content = content.replace(old_main_shell, new_main_shell)

# We also need to add our state variables inside _StudentDashboardState:
state_vars_insertion = """  int _currentIndex = 0;

  bool _isEditingProfile = false;
  String _profilePicUrl = "";"""
content = re.sub(r"  int _currentIndex = 0;", state_vars_insertion, content, count=1)


# 3. Replace _loadPreferences
old_load_prefs = r"  void _loadPreferences\(\) async \{[\s\S]*?_listenForStudentIntercomMessages\(\);\n  \}"
new_load_prefs = """  void _loadPreferences() async {
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
      final response = await http.get(Uri.parse('http://localhost:5000/api/students/${widget.studentRollNo}'));
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
  }"""
content = re.sub(old_load_prefs, new_load_prefs, content)

# 4. Replace _saveProfile and add _uploadProfilePhoto
old_save_profile = r"  void _saveProfile\(String name, String year, String dept,[\s\S]*?_showSnackBar\(\"✅ Profile saved successfully\"\);\n  \}"
new_save_profile = """  void _saveProfile(String name, String year, String dept, {required String busNo, required String boardingStop}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentName', name);
    await prefs.setString('studentYear', year);
    await prefs.setString('studentDept', dept);
    await prefs.setString('profilePicUrl', _profilePicUrl);
    await prefs.setString('studentBusNo', busNo);
    await prefs.setString('studentSavedStop', boardingStop);
    
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5000/api/students/${widget.studentRollNo}'),
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
  }"""
content = re.sub(old_save_profile, new_save_profile, content)


# 5. Fix AppBar
# Since there are multiple AppBars, we want to replace the one inside the main `Widget build(BuildContext context)` method
# We'll use a precise replacement.
appbar_old = r"""      appBar: AppBar\(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row\(
          children: \[
            Container\(
              width: 38,
              height: 38,
              decoration: BoxDecoration\(
                color: Colors.white,
                borderRadius: BorderRadius.circular\(11\),
                border: Border.all\(color: const Color\(0xFFE2E8F0\)\),
              \),
              child: const Icon\(
                Icons.directions_bus_rounded,
                color: Color\(0xFF2563EB\),
                size: 22,
              \),
            \),
            const SizedBox\(width: 10\),
            Column\(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: \[
                const Text\(
                  "Panimalar Transit",
                  style: TextStyle\(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color\(0xFF0F172A\),
                  \),
                \),
                Row\(
                  children: \[
                    Container\(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration\(
                        color: Color\(0xFF16A34A\),
                        shape: BoxShape.circle,
                      \),
                    \),
                    const SizedBox\(width: 4\),
                    const Text\(
                      "Student Portal",
                      style: TextStyle\(fontSize: 10, color: Color\(0xFF64748B\), fontWeight: FontWeight.bold\),
                    \)
                  \],
                \)
              \],
            \)
          \],
        \),
        actions: \[
          SizedBox\(
            width: 48,
            height: 48,
            child: Stack\(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: \[
                IconButton\(
                  padding: EdgeInsets.zero,
                  icon: const Icon\(
                    Icons.notifications_rounded,
                    color: Color\(0xFF2563EB\),
                    size: 26,
                  \),
                  onPressed: _showNotificationsPanel,
                \),
                if \(_unreadNotifCount > 0 \|\| _breakdownActive\)
                  Positioned\(
                    right: 4,
                    top: 4,
                    child: Container\(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration\(
                        color: Color\(0xFFDC2626\),
                        shape: BoxShape.circle,
                      \),
                      child: Center\(
                        child: Text\(
                          \(\(_unreadNotifCount \+ \(_breakdownActive \? 1 : 0\)\) > 9\)
                              \? '9\+'
                              : '\$\{\_unreadNotifCount \+ \(_breakdownActive \? 1 : 0\)\}',
                          style: const TextStyle\(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          \),
                        \),
                      \),
                    \),
                  \),
              \],
            \),
          \),
        \],
      \),"""

appbar_new = """      appBar: AppBar(
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
      ),"""
content = re.sub(appbar_old, appbar_new, content)

# 6. Completely Replace _buildProfileTab
profile_tab_regex = r"  Widget _buildProfileTab\(\) \{[\s\S]*?String\? _deptDropdownValue\(\) \{"
new_profile_tab = """  Widget _buildProfileTab() {
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
                    onChanged: (_) => setState(() {}), // rebuild for route dropdown
                    decoration: InputDecoration(
                      hintText: "e.g. B101, B202, B303",
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Icon(Icons.directions_bus_rounded,
                          color: Color(0xFF2563EB), size: 18),
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
                        final key = _busToRouteKey[
                            _profileBusCtrl.text.trim().toUpperCase()];
                        if (key == null) return null;
                        return '✓  ' + (routeLabelsConfig[key] ?? '');
                      }(),
                      helperStyle: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      errorText: _profileBusCtrl.text.trim().isNotEmpty &&
                              _busToRouteKey[_profileBusCtrl.text
                                      .trim()
                                      .toUpperCase()] ==
                                  null
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

  String? _deptDropdownValue() {"""
content = re.sub(profile_tab_regex, new_profile_tab, content)

# 7. Remove the old Logout button at the very end of _buildProfileTab
# Wait, I already removed it because the regex matched up to _deptDropdownValue.
# Let's double check if there are any trailing } or things missed.

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Patch applied successfully.")
