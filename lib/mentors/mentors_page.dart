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
  bool _obscurePassword = true;
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: const [
            Icon(Icons.person, color: Colors.white),
            SizedBox(width: 8),
            Text('Mentor added successfully'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
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
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Header
                    Row(
                      children: [
                        const Icon(
                          Icons.person_add_alt_1,
                          size: 26,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Add Mentor",
                          style: theme.textTheme.titleLarge!.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    /// Name
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: "Mentor Name",
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    /// User ID
                    TextField(
                      controller: _userIdController,
                      decoration: InputDecoration(
                        labelText: "User ID (email/ID)",
                        prefixIcon: const Icon(Icons.account_box_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    /// Password
                    // bool _obscurePassword = true;
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    /// Batch & Section Dropdowns in Row
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedBatch,
                            hint: const Text("Select Batch"),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.school),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value:
                                availableSections.contains(selectedSection)
                                    ? selectedSection
                                    : null,
                            hint: const Text("Select Section"),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.class_),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    /// Add Batch-Section Button
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: addBatchSection,
                        icon: const Icon(Icons.add),
                        label: const Text("Add Batch-Section"),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    /// Chips Display
                    if (selectedBatchSections.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Assigned Sections:",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children:
                                selectedBatchSections.map((e) {
                                  return Chip(
                                    label: Text(
                                      "${e['batch']} - ${e['section']}",
                                    ),
                                    backgroundColor: Colors.indigo.shade50,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    deleteIcon: const Icon(Icons.close),
                                    onDeleted: () {
                                      setState(() {
                                        selectedBatchSections.remove(e);
                                      });
                                    },
                                  );
                                }).toList(),
                          ),
                        ],
                      ),

                    const SizedBox(height: 30),

                    /// Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addMentor,
                        icon: const Icon(Icons.save_rounded, size: 20),
                        label: const Text(
                          "Save Mentor",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          /// Right: Mentors List
          /// Right: Mentors List
          ///
          ///
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Title
                  Row(
                    children: const [
                      Icon(Icons.group, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        "Assigned Mentors",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    flex: 3,
                    child: StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('mentors')
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final mentors = snapshot.data!.docs;
                        if (mentors.isEmpty) {
                          return const Center(
                            child: Text("No mentors added yet."),
                          );
                        }
                        return ListView.separated(
                          itemCount: mentors.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data =
                                mentors[index].data() as Map<String, dynamic>;
                            final List assigned = data['assigned'] ?? [];
                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.indigo,
                                  child: Text(
                                    (data['name'] != null &&
                                            data['name'].isNotEmpty)
                                        ? data['name'][0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  data['name'] ?? 'No Name',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
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

                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.grey,
                                      ),
                                      tooltip: "Edit",
                                      onPressed: () async {
                                        final nameController =
                                            TextEditingController(
                                              text: data['name'] ?? '',
                                            );
                                        final userIdController =
                                            TextEditingController(
                                              text: data['userId'] ?? '',
                                            );
                                        final passwordController =
                                            TextEditingController(
                                              text: data['password'] ?? '',
                                            );

                                        try {
                                          debugPrint(
                                            "🪐 Opening edit dialog for mentor: ${data['name']}",
                                          );

                                          final List<Map<String, String>>
                                          assignedList =
                                              (data['assigned']
                                                          as List<dynamic>? ??
                                                      [])
                                                  .map<Map<String, String>>((
                                                    e,
                                                  ) {
                                                    final map =
                                                        <String, String>{};
                                                    (e as Map).forEach((
                                                      key,
                                                      value,
                                                    ) {
                                                      map[key.toString()] =
                                                          value.toString();
                                                    });
                                                    return map;
                                                  })
                                                  .toList();

                                          final result = await showDialog<bool>(
                                            context: context,
                                            builder: (context) {
                                              // local availableSections inside dialog
                                              List<String>
                                              localAvailableSections = [];

                                              Future<void>
                                              fetchSectionsForBatchInDialog(
                                                String batch,
                                              ) async {
                                                debugPrint(
                                                  "🔍 [Edit] Fetching sections for batch: $batch",
                                                );

                                                try {
                                                  final snapshot =
                                                      await FirebaseFirestore
                                                          .instance
                                                          .collectionGroup(
                                                            'students',
                                                          )
                                                          .get();

                                                  final Set<String> sections =
                                                      {};

                                                  for (var doc
                                                      in snapshot.docs) {
                                                    final data = doc.data();
                                                    if (data.containsKey(
                                                          'endYear',
                                                        ) &&
                                                        data['endYear']
                                                                .toString() ==
                                                            batch) {
                                                      final section =
                                                          data['section']
                                                              ?.toString()
                                                              .toUpperCase();
                                                      if (section != null &&
                                                          section.isNotEmpty) {
                                                        sections.add(section);
                                                      }
                                                    }
                                                  }

                                                  final sortedSections =
                                                      sections.toList()..sort();

                                                  localAvailableSections =
                                                      sortedSections;
                                                  debugPrint(
                                                    "✅ [Edit] Sections for $batch: $localAvailableSections",
                                                  );
                                                } catch (e, stack) {
                                                  debugPrint(
                                                    "❌ Error fetching sections: $e",
                                                  );
                                                  debugPrint("$stack");
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        "Error fetching sections: $e",
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }

                                              return StatefulBuilder(
                                                builder: (context, setState) {
                                                  // Filter out already assigned sections for the selected batch
                                                  final filteredSections =
                                                      localAvailableSections.where((
                                                        sec,
                                                      ) {
                                                        return !assignedList.any(
                                                          (e) =>
                                                              e['batch'] ==
                                                                  selectedBatch &&
                                                              e['section'] ==
                                                                  sec,
                                                        );
                                                      }).toList();

                                                  return Dialog(
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 600,
                                                            maxHeight: 600,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              20,
                                                            ),
                                                        child: SingleChildScrollView(
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Row(
                                                                children: const [
                                                                  Icon(
                                                                    Icons.edit,
                                                                    color:
                                                                        Colors
                                                                            .blue,
                                                                  ),
                                                                  SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  Text(
                                                                    "Edit Mentor Details",
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          18,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                height: 20,
                                                              ),
                                                              TextField(
                                                                controller:
                                                                    nameController,
                                                                decoration: const InputDecoration(
                                                                  labelText:
                                                                      "Name",
                                                                  prefixIcon: Icon(
                                                                    Icons
                                                                        .person,
                                                                  ),
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 10,
                                                              ),
                                                              TextField(
                                                                controller:
                                                                    userIdController,
                                                                decoration: const InputDecoration(
                                                                  labelText:
                                                                      "User ID",
                                                                  prefixIcon: Icon(
                                                                    Icons.badge,
                                                                  ),
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 10,
                                                              ),
                                                              TextField(
                                                                controller:
                                                                    passwordController,
                                                                obscureText:
                                                                    _obscurePassword,
                                                                decoration: InputDecoration(
                                                                  labelText:
                                                                      "Password",
                                                                  prefixIcon: IconButton(
                                                                    icon: Icon(
                                                                      _obscurePassword
                                                                          ? Icons
                                                                              .visibility_off
                                                                          : Icons
                                                                              .visibility,
                                                                    ),
                                                                    onPressed: () {
                                                                      setState(() {
                                                                        _obscurePassword =
                                                                            !_obscurePassword;
                                                                      });
                                                                    },
                                                                  ),
                                                                  border:
                                                                      const OutlineInputBorder(),
                                                                ),
                                                              ),

                                                              const SizedBox(
                                                                height: 20,
                                                              ),
                                                              const Align(
                                                                alignment:
                                                                    Alignment
                                                                        .centerLeft,
                                                                child: Text(
                                                                  "Assigned Batch-Sections:",
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Column(
                                                                children:
                                                                    assignedList.asMap().entries.map((
                                                                      entry,
                                                                    ) {
                                                                      final idx =
                                                                          entry
                                                                              .key;
                                                                      final item =
                                                                          entry
                                                                              .value;
                                                                      final batch =
                                                                          item['batch'];
                                                                      final section =
                                                                          item['section'];

                                                                      return ListTile(
                                                                        contentPadding:
                                                                            EdgeInsets.zero,
                                                                        title: Text(
                                                                          "$batch - $section",
                                                                        ),
                                                                        trailing: IconButton(
                                                                          icon: const Icon(
                                                                            Icons.delete,
                                                                            color:
                                                                                Colors.red,
                                                                          ),
                                                                          onPressed: () {
                                                                            setState(() {
                                                                              assignedList.removeAt(
                                                                                idx,
                                                                              );
                                                                            });
                                                                          },
                                                                        ),
                                                                      );
                                                                    }).toList(),
                                                              ),
                                                              const Divider(
                                                                height: 30,
                                                              ),
                                                              const Align(
                                                                alignment:
                                                                    Alignment
                                                                        .centerLeft,
                                                                child: Text(
                                                                  "Add New Batch-Section",
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: DropdownButtonFormField<
                                                                      String
                                                                    >(
                                                                      value:
                                                                          selectedBatch,
                                                                      hint: const Text(
                                                                        "Select Batch",
                                                                      ),
                                                                      items:
                                                                          availableBatches.map((
                                                                            batch,
                                                                          ) {
                                                                            return DropdownMenuItem(
                                                                              value:
                                                                                  batch,
                                                                              child: Text(
                                                                                batch,
                                                                              ),
                                                                            );
                                                                          }).toList(),
                                                                      onChanged: (
                                                                        val,
                                                                      ) async {
                                                                        selectedBatch =
                                                                            val;
                                                                        selectedSection =
                                                                            null;
                                                                        await fetchSectionsForBatchInDialog(
                                                                          val!,
                                                                        );
                                                                        setState(
                                                                          () {},
                                                                        );
                                                                      },
                                                                      decoration: const InputDecoration(
                                                                        border:
                                                                            OutlineInputBorder(),
                                                                        prefixIcon: Icon(
                                                                          Icons
                                                                              .calendar_today,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: DropdownButtonFormField<
                                                                      String
                                                                    >(
                                                                      value:
                                                                          selectedSection,
                                                                      hint: const Text(
                                                                        "Select Section",
                                                                      ),
                                                                      items:
                                                                          filteredSections.map((
                                                                            section,
                                                                          ) {
                                                                            return DropdownMenuItem(
                                                                              value:
                                                                                  section,
                                                                              child: Text(
                                                                                section,
                                                                              ),
                                                                            );
                                                                          }).toList(),
                                                                      onChanged: (
                                                                        val,
                                                                      ) {
                                                                        setState(
                                                                          () =>
                                                                              selectedSection =
                                                                                  val,
                                                                        );
                                                                      },
                                                                      decoration: const InputDecoration(
                                                                        border:
                                                                            OutlineInputBorder(),
                                                                        prefixIcon: Icon(
                                                                          Icons
                                                                              .class_,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                height: 10,
                                                              ),
                                                              Align(
                                                                alignment:
                                                                    Alignment
                                                                        .centerRight,
                                                                child: ElevatedButton.icon(
                                                                  onPressed:
                                                                      (selectedBatch !=
                                                                                  null &&
                                                                              selectedSection !=
                                                                                  null &&
                                                                              !assignedList.any(
                                                                                (
                                                                                  e,
                                                                                ) =>
                                                                                    e['batch'] ==
                                                                                        selectedBatch &&
                                                                                    e['section'] ==
                                                                                        selectedSection,
                                                                              ))
                                                                          ? () {
                                                                            assignedList.add({
                                                                              'batch':
                                                                                  selectedBatch!,
                                                                              'section':
                                                                                  selectedSection!,
                                                                            });
                                                                            selectedBatch =
                                                                                null;
                                                                            selectedSection =
                                                                                null;
                                                                            localAvailableSections =
                                                                                [];
                                                                            setState(
                                                                              () {},
                                                                            );
                                                                          }
                                                                          : null,
                                                                  icon:
                                                                      const Icon(
                                                                        Icons
                                                                            .add,
                                                                      ),
                                                                  label: const Text(
                                                                    "Add Section",
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 20,
                                                              ),
                                                              Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .end,
                                                                children: [
                                                                  TextButton(
                                                                    onPressed:
                                                                        () => Navigator.pop(
                                                                          context,
                                                                          false,
                                                                        ),
                                                                    child: const Text(
                                                                      "Cancel",
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  ElevatedButton(
                                                                    onPressed:
                                                                        assignedList.isEmpty
                                                                            ? null
                                                                            : () => Navigator.pop(
                                                                              context,
                                                                              true,
                                                                            ),
                                                                    style: ElevatedButton.styleFrom(
                                                                      backgroundColor:
                                                                          Colors
                                                                              .green, // Green button
                                                                      foregroundColor:
                                                                          Colors
                                                                              .white, // White text
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            24,
                                                                        vertical:
                                                                            12,
                                                                      ),
                                                                      textStyle: const TextStyle(
                                                                        fontSize:
                                                                            16,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    child: const Text(
                                                                      "Save Changes",
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );

                                          if (result == true) {
                                            try {
                                              debugPrint(
                                                "💾 Saving updated mentor data to Firestore...",
                                              );

                                              final mentorRef =
                                                  FirebaseFirestore.instance
                                                      .collection('mentors')
                                                      .doc(mentors[index].id);

                                              try {
                                                // 1️⃣ Get the old assigned list
                                                final oldDoc =
                                                    await mentorRef.get();
                                                final oldAssigned =
                                                    (oldDoc.data()?['assigned']
                                                        as List<dynamic>?) ??
                                                    [];

                                                // 2️⃣ Build keys like "2027-A" to compare
                                                final oldKeys =
                                                    oldAssigned
                                                        .map(
                                                          (e) =>
                                                              "${e['batch']}-${e['section']}",
                                                        )
                                                        .toSet();
                                                final newKeys =
                                                    assignedList
                                                        .map(
                                                          (e) =>
                                                              "${e['batch']}-${e['section']}",
                                                        )
                                                        .toSet();

                                                // 3️⃣ Find removed keys
                                                final removedKeys = oldKeys
                                                    .difference(newKeys);

                                                // 4️⃣ Start a Firestore batch
                                                final batch =
                                                    FirebaseFirestore.instance
                                                        .batch();

                                                // 5️⃣ Update mentor's details + new assigned list
                                                batch.update(mentorRef, {
                                                  'name':
                                                      nameController.text
                                                          .trim(),
                                                  'userId':
                                                      userIdController.text
                                                          .trim(),
                                                  'password':
                                                      passwordController.text
                                                          .trim(),
                                                  'assigned': assignedList,
                                                });

                                                // 6️⃣ Delete only removed assignedStudents docs
                                                for (final key in removedKeys) {
                                                  final docRef = mentorRef
                                                      .collection(
                                                        'assignedStudents',
                                                      )
                                                      .doc(key);
                                                  batch.delete(docRef);
                                                }

                                                // 7️⃣ Commit the batch (atomic operation)
                                                await batch.commit();

                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.check_circle,
                                                          color: Colors.white,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text(
                                                          "Mentor updated successfully",
                                                        ),
                                                      ],
                                                    ),
                                                    backgroundColor:
                                                        Colors.green,
                                                    duration: Duration(
                                                      seconds: 2,
                                                    ),
                                                  ),
                                                );
                                              } catch (e) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      "Failed to update mentor: $e",
                                                    ),
                                                  ),
                                                );
                                              }

                                              debugPrint(
                                                "✅ Mentor updated successfully in Firestore.",
                                              );
                                            } catch (e, stack) {
                                              debugPrint(
                                                "❌ Error updating mentor in Firestore: $e",
                                              );
                                              debugPrint("$stack");
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    "Failed to update mentor: $e",
                                                  ),
                                                ),
                                              );
                                            }
                                          } else {
                                            debugPrint(
                                              "🛑 Edit dialog cancelled, no update performed.",
                                            );
                                          }
                                        } catch (e, stack) {
                                          debugPrint(
                                            "❌ Error while opening or processing edit dialog: $e",
                                          );
                                          debugPrint("$stack");
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text("Error: $e"),
                                            ),
                                          );
                                        }
                                      },
                                    ),

                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      tooltip: "Delete",
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder:
                                              (_) => AlertDialog(
                                                title: const Text(
                                                  "Confirm Delete",
                                                ),
                                                content: const Text(
                                                  "Are you sure you want to delete this mentor?",
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text("Cancel"),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                    child: const Text(
                                                      "Delete",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                        );

                                        if (confirm == true) {
                                          final messenger =
                                              ScaffoldMessenger.of(context);

                                          try {
                                            final mentorRef = FirebaseFirestore
                                                .instance
                                                .collection('mentors')
                                                .doc(mentors[index].id);

                                            // 1️⃣ Get all assigned students for this mentor
                                            final assignedStudentsSnap =
                                                await mentorRef
                                                    .collection(
                                                      'assignedStudents',
                                                    )
                                                    .get();

                                            // 2️⃣ Delete each assigned student doc
                                            for (var doc
                                                in assignedStudentsSnap.docs) {
                                              await doc.reference.delete();
                                            }

                                            // 3️⃣ Delete the mentor doc itself
                                            await mentorRef.delete();

                                            messenger.showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.red,
                                                content: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .delete_forever_outlined,
                                                      color: Colors.white,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      "Mentor deleted successfully!",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          } catch (e) {
                                            debugPrint(
                                              "❌ Error deleting mentor: $e",
                                            );

                                            messenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: Colors.red,
                                                content: Text(
                                                  "Failed to delete mentor: $e",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                duration: const Duration(
                                                  seconds: 2,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
