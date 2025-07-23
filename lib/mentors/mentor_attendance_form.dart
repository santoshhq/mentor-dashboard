import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AttendanceForm extends StatefulWidget {
  final String branchName;
  final List<Map<String, dynamic>>? cachedData;
  final void Function(List<Map<String, dynamic>>)? onCacheUpdate;

  const AttendanceForm({
    super.key,
    required this.branchName,
    this.cachedData,
    this.onCacheUpdate,
  });

  @override
  State<AttendanceForm> createState() => _AttendanceFormState();
}

class _AttendanceFormState extends State<AttendanceForm> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;

  @override
  void initState() {
    super.initState();
    if (widget.cachedData != null) {
      _studentsFuture = Future.value(widget.cachedData);
    } else {
      _studentsFuture = fetchStudentsForToday(widget.branchName).then((data) {
        if (widget.onCacheUpdate != null) {
          widget.onCacheUpdate!(data);
        }
        return data;
      });
    }
  }

  Future<List<Map<String, dynamic>>> fetchStudentsForToday(
    String branchName,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    // Extract batch and section from branchName (e.g., CSE-A => batch/year is dynamic in this structure)
    final parts = branchName.split('-');
    final department = parts[0];
    final section = parts.length > 1 ? parts[1] : '';
    final batch = DateTime.now().year.toString(); // or derive from mentor data

    final path = 'Branch/$department/$batch/$section/students';
    final studentsSnapshot = await firestore.collection(path).get();

    final List<Map<String, dynamic>> students = [];

    for (final doc in studentsSnapshot.docs) {
      final data = doc.data();
      final rollNo = data['rollNo'] ?? '';
      final name = data['name'] ?? 'Unknown';

      final attendanceRef = firestore.doc('$path/$rollNo/attendance/$today');
      final attendanceSnapshot = await attendanceRef.get();

      DateTime? inTime;
      DateTime? outTime;

      if (attendanceSnapshot.exists) {
        final attendanceData = attendanceSnapshot.data();
        if (attendanceData != null && attendanceData['inTime'] != null) {
          inTime = (attendanceData['inTime'] as Timestamp).toDate();
        }
        if (attendanceData != null && attendanceData['outTime'] != null) {
          outTime = (attendanceData['outTime'] as Timestamp).toDate();
        }
      }

      final bool scannedToday =
          (inTime != null && _isSameDay(inTime, now)) ||
          (outTime != null && _isSameDay(outTime, now));

      Duration duration = Duration.zero;
      if (inTime != null && outTime != null) {
        duration = outTime.difference(inTime);
      }

      students.add({
        'name': name,
        'rollNo': rollNo,
        'inTime': inTime,
        'outTime': outTime,
        'hours': duration.inHours,
        'scannedToday': scannedToday,
        'partialScan': (inTime == null) != (outTime == null),
      });
    }

    students.sort((a, b) {
      int getStatus(Map<String, dynamic> s) {
        if (!s['scannedToday']) return 0;
        if (s['partialScan']) return 1;
        if (s['hours'] < 5) return 2;
        return 3;
      }

      return getStatus(a).compareTo(getStatus(b));
    });

    return students;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Attendance Sheet - ${widget.branchName}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const Divider(),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _studentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error loading students"));
              }
              final students = snapshot.data ?? [];

              if (students.isEmpty) {
                return const Center(
                  child: Text("No data to display (Holiday or no scans)."),
                );
              }

              return ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final s = students[index];
                  final redHighlight =
                      !s['scannedToday'] ||
                      s['partialScan'] ||
                      (s['hours'] < 5 && s['hours'] > 0);

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: redHighlight ? Colors.red : Colors.grey.shade300,
                        width: redHighlight ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text(s['name']),
                      subtitle: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Roll No: ${s['rollNo']}"),
                          Text(
                            "IN: ${s['inTime'] != null ? DateFormat('hh:mm a').format(s['inTime']) : '--'}",
                          ),
                          Text(
                            "OUT: ${s['outTime'] != null ? DateFormat('hh:mm a').format(s['outTime']) : '--'}",
                          ),
                          Text("Hours: ${s['hours']}h"),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
