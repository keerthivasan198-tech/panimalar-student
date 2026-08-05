import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

class _StudentLoginScreenState extends State<StudentLoginScreen> with SingleTickerProviderStateMixin {
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
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
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
    final rollNo = _rollNoController.text.trim();
    if (rollNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFacultyLogin ? 'Please enter your Faculty ID' : 'Please enter your Roll Number', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        final snapshot = await FirebaseDatabase.instance.ref('$node/$rollNo').get();
        if (snapshot.exists && snapshot.value != null) {
          // Profile exists, log in
          widget.onLogin(rollNo, _isFacultyLogin);
        } else {
          // Profile not found, prompt to create
          widget.onCreateProfile(_isFacultyLogin);
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 30,
                              spreadRadius: -5,
                            )
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
                                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.school_rounded, size: 64, color: Colors.white),
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
                                      onTap: () => setState(() => _isFacultyLogin = false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: !_isFacultyLogin ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Student',
                                          style: TextStyle(
                                            color: !_isFacultyLogin ? const Color(0xFF1E3A8A) : Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _isFacultyLogin = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _isFacultyLogin ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Faculty',
                                          style: TextStyle(
                                            color: _isFacultyLogin ? const Color(0xFF1E3A8A) : Colors.white,
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
                              _isFacultyLogin ? 'Faculty Portal' : 'Student Portal',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isFacultyLogin ? 'Enter your Faculty ID (e.g. CSE/001)' : 'Enter your Roll Number to continue',
                              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85)),
                            ),
                            const SizedBox(height: 40),
                            
                            // Input Field
                            TextField(
                              controller: _rollNoController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              cursorColor: Colors.white,
                              decoration: InputDecoration(
                                labelText: _isFacultyLogin ? 'Faculty ID' : 'Roll Number',
                                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                prefixIcon: Icon(Icons.badge_outlined, color: Colors.white.withValues(alpha: 0.8)),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.15),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
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
                                  shadowColor: Colors.black.withValues(alpha: 0.3),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _isLoading 
                                    ? const SizedBox(
                                        height: 24, 
                                        width: 24, 
                                        child: CircularProgressIndicator(color: Color(0xFF1E3A8A), strokeWidth: 3)
                                      )
                                    : const Text(
                                        'Login', 
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.0)
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // Create Profile
                            TextButton(
                              onPressed: () => widget.onCreateProfile(_isFacultyLogin),
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
                              onPressed: () => widget.onLogin('Guest', false),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
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

