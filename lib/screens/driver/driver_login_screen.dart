import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../config/routes_config.dart';

class DriverLoginScreen extends StatefulWidget {
  final String currentLang;
  final Function(String) onLogin;
  final Function(String) onLanguageChanged;
  final VoidCallback onSwitchRole;

  const DriverLoginScreen({
    super.key,
    required this.currentLang,
    required this.onLogin,
    required this.onLanguageChanged,
    required this.onSwitchRole,
  });

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final TextEditingController _busController = TextEditingController();
  String _errorMsg = "";
  bool _isLoading = false;

  String t(String key) {
    return driverLang[widget.currentLang]?[key] ?? key;
  }

  void _attemptLogin() async {
    final bus = _busController.text.trim().toUpperCase();

    if (bus.isEmpty) {
      setState(() {
        _errorMsg = t('errorEnter');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = "";
    });

    try {
      if (Firebase.apps.isNotEmpty) {
        final snapshot = await FirebaseDatabase.instance.ref('drivers').get();
        if (snapshot.exists && snapshot.value != null) {
          final data = snapshot.value;
          List driversList = [];
          if (data is List) {
            driversList = data;
          } else if (data is Map) {
            driversList = data.values.toList();
          }

          bool found = false;
          for (var item in driversList) {
            if (item is Map) {
              final dbBus = item['bus']?.toString().trim().toUpperCase();
              if (dbBus == bus) {
                found = true;
                break;
              }
            }
          }
          
          if (found) {
            widget.onLogin(bus);
            return;
          } else {
            setState(() {
              _errorMsg = "Route $bus not registered by Admin.";
            });
            return;
          }
        } else {
          setState(() {
            _errorMsg = "No routes registered yet.";
          });
          return;
        }
      }

      setState(() {
        _errorMsg = "Cannot connect to Firebase.";
      });
    } catch (e) {
      setState(() {
        _errorMsg = "Login error: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDBE2F8)),
                        ),
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset('assets/images/panimalar_logo.png', width: 24, height: 24, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('appTitle'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          Text(
                            t('appSubtitle'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 36),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFDBE2F8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('sectionLogin'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          "Route Number / Bus No",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _busController,
                          decoration: InputDecoration(
                            hintText: "e.g. 4 or 86",
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                          ),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),

                        if (_errorMsg.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              _errorMsg,
                              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _attemptLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  t('btnLogin'),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: widget.onSwitchRole,
                    child: const Text(
                      "🎓 Switch to Student Mode",
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
