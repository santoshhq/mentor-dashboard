// mentor_dashboard_page.dart (revised as clone of dashboardpage with mentor logic)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hod_web_dashboard/applogin_page.dart';
import 'package:hod_web_dashboard/attendance_form.dart';
import 'package:hod_web_dashboard/dashboardpage.dart';
import 'package:hod_web_dashboard/login_page.dart';
import 'package:hod_web_dashboard/firebase_service.dart' as firebase_service;
import 'package:hod_web_dashboard/sidebar_item.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class MentorDashboardPage extends StatefulWidget {
  final String mentorUserId;
  const MentorDashboardPage({super.key, required this.mentorUserId});

  @override
  State<MentorDashboardPage> createState() => _MentorDashboardPageState();
}

class _MentorDashboardPageState extends State<MentorDashboardPage> {
  final Map<String, List<List<dynamic>>> _yearDataCache = {};
  String? selectedBranch;
  int selectedIndex = 0;
  String? selectedYear;
  final firebase_service.FirebaseService firebaseService =
      firebase_service.FirebaseService();
  Map<String, List<Map<String, dynamic>>> cachedStudentData = {};
  List<Map<String, String>> assignedSections = [];
  List<String> _endYears = [];
  bool _isLoading = true;
  String mentorName = '';

  @override
  void initState() {
    super.initState();
    _loadMentorData();
  }

  Future<void> _loadMentorData() async {
    try {
      final mentorSnapshot =
          await FirebaseFirestore.instance
              .collection('mentors')
              .where('userId', isEqualTo: widget.mentorUserId)
              .limit(1)
              .get();

      if (mentorSnapshot.docs.isEmpty) throw Exception("Mentor not found");

      final mentorData = mentorSnapshot.docs.first.data();
      mentorName = mentorData['name'] ?? 'Mentor';
      assignedSections =
          (mentorData['assigned'] ?? [])
              .map<Map<String, String>>(
                (e) => {
                  'batch': e['batch'].toString(),
                  'section': e['section'].toString(),
                },
              )
              .toList();

      _endYears = assignedSections.map((e) => e['batch']!).toSet().toList();

      for (String year in _endYears) {
        final allData = await firebaseService.fetchYearAttendanceData(year);

        final allowedBranches =
            assignedSections
                .where((e) => e['batch'] == year)
                .map((e) => 'CSE-${e['section']}')
                .toSet();

        final filtered =
            allData.where((row) => allowedBranches.contains(row[0])).toList();
        _yearDataCache[year] = filtered;
      }
    } catch (e) {
      print("Error loading mentor data: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void onBranchSelected(String year, String branch) {
    setState(() {
      selectedYear = year;
      selectedBranch = branch;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [_buildTopBar(), Expanded(child: _buildBody())],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final items = [Icons.dashboard, Icons.logout];

    final labels = ['Dashboard', 'Log Out'];

    return Container(
      width: 220,
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Image.asset(
              'assets/images/mlritlogo.png',
              height: 100,
              width: 180,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 40),
          for (int i = 0; i < items.length; i++)
            GestureDetector(
              onTap: () async {
                if (labels[i] == 'Log Out') {
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Confirm Logout'),
                          content: const Text(
                            'Are you sure you want to logout?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text(
                                'Yes',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                  );

                  if (shouldLogout == true) {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  }
                } else {
                  setState(() {
                    selectedIndex = i;
                  });
                }
              },
              child: SidebarItem(
                icon: items[i],
                label: labels[i],
                selected: selectedIndex == i,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.blue[800],
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.person_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    mentorName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          offset: Offset(0, 2),
                          blurRadius: 12,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(
            width: 300,
            child: TextField(
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAttendanceOverview(),
          const SizedBox(width: 20),
          _buildAttendanceForm(),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverview() {
    return Expanded(
      flex: 3,
      child:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSummaryHeader(
                      DateFormat('dd/MM/yyyy').format(DateTime.now()),
                      _yearDataCache.values.fold<int>(
                        0,
                        (p, e) => p + e.fold(0, (p2, r) => p2 + (r[1] as int)),
                      ),
                      _yearDataCache.values.fold<int>(
                        0,
                        (p, e) => p + e.fold(0, (p2, r) => p2 + (r[2] as int)),
                      ),
                      0,
                    ),
                    ...(() {
                      final sortedYears = [..._endYears];
                      sortedYears.sort(
                        (a, b) => b.compareTo(a),
                      ); // descending sort

                      return sortedYears.map((endYear) {
                        final index = sortedYears.indexOf(endYear);
                        Color color;

                        if (sortedYears.length == 1) {
                          color = const Color(0xFF4CAF50); // green
                        } else if (index == 0) {
                          color = const Color(0xFF4CAF50); // green
                        } else if (index == 1) {
                          color = const Color(0xFF42A5F5); // blue
                        } else {
                          color = const Color(0xFFFF4E8A); // pink
                        }

                        final data = _yearDataCache[endYear] ?? [];
                        final total = data.fold<int>(
                          0,
                          (sum, row) => sum + (row[1] as int),
                        );

                        return buildYearTable(
                          title: "$endYear BATCH",
                          data: data,
                          total: total,
                          gradient: LinearGradient(
                            colors: [color, color],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          onRowTap: onBranchSelected,
                          selectedBranch: selectedBranch,
                          selectedYear: selectedYear,
                        );
                      }).toList();
                    })(),
                  ],
                ),
              ),
    );
  }

  Widget _buildAttendanceForm() {
    return Expanded(
      flex: 2,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            selectedBranch == null
                ? const Center(
                  child: Text("Select a branch to view attendance."),
                )
                : AttendanceForm(
                  branchName: selectedBranch!,
                  cachedData: cachedStudentData[selectedBranch!],
                  onCacheUpdate: (data) {
                    setState(() {
                      cachedStudentData[selectedBranch!] = data;
                    });
                  },
                ),
      ),
    );
  }
}
