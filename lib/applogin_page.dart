import 'package:flutter/material.dart';

class AppLoginPage extends StatefulWidget {
  const AppLoginPage({super.key});

  @override
  State<AppLoginPage> createState() => _AppLoginPageState();
}

class _AppLoginPageState extends State<AppLoginPage> {
  final List<Map<String, dynamic>> loginAccessList = [
    {
      "username": "scanner_user1",
      "role": "Scanner",
      "password": "123456",
      "isActive": true,
    },
    {
      "username": "scanner_user2",
      "role": "Scanner",
      "password": "654321",
      "isActive": false,
    },
  ];

  void _showAddLoginDialog({Map<String, dynamic>? existingUser, int? index}) {
    final usernameController = TextEditingController(
      text: existingUser?["username"] ?? "",
    );
    final passwordController = TextEditingController(
      text: existingUser?["password"] ?? "",
    );
    bool isPasswordVisible = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                existingUser == null ? "Add Login Access" : "Edit Login Access",
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: "Username",
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: "Password",
                      //prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      prefixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed:
                            () => setModalState(
                              () => isPasswordVisible = !isPasswordVisible,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      if (existingUser == null) {
                        loginAccessList.add({
                          "username": usernameController.text,
                          "password": passwordController.text,
                          "role": "Scanner",
                          "isActive": true,
                        });
                      } else if (index != null) {
                        loginAccessList[index]["username"] =
                            usernameController.text;
                        loginAccessList[index]["password"] =
                            passwordController.text;
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text("Confirm Delete"),
            content: Text(
              "Are you sure you want to delete '${loginAccessList[index]["username"]}'?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    loginAccessList.removeAt(index);
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, int index) {
    final DateTime date =
        user["updatedAt"] ?? user["createdAt"] ?? DateTime.now();
    final formattedDate =
        "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: const Icon(Icons.person, color: Colors.blue),
        ),
        title: Text(
          user["username"],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(user["role"]),
                const SizedBox(width: 10),
                Chip(
                  label: Text(user["isActive"] ? "Active" : "Inactive"),
                  backgroundColor:
                      user["isActive"]
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                  labelStyle: TextStyle(
                    color:
                        user["isActive"]
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Updated: $formattedDate",
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: "Edit",
              icon: const Icon(Icons.edit, color: Colors.grey),
              onPressed:
                  () => _showAddLoginDialog(existingUser: user, index: index),
            ),
            IconButton(
              tooltip: "Delete",
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDelete(index),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Manage App Logins Section
            Expanded(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Manage App Logins",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => _showAddLoginDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text("Add Login Access"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            // Available Logins Section
            Expanded(
              flex: 2,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Available Logins",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child:
                            loginAccessList.isEmpty
                                ? Center(
                                  child: Text(
                                    "No login accounts available.\nClick 'Add Login Access' to create one.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                                : ListView.builder(
                                  itemCount: loginAccessList.length,
                                  itemBuilder:
                                      (context, index) => _buildUserCard(
                                        loginAccessList[index],
                                        index,
                                      ),
                                ),
                      ),
                    ],
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
