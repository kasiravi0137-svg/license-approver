import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

// --------------------------------------------------------------------
// LICENSE APPROVER (with push notifications, nicknames and revoke)
//
// 1. On startup, this app asks for notification permission, gets its
//    FCM device token, and saves it to Firestore at
//    device_tokens/approver so your Windows app (or whatever sends the
//    notification) knows where to send it.
// 2. Your Windows app creates a document in "activation_requests" with
//    status "pending", then sends a push notification to that token.
// 3. This app shows the notification even when closed. Tapping it (or
//    just opening the app) shows the request with Approve/Reject.
// 4. Approved devices can be given a nickname and revoked later --
//    revoking sets status back to "rejected", which the Windows app's
//    background watchdog picks up within a couple of minutes.
// --------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required top-level handler for background/terminated-state messages.
  // Firebase shows the system notification automatically when the
  // message has a "notification" payload; nothing else to do here.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
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
  void initState() {
    super.initState();
    _setUpPushNotifications();
  }

  Future<void> _setUpPushNotifications() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    Future<void> saveToken(String? token) async {
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection('device_tokens')
          .doc('approver')
          .set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await saveToken(await messaging.getToken());
    messaging.onTokenRefresh.listen(saveToken);
  }

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

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: (data['nickname'] ?? '') as String);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Office PC'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    final col = FirebaseFirestore.instance.collection('activation_requests');
    await col.doc(docId).update({'nickname': newName});
  }

  Future<void> _revoke(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text(
          'This will lock out "${(data['nickname'] ?? '') as String != '' ? data['nickname'] : 'this device'}". '
          'It will stop working within a couple of minutes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final col = FirebaseFirestore.instance.collection('activation_requests');
    await col.doc(docId).update({
      'status': 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending') as String;
    final machineId = (data['machineId'] ?? 'unknown') as String;
    final appName = (data['appName'] ?? 'Unknown app') as String;
    final nickname = (data['nickname'] ?? '') as String;
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
                    nickname.isNotEmpty ? nickname : 'Unnamed device',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontStyle: nickname.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                      color: nickname.isNotEmpty ? null : Colors.grey,
                    ),
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
            const SizedBox(height: 4),
            Text(appName, style: Theme.of(context).textTheme.bodySmall),
            Text('Machine ID: $machineId',
                style: Theme.of(context).textTheme.bodySmall),
            if (whenText.isNotEmpty)
              Text(whenText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (status == 'pending')
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
              )
            else if (status == 'approved')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rename(context),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Rename'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () => _revoke(context),
                      child: const Text('Revoke'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
