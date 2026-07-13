import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/role_selection_screen.dart';
import 'screens/student/student_shell.dart';
import 'screens/driver/driver_shell.dart';
import 'screens/admin/admin_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBUozEQcU48yRBSSM3EquhV8Sm1vWtRPFY",
        appId: "1:538185362536:web:e8d35e63d4c641979c1fdd",
        messagingSenderId: "538185362536",
        projectId: "gen-lang-client-0636615491",
        databaseURL: "https://gen-lang-client-0636615491-default-rtdb.asia-southeast1.firebasedatabase.app",
      ),
    );
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint("Firebase initialization or auth error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panimalar Smart Transit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF16A34A),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'Plus Jakarta Sans',
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  String _role = "loading";
  String _currentLang = "en";

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRole = prefs.getString("user_role") ?? "none";
    final savedLang = prefs.getString("user_lang") ?? "en";
    setState(() {
      _role = savedRole;
      _currentLang = savedLang;
    });
  }

  void _updateRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("user_role", role);
    setState(() {
      _role = role;
    });
  }

  void _updateLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("user_lang", lang);
    setState(() {
      _currentLang = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_role == "loading") {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_role == "driver") {
      return DriverShell(onSwitchRole: () => _updateRole("none"), currentLang: _currentLang, onLanguageChanged: _updateLang);
    } else if (_role == "admin") {
      return AdminShell(onSwitchRole: () => _updateRole("none"), currentLang: _currentLang, onLanguageChanged: _updateLang);
    } else if (_role == "student") {
      return MainShell(onSwitchRole: () => _updateRole("none"), currentLang: _currentLang, onLanguageChanged: _updateLang);
    } else {
      return RoleSelectionScreen(
        onSelectRole: (role) {
          _updateRole(role);
        },
        currentLang: _currentLang,
        onLanguageChanged: _updateLang,
      );
    }
  }
}