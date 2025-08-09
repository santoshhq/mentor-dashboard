import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class MentorStudentSelectorPage extends StatefulWidget {
  final String mentorUserId;

  const MentorStudentSelectorPage({super.key, required this.mentorUserId});

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

  // Baseline from Firestore (saved previously) — used for change detection
  List<String> initialSelectedRollNos = [];

  // Represents which students are currently "frozen" on left (un-tappable).
  // Initially equals initialSelectedRollNos. If user removes a frozen student
  // from the right list, we remove it from frozenRollNos (so it becomes selectable).
  List<String> frozenRollNos = [];

  bool isLoading = false;
  bool showApplyButton = false;
  bool hasChanges = false; // true when user made add/remove compared to initial

  @override
  void initState() {
    super.initState();
    fetchAssignedSections();
  }

  /// Called from parent/global refresh button
  Future<void> refreshPage() async {
    await fetchAssignedSections();
    if (selectedBatch != null && selectedSection != null) {
      await fetchStudents();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("✅ Refreshed!")));
    }
  }

  Future<void> fetchAssignedSections() async {
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

    // load persisted selection (baseline)
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
      // frozen initially = baseline
      frozenRollNos = List<String>.from(initialSelectedRollNos);
    }

    // Load all students
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

    setState(() {
      allStudents = fetched;
      // Selected students initially = those saved previously
      selectedStudents =
          fetched
              .where((s) => initialSelectedRollNos.contains(s['rollNo']))
              .toList();
      isLoading = false;
      showApplyButton =
          true; // show the Apply/Cancel row (Apply disabled until change)
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

    // After save, update baseline and re-freeze the saved ones
    setState(() {
      initialSelectedRollNos =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      frozenRollNos = List<String>.from(initialSelectedRollNos);
      hasChanges = false;
    });

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
    // Reset to the initial starting state so user can choose batch/section again
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
  }

  void toggleStudentSelection(Map<String, dynamic> student) {
    final roll = student['rollNo'] as String;

    // If currently frozen, do nothing (cannot toggle)
    if (frozenRollNos.contains(roll)) return;

    setState(() {
      final alreadySelected = selectedStudents.any((s) => s['rollNo'] == roll);
      if (alreadySelected) {
        selectedStudents.removeWhere((s) => s['rollNo'] == roll);
      } else {
        selectedStudents.add(student);
      }

      // recompute hasChanges: compare selected rollNos with baseline initialSelectedRollNos
      final current =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      hasChanges = !_listEqualsIgnoreOrder(current, initialSelectedRollNos);
    });
  }

  // When user removes from the right list (unselect)
  void removeFromSelected(Map<String, dynamic> student) {
    final roll = student['rollNo'] as String;

    setState(() {
      // Remove from selected
      selectedStudents.removeWhere((s) => s['rollNo'] == roll);

      // If this roll was initially frozen (baseline), we should unfreeze it so
      // the left list becomes tappable for that student (user can re-add it).
      if (initialSelectedRollNos.contains(roll) &&
          frozenRollNos.contains(roll)) {
        frozenRollNos.remove(roll); // unfreeze
      }

      // recompute hasChanges
      final current =
          selectedStudents.map((s) => s['rollNo'] as String).toList();
      hasChanges = !_listEqualsIgnoreOrder(current, initialSelectedRollNos);
    });
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

          // Dropdowns + Show Students + Refresh (if desired)
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
                  // Left: All Students (shows check / lock)
                  Expanded(
                    child: Container(
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
                              const Icon(Icons.school, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                "All Students (${allStudents.length})",
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
                                itemCount: allStudents.length,
                                itemBuilder: (context, index) {
                                  final student = allStudents[index];
                                  final roll = student['rollNo'] as String;
                                  final name = student['name'] as String;

                                  final isSelected = selectedStudents.any(
                                    (s) => s['rollNo'] == roll,
                                  );
                                  final isFrozen = frozenRollNos.contains(roll);

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    color:
                                        isFrozen
                                            ? const Color.fromARGB(
                                              255,
                                              21,
                                              184,
                                              3,
                                            )
                                            : null,
                                    child: ListTile(
                                      title: Text(
                                        "$roll - $name",
                                        style: TextStyle(
                                          color: isFrozen ? Colors.white : null,
                                        ),
                                      ),
                                      trailing:
                                          isFrozen
                                              ? const Icon(
                                                Icons.lock,
                                                color: Colors.white,
                                              )
                                              : Icon(
                                                isSelected
                                                    ? Icons.check_circle
                                                    : Icons.circle_outlined,
                                                color:
                                                    isSelected
                                                        ? Colors.green
                                                        : null,
                                              ),
                                      onTap:
                                          isFrozen
                                              ? null
                                              : () => toggleStudentSelection(
                                                student,
                                              ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const VerticalDivider(width: 16),

                  // Right: Selected Students (removable)
                  Expanded(
                    child: Container(
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
                              const Icon(Icons.check_circle_outline, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                "Selected Students (${selectedStudents.length})",
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
                                itemCount: selectedStudents.length,
                                itemBuilder: (context, index) {
                                  // Sort here before building
                                  final sortedStudents = [...selectedStudents]
                                    ..sort(
                                      (a, b) => (a['rollNo'] as String)
                                          .compareTo(b['rollNo'] as String),
                                    );

                                  final student = sortedStudents[index];
                                  final roll = student['rollNo'] as String;
                                  final name = student['name'] as String;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: ListTile(
                                      title: Text("$roll - $name"),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle,
                                          color: Colors.red,
                                        ),
                                        onPressed:
                                            () => removeFromSelected(student),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  // Cancel resets to initial page state
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
                    label: Text("Apply (${selectedStudents.length})"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasChanges ? Colors.blue : Colors.grey,
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
}
