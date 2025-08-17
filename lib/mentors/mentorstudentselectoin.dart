import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hod_web_dashboard/firebase_service.dart';

class MentorStudentSelectorPage extends StatefulWidget {
  final String mentorUserId;

  /// Callback: (endYear, updatedData)
  final void Function(String endYear, List<List<dynamic>> updatedData)?
  onCacheUpdate;

  /// NEW: Callback to pass frozen roll numbers (students that can't be deleted) to parent
  final void Function(List<String> frozenRollNos)? onFrozenListChanged;

  /// Callback to pass currently selected roll numbers to parent
  final void Function(Set<String>)? onSelectedRollNosChanged;

  const MentorStudentSelectorPage({
    super.key,
    required this.mentorUserId,
    this.onCacheUpdate,
    this.onFrozenListChanged,
    this.onSelectedRollNosChanged,
  });

  @override
  MentorStudentSelectorPageState createState() =>
      MentorStudentSelectorPageState();
}

class MentorStudentSelectorPageState extends State<MentorStudentSelectorPage> {
  List<Map<String, String>> assignedSections = [];
  String? selectedBatch;
  String? selectedSection;
  String? selectedDept;

  List<Map<String, dynamic>> allStudents = [];
  List<Map<String, dynamic>> selectedStudents = [];

  List<String> initialSelectedRollNos = [];
  List<String> frozenRollNos = [];

  bool isLoading = false;
  bool showApplyButton = false;
  bool hasChanges = false;

  @override
  void initState() {
    super.initState();
    fetchAssignedSections();
  }

