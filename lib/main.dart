import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/student/student_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }
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
      title: 'Panimalar Smart Transit - Student',
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
  String _currentLang = "en";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString("student_user_lang") ?? "en";
    setState(() {
      _currentLang = savedLang;
      _isLoading = false;
    });
  }

  void _updateLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("student_user_lang", lang);
    setState(() {
      _currentLang = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return MainShell(
      onSwitchRole: () {}, // Removed role switching
      currentLang: _currentLang, 
      onLanguageChanged: _updateLang
    );
  }
}