import 'package:flutter/material.dart';

class RoleSelectionScreen extends StatelessWidget {
  final Function(String) onSelectRole;
  final String currentLang;
  final Function(String) onLanguageChanged;
  
  RoleSelectionScreen({
    super.key,
    required this.onSelectRole,
    required this.currentLang,
    required this.onLanguageChanged,
  });

  // Local translations for the role selection screen
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Smart Transit Platform',
      'subtitle': 'SELECT YOUR ROLE',
      'student_title': 'I am a Student',
      'student_desc': 'Track live buses, find routes, and view schedules.',
      'driver_title': 'I am a Driver',
      'driver_desc': 'Share live GPS location, log boarding, and report alerts.',
      'admin_title': 'I am an Admin',
      'admin_desc': 'Review permission letters, confirm pickup requests.',
      'footer': 'Panimalar Engineering College',
    },
    'ta': {
      'title': 'ஸ்மார்ட் போக்குவரத்து தளம்',
      'subtitle': 'உங்கள் பாத்திரத்தை தேர்ந்தெடுக்கவும்',
      'student_title': 'நான் ஒரு மாணவர்',
      'student_desc': 'பேருந்துகளைத் தடம் காணவும், வழிகளைக் கண்டறியவும்.',
      'driver_title': 'நான் ஒரு ஓட்டுநர்',
      'driver_desc': 'GPS இருப்பிடத்தைப் பகிரவும் மற்றும் எச்சரிக்கைகளை தெரிவிக்கவும்.',
      'admin_title': 'நான் ஒரு நிர்வாகி',
      'admin_desc': 'அனுமதி கடிதங்களை மதிப்பாய்வு செய்யவும்.',
      'footer': 'பனிமலர் பொறியியல் கல்லூரி',
    },
    'te': {
      'title': 'స్మార్ట్ రవాణా వేదిక',
      'subtitle': 'మీ పాత్రను ఎంచుకోండి',
      'student_title': 'నేను విద్యార్థిని',
      'student_desc': 'బస్సులను ట్రాక్ చేయండి, మార్గాలను కనుగొనండి.',
      'driver_title': 'నేను డ్రైవర్‌ను',
      'driver_desc': 'GPS స్థానాన్ని పంచుకోండి మరియు హెచ్చరికలను నివేదించండి.',
      'admin_title': 'నేను అడ్మిన్‌ను',
      'admin_desc': 'అనుమతి లేఖలను సమీక్షించండి.',
      'footer': 'పనిమలర్ ఇంజనీరింగ్ కళాశాల',
    }
  };

  String t(String key) {
    return _translations[currentLang]?[key] ?? _translations['en']![key]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), Color(0xFFE6ECFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFF2563EB),
                      selectedForegroundColor: Colors.white,
                    ),
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English', style: TextStyle(fontSize: 10))),
                      ButtonSegment(value: 'ta', label: Text('தமிழ்', style: TextStyle(fontSize: 10))),
                      ButtonSegment(value: 'te', label: Text('తెలుగు', style: TextStyle(fontSize: 10))),
                    ],
                    selected: {currentLang},
                    onSelectionChanged: (set) {
                      if (set.isNotEmpty) {
                        onLanguageChanged(set.first);
                      }
                    },
                  ),
                ),
                const Spacer(),
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/images/panimalar_logo.png', width: 56, height: 56, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "PANIMALAR",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                Text(
                  t('title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                Text(
                  t('subtitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => onSelectRole("student"),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFDBE2F8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: const Text("🎓", style: TextStyle(fontSize: 28)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('student_title'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('student_desc'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => onSelectRole("driver"),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFDBE2F8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: const Text("👔", style: TextStyle(fontSize: 28)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('driver_title'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('driver_desc'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => onSelectRole("admin"),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFDBE2F8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: const Text("🔑", style: TextStyle(fontSize: 28)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('admin_title'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('admin_desc'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  t('footer'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
