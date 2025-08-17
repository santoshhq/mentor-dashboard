import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hod_web_dashboard/applogin_page.dart';
import 'package:hod_web_dashboard/attendanceform.dart';
import 'package:hod_web_dashboard/dashboardpage.dart';
import 'package:hod_web_dashboard/firebase_service.dart';
import 'package:hod_web_dashboard/hodstudentattendancedialog.dart';
import 'package:hod_web_dashboard/login_page.dart';
import 'package:hod_web_dashboard/firebase_service.dart' as firebase_service;
import 'package:hod_web_dashboard/mentors/mentor_student_upload_page.dart';
import 'package:hod_web_dashboard/mentors/mentorstudentselectoin.dart';
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
  final GlobalKey<MentorStudentSelectorPageState> _studentSelectorKey =
      GlobalKey<MentorStudentSelectorPageState>();
  final GlobalKey<MentorStudentUploadPageState> _studentUploadKey =
      GlobalKey<MentorStudentUploadPageState>();
  final Set<String> _selectedStudentRollNos = {};
  Set<String> _currentSelectedRollNos = {};
  Map<String, int> _sectionStrengthMap = {};

  Set<String> _currentFrozenRollNos = {};

  final Map<String, List<List<dynamic>>> _yearDataCache = {};
  String? selectedBranch;
  int selectedIndex = 0;
  DateTime selectedDate = DateTime.now();
  List<DateTime> availableDates = [];

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
    selectedDate = DateTime.now(); // force today's date every time
    _initializeMentorDashboard();
    _yearDataCache.clear();
  }

  Future<void> _initializeMentorDashboard() async {
    await _loadAvailableDates();
    await _loadMentorData();
    setState(() {
      _isLoading = false;
    });
  }

  bool _allowTodaySelection = false; // Place this at class level

  Future<void> _pickDate() async {
    debugPrint("📅 Pick date tapped!");
    if (!mounted || availableDates.isEmpty) return;

    final DateTime firstDate = availableDates.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final DateTime lastDate = availableDates.reduce(
      (a, b) => a.isAfter(b) ? a : b,
    );

    DateTime initialDate =
        selectedDate.isBefore(firstDate)
            ? firstDate
            : selectedDate.isAfter(lastDate)
            ? lastDate
            : selectedDate;

    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        selectableDayPredicate: (date) {
          // ✅ Allow only dates that are in availableDates
          return availableDates.any(
            (d) =>
                d.year == date.year &&
                d.month == date.month &&
                d.day == date.day,
          );
        },
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Color(0xFF0746C5), // Header and selected color
                onPrimary: Colors.white,
                onSurface: Colors.black87,
              ),
              datePickerTheme: DatePickerThemeData(
                todayBackgroundColor: MaterialStateProperty.all(
                  const Color.fromARGB(255, 4, 153, 81).withOpacity(0.2),
                ),
                todayBorder: BorderSide(color: Colors.green, width: 1.5),
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null && picked != selectedDate) {
        setState(() {
          selectedDate = picked;
          selectedBranch = null;
          selectedYear = null;
          _isLoading = true;
        });

        await _loadMentorData(); // or _loadMentorData()
      }
    } catch (e) {
      debugPrint("❌ Error showing date picker: $e");
    }
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
                  'department': e['department']?.toString() ?? 'CSE',
                },
              )
              .toList();

      _endYears = assignedSections.map((e) => e['batch']!).toSet().toList();

      // 🔹 Build fresh strength map
      Map<String, int> sectionStrengthMap = {};

      for (var sec in assignedSections) {
        final sectionKey = "${sec['batch']}-${sec['section']}";
        final assignedDoc =
            await FirebaseFirestore.instance
                .collection('mentors')
                .doc(widget.mentorUserId)
                .collection('assignedStudents')
                .doc(sectionKey)
                .get();

        if (assignedDoc.exists && assignedDoc.data() != null) {
          final selectedRollNos = List<String>.from(
            assignedDoc.data()!['selectedRollNos'] ?? [],
          );
          sectionStrengthMap[sectionKey] = selectedRollNos.length;
        } else {
          // 🛑 FIX: Do NOT default to total count for new section → set to 0
          sectionStrengthMap[sectionKey] = 0;
        }
      }

      _sectionStrengthMap = sectionStrengthMap; // Store for later use

      // 🔹 Fetch year attendance data (force refresh)
      for (String year in _endYears) {
        final allData = await firebaseService.fetchYearAttendanceData(
          year,
          forceRefresh: true, // Always fresh for mentor dashboard
          forDate: selectedDate,
          mentorUserId: widget.mentorUserId,
        );

        // Filter only assigned branches
        final allowedBranches =
            assignedSections
                .where((e) => e['batch'] == year)
                .map((e) => "${e['department']}-${e['section']}")
                .toSet();

        final filtered =
            allData.where((row) => allowedBranches.contains(row[0])).map((row) {
              final secKey = "$year-${row[0].split('-')[1]}"; // batch-section
              final strength = _sectionStrengthMap[secKey] ?? 0;
              return [row[0], strength, row[2], row[3]];
            }).toList();

        setState(() {
          _yearDataCache[year] = filtered;
        });
      }
    } catch (e) {
      print("Error loading mentor data: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAvailableDates() async {
    availableDates =
        await FirebaseService.instance.fetchAvailableAttendanceDates();
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
              children: [
                _buildTopBar(),
                Expanded(
                  child:
                      selectedIndex == 0
                          ? _buildBody()
                          : selectedIndex == 1
                          ? MentorStudentSelectorPage(
                            key: _studentSelectorKey,
                            mentorUserId: widget.mentorUserId,
                            onSelectedRollNosChanged: (rollNos) {
                              setState(() {
                                _currentSelectedRollNos = rollNos;
                              });
                            },
                          )
                          : selectedIndex == 2
                          ? MentorStudentUploadPage(
                            key: _studentUploadKey,
                            mentorUserId: widget.mentorUserId,
                            assignedSections: assignedSections,
                            selectedStudentRollNos: Set<String>.from(
                              _currentSelectedRollNos,
                            ), // ⬅ From Selector page
                            onCacheUpdate: (
                              String endYear,
                              List<List<dynamic>> updatedData,
                            ) async {
                              // 🔄 Refresh section strength counts for only this endYear
                              final Map<String, int> freshCounts = {};
                              final sectionsForYear = assignedSections.where(
                                (e) => e['batch'] == endYear,
                              );

                              for (final sec in sectionsForYear) {
                                final sectionKey = "$endYear-${sec['section']}";
                                try {
                                  final doc =
                                      await FirebaseFirestore.instance
                                          .collection('mentors')
                                          .doc(widget.mentorUserId)
                                          .collection('assignedStudents')
                                          .doc(sectionKey)
                                          .get();

                                  if (doc.exists && doc.data() != null) {
                                    final selectedRollNos = List<String>.from(
                                      doc.data()!['selectedRollNos'] ?? [],
                                    );
                                    freshCounts[sectionKey] =
                                        selectedRollNos.length;
                                  } else {
                                    freshCounts[sectionKey] = 0;
                                  }
                                } catch (_) {
                                  freshCounts[sectionKey] = 0;
                                }
                              }

                              // Update _sectionStrengthMap with fresh counts
                              setState(() {
                                _sectionStrengthMap.addAll(freshCounts);
                              });

                              // Now rebuild the year data cache with the new counts
                              final allowedBranches =
                                  assignedSections
                                      .where((e) => e['batch'] == endYear)
                                      .map(
                                        (e) =>
                                            "${e['department']}-${e['section']}",
                                      )
                                      .toSet();

                              final filtered =
                                  updatedData
                                      .where(
                                        (row) =>
                                            allowedBranches.contains(row[0]),
                                      )
                                      .map((row) {
                                        final secKey =
                                            "$endYear-${row[0].split('-')[1]}";
                                        final strength =
                                            _sectionStrengthMap[secKey] ??
                                            row[1];
                                        return [
                                          row[0],
                                          strength,
                                          row[2],
                                          row[3],
                                        ];
                                      })
                                      .toList();

                              setState(() {
                                _yearDataCache[endYear] = filtered;
                              });
                            },
                          )
                          : Container(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    // Added upload icon and label in correct order
    final items = [
      Icons.dashboard,
      Icons.people,
      Icons.upload_file,
      Icons.logout,
    ];
    final labels = ['Dashboard', 'Students', 'Upload', 'Log Out'];

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
                        (context) => Dialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 10,
                          backgroundColor: Colors.white,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 300,
                              maxWidth: 400,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 32,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Text(
                                        "Confirm Logout?",
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.exit_to_app_outlined,
                                        size: 28,
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "Are you sure want to logout?",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 32),
                                  FractionallySizedBox(
                                    widthFactor: 1,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0746C5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 2,
                                      ),
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text(
                                        "Confirm Logout",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FractionallySizedBox(
                                    widthFactor: 1,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        side: const BorderSide(
                                          color: Colors.grey,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text(
                                        "No",
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
      color: Color(0xFF0746C5),
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

          //  Refresh to Today Button
          Row(
            children: [
              Container(
                width: 320,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade300, width: 1.4),
                ),
                child: TextField(
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search Roll No...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Colors.grey.shade600,
                      size: 26,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 0,
                    ),
                    border: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(
                        color: Color(0xFF0746C5),
                        width: 2.2,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    final rollNo = value.trim().toUpperCase();
                    if (rollNo.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder:
                            (_) => HodStudentAttendanceDialog(rollNo: rollNo),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(width: 16),

              //  Refresh IconButton
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh',
                onPressed: () async {
                  if (selectedIndex == 0) {
                    // Dashboard page refresh
                    setState(() {
                      selectedDate = DateTime.now();
                      _allowTodaySelection = true;
                      _yearDataCache.clear();
                      _isLoading = true;
                    });
                    await _loadMentorData();
                    setState(() => _isLoading = false);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF0746C5),
                        content: Row(
                          children: const [
                            Icon(Icons.refresh, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              "Refreshed Successfully!",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else if (selectedIndex == 1) {
                    // Student selector refresh
                    _studentSelectorKey.currentState?.refreshPage();
                  } else if (selectedIndex == 2) {
                    // Student upload refresh
                    _studentUploadKey.currentState?.refreshPage();
                  }
                },
              ),
            ],
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
    final totalStudents = _yearDataCache.values.fold<int>(
      0,
      (p, e) => p + e.fold(0, (p2, r) => p2 + (r[1] as int)),
    );

    final totalAttended = _yearDataCache.values.fold<int>(
      0,
      (p, e) => p + e.fold(0, (p2, r) => p2 + (r[2] as int)),
    );

    final int percent =
        totalStudents > 0 ? ((totalAttended / totalStudents) * 100).round() : 0;

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
                      DateFormat(
                        'dd/MM/yyyy',
                      ).format(selectedDate), // ✅ show picked date
                      totalStudents,
                      totalAttended,
                      percent, // ✅ now calculated instead of hardcoded
                      _pickDate, // ✅ calendar popup
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
    if (selectedBranch != null) {
      final rawBranch = selectedBranch!;
      final branchCleaned = rawBranch.split(' ').first.trim(); // e.g., CSE-D
      final parts = branchCleaned.split('-');
      final department = parts[0];
      final section = parts[1];
      final rawYear = selectedYear ?? 'Unknown';
      final yearCleaned = rawYear.split(' ').first.trim(); // e.g., 2028

      debugPrint("🔎 Requested: $rawBranch → Cleaned: $branchCleaned");
      debugPrint(
        "🧪 dept=$department | section=$section | endYear=$yearCleaned",
      );

      // ✅ NO NEED to re-fetch _yearDataCache here (do it in _loadMentorData)

      return Expanded(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AttendanceForm(
            key: ValueKey("${selectedBranch}_$selectedDate"),
            branchName: branchCleaned,
            endYear: yearCleaned,
            selectedDate: selectedDate,
            cachedData: cachedStudentData[selectedBranch!],
            onCacheUpdate: (data) async {
              final updatedData = await firebaseService.fetchYearAttendanceData(
                yearCleaned,
                forceRefresh: true,
                forDate: selectedDate,
                mentorUserId: widget.mentorUserId,
              );

              final allowedBranches =
                  assignedSections
                      .where((e) => e['batch'] == yearCleaned)
                      .map((e) => "${e['department']}-${e['section']}")
                      .toSet();

              final filtered =
                  updatedData
                      .where((row) => allowedBranches.contains(row[0]))
                      .map((row) {
                        final secKey = "$yearCleaned-${row[0].split('-')[1]}";
                        final strength = _sectionStrengthMap[secKey] ?? row[1];
                        return [
                          row[0],
                          strength, // ✅ Always use mentor's selected count here
                          row[2],
                          row[3],
                        ];
                      })
                      .toList();

              setState(() {
                cachedStudentData[selectedBranch!] = data;
                _yearDataCache[yearCleaned] = filtered;
              });
            },

            mentorUserId: widget.mentorUserId,
          ),
        ),
      );
    }

    // When no section selected
    return const Expanded(
      flex: 2,
      child: Center(child: Text("Select a Section to view attendance.")),
    );
  }
}
