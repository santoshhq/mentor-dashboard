import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hod_web_dashboard/firebase_service.dart';

class MentorsPage extends StatefulWidget {
  final FirebaseService firebaseService;

  const MentorsPage({super.key, required this.firebaseService});

  @override
  State<MentorsPage> createState() => _MentorsPageState();
}

class _MentorsPageState extends State<MentorsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  List<String> availableBatches = [];
  List<String> availableSections = [];
  String? selectedBatch;
  String? selectedSection;
  List<Map<String, String>> selectedBatchSections = [];

  @override
  void initState() {
    super.initState();
    fetchAvailableBatches();
  }

  Future<void> fetchAvailableBatches() async {
    final snapshot =
        await FirebaseFirestore.instance.collectionGroup('students').get();
    final Set<int> batches = {};
    for (var doc in snapshot.docs) {
      if (doc.data().containsKey('endYear')) {
        final year = doc['endYear'];
        if (year is int) {
          batches.add(year);
        } else if (year is String) {
          final parsed = int.tryParse(year);
          if (parsed != null) {
            batches.add(parsed);
          }
        }
      }
    }
    final sortedList =
        batches.toList()..sort((a, b) => b.compareTo(a)); // descending
    setState(() {
      availableBatches = sortedList.map((e) => e.toString()).toList();
    });
  }

  Future<void> fetchSectionsForBatch(String batch) async {
    debugPrint("🔍 Attempting to fetch sections for batch: $batch");

    try {
      final snapshot =
          await FirebaseFirestore.instance.collectionGroup('students').get();

      final Set<String> sections = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();

        if (data.containsKey('endYear') &&
            data['endYear'].toString() == batch) {
          final section = data['section']?.toString().toUpperCase();
          if (section != null && section.isNotEmpty) {
            sections.add(section);
          }
        }
      }

      final sortedSections = sections.toList()..sort();

      setState(() {
        availableSections = sortedSections;
        selectedSection = null;
      });

      debugPrint("✅ Sections available for $batch: $availableSections");
    } catch (e, stack) {
      debugPrint("❌ Error fetching sections: $e");
      debugPrint("$stack");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error fetching sections: $e")));
    }
  }

  void addBatchSection() {
    if (selectedBatch != null && selectedSection != null) {
      final exists = selectedBatchSections.any(
        (e) => e['batch'] == selectedBatch && e['section'] == selectedSection,
      );
      if (!exists) {
        setState(() {
          selectedBatchSections.add({
            'batch': selectedBatch!,
            'section': selectedSection!,
          });
        });
      }
    }
  }

  Future<void> _addMentor() async {
    if (_nameController.text.trim().isEmpty ||
        _userIdController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        selectedBatchSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All fields and at least one batch-section required'),
        ),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('mentors').add({
      'name': _nameController.text.trim(),
      'userId': _userIdController.text.trim(),
      'password': _passwordController.text.trim(),
      'isActive': true,
      'assigned': selectedBatchSections,
    });

    _nameController.clear();
    _userIdController.clear();
    _passwordController.clear();
    selectedBatchSections.clear();
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mentor added successfully')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          /// Left: Add Mentor Card
          Expanded(
            flex: 2,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Add Mentor",
                        style: theme.textTheme.titleLarge!.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Mentor Name",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _userIdController,
                        decoration: const InputDecoration(
                          labelText: "User ID (email/ID)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: "Password",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedBatch,
                        hint: const Text("Select Batch"),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items:
                            availableBatches.map((batch) {
                              return DropdownMenuItem(
                                value: batch,
                                child: Text(batch),
                              );
                            }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedBatch = val;
                            fetchSectionsForBatch(val!);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value:
                            availableSections.contains(selectedSection)
                                ? selectedSection
                                : null,
                        hint: const Text("Select Section"),
                        decoration: const InputDecoration(
                          labelText: "Section",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.class_),
                        ),
                        isExpanded: true,
                        items:
                            availableSections.map((section) {
                              return DropdownMenuItem(
                                value: section,
                                child: Text(section),
                              );
                            }).toList(),
                        onChanged:
                            availableSections.isEmpty
                                ? null
                                : (val) {
                                  setState(() {
                                    selectedSection = val;
                                  });
                                },
                      ),

                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: addBatchSection,
                        icon: const Icon(Icons.add),
                        label: const Text("Add Batch-Section"),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children:
                            selectedBatchSections.map((e) {
                              return Chip(
                                label: Text("${e['batch']} - ${e['section']}"),
                                backgroundColor: Colors.blue[50],
                                onDeleted: () {
                                  setState(() {
                                    selectedBatchSections.remove(e);
                                  });
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _addMentor,
                          icon: const Icon(Icons.save),
                          label: const Text("Save Mentor"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),

          /// Right: Mentors List
          Expanded(
            flex: 3,
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('mentors').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final mentors = snapshot.data!.docs;
                if (mentors.isEmpty) {
                  return const Center(child: Text("No mentors added yet."));
                }
                return ListView.separated(
                  itemCount: mentors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = mentors[index].data() as Map<String, dynamic>;
                    final List assigned = data['assigned'] ?? [];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      child: ListTile(
                        title: Text(
                          data['name'] ?? 'No Name',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              "User ID: ${data['userId'] ?? ''}",
                              if (assigned.isNotEmpty)
                                "Assigned: ${assigned.map((e) => "${e['batch']} - ${e['section']}").join(', ')}",
                            ].join('\n'),
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder:
                                  (_) => AlertDialog(
                                    title: const Text("Confirm Delete"),
                                    content: const Text(
                                      "Are you sure you want to delete this mentor?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text("Cancel"),
                                      ),
                                      ElevatedButton(
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text(
                                          "Delete",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                            );

                            if (confirm == true) {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('mentors')
                                    .doc(mentors[index].id)
                                    .delete();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Mentor deleted"),
                                  ),
                                );
                              } catch (e) {
                                debugPrint("❌ Error deleting mentor: $e");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Failed to delete mentor: $e",
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
