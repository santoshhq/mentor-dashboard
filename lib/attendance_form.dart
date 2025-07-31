import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AttendanceForm extends StatefulWidget {
  final String branchName;
  final String endYear;
  final List<Map<String, dynamic>>? cachedData;
  final void Function(List<Map<String, dynamic>>)? onCacheUpdate;

  const AttendanceForm({
    super.key,
    required this.branchName,
    required this.endYear,
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
    _studentsFuture = fetchStudentsForToday(
      widget.branchName,
      widget.endYear,
    ).then((data) {
      widget.onCacheUpdate?.call(data);
      return data;
    });
  }

  Future<List<Map<String, dynamic>>> fetchStudentsForToday(
    String branchName,
    String endYear,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final parts = branchName.split('-');
    final department = parts[0].trim();
    final section = parts[1].trim().toUpperCase();
    final todayDocId = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final studentSnapshot =
        await firestore
            .collection('Branch')
            .doc(department)
            .collection(endYear)
            .doc(section)
            .collection('students')
            .get();

    List<Map<String, dynamic>> students = [];

    for (var doc in studentSnapshot.docs) {
      final studentData = doc.data();
      final rollNo = doc.id;
      final name = studentData['name'] ?? 'Unknown';

      final attendanceDoc =
          await firestore
              .collection('Branch')
              .doc(department)
              .collection(endYear)
              .doc(section)
              .collection('students')
              .doc(rollNo)
              .collection('attendance')
              .doc(todayDocId)
              .get();

      List<DateTime> scans = [];
      if (attendanceDoc.exists) {
        final attData = attendanceDoc.data();
        if (attData != null && attData['scans'] != null) {
          for (var ts in attData['scans']) {
            if (ts is Timestamp) {
              scans.add(ts.toDate());
            }
          }
          scans.sort(); // sort chronologically
        }
      }

      DateTime? inTime;
      DateTime? outTime;
      int duration = 0;
      String status = 'noScan';

      if (scans.length >= 2) {
        inTime = scans.first;
        outTime = scans.last;
        duration = outTime.difference(inTime).inHours;

        if (duration >= 5) {
          status = 'present';
        } else {
          status = 'less_than_5h';
        }
      } else if (scans.length == 1) {
        inTime = scans.first;
        status = 'partial';
      }

      students.add({
        'name': name,
        'rollNo': rollNo,
        'inTime': inTime,
        'outTime': outTime,
        'hours': duration,
        'status': status,
        'scanCount': scans.length,
      });
    }

    // Sort by scan status
    const sortPriority = {
      'noScan': 0,
      'partial': 1,
      'less_than_5h': 2,
      'present': 3,
    };

    students.sort(
      (a, b) =>
          sortPriority[a['status']]!.compareTo(sortPriority[b['status']]!),
    );
    return students;
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
                return const Center(child: Text("Error loading students"));
              }

              final students = snapshot.data ?? [];

              if (students.isEmpty) {
                return const Center(child: Text("No data found"));
              }

              return ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final s = students[index];

                  Color borderColor;
                  String statusLabel;

                  switch (s['status']) {
                    case 'noScan':
                      borderColor = Colors.grey;
                      statusLabel = '❌ Not Scanned';
                      break;
                    case 'partial':
                      borderColor = Colors.orange;
                      statusLabel = '⚠️ Only One Scan';
                      break;
                    case 'less_than_5h':
                      borderColor = Colors.red;
                      statusLabel = '⛔ < 5 Hours';
                      break;
                    case 'present':
                    default:
                      borderColor = Colors.green;
                      statusLabel = '✅ Present';
                      break;
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${s['rollNo']} - ${s['name']}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text("Status: $statusLabel"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "IN: ${s['inTime'] != null ? DateFormat('hh:mm a').format(s['inTime']) : '--'}",
                            ),
                            Text(
                              "OUT: ${s['outTime'] != null ? DateFormat('hh:mm a').format(s['outTime']) : '--'}",
                            ),
                            Text("Hours: ${s['hours']}h"),
                          ],
                        ),
                      ],
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
