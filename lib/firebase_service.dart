import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  Future<List<List<dynamic>>> fetchYearAttendanceData(String endYear) async {
    if (_isCacheValid && _yearDataCache.containsKey(endYear)) {
      print("✅ Returning cached year data for $endYear");
      return _yearDataCache[endYear]!;
    }

    try {
      final snapshot = await _firestore.collectionGroup('students').get();

      final todayDocId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final Map<String, List<Map<String, dynamic>>> sectionGroups = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['endYear'].toString() != endYear) continue;

        final department = data['department'] ?? 'CSE';
        final section = data['section'] ?? 'Unknown';
        final branch = "$department-${section.toUpperCase()}";
        final rollNo = data['rollNo'];

        sectionGroups.putIfAbsent(branch, () => []).add({
          'rollNo': rollNo,
          'department': department,
          'section': section,
        });
      }

      final List<List<dynamic>> result = [];

      for (var entry in sectionGroups.entries) {
        final branch = entry.key;
        final students = entry.value;
        int total = students.length;
        int attended = 0;

        for (var student in students) {
          final docRef = _firestore
              .collection('Branch')
              .doc(student['department'])
              .collection(endYear)
              .doc(student['section'])
              .collection('students')
              .doc(student['rollNo'])
              .collection('attendance')
              .doc(todayDocId);

          final attDoc = await docRef.get();

          if (attDoc.exists) {
            final attData = attDoc.data();
            if (attData != null && attData['status'] == 'present') {
              attended++;
            }
          }
        }

        final percent = total == 0 ? 0 : (attended / total) * 100;
        result.add([branch, total, attended, "${percent.toStringAsFixed(1)}%"]);
      }

      result.sort((a, b) => a[0].toString().compareTo(b[0].toString()));
      _yearDataCache[endYear] = result;
      _cacheDate = DateTime.now();

      print("✅ Final Data for $endYear: $result");
      return result;
    } catch (e) {
      print("❌ Error fetching year data for $endYear: $e");
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