  Future<void> refreshPage() async {
    try {
      await fetchAssignedSections();
      if (selectedBatch != null && selectedSection != null) {
        await fetchStudents();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ Refreshed!")));
      }
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Refresh failed: $e")));
      }
      print('refreshPage error: $e');
      print(stack);
    }
  }

  Future<void> fetchAssignedSections() async {
    try {
      final mentorDoc =
          await FirebaseFirestore.instance
              .collection('mentors')
              .where('userId', isEqualTo: widget.mentorUserId)
              .limit(1)
              .get();

      if (mentorDoc.docs.isNotEmpty) {
        final data = mentorDoc.docs.first.data();
        setState(() {
          assignedSections =
              (data['assigned'] as List)
                  .map<Map<String, String>>(
                    (e) => {
                      'batch': e['batch'],
                      'section': e['section'],
                      'department': e['department'] ?? 'CSE',
                    },
                  )
                  .toList();
        });
      }
    } catch (e, stack) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching sections: $e')));
      }
      print('fetchAssignedSections error: $e');
      print(stack);
    }
  }

  Future<void> fetchStudents() async {
    if (selectedBatch == null ||
        selectedSection == null ||
        selectedDept == null)
      return;

    setState(() {
      isLoading = true;
      allStudents = [];
      selectedStudents = [];
      initialSelectedRollNos = [];
      frozenRollNos = [];
      showApplyButton = false;
      hasChanges = false;
    });

    final docId = "$selectedBatch-$selectedSection";

    final existingSelection =
        await FirebaseFirestore.instance
            .collection('mentors')
            .doc(widget.mentorUserId)
            .collection('assignedStudents')
            .doc(docId)
            .get();

    if (existingSelection.exists && existingSelection.data() != null) {
      initialSelectedRollNos = List<String>.from(
        existingSelection.data()!['selectedRollNos'] ?? [],
      );
      frozenRollNos = List<String>.from(initialSelectedRollNos);

      /// 🔄 Notify parent with frozen list
      widget.onFrozenListChanged?.call(frozenRollNos);
    }

    final snapshot =
        await FirebaseFirestore.instance
            .collection('Branch')
            .doc(selectedDept)
            .collection(selectedBatch!)
            .doc(selectedSection!)
            .collection('students')
            .get();

    final fetched =
        snapshot.docs
            .map(
              (doc) => {
                'rollNo': doc.id,
                'name': (doc.data()['name'] ?? 'Unknown'),
              },
            )
            .toList();

    fetched.sort(
      (a, b) => (a['rollNo'] as String).compareTo(b['rollNo'] as String),
    );

    setState(() {
      allStudents = fetched;
      selectedStudents =
          fetched
              .where((s) => initialSelectedRollNos.contains(s['rollNo']))
              .toList();
      isLoading = false;
      showApplyButton = true;
      hasChanges = false;
    });
  }

  Future<void> saveSelectedStudents() async {
    final docId = "$selectedBatch-$selectedSection";

    await FirebaseFirestore.instance
        .collection('mentors')
        .doc(widget.mentorUserId)
        .collection('assignedStudents')
        .doc(docId)
        .set({
          'endYear': selectedBatch,
          'section': selectedSection,
          'department': selectedDept,
          'selectedRollNos': selectedStudents.map((e) => e['rollNo']).toList(),
          'updatedAt': DateTime.now(),
        });

    setState(() {
      initialSelectedRollNos =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      frozenRollNos = List<String>.from(initialSelectedRollNos);
      hasChanges = false;
    });

    /// 🔄 Notify parent with frozen list after save
    widget.onFrozenListChanged?.call(frozenRollNos);

    if (widget.onCacheUpdate != null && selectedBatch != null) {
      try {
        final updatedData = await FirebaseService.instance
            .fetchYearAttendanceData(
              selectedBatch!,
              forceRefresh: true,
              mentorUserId: widget.mentorUserId,
            );
        widget.onCacheUpdate!(selectedBatch!, updatedData);
      } catch (e) {
        debugPrint(
          "Error updating dashboard cache after saveSelectedStudents: $e",
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.people_alt, color: Colors.white),
              SizedBox(width: 8),
              Text(
                "Student list saved successfully.",
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void cancelSelectionChanges() {
    setState(() {
      selectedBatch = null;
      selectedSection = null;
      selectedDept = null;
      allStudents.clear();
      selectedStudents.clear();
      initialSelectedRollNos.clear();
      frozenRollNos.clear();
      showApplyButton = false;
      hasChanges = false;
    });

    /// Notify parent when cleared
    widget.onFrozenListChanged?.call([]);
  }

  void toggleStudentSelection(Map<String, dynamic> student) {
    final roll = student['rollNo'] as String;

    if (frozenRollNos.contains(roll)) return;

    setState(() {
      final alreadySelected = selectedStudents.any((s) => s['rollNo'] == roll);
      if (alreadySelected) {
        selectedStudents.removeWhere((s) => s['rollNo'] == roll);
      } else {
        selectedStudents.add(student);
      }

      final current =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      hasChanges = !_listEqualsIgnoreOrder(current, initialSelectedRollNos);
    });

    // ✅ Notify parent about updated roll numbers
    widget.onSelectedRollNosChanged?.call(
      selectedStudents.map((s) => s['rollNo'] as String).toSet(),
    );
  }

  void removeFromSelected(Map<String, dynamic> student) {
    final roll = student['rollNo'] as String;

    setState(() {
      selectedStudents.removeWhere((s) => s['rollNo'] == roll);

      if (initialSelectedRollNos.contains(roll) &&
          frozenRollNos.contains(roll)) {
        frozenRollNos.remove(roll);
      }

      final current =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      hasChanges = !_listEqualsIgnoreOrder(current, initialSelectedRollNos);
    });

    // ✅ Notify parent about updated roll numbers
    widget.onSelectedRollNosChanged?.call(
      selectedStudents.map((s) => s['rollNo'] as String).toSet(),
    );
  }

  bool _listEqualsIgnoreOrder(List<String> a, List<String> b) {
    return Set.from(a).containsAll(b) && Set.from(b).containsAll(a);
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF0746C5);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt_rounded, color: Colors.black87),
              const SizedBox(width: 8),
              Text(
                "Select Students",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Select Batch",
                    border: OutlineInputBorder(),
                  ),
                  value: selectedBatch,
                  items:
                      assignedSections
                          .map((e) => e['batch']!)
                          .toSet()
                          .map(
                            (batch) => DropdownMenuItem(
                              value: batch,
                              child: Text(batch),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedBatch = val;
                      selectedSection = null;
                      selectedDept = null;
                      showApplyButton = false;
                      hasChanges = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Select Section",
                    border: OutlineInputBorder(),
                  ),
                  value: selectedSection,
                  items:
                      assignedSections
                          .where((e) => e['batch'] == selectedBatch)
                          .map(
                            (e) => DropdownMenuItem(
                              value: e['section'],
                              child: Text(e['section']!),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    final dept =
                        assignedSections.firstWhere(
                          (e) =>
                              e['batch'] == selectedBatch &&
                              e['section'] == val,
                        )['department'];
                    setState(() {
                      selectedSection = val;
                      selectedDept = dept;
                      showApplyButton = false;
                      hasChanges = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.people, color: Colors.white),
                label: const Text(
                  "Show Students",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                onPressed: fetchStudents,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (isLoading) const Center(child: CircularProgressIndicator()),
          if (!isLoading && allStudents.isNotEmpty)
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildStudentList(allStudents, true)),
                  const VerticalDivider(width: 16),
                  Expanded(child: _buildStudentList(selectedStudents, false)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (showApplyButton)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: cancelSelectionChanges,
                    icon: const Icon(Icons.close),
                    label: const Text("Cancel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: hasChanges ? saveSelectedStudents : null,
                    icon: const Icon(Icons.save),
                    label: Text(
                      "Apply (${selectedStudents.length})",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          hasChanges ? Color(0xFF0746C5) : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStudentList(List<Map<String, dynamic>> students, bool isAll) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isAll ? Icons.school : Icons.check_circle_outline, size: 20),
              const SizedBox(width: 6),
              Text(
                isAll
                    ? "All Students (${students.length})"
                    : "Selected Students (${students.length})",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final sorted = [...students]..sort(
                    (a, b) => (a['rollNo'] as String).compareTo(
                      b['rollNo'] as String,
                    ),
                  );
                  final student = sorted[index];
                  final roll = student['rollNo'] as String;
                  final name = student['name'] as String;
                  final isSelected = selectedStudents.any(
                    (s) => s['rollNo'] == roll,
                  );
                  final isFrozen = frozenRollNos.contains(roll);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color:
                        isAll && isFrozen
                            ? const Color.fromARGB(255, 21, 184, 3)
                            : null,
                    child: ListTile(
                      title: Text(
                        "$roll - $name",
                        style: TextStyle(
                          color: isAll && isFrozen ? Colors.white : null,
                        ),
                      ),
                      trailing:
                          isAll
                              ? (isFrozen
                                  ? const Icon(Icons.lock, color: Colors.white)
                                  : Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: isSelected ? Colors.green : null,
                                  ))
                              : IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.red,
                                ),
                                onPressed: () => removeFromSelected(student),
                              ),
                      onTap:
                          isAll && isFrozen
                              ? null
                              : () => toggleStudentSelection(student),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
