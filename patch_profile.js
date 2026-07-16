const fs = require('fs');

const filePath = 'lib/screens/student/student_shell.dart';
let content = fs.readFileSync(filePath, 'utf8');

// The new profile tab code
const newProfileTab = `  Widget _buildProfileTab() {
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

  /// Returns the current department value only if it matches one of the`;

// Extract everything before _buildProfileTab()
const parts = content.split(/Widget _buildProfileTab\(\) \{/);
const before = parts[0];
const after = parts[1];

// Find where _deptDropdownValue starts (which is right after _buildProfileTab ends)
const afterParts = after.split(/String\? _deptDropdownValue\(\) \{/);
const veryAfter = afterParts[1];

const finalContent = before + newProfileTab + "\n  String? _deptDropdownValue() {" + veryAfter;

fs.writeFileSync(filePath, finalContent);
console.log('Patched profile UI successfully');
