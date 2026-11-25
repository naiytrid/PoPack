import 'package:flutter/material.dart';
import '../core.dart';
import '../widgets.dart';
import 'home_shell.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    notifs.load();
    myProfile().then((p) {
      if (mounted) setState(() => isAdmin = p?['role'] == 'admin');
    });
  }

  (IconData, Color) _look(String t) => switch (t) {
        'order_new' => (Icons.receipt_long_outlined, navy),
        'cancel_request' => (Icons.undo_rounded, const Color(0xFFEA580C)),
        'approved' => (Icons.check_circle_outline, const Color(0xFF16A34A)),
        'rejected' => (Icons.block_outlined, const Color(0xFFDC2626)),
        'cancelled' => (Icons.cancel_outlined, const Color(0xFFDC2626)),
        'cancel_rejected' => (Icons.info_outline, const Color(0xFFF59E0B)),
        _ => (Icons.notifications_outlined, muted),
      };

  String _ago(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final s = DateTime.now().difference(d);
    if (s.inMinutes < 1) return 'Baru saja';
    if (s.inMinutes < 60) return '${s.inMinutes} menit lalu';
    if (s.inHours < 24) return '${s.inHours} jam lalu';
    if (s.inDays < 7) return '${s.inDays} hari lalu';
    return d.toString().substring(0, 10);
  }

  void _open(Map<String, dynamic> n) {
    notifs.markRead(n['id'] as int);
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (isAdmin) {
      HomeShell.adminTab.value = 1; // tab Pesanan
    } else {
      HomeShell.tab.value = 3; // tab Akun (daftar pesanan)
    }
  }

  Widget _tile(Map<String, dynamic> n) {
    final (icon, color) = _look('${n['type']}');
    final unread = n['read'] != true;
    return Material(
      color: unread ? const Color(0x0AE53935) : Colors.white,
      child: InkWell(
        onTap: () => _open(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['title']}', style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14.5)),
                if ((n['body'] ?? '').toString().isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text('${n['body']}', style: const TextStyle(color: muted, fontSize: 13, height: 1.35))),
                const SizedBox(height: 4),
                Text(_ago(n['created_at'] as String?), style: const TextStyle(color: muted, fontSize: 11.5)),
              ]),
            ),
            if (unread)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 8),
                child: CircleAvatar(radius: 4, backgroundColor: brand),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifikasi'),
          centerTitle: false,
          actions: [
            ListenableBuilder(
              listenable: notifs,
              builder: (_, __) => TextButton(
                onPressed: notifs.unread == 0 ? null : notifs.markAllRead,
                child: const Text('Tandai semua dibaca', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: notifs,
              builder: (_, __) {
                final l = notifs.items;
                if (l.isEmpty) {
                  return const EmptyState(Icons.notifications_none, 'Belum ada notifikasi', sub: 'Info pesanan akan muncul di sini');
                }
                return RefreshIndicator(
                  onRefresh: notifs.load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: l.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: line),
                    itemBuilder: (_, i) => _tile(l[i]),
                  ),
                );
              },
            ),
          ),
        ),
      );
}