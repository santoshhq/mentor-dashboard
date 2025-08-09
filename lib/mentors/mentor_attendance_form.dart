import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

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
        widget.onCacheUpdate?.call(data);
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

    final parts = branchName.split('-');
    final department = parts[0];
    final section = parts.length > 1 ? parts[1] : '';
    final batch = DateTime.now().year.toString();

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
        if (attendanceData?['inTime'] != null) {
          inTime = (attendanceData!['inTime'] as Timestamp).toDate();
        }
        if (attendanceData?['outTime'] != null) {
          outTime = (attendanceData!['outTime'] as Timestamp).toDate();
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

      return getStatus(b).compareTo(getStatus(a));
    });

    return students;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color _getBorderColor(Map<String, dynamic> s) {
    if (!s['scannedToday']) return Colors.red;
    if (s['partialScan']) return Colors.orange;
    if (s['hours'] < 5) return Colors.purple;
    return Colors.green;
  }

  String _getStatusLabel(Map<String, dynamic> s) {
    if (!s['scannedToday']) return "Absent";
    if (s['partialScan']) return "Partial";
    if (s['hours'] < 5) return "Short Hours";
    return "Present";
  }

  IconData _getStatusIcon(Map<String, dynamic> s) {
    if (!s['scannedToday']) return Icons.cancel;
    if (s['partialScan']) return Icons.warning_amber_rounded;
    if (s['hours'] < 5) return Icons.timer_off;
    return Icons.check_circle;
  }

  Color _getStatusColor(Map<String, dynamic> s) {
    if (!s['scannedToday']) return Colors.red;
    if (s['partialScan']) return Colors.orange;
    if (s['hours'] < 5) return Colors.purple;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0746C5), Color(0xFF052F80)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.assignment, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Attendance - ${widget.branchName}",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                DateFormat('dd MMM yyyy').format(DateTime.now()),
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Attendance List
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
                padding: const EdgeInsets.only(top: 4),
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final s = students[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: _getBorderColor(s), width: 1.5),
                    ),
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: CircleAvatar(
                        backgroundColor: _getStatusColor(s).withOpacity(0.15),
                        child: Icon(
                          _getStatusIcon(s),
                          color: _getStatusColor(s),
                        ),
                      ),
                      title: Text(
                        "${s['rollNo']} - ${s['name']}",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.login, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                s['inTime'] != null
                                    ? DateFormat('hh:mm a').format(s['inTime'])
                                    : '--',
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.logout, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              Text(
                                s['outTime'] != null
                                    ? DateFormat('hh:mm a').format(s['outTime'])
                                    : '--',
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              const Spacer(),
                              Text(
                                "${s['hours']}h",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(
                          _getStatusLabel(s),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: _getStatusColor(s),
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
