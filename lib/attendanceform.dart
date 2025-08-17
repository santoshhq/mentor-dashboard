import 'dart:convert'; // For utf8.encode
import 'dart:html' as html; // For Flutter Web download
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hod_web_dashboard/firebase_service.dart';
import 'package:intl/intl.dart';

class AttendanceForm extends StatefulWidget {
  final String branchName;
  final String endYear;
  final DateTime selectedDate;
  final List<Map<String, dynamic>>? cachedData;
  final void Function(List<Map<String, dynamic>>)? onCacheUpdate;
  final String? mentorUserId; // ✅ NEW

  const AttendanceForm({
    super.key,
    required this.branchName,
    required this.endYear,
    required this.selectedDate,
    this.cachedData,
    this.onCacheUpdate,
    this.mentorUserId, // ✅ NEW
  });

  @override
  State<AttendanceForm> createState() => _AttendanceFormState();
}

class _AttendanceFormState extends State<AttendanceForm> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  List<Map<String, dynamic>> _lastFetchedStudents = [];

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  @override
  void didUpdateWidget(covariant AttendanceForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.branchName != oldWidget.branchName ||
        widget.endYear != oldWidget.endYear) {
      _loadStudentData();
    }
  }

  void _loadStudentData() {
    _studentsFuture = fetchStudentsForToday(
      widget.branchName,
      widget.endYear,
      selectedDate: widget.selectedDate,
      mentorUserId: widget.mentorUserId, // ✅ Pass if exists
    ).then((data) {
      _lastFetchedStudents = data; // Save for CSV export
      widget.onCacheUpdate?.call(data);
      return data;
    });

    setState(() {});
  }

  Future<List<Map<String, dynamic>>> fetchStudentsForToday(
    String branchName,
    String endYear, {
    DateTime? selectedDate,
    String? mentorUserId, // ✅ Optional new param
  }) async {
    final firestore = FirebaseFirestore.instance;
    final cleanBranch = branchName.split(' ').first;
    final parts = cleanBranch.split('-');
    final department = parts[0].trim();
    final section = parts[1].trim().toUpperCase();

    final dateToUse = selectedDate ?? DateTime.now();
    final docId = DateFormat('yyyy-MM-dd').format(dateToUse);

    final now = DateTime.now();
    final isToday =
        now.year == dateToUse.year &&
        now.month == dateToUse.month &&
        now.day == dateToUse.day;

    final isBefore1230 = now.isBefore(
      DateTime(now.year, now.month, now.day, 12, 30),
    );

    print("📅 Date: $docId | 🕒 isBefore12:30 = $isBefore1230");
    print("🔍 Fetching students for: Branch/$department/$endYear/$section");

    // ✅ If mentorUserId is provided, fetch allowed rollNos from Firestore
    List<String> allowedRollNos = [];
    if (mentorUserId != null) {
      final docRef = firestore
          .collection('mentors')
          .doc(mentorUserId)
          .collection('assignedStudents')
          .doc('$endYear-$section');

      final docSnap = await docRef.get();
      if (docSnap.exists && docSnap.data()?['selectedRollNos'] is List) {
        allowedRollNos = List<String>.from(docSnap['selectedRollNos']);
        print("✅ Mentor $mentorUserId allowed rollNos: $allowedRollNos");
      } else {
        print(
          "⚠️ No allowed rollNos found for mentor $mentorUserId ($endYear-$section)",
        );
      }
    }

    final studentSnapshot =
        await firestore
            .collection('Branch')
            .doc(department)
            .collection(endYear)
            .doc(section)
            .collection('students')
            .get();

    print(
      "📥 Fetched ${studentSnapshot.docs.length} students for $department-$section ($endYear)",
    );

    List<Map<String, dynamic>> students = [];

    for (var doc in studentSnapshot.docs) {
      final studentData = doc.data();
      final rollNo = doc.id;

      // ✅ Skip if mentorUserId is set and rollNo not in assigned list
      if (mentorUserId != null && !allowedRollNos.contains(rollNo)) {
        continue;
      }

      final name = studentData['name'] ?? 'Unknown';
      print("👤 Checking student: $name [$rollNo]");

      final attendanceDoc =
          await firestore
              .collection('Branch')
              .doc(department)
              .collection(endYear)
              .doc(section)
              .collection('students')
              .doc(rollNo)
              .collection('attendance')
              .doc(docId)
              .get();

      DateTime? inTime;
      DateTime? outTime;
      String? statusFromDb;
      int duration = 0;
      String status = 'noScan';

      if (attendanceDoc.exists) {
        final attData = attendanceDoc.data();
        print("📄 Attendance doc found: $attData");

        if (attData != null) {
          try {
            if (attData['inTime'] != null) {
              final ts = attData['inTime'];
              inTime =
                  ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
            }
          } catch (e) {
            print("❌ Failed to parse inTime for $rollNo: $e");
          }

          try {
            if (attData['outTime'] != null) {
              final ts = attData['outTime'];
              outTime =
                  ts is Timestamp ? ts.toDate() : DateTime.parse(ts.toString());
            }
          } catch (e) {
            print("❌ Failed to parse outTime for $rollNo: $e");
          }

          statusFromDb = attData['status'];
        }

        if (inTime != null && outTime != null) {
          duration = outTime.difference(inTime).inHours;
          if (duration >= 5) {
            status = 'present';
            if (statusFromDb != 'present' && isToday) {
              try {
                await firestore
                    .collection('Branch')
                    .doc(department)
                    .collection(endYear)
                    .doc(section)
                    .collection('students')
                    .doc(rollNo)
                    .collection('attendance')
                    .doc(docId)
                    .set({'status': 'present'}, SetOptions(merge: true));

                print("✅ Firestore updated with status: present for $rollNo");

                await FirebaseService().fetchYearAttendanceData(
                  endYear,
                  forceRefresh: true,
                );
              } catch (e) {
                print("❌ Failed to update status for $rollNo: $e");
              }
            }
          } else {
            status = 'less_than_5h';
          }
        } else if (inTime != null || outTime != null) {
          status = 'partial';
        }

        print("✅ Computed: inTime=$inTime, outTime=$outTime, status=$status");
      } else {
        print("❌ No attendance found for $name [$rollNo]");
      }

      if (isToday && isBefore1230) {
        if (inTime != null && outTime == null) {
          final cutoff = DateTime(
            inTime.year,
            inTime.month,
            inTime.day,
            12,
            30,
          );
          if (inTime.isBefore(cutoff)) {
            students.add({
              'name': name,
              'rollNo': rollNo,
              'inTime': inTime,
              'outTime': outTime,
              'hours': duration,
              'status': 'in_morning_only',
            });
            continue;
          }
        }
      }

      students.add({
        'name': name,
        'rollNo': rollNo,
        'inTime': inTime,
        'outTime': outTime,
        'hours': duration,
        'status': status,
      });
    }

    if (!isBefore1230 || !isToday) {
      const priority = {
        'noScan': 0,
        'partial': 1,
        'less_than_5h': 2,
        'present': 3,
      };
      students.sort((a, b) {
        return (priority[a['status']] ?? 99).compareTo(
          priority[b['status']] ?? 99,
        );
      });
    }

    print("📊 Final student list count: ${students.length}");
    return students;
  }

  void _downloadCSV() {
    final filtered =
        _lastFetchedStudents
            .where(
              (s) =>
                  s['status'] == 'noScan' ||
                  s['status'] == 'partial' ||
                  s['status'] == 'less_than_5h',
            )
            .toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No students to download')));
      return;
    }

    final rows = [
      ['Roll No', 'Name', 'Status'],
    ];

    for (var s in filtered) {
      rows.add([s['rollNo'], s['name'], s['status']]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final bytes = utf8.encode(csvData);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor =
        html.AnchorElement(href: url)
          ..setAttribute(
            "download",
            "absent_students_${widget.branchName}_${widget.selectedDate.toIso8601String()}.csv",
          )
          ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Attendance Sheet - ${widget.branchName}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            IconButton(
              icon: const Icon(
                Icons.download,
                color: Color.fromARGB(137, 16, 16, 16),
              ),
              tooltip: "Download",
              onPressed: _downloadCSV,
            ),
          ],
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
                    case 'present':
                      borderColor = Colors.blueAccent;
                      statusLabel = '✅ Present (5+ Hours)';
                      break;
                    case 'in_morning_only':
                      borderColor = Colors.green;
                      statusLabel = '🟢 IN Scanned (Morning)';
                      break;
                    case 'noScan':
                      borderColor = Colors.grey;
                      statusLabel = '❌ Not Scanned(Absent)';
                      break;
                    case 'partial':
                      borderColor = Colors.orange;
                      statusLabel = '⚠️ Only One Scan';
                      break;
                    case 'less_than_5h':
                      borderColor = Colors.red;
                      statusLabel = '⛔ Less than 5 Hours';
                      break;
                    default:
                      borderColor = Colors.black45;
                      statusLabel = 'Unknown';
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
