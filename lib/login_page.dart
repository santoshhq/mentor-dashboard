import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hod_web_dashboard/firebase_service.dart';
import 'package:hod_web_dashboard/mentors/mentor_dashboard_page.dart';
import 'package:marquee/marquee.dart';
import 'dashboardpage.dart'; // replace with your actual dashboard page import

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isHodLogin = true;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _usernameError;
  String? _passwordError;
  int _failedAttempts = 0;

  Future<void> _loginUser() async {
    setState(() {
      _isLoading = true;
      _usernameError = null;
      _passwordError = null;
    });

    try {
      if (isHodLogin) {
        // ✅ HOD login validation
        final isValid = await FirebaseService().validateHodLogin(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        if (isValid) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        } else {
          setState(() {
            _passwordError = "Invalid HOD username or password";
            _isLoading = false;
          });
        }
      } else {
        // ✅ Mentor login validation and fetching required fields
        final mentorDoc = await FirebaseService().getMentorDocument(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        if (mentorDoc != null) {
          final mentorUserId = mentorDoc['userId'] ?? '';
          // Optional: you can use this if needed
          // final mentorName = mentorDoc['name'] ?? 'Mentor';

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MentorDashboardPage(mentorUserId: mentorUserId),
            ),
          );
        } else {
          setState(() {
            _passwordError = "Invalid Mentor username or password";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _passwordError = "An error occurred: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _usernameError = "Enter email to reset password";
      });
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _usernameController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password reset email sent")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          SizedBox(
            height: 100,
            child: Image.asset(
              'images/banner_top.png',
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Container(
            color: Colors.blue[800],
            height: 30,
            child: Marquee(
              text: 'Welcome to MLR Institute Of Technology    ',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              velocity: 40,
              blankSpace: 100,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 900),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'images/mlrit_building.png',
                          fit: BoxFit.cover,
                          height: 400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 30),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "MLRIT - STUDENT ATTENDANCE",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ToggleButtons(
                              isSelected: [isHodLogin, !isHodLogin],
                              onPressed: (index) {
                                setState(() {
                                  isHodLogin = index == 0;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              selectedColor: Colors.white,
                              fillColor: Colors.blue,
                              color: Colors.blue,
                              constraints: const BoxConstraints(
                                minHeight: 40,
                                minWidth: 120,
                              ),
                              children: const [
                                Text("HOD Login"),
                                Text("Mentor Login"),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                hintText: 'Email',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                errorText: _usernameError,
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                prefixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                errorText: _passwordError,
                              ),
                            ),
                            if (_failedAttempts >= 2 && isHodLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _resetPassword,
                                  child: const Text("Forgot Password?"),
                                ),
                              ),

                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoading
                                        ? null
                                        : () {
                                          setState(() {
                                            _usernameError =
                                                _usernameController.text
                                                        .trim()
                                                        .isEmpty
                                                    ? "Please enter username"
                                                    : null;
                                            _passwordError =
                                                _passwordController.text
                                                        .trim()
                                                        .isEmpty
                                                    ? "Please enter a valid password"
                                                    : null;
                                          });

                                          if (_usernameError == null &&
                                              _passwordError == null) {
                                            _loginUser();
                                          }
                                        },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child:
                                    _isLoading
                                        ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                        : const Text(
                                          "Login",
                                          style: TextStyle(fontSize: 16),
                                        ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "2025 © MLR Institute Of Technology - All Rights Reserved",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
