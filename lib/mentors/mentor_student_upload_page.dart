import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hod_web_dashboard/firebase_service.dart';

class MentorStudentUploadPage extends StatefulWidget {
  final String mentorUserId;
  final List<Map<String, String>> assignedSections;
  final void Function(String year, List<List<dynamic>> updatedData)?
  onCacheUpdate;

  /// ✅ Set of selected roll numbers from selection page
  final Set<String> selectedStudentRollNos;

  const MentorStudentUploadPage({
    super.key,
    required this.mentorUserId,
    required this.assignedSections,
    this.onCacheUpdate,
    required this.selectedStudentRollNos,
  });

  @override
  State<MentorStudentUploadPage> createState() =>
      MentorStudentUploadPageState();
}

class MentorStudentUploadPageState extends State<MentorStudentUploadPage> {
  String? selectedBatch;
  String? selectedSection;
  String? selectedDepartment;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController rollNoController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Set<String> globallySelectedRollNos = {};

  String? editingDocId;

  List<String> get batches =>
      widget.assignedSections.map((e) => e['batch']!).toSet().toList();

  List<String> get sectionsForBatch {
    if (selectedBatch == null) return [];
    return widget.assignedSections
        .where((e) => e['batch'] == selectedBatch)
        .map((e) => e['section']!)
        .toList();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// ✅ Called from dashboard AppBar refresh button
  Future<void> refreshPage() async {
    setState(() {}); // Rebuild
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
      ),
    );
  }

  void clearForm() {
    nameController.clear();
    rollNoController.clear();
    editingDocId = null;
  }

  Future<void> saveStudent() async {
    if (selectedBatch == null ||
        selectedSection == null ||
        nameController.text.trim().isEmpty ||
        rollNoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    final rollNo = rollNoController.text.trim().toUpperCase();
    final studentData = {
      'name': nameController.text.trim(),
      'rollNo': rollNo,
      'department': selectedDepartment,
      'section': selectedSection,
      'endYear': selectedBatch,
      'updatedAt': DateTime.now(),
    };

    final studentRef = FirebaseFirestore.instance
        .collection('Branch')
        .doc(selectedDepartment)
        .collection(selectedBatch!)
        .doc(selectedSection)
        .collection('students');

    if (editingDocId == null) {
      // Add new student
      await studentRef.doc(rollNo).set(studentData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Student added successfully")),
      );
    } else {
      if (editingDocId != rollNo) {
        // RollNo changed → delete old doc & create new
        final oldData =
            (await studentRef.doc(editingDocId!).get()).data() ?? {};
        await studentRef.doc(editingDocId!).delete();
        await studentRef.doc(rollNo).set({...oldData, ...studentData});
      } else {
        // Update existing
        await studentRef.doc(editingDocId!).update(studentData);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Student updated successfully")),
      );
    }

    // ✅ Update dashboard cache
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
        debugPrint("Error updating dashboard cache after saveStudent: $e");
      }
    }

    clearForm();
    setState(() {});

    // 🔴 ADD THIS LINE HERE, AT END!
    await _refreshGlobalFrozenRollNos();
  }

  Future<void> _refreshGlobalFrozenRollNos() async {
    if (selectedBatch != null && selectedSection != null) {
      globallySelectedRollNos = await FirebaseService.instance
          .getGloballySelectedRollNos(
            batch: selectedBatch!,
            section: selectedSection!,
          );
      setState(() {});
    }
  }

  Future<void> deleteStudentFromEntireDB(String rollNo) async {
    try {
      // Delete from main students collection
      final studentRef = FirebaseFirestore.instance
          .collection('Branch')
          .doc(selectedDepartment)
          .collection(selectedBatch!)
          .doc(selectedSection!)
          .collection('students');
      await studentRef.doc(rollNo).delete();

      // Remove from all mentor assignedStudents
      final mentorsSnapshot =
          await FirebaseFirestore.instance.collection('mentors').get();

      for (final mentorDoc in mentorsSnapshot.docs) {
        final assignedStudentsRef = mentorDoc.reference.collection(
          'assignedStudents',
        );
        final sectionDocId = "$selectedBatch-$selectedSection";
        final sectionDoc = await assignedStudentsRef.doc(sectionDocId).get();

        if (sectionDoc.exists) {
          final data = sectionDoc.data()!;
          final List<dynamic> selectedRollNos = List.from(
            data['selectedRollNos'] ?? [],
          );

          if (selectedRollNos.contains(rollNo)) {
            selectedRollNos.remove(rollNo);
            await assignedStudentsRef.doc(sectionDocId).update({
              'selectedRollNos': selectedRollNos,
              'updatedAt': DateTime.now(),
            });
          }
        }
      }

      // Refresh dashboard cache
      if (widget.onCacheUpdate != null && selectedBatch != null) {
        final updatedData = await FirebaseService.instance
            .fetchYearAttendanceData(
              selectedBatch!,
              forceRefresh: true,
              mentorUserId: widget.mentorUserId,
            );
        widget.onCacheUpdate!(selectedBatch!, updatedData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Row(
            children: [
              Icon(Icons.delete, color: Colors.white),
              SizedBox(width: 8),
              Text("Student deleted successfully."),
            ],
          ),
        ),
      );

      await _refreshGlobalFrozenRollNos();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting student: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // LEFT PANEL (Form)
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(20),
            color: Colors.grey.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.upload_file,
                      color: Colors.black,
                      size: 24,
                    ), // 👈 upload icon
                    const SizedBox(width: 10),
                    const Text(
                      "Upload Student Details",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Batch dropdown
                DropdownButtonFormField<String>(
                  value: selectedBatch,
                  decoration: const InputDecoration(
                    labelText: "Batch",
                    border: OutlineInputBorder(),
                  ),
                  items:
                      batches
                          .map(
                            (b) => DropdownMenuItem(value: b, child: Text(b)),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedBatch = val;
                      selectedSection = null;
                    });
                    _refreshGlobalFrozenRollNos();
                  },
                ),
                const SizedBox(height: 12),

                // Section dropdown
                DropdownButtonFormField<String>(
                  value: selectedSection,
                  decoration: const InputDecoration(
                    labelText: "Section",
                    border: OutlineInputBorder(),
                  ),
                  items:
                      sectionsForBatch.map((s) {
                        final dept =
                            widget.assignedSections.firstWhere(
                              (e) =>
                                  e['batch'] == selectedBatch &&
                                  e['section'] == s,
                            )['department'];
                        return DropdownMenuItem(
                          value: s,
                          onTap: () {
                            selectedDepartment = dept;
                          },
                          child: Text(s),
                        );
                      }).toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedSection = val;
                    });
                    _refreshGlobalFrozenRollNos();
                  },
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Name",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: rollNoController,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (val) {
                    rollNoController.value = rollNoController.value.copyWith(
                      text: val.toUpperCase(),
                      selection: TextSelection.collapsed(
                        offset: val.toUpperCase().length,
                      ),
                    );
                  },
                  decoration: const InputDecoration(
                    labelText: "Roll No",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: saveStudent,
                      icon: Icon(
                        editingDocId == null ? Icons.add : Icons.update,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: Text(
                        editingDocId == null ? "Add Student" : "Update Student",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 3,
                        backgroundColor: const Color(
                          0xFF0746C5,
                        ), // Your primary blue
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        shadowColor: Colors.black45,
                        minimumSize: Size(140, 48),
                      ),
                    ),

                    const SizedBox(width: 10),
                    if (editingDocId != null)
                      OutlinedButton(
                        onPressed: clearForm,
                        child: const Text("Cancel Edit"),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // RIGHT PANEL (List)
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child:
                  selectedBatch != null && selectedSection != null
                      ? StreamBuilder<QuerySnapshot>(
                        stream:
                            FirebaseFirestore.instance
                                .collection('Branch')
                                .doc(selectedDepartment)
                                .collection(selectedBatch!)
                                .doc(selectedSection)
                                .collection('students')
                                .orderBy('rollNo')
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final students = snapshot.data!.docs;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.people,
                                    color: Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Students (${students.length})",
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Expanded(
                                child:
                                    students.isEmpty
                                        ? const Center(
                                          child: Text("No students found"),
                                        )
                                        : Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: true,
                                          child: ListView.separated(
                                            controller: _scrollController,
                                            itemCount: students.length,
                                            separatorBuilder:
                                                (_, __) => const Divider(),
                                            itemBuilder: (context, index) {
                                              final data =
                                                  students[index].data()
                                                      as Map<String, dynamic>;

                                              // Normalize roll number from DB
                                              final rollNo =
                                                  (data['rollNo'] ?? '')
                                                      .toString()
                                                      .trim()
                                                      .toUpperCase();

                                              // Freeze if this roll number is in the selected list (case-insensitive)
                                              final isFrozen =
                                                  globallySelectedRollNos
                                                      .contains(rollNo);

                                              return ListTile(
                                                title: Text(
                                                  "${data['name']} ($rollNo)",
                                                ),
                                                subtitle: Text(
                                                  "Dept: ${data['department']} | Batch: ${data['endYear']}",
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.edit,
                                                        color: Colors.blue,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          selectedBatch =
                                                              data['endYear'];
                                                          selectedSection =
                                                              data['section'];
                                                          selectedDepartment =
                                                              data['department'];
                                                          nameController.text =
                                                              data['name'] ??
                                                              '';
                                                          rollNoController
                                                              .text = rollNo;
                                                          editingDocId = rollNo;
                                                        });
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.delete,
                                                        color:
                                                            isFrozen
                                                                ? Colors.grey
                                                                : Colors.red,
                                                      ),
                                                      tooltip:
                                                          isFrozen
                                                              ? "This student is assigned to a mentor, cannot delete"
                                                              : "Delete Student",
                                                      onPressed:
                                                          isFrozen
                                                              ? null
                                                              : () =>
                                                                  deleteStudentFromEntireDB(
                                                                    rollNo,
                                                                  ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                              ),
                            ],
                          );
                        },
                      )
                      : const Center(
                        child: Text("Select batch & section to view students"),
                      ),
            ),
          ),
        ),
      ],
    );
  }
}
