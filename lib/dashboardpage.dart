import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hod_web_dashboard/applogin_page.dart';
import 'package:hod_web_dashboard/firebase_service.dart';
import 'package:hod_web_dashboard/login_page.dart';
import 'package:hod_web_dashboard/mentors/mentors_page.dart';
import 'package:intl/intl.dart';
import 'package:hod_web_dashboard/firebase_service.dart' as firebase_service;
import 'package:table_calendar/table_calendar.dart';
import 'sidebar_item.dart';
import 'package:hod_web_dashboard/attendanceform.dart';
//import 'package:flutter/material.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Map<String, List<List<dynamic>>> _yearDataCache = {};
  String? selectedBranch;
  int selectedIndex = 0;
  String? selectedYear;
  DateTime selectedDate =
      DateTime.now(); // 👈 This stores the current or selected date
  List<DateTime> availableDates = [];

  final firebase_service.FirebaseService firebaseService =
      firebase_service.FirebaseService();
  Map<String, List<Map<String, dynamic>>> cachedStudentData = {};

  void onBranchSelected(String year, String branch) {
    setState(() {
      selectedYear = year;
      selectedBranch = branch;
    });
  }

  List<String> _endYears = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
    _initializeDashboard(); // 🔄 Call the combined setup method
  }

  Future<void> _initializeDashboard() async {
    await _loadAvailableDates(); // must be done first!
    await _loadYearData();
    setState(() {
      _isLoading = false;
    });
  }

  /*Future<void> showCustomDatePicker({
    required BuildContext context,
    required DateTime selectedDate,
    required List<DateTime> availableDates,
    required void Function(DateTime) onDateSelected,
  }) async {
    if (availableDates.isEmpty) return;

    DateTime tempSelectedDate = selectedDate;

    final firstAvailable = availableDates.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final lastAvailable = availableDates.reduce((a, b) => a.isAfter(b) ? a : b);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          child: Container(
            width: 400, // Ideal for web dialog
            height: 500, // Fixed height like your reference image
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    TableCalendar(
                      firstDay: DateTime.now().subtract(
                        const Duration(days: 60),
                      ),
                      lastDay: DateTime.now(),
                      focusedDay: tempSelectedDate,
                      selectedDayPredicate:
                          (day) => isSameDay(tempSelectedDate, day),
                      onDaySelected: (selected, focused) {
                        if (availableDates.any((d) => isSameDay(d, selected))) {
                          setState(() {
                            tempSelectedDate = selected;
                          });
                        }
                      },
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Colors.green.shade600, // ✅ mark today
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: const TextStyle(color: Colors.white),
                        defaultTextStyle: const TextStyle(fontSize: 14),
                        weekendTextStyle: const TextStyle(color: Colors.red),
                      ),
                      headerStyle: const HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                        leftChevronIcon: Icon(Icons.chevron_left),
                        rightChevronIcon: Icon(Icons.chevron_right),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(fontWeight: FontWeight.w500),
                        weekendStyle: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      enabledDayPredicate: (day) {
                        return availableDates.any(
                          (d) =>
                              d.year == day.year &&
                              d.month == day.month &&
                              d.day == day.day,
                        );
                      },
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Month',
                      },
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          child: const Text("Cancel"),
                          onPressed: () => Navigator.pop(context),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            onDateSelected(tempSelectedDate);
                            Navigator.pop(context);
                          },
                          child: const Text("Apply"),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }*/

  Future<void> _loadAvailableDates() async {
    availableDates =
        await firebaseService
            .fetchAvailableAttendanceDates(); // ✅ Correct for HOD
  }

  Future<void> _loadYearData() async {
    try {
      _endYears = await firebaseService.fetchAvailableEndYears();
      for (String year in _endYears) {
        final data = await firebaseService.fetchYearAttendanceData(
          year,
          forDate: selectedDate, // ✅ pass the selected date
        );
        _yearDataCache[year] = data;
      }
    } catch (e) {
      print("Error loading year data: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildBody() {
    switch (selectedIndex) {
      case 0:
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
      case 1:
        return MentorsPage(firebaseService: firebaseService);

      case 2:
        return const AppLoginPage(); // will now display inside your DashboardPage
      case 3:
        return Center(
          child: Text(
            'Settings Page (Coming Soon)',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        );
      default:
        return Center(
          child: Text(
            'Dashboard',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        );
    }
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
                _buildTopBar(), // Always visible
                Expanded(
                  child: _buildBody(), // Dynamic body content
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the left sidebar with navigation items.
  // add this import at the top

  Widget _buildSidebar() {
    final items = [
      Icons.dashboard,
      Icons.person,
      Icons.app_registration_outlined,
      Icons.settings,
      Icons.logout,
    ];

    final labels = ['Dashboard', 'Mentors', 'App Login', 'Settings', 'Log Out'];

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
                            constraints: BoxConstraints(
                              minWidth: 300,
                              maxWidth: 400, // good for web dialogs
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
                                    children: [
                                      const Text(
                                        "Confirm Logout?",
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
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
                    FirebaseService()
                        .markDisposedOrLoggedOut(); // ✅ Prevent background fetches

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

  /// Builds the top navigation bar with welcome message and search.
  Widget _buildTopBar() {
    return Container(
      color: const Color(0xFF0746C5),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Welcome To HOD Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              Container(
                width: 250,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const TextField(
                  decoration: InputDecoration(
                    hintText: 'Search here',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.search, color: Colors.white),

              // 🔁 Refresh IconButton
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh to Today',
                onPressed: () async {
                  final cleanedYear = selectedYear?.split(' ').first.trim();
                  if (cleanedYear == null) return;

                  final DateTime today = DateTime.now();

                  debugPrint(
                    "🔁 Refreshing dashboard for today (${today.toIso8601String()})",
                  );

                  setState(() {
                    selectedDate = today;
                    _allowTodaySelection = true; // ✅ Always allow picking today
                    _isLoading = true;
                  });

                  // ✅ Optionally force refresh from Firestore (if caching used)
                  final freshData = await FirebaseService()
                      .fetchYearAttendanceData(cleanedYear, forceRefresh: true);

                  setState(() {
                    _yearDataCache[cleanedYear] = freshData;
                  });

                  // ✅ Always reload dashboard data for today
                  await _loadYearData(); // or _loadMentorData() depending on your logic

                  setState(() {
                    _isLoading = false;
                  });
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
                      // duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
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

        await _loadYearData(); // or _loadMentorData()
      }
    } catch (e) {
      debugPrint("❌ Error showing date picker: $e");
    }
  }

  /// Displays the branch-wise attendance tables and summaries.
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
                      DateFormat('dd/MM/yyyy').format(selectedDate),

                      totalStudents,
                      totalAttended,
                      percent,
                      _pickDate,
                    ),
                    ..._endYears.map((endYear) {
                      Color color;
                      if (endYear == _endYears.first) {
                        color = const Color(0xFF4CAF50); // Green for highest
                      } else if (_endYears.length > 1 &&
                          endYear == _endYears[1]) {
                        color = const Color(
                          0xFF42A5F5,
                        ); // Blue for second highest
                      } else {
                        color = const Color(0xFFFF4E8A); // Pink for others
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
                    }).toList(),
                  ],
                ),
              ),
    );
  }

  /// Displays the right-side container showing the attendance form.
  Widget _buildAttendanceForm() {
    if (selectedBranch == null) {
      return const Expanded(
        flex: 2,
        child: Center(child: Text("Select a Section to view attendance.")),
      );
    }

    final rawBranch = selectedBranch!;
    final branchCleaned = rawBranch.split(' ').first.trim(); // CSE-D
    final parts = branchCleaned.split('-');
    final department = parts[0];
    final section = parts[1];
    final rawYear = selectedYear ?? 'Unknown';
    final yearCleaned = rawYear.split(' ').first.trim(); // 2028

    debugPrint("🔎 Requested: $rawBranch → Cleaned: $branchCleaned");
    debugPrint("🧪 dept=$department | section=$section | endYear=$yearCleaned");

    // ✅ Just logs — these don’t affect state
    FirebaseFirestore.instance
        .collection('Branch')
        .doc(department)
        .collection(yearCleaned)
        .doc(section)
        .collection('students')
        .get()
        .then((snapshot) {
          debugPrint("📦 Found ${snapshot.docs.length} students in that path.");
        })
        .catchError((e) {
          debugPrint("🔥 ERROR reading students: $e");
        });

    // ✅ Only refresh the attended cache when section changes
    if (!FirebaseService.instance.isDisposedOrLoggedOut) {
      FirebaseService.instance
          .fetchYearAttendanceData(
            yearCleaned,
            forceRefresh: true,
            forDate: selectedDate, // ✅ Respect selected date
          )
          .then((freshData) {
            if (!mounted || FirebaseService.instance.isDisposedOrLoggedOut)
              return;

            setState(() {
              _yearDataCache[yearCleaned] = freshData;
            });
          });
    }

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

/// Widget to build the top summary bar
Widget buildSummaryHeader(
  String date,
  int totalStrength,
  int totalAttended,
  int percent,
  VoidCallback onDateTap, // 👈 Add this
) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0746C5), Color(0xFF0746C5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            // 👈 This makes date card clickable
            onTap: onDateTap,
            child: summaryCard(Icons.calendar_today, "Date", date),
          ),
        ),
        Expanded(
          child: summaryCard(
            Icons.group,
            "Total Strength",
            totalStrength.toString(),
          ),
        ),
        Expanded(
          child: summaryCard(
            Icons.check_circle,
            "Total Attended",
            totalAttended.toString(),
          ),
        ),
        Expanded(
          child: summaryCard(Icons.pie_chart, "Percentage", "$percent%"),
        ),
      ],
    ),
  );
}

/// A reusable cell widget for summary bar
Widget summaryCard(IconData icon, String title, String value) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
      ],
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 32),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Builds a branch-wise table for a given year group
Widget buildYearTable({
  required String title,
  required List<List<dynamic>> data,
  required int total,
  Color? color, // Optional solid color
  Gradient? gradient, // Optional gradient
  String? selectedBranch,
  String? selectedYear,
  void Function(String year, String branch)? onRowTap,
}) {
  return Container(
    margin: const EdgeInsets.only(top: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gradient == null ? color?.withOpacity(0.9) : null,
            gradient: gradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: Colors.white,
            ),
          ),
        ),

        // Table content with dynamic rows
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2.5),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2.5),
          },
          border: TableBorder.symmetric(
            inside: BorderSide(color: Colors.grey.shade600, width: 0.5),
          ),
          children: [
            // Table Header Row
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[1000]),
              children: [
                tableHeader("Branch"),
                tableHeader("Strength"),
                tableHeader("Attended"),
                tableHeader("Branch Wise %"),
              ],
            ),

            // Table Body Rows
            ...data.map((row) {
              final isSelected =
                  selectedBranch == row[0] &&
                  selectedYear == title.split(" ").first;

              final Color rowBgColor =
                  isSelected
                      ? (gradient?.colors.first ?? color ?? Colors.blue)
                      : Colors.white;

              final Color rowTextColor =
                  isSelected ? Colors.white : Colors.black87;

              return TableRow(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border:
                      isSelected
                          ? Border.all(color: rowBgColor, width: 2)
                          : null,
                ),
                children:
                    row.map((cell) {
                      return GestureDetector(
                        onTap: () {
                          if (onRowTap != null)
                            onRowTap(title.split(" ").first, row[0]);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 8,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? rowBgColor : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow:
                                  isSelected
                                      ? [
                                        BoxShadow(
                                          color: rowBgColor.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                      : [],
                            ),
                            child: Center(
                              child: Text(
                                cell.toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: rowTextColor,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              );
            }),
          ],
        ),

        // Footer
        // Footer with actual attended and percentage
        Builder(
          builder: (_) {
            final attended = data.fold<int>(
              0,
              (sum, row) =>
                  sum + (row[2] as int), // Column index 2 = present count
            );
            final percent = total > 0 ? ((attended / total) * 100).round() : 0;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: gradient,
                color: gradient == null ? color?.withOpacity(0.85) : null,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Text(
                "$title Total: $total   Attended: $attended   $percent%",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

/// Builds a styled header cell for tables
Widget tableHeader(String text) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.grey[200], // Light grey background
      borderRadius: BorderRadius.circular(6),
    ),
    child: Center(
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
  );
}
