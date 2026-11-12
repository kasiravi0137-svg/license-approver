import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

// --------------------------------------------------------------------
// LICENSE APPROVER (with push notifications, nicknames, revoke, delete
// and an access-level choice)
//
// 1. On startup, this app asks for notification permission, gets its
//    FCM device token, and saves it to Firestore at
//    device_tokens/approver so your Windows app (or whatever sends the
//    notification) knows where to send it.
// 2. Your Windows app creates a document in "activation_requests" with
//    status "pending", then sends a push notification to that token.
// 3. This app shows the notification even when closed. Tapping it (or
//    just opening the app) shows the request with Approve/Reject.
// 4. Before approving, you choose an access level for that device --
//    "Scripts only" or "With data check" -- saved as accessLevel on
//    the same document. You can change it later from an approved card.
// 5. Approved devices can be given a nickname, revoked, or deleted
//    (once rejected) -- revoking sets status back to "rejected", which
//    the Windows app's background watchdog picks up within seconds.
// --------------------------------------------------------------------

const String kScriptsOnly = 'scripts_only';
const String kWithData = 'with_data';

String accessLabel(String? level) =>
    level == kWithData ? 'With data check' : 'Scripts only';

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

class RequestCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const RequestCard({super.key, required this.docId, required this.data});

  @override
  State<RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<RequestCard> {
  // Which access level is selected in the picker before approving a
  // pending request. Defaults to the safer "Scripts only".
  late String _pendingChoice;

  @override
  void initState() {
    super.initState();
    _pendingChoice = (widget.data['accessLevel'] as String?) ?? kScriptsOnly;
  }

  String get docId => widget.docId;
  Map<String, dynamic> get data => widget.data;
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('activation_requests');

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

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _approve() async {
    await _col.doc(docId).update({
      'status': 'approved',
      'accessLevel': _pendingChoice,
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _reject() async {
    await _col.doc(docId).update({
      'status': 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
    });
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
    await _col.doc(docId).update({'nickname': newName});
  }

  // Lets the admin change an already-approved device's access level
  // later, without touching its status.
  Future<void> _changeAccessLevel(BuildContext context) async {
    var choice = (data['accessLevel'] as String?) ?? kScriptsOnly;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Access level'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: kScriptsOnly,
                groupValue: choice,
                title: const Text('Scripts only'),
                subtitle: const Text('Compare & generate scripts. No data checking.'),
                onChanged: (v) => setDialogState(() => choice = v!),
              ),
              RadioListTile<String>(
                value: kWithData,
                groupValue: choice,
                title: const Text('With data check'),
                subtitle: const Text('Also allowed to check/compare table data.'),
                onChanged: (v) => setDialogState(() => choice = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, choice), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await _col.doc(docId).update({'accessLevel': saved});
  }

  Future<void> _revoke(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text(
          'This will lock out "${(data['nickname'] ?? '') as String != '' ? data['nickname'] : 'this device'}". '
          'It will stop working within a few seconds.',
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
    await _col.doc(docId).update({
      'status': 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this request?'),
        content: const Text('This removes it from the list permanently. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _col.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending') as String;
    final machineId = (data['machineId'] ?? 'unknown') as String;
    final appName = (data['appName'] ?? 'Unknown app') as String;
    final nickname = (data['nickname'] ?? '') as String;
    final accessLevel = data['accessLevel'] as String?;
    final ts = data['createdAt'];
    String whenText = '';
    if (ts is Timestamp) {
      whenText = DateFormat('dd MMM, hh:mm a').format(ts.toDate());
    }

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
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status),
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

            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Text('Allow this device to',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _AccessChoiceTile(
                      selected: _pendingChoice == kScriptsOnly,
                      icon: Icons.description_outlined,
                      label: 'Scripts only',
                      desc: 'Compare & generate scripts.\nNo data checking.',
                      onTap: () => setState(() => _pendingChoice = kScriptsOnly),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AccessChoiceTile(
                      selected: _pendingChoice == kWithData,
                      icon: Icons.search,
                      label: 'With data check',
                      desc: 'Also allowed to check\n/compare table data.',
                      onTap: () => setState(() => _pendingChoice = kWithData),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _approve,
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ] else if (status == 'approved') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text('Access level', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                      accessLabel(accessLevel),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _changeAccessLevel(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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
            ] else if (status == 'rejected')
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: () => _delete(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessChoiceTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String desc;
  final VoidCallback onTap;

  const _AccessChoiceTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: 1.5),
          borderRadius: BorderRadius.circular(10),
          color: selected ? color.withOpacity(0.08) : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? color : Colors.grey.shade600),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : null,
                )),
            const SizedBox(height: 2),
            Text(desc,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
