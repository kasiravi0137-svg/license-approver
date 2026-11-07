import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LicenseApproverApp());
}

class LicenseApproverApp extends StatelessWidget {
  const LicenseApproverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'License Approver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RequestsPage(),
    );
  }
}

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final _col = FirebaseFirestore.instance.collection('activation_requests');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activation requests')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No activation requests yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              return RequestCard(docId: doc.id, data: data);
            },
          );
        },
      ),
    );
  }
}

class RequestCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  const RequestCard({super.key, required this.docId, required this.data});

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status, BuildContext context) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending') as String;
    final machineId = (data['machineId'] ?? 'unknown') as String;
    final appName = (data['appName'] ?? 'Unknown app') as String;
    final userLabel = (data['userLabel'] ?? '') as String;
    final ts = data['createdAt'];
    String whenText = '';
    if (ts is Timestamp) {
      whenText = DateFormat('dd MMM, hh:mm a').format(ts.toDate());
    }

    final col = FirebaseFirestore.instance.collection('activation_requests');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status, context).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status, context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Machine ID: $machineId',
                style: Theme.of(context).textTheme.bodySmall),
            if (userLabel.isNotEmpty)
              Text('From: $userLabel',
                  style: Theme.of(context).textTheme.bodySmall),
            if (whenText.isNotEmpty)
              Text(whenText, style: Theme.of(context).textTheme.bodySmall),
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => col.doc(docId).update({
                        'status': 'rejected',
                        'decidedAt': FieldValue.serverTimestamp(),
                      }),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => col.doc(docId).update({
                        'status': 'approved',
                        'decidedAt': FieldValue.serverTimestamp(),
                      }),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
