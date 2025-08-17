import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  static final FirebaseService instance = FirebaseService._internal();
  factory FirebaseService() => instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isDisposedOrLoggedOut = false;
  Future<List<DateTime>> fetchAvailableAttendanceDates() async {
    try {
      final snapshot = await _firestore.collectionGroup('attendance').get();

      final Set<String> uniqueDateIds = {};

      for (var doc in snapshot.docs) {
        final id = doc.id;
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(id)) {
          uniqueDateIds.add(id);
        }
      }

      final dates =
          uniqueDateIds.map((id) {
            return DateFormat('yyyy-MM-dd').parse(id);
          }).toList();

      dates.sort((a, b) => b.compareTo(a)); // latest first
      return dates;
    } catch (e) {
      print("❌ Error fetching attendance dates: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchStudentAttendance(
    String rollNo,
    DateTime start,
    DateTime end,
  ) async {
    final querySnapshot =
        await FirebaseFirestore.instance
            .collectionGroup("attendance") // adjust to your structure
            .where("rollNo", isEqualTo: rollNo)
            .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where("date", isLessThanOrEqualTo: Timestamp.fromDate(end))
            .orderBy("date", descending: true)
            .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }

  void markDisposedOrLoggedOut() {
    _isDisposedOrLoggedOut = true;
  }

  void resetState() {
    _isDisposedOrLoggedOut = false;
  }

  // Fetch roll numbers selected by any mentor for this batch-section
  Future<Set<String>> getGloballySelectedRollNos({
    required String batch,
    required String section,
  }) async {
    final docId = '$batch-$section';
    final mentorsSnapshot =
        await FirebaseFirestore.instance.collection('mentors').get();
    final Set<String> allSelected = {};

    for (final mentorDoc in mentorsSnapshot.docs) {
      final userId = mentorDoc.data()['userId'];
      if (userId == null) continue;
      final assignedStudentsRef = FirebaseFirestore.instance
          .collection('mentors')
          .doc(userId)
          .collection('assignedStudents')
          .doc(docId);
      final sectionDoc = await assignedStudentsRef.get();
      if (sectionDoc.exists && sectionDoc.data() != null) {
        final rollNos = List<String>.from(
          sectionDoc.data()!['selectedRollNos'] ?? [],
        );
        allSelected.addAll(rollNos.map((e) => e.trim().toUpperCase()));
      }
    }
    return allSelected;
  }

  bool get isDisposedOrLoggedOut => _isDisposedOrLoggedOut;

  /// ====== Added Caching ======
  final Map<String, List<List<dynamic>>> _yearDataCache = {};
  List<String>? _endYearsCache;
  List<int>? _overallSummaryCache;
  DateTime _cacheDate = DateTime.now();

  /// Check if cache is valid for today
  bool get _isCacheValid =>
      _cacheDate.year == DateTime.now().year &&
      _cacheDate.month == DateTime.now().month &&
      _cacheDate.day == DateTime.now().day;

  Future<List<List<dynamic>>> fetchYearAttendanceData(
    String endYear, {
    bool forceRefresh = false,
    DateTime? forDate, // ✅ Optional date for past/future view
    String? mentorUserId, // ✅ Optional for mentor filter
  }) async {
    final DateTime dateToUse = forDate ?? DateTime.now();
    final String docId = DateFormat('yyyy-MM-dd').format(dateToUse);

    final bool isToday =
        dateToUse.year == DateTime.now().year &&
        dateToUse.month == DateTime.now().month &&
        dateToUse.day == DateTime.now().day;

    // ✅ Only cache for HOD (i.e., if mentorUserId is null)
    if (!forceRefresh &&
        isToday &&
        _isCacheValid &&
        _yearDataCache.containsKey(endYear) &&
        mentorUserId == null) {
      print("✅ Returning cached year data for $endYear");
      return _yearDataCache[endYear]!;
    }

    try {
      final querySnapshot = await _firestore.collectionGroup('students').get();
      final Map<String, List<Map<String, dynamic>>> sectionGroups = {};

      // ✅ Cache to avoid multiple Firestore reads per section
      final Map<String, List<String>> mentorRollNoMap = {};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        if (data['endYear']?.toString() != endYear) continue;
        if (data['rollNo'] == null ||
            data['department'] == null ||
            data['section'] == null)
          continue;

        final department = data['department'].toString();
        final section = data['section'].toString();
        final rollNo = data['rollNo'].toString();
        final branch = "$department-${section.toUpperCase()}";

        // ✅ Mentor filtering
        if (mentorUserId != null) {
          final cacheKey = '$endYear-${section.toUpperCase()}';
          if (!mentorRollNoMap.containsKey(cacheKey)) {
            final selectedRollNos = await getMentorSelectedRollNos(
              mentorUserId: mentorUserId,
              endYear: endYear,
              section: section,
            );
            mentorRollNoMap[cacheKey] = selectedRollNos;
          }

          final selectedList = mentorRollNoMap[cacheKey] ?? [];

          // ✅ If no students selected → skip filtering now, we'll add empty section later
          if (selectedList.isNotEmpty && !selectedList.contains(rollNo)) {
            continue;
          }
        }

        sectionGroups.putIfAbsent(branch, () => []).add({
          'rollNo': rollNo,
          'department': department,
          'section': section,
        });
      }

      // ✅ Ensure all assigned sections exist even if no students
      if (mentorUserId != null) {
        final mentorDoc =
            await _firestore.collection('mentors').doc(mentorUserId).get();
        final assignedList = (mentorDoc.data()?['assigned'] ?? []) as List;
        for (var sec in assignedList) {
          final branchKey =
              "${sec['department']}-${sec['section'].toString().toUpperCase()}";
          sectionGroups.putIfAbsent(branchKey, () => []);
        }
      }

      final List<List<dynamic>> result = [];

      for (final entry in sectionGroups.entries) {
        final branch = entry.key;
        final students = entry.value;
        int total = students.length;
        int attended = 0;

        for (final student in students) {
          if (_isDisposedOrLoggedOut) {
            print("⚠️ Operation cancelled: Already logged out");
            return _yearDataCache[endYear] ?? [];
          }

          try {
            final department = student['department'];
            final section = student['section'];
            final rollNo = student['rollNo'];

            final studentPath = _firestore
                .collection('Branch')
                .doc(department)
                .collection(endYear)
                .doc(section)
                .collection('students')
                .doc(rollNo)
                .collection('attendance')
                .doc(docId);

            final snapshot = await studentPath.get();
            if (snapshot.exists) {
              final data = snapshot.data();
              bool counted = false;

              if (data != null) {
                if (data['status'] == 'present') {
                  attended++;
                  counted = true;
                } else if (data['inTime'] != null && data['outTime'] != null) {
                  try {
                    final inTime = (data['inTime'] as Timestamp).toDate();
                    final outTime = (data['outTime'] as Timestamp).toDate();
                    final duration = outTime.difference(inTime).inHours;

                    if (duration >= 5) {
                      attended++;
                      counted = true;
                    }
                  } catch (e) {
                    debugPrint(
                      "⚠️ Failed to calculate duration for $rollNo: $e",
                    );
                  }
                }
              }

              if (!counted) {
                debugPrint("⛔ Not counted as present: $rollNo");
              }
            }
          } catch (e) {
            debugPrint(
              "❌ Error in attendance fetch for ${student['rollNo']}: $e",
            );
          }
        }

        final percent = total > 0 ? (attended / total) * 100 : 0.0;
        result.add([branch, total, attended, "${percent.toStringAsFixed(1)}%"]);
      }

      result.sort((a, b) => a[0].compareTo(b[0]));

      if (isToday && mentorUserId == null) {
        _yearDataCache[endYear] = result;
        _cacheDate = DateTime.now();
      }

      print("✅ Attendance summary for $endYear on $docId: $result");
      return result;
    } catch (e, stackTrace) {
      print("❌ Failed to fetch attendance data for $endYear: $e");
      print(stackTrace);
      return [];
    }
  }

  Future<List<String>> fetchAvailableEndYears() async {
    if (_isCacheValid && _endYearsCache != null) {
      print("✅ Returning cached end years");
      return _endYearsCache!;
    }

    try {
      final snapshot = await _firestore.collectionGroup('students').get();
      final Set<String> endYears = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('endYear')) {
          endYears.add(data['endYear'].toString());
        }
      }
      final sortedList =
          endYears.toList()..sort((a, b) => b.compareTo(a)); // descending
      _endYearsCache = sortedList;
      _cacheDate = DateTime.now();

      print("Fetched endYears (descending): $sortedList");
      return sortedList;
    } catch (e) {
      print("Error fetching endYears: $e");
      return [];
    }
  }

  Future<List<int>> fetchOverallSummary() async {
    if (_isCacheValid && _overallSummaryCache != null) {
      print("✅ Returning cached overall summary");
      return _overallSummaryCache!;
    }

    try {
      final querySnapshot = await _firestore.collectionGroup('students').get();
      int total = querySnapshot.docs.length;
      int attended = 0;

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['inTime'] != null) {
          Timestamp ts = data['inTime'];
          DateTime dt = ts.toDate();
          if (isToday(dt)) {
            attended++;
          }
        }
      }
      _overallSummaryCache = [total, attended];
      _cacheDate = DateTime.now();

      return [total, attended];
    } catch (e) {
      print("Error fetching overall summary: $e");
      return [0, 0];
    }
  }

  Future<bool> validateHodLogin(String username, String password) async {
    final snapshot =
        await _firestore
            .collection('hod_logins')
            .where('username', isEqualTo: username.trim())
            .where('password', isEqualTo: password.trim())
            .where('isActive', isEqualTo: true)
            .get();

    debugPrint(
      "HOD login attempt for $username returned ${snapshot.docs.length} documents.",
    );

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> validateMentorLogin(String username, String password) async {
    final snapshot =
        await _firestore
            .collection('mentors')
            .where('username', isEqualTo: username)
            .where('password', isEqualTo: password)
            .where('isActive', isEqualTo: true)
            .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getMentorDocument(
    String userId,
    String password,
  ) async {
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('mentors')
              .where('userId', isEqualTo: userId)
              .where('password', isEqualTo: password)
              .where('isActive', isEqualTo: true)
              .limit(1)
              .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
      return null;
    } catch (e) {
      debugPrint("Error fetching mentor document: $e");
      return null;
    }
  }

  Future<void> saveMentorSelectedStudents({
    required String mentorUserId,
    required String endYear,
    required String section,
    required String department,
    required List<String> selectedRollNos,
  }) async {
    final docId = '$endYear-$section';

    await _firestore
        .collection('mentors')
        .doc(mentorUserId)
        .collection('assignedStudents')
        .doc(docId)
        .set({
          'endYear': endYear,
          'section': section,
          'department': department,
          'selectedRollNos': selectedRollNos,
          'updatedAt': DateTime.now(),
        });
  }

  Future<List<String>> getMentorSelectedRollNos({
    required String mentorUserId,
    required String endYear,
    required String section,
  }) async {
    try {
      final docId = '$endYear-$section';
      final snapshot =
          await _firestore
              .collection('mentors')
              .doc(mentorUserId)
              .collection('assignedStudents')
              .doc(docId)
              .get();

      if (snapshot.exists && snapshot.data()?['selectedRollNos'] != null) {
        return List<String>.from(snapshot.data()!['selectedRollNos']);
      }
    } catch (e) {
      debugPrint("❌ Error fetching selected rollNos for mentor: $e");
    }
    return [];
  }

  /// Helper to determine year group from end year
  String getYearGroup(String endYear) {
    int year = int.tryParse(endYear) ?? 0;
    int currentYear = DateTime.now().year;
    int diff = year - currentYear;
    if (diff == 3) return "I BTECH";
    if (diff == 2) return "II BTECH";
    if (diff == 1) return "III BTECH";
    if (diff == 0) return "IV BTECH";
    return "Unknown";
  }

  bool isToday(DateTime date) {
    final now = DateTime.now();
    return now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
  }
}

Future<void> updateAppLogin({
  required String docId,
  required String username,
  required String password,
}) async {
  await FirebaseFirestore.instance.collection('app_logins').doc(docId).update({
    'username': username.trim(),
    'password': password.trim(),
    'updatedAt': DateTime.now(),
  });
}
