import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'attendanceform.dart';

class HodStudentAttendanceDialog extends StatefulWidget {
  final String rollNo;
  const HodStudentAttendanceDialog({Key? key, required this.rollNo})
    : super(key: key);

  @override
  State<HodStudentAttendanceDialog> createState() =>
      _HodStudentAttendanceDialogState();
}

class _HodStudentAttendanceDialogState
    extends State<HodStudentAttendanceDialog> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _loading = true;
  String _studentName = "";

  String _department = "";
  String _section = "";
  String _endYear = "";

  List<Map<String, dynamic>> _attendanceRecords = [];
  int _presentCount = 0;
  int _absentCount = 0;
  int _workingDays = 0;
  String _currentFilter = "thisMonth";

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData(filter: _currentFilter);
  }

  bool isLateIn(String inTime) {
    try {
      DateTime parsedIn = DateFormat('hh:mm a').parse(inTime);
      DateTime threshold = DateFormat('hh:mm a').parse('09:20 AM');
      return parsedIn.isAfter(threshold);
    } catch (_) {
      return false;
    }
  }

  // Final name length limit is 28
  int nameLimit = 28;

  String truncateName(String name) {
    if (name.length <= nameLimit) return name;
    return name.substring(0, nameLimit) + "......";
  }

  // Fetch student details
  Future<Map<String, dynamic>?> _fetchStudentDetails(String rollNo) async {
    final query =
        await FirebaseFirestore.instance
            .collectionGroup('students')
            .where('rollNo', isEqualTo: rollNo)
            .limit(1)
            .get();

    if (query.docs.isEmpty) return null;
    return query.docs.first.data();
  }

  // Build dropdown items dynamically based on current date
  List<DropdownMenuItem<String>> _buildMonthFilterItems() {
    DateTime now = DateTime.now();
    DateTime lastMonth = DateTime(now.year, now.month - 1, 1);
    DateTime prevMonth = DateTime(now.year, now.month - 2, 1);

    String currentMonthName = DateFormat('MMMM').format(now);
    String lastMonthName = DateFormat('MMMM').format(lastMonth);
    String prevMonthName = DateFormat('MMMM').format(prevMonth);

    return [
      DropdownMenuItem(
        value: "thisMonth",
        child: Text("This Month ($currentMonthName)"),
      ),
      DropdownMenuItem(
        value: "lastMonth",
        child: Text("Last Month ($lastMonthName)"),
      ),
      DropdownMenuItem(value: "prevMonth", child: Text("$prevMonthName")),
    ];
  }

  // Fetch attendance data based on selected month
  Future _fetchAttendanceData({required String filter}) async {
    setState(() {
      _loading = true;
      _attendanceRecords.clear();
    });

    DateTime now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    if (filter == "thisMonth") {
      startDate = DateTime(now.year, now.month, 1);
    } else if (filter == "lastMonth") {
      DateTime lastMonth = DateTime(now.year, now.month - 1, 1);
      startDate = lastMonth;
      endDate = DateTime(now.year, now.month, 0);
    } else if (filter == "prevMonth") {
      DateTime prevMonth = DateTime(now.year, now.month - 2, 1);
      startDate = prevMonth;
      endDate = DateTime(now.year, now.month - 1, 0);
    } else {
      startDate = DateTime(now.year, now.month, 1);
    }

    try {
      // 1️⃣ Fetch student doc
      final studentQuery =
          await FirebaseFirestore.instance
              .collectionGroup('students')
              .where('rollNo', isEqualTo: widget.rollNo)
              .limit(1)
              .get();

      if (studentQuery.docs.isEmpty) {
        setState(() {
          _studentName = widget.rollNo;
          _department = "";
          _section = "";
          _endYear = "";
          _loading = false;
        });
        // 👇 Show snackbar at bottom if not found
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Student not found')));
        });
        return;
      }

      final studentDoc = studentQuery.docs.first;
      _studentName = studentDoc['name'] ?? widget.rollNo;
      _department = studentDoc['department'] ?? "";
      _section = studentDoc['section'] ?? "";
      _endYear = studentDoc['endYear']?.toString() ?? "";

      // 2️⃣ Fetch attendance docs
      final attendanceSnap =
          await studentDoc.reference.collection('attendance').get();

      List<Map<String, dynamic>> records = [];
      int presentCount = 0;
      for (var doc in attendanceSnap.docs) {
        try {
          DateTime date = DateTime.parse(doc.id);
          if (date.isBefore(startDate) || date.isAfter(endDate)) continue;
          var data = doc.data();
          DateTime? inTime;
          DateTime? outTime;

          // Convert to DateTime if needed
          if (data['inTime'] != null) {
            inTime =
                data['inTime'] is Timestamp
                    ? (data['inTime'] as Timestamp).toDate()
                    : DateTime.tryParse(data['inTime'].toString());
          }
          if (data['outTime'] != null) {
            outTime =
                data['outTime'] is Timestamp
                    ? (data['outTime'] as Timestamp).toDate()
                    : DateTime.tryParse(data['outTime'].toString());
          }

          String durationStr = "NA";
          bool isPresent = false;
          if (inTime != null && outTime != null) {
            final duration = outTime.difference(inTime);
            durationStr =
                "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
            if (duration.inHours >= 5) {
              isPresent = true;
            }
          }

          if (isPresent) {
            presentCount++;
          }

          records.add({
            'date': date,
            'present': isPresent,
            'inTime':
                inTime != null ? DateFormat('hh:mm a').format(inTime) : '--',
            'outTime':
                outTime != null ? DateFormat('hh:mm a').format(outTime) : '--',
            'duration': durationStr,
          });
        } catch (e) {
          debugPrint("Error parsing record ${doc.id}: $e");
        }
      }

      // Sort newest first
      records.sort((a, b) => b['date'].compareTo(a['date']));
      setState(() {
        _attendanceRecords = records;
        _workingDays = records.length;
        _presentCount = presentCount;
        _absentCount = _workingDays - _presentCount;
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching attendance: $e");
      setState(() => _loading = false);
    }
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.all(30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        height: 600,
        padding: EdgeInsets.all(24),
        child:
            _loading
                ? Center(child: CircularProgressIndicator())
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person),
                            SizedBox(width: 8),
                            Text(
                              "Student Attendance Data",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            DropdownButton<String>(
                              value: _currentFilter,
                              items: _buildMonthFilterItems(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _currentFilter = value);
                                  _fetchAttendanceData(filter: value);
                                }
                              },
                            ),
                            SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () => Navigator.pop(context),
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: 14),

                    // Student Details Row (modern layout)
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFFF7F9FC),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.08),
                            blurRadius: 2,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.blueAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Name: ${truncateName(_studentName)}",
                            style: TextStyle(fontSize: 14),
                          ),

                          Spacer(),
                          Icon(
                            Icons.school,
                            size: 18,
                            color: Colors.purpleAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Section: $_department-$_section",
                            style: TextStyle(fontSize: 15),
                          ),
                          Spacer(),
                          Icon(
                            Icons.date_range,
                            size: 18,
                            color: Colors.orangeAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Batch: $_endYear",
                            style: TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 18),

                    // Three Summary Cards (fixed at the top)
                    Row(
                      children: [
                        _buildSummaryCard(
                          "Working Days",
                          "$_workingDays",
                          Icons.calendar_today,
                          Colors.blue,
                        ),
                        _buildSummaryCard(
                          "Present",
                          "$_presentCount",
                          Icons.check_circle,
                          Colors.green,
                        ),
                        _buildSummaryCard(
                          "Absent",
                          "$_absentCount",
                          Icons.cancel,
                          Colors.red,
                        ),
                      ],
                    ),

                    SizedBox(height: 18),

                    // Scrollable Attendance List below summary cards
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFF2F4F8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child:
                            _attendanceRecords.isEmpty
                                ? Center(
                                  child: Text(
                                    "No attendance records found",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                                : Scrollbar(
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    itemCount: _attendanceRecords.length,
                                    padding: EdgeInsets.only(top: 8, bottom: 8),
                                    itemBuilder: (context, index) {
                                      final record = _attendanceRecords[index];
                                      return Card(
                                        elevation: 2,
                                        margin: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          side: BorderSide(
                                            color: Color(0xFFE7EAF1),
                                          ),
                                        ),
                                        child: ListTile(
                                          leading: Icon(
                                            record["present"]
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            color:
                                                record["present"]
                                                    ? Colors.green
                                                    : Colors.red,
                                            size: 30,
                                          ),
                                          title: Text(
                                            DateFormat(
                                              "dd/MM/yyyy",
                                            ).format(record["date"]),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Color(0xFF0746C5),
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(
                                                  "IN: ",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                Text(
                                                  record['inTime'],
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        isLateIn(
                                                              record['inTime'],
                                                            )
                                                            ? Colors.red
                                                            : Colors.black87,
                                                    fontWeight:
                                                        isLateIn(
                                                              record['inTime'],
                                                            )
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                  ),
                                                ),
                                                Text(
                                                  "  |  OUT: ${record['outTime']}  |  Duration: ${record['duration']}",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          tileColor: Colors.white,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
