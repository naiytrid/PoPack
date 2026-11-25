import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';
import '../widgets.dart';
import 'auth_page.dart';
import 'edit_profile_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final StreamSubscription _sub;
  void _onSync() => mounted ? setState(() {}) : null; // auto reload
  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((_) => mounted ? setState(() {}) : null);
    sync.addListener(_onSync);
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    _sub.cancel();
    super.dispose();
  }

  Future<(Map<String, dynamic>?, List)> _load() async {
    final p = await myProfile();
    // Admin tidak berbelanja, jadi tidak perlu memuat pesanan pribadi
    final List o = p?['role'] == 'admin'
        ? []
        : await sb
            .from('orders')
            .select('id,status,created_at,order_items(qty,price,variant_name,products(name))')
            .eq('user_id', sb.auth.currentUser!.id)
            .order('created_at', ascending: false);
    return (p, o);
  }

  Future<void> _cancel(String id) async {
    try {
      await sb.rpc('request_cancel', params: {'oid': id});
      if (mounted) toast(context, 'Pengajuan batal dikirim, menunggu persetujuan admin');
    } on PostgrestException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit(Map<String, dynamic>? p, bool isAdmin) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(p: p, isAdmin: isAdmin)),
    );
    if (ok == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (sb.auth.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Akun')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: cardShadow),
                child: const Icon(Icons.person_outline, size: 52, color: brand)),
            const SizedBox(height: 16),
            const Text('Belum masuk', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: brand, minimumSize: const Size(220, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage())),
                child: const Text('Masuk / Daftar')),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Akun'), centerTitle: false, automaticallyImplyLeading: false),
      body: FutureBuilder(
        future: _load(),
        builder: (_, s) {
          if (s.hasError) return Center(child: Text('Gagal memuat: ${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final (p, orders) = s.data!;
          final isAdmin = p?['role'] == 'admin';
          final nama = _s(p?['full_name']);
          final email = sb.auth.currentUser!.email ?? '';
          final initial = (nama ?? (email.isEmpty ? '?' : email))[0].toUpperCase();
          final blocked = p?['status'] == 'rejected';
          final created = _s(p?['created_at']);
          final rows = <Widget>[
            if (_s(p?['company']) != null && !isAdmin) _infoRow(Icons.business_outlined, 'Perusahaan', _s(p?['company'])!),
            if (_s(p?['phone']) != null) _infoRow(Icons.phone_outlined, 'No. HP', _s(p?['phone'])!),
            if (created != null && created.length >= 10) _infoRow(Icons.event_outlined, 'Bergabung', created.substring(0, 10)),
          ];
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  // Kartu profil
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(20),
                    decoration: cardDeco(14),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0x1AE53935),
                        backgroundImage: _s(p?['avatar_url']) != null ? NetworkImage(_s(p?['avatar_url'])!) : null,
                        child: _s(p?['avatar_url']) != null
                            ? null
                            : Text(initial, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: brand)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(nama ?? 'Pengguna', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                          const SizedBox(height: 2),
                          Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 13)),
                          const SizedBox(height: 8),
                          isAdmin
                              ? _pill('Administrator', navy)
                              : (blocked ? _pill('Diblokir', Colors.red) : _pill('Akun aktif', const Color(0xFF16A34A))),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Edit profil',
                        icon: const Icon(Icons.edit_outlined, color: muted),
                        onPressed: () => _edit(p, isAdmin),
                      ),
                    ]),
                  ),
                  if (blocked)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                      child: const Text('Akun Anda diblokir. Hubungi admin untuk informasi lebih lanjut.', style: TextStyle(fontSize: 13)),
                    ),
                  // Informasi akun
                  if (rows.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      decoration: cardDeco(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Informasi akun', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 4),
                        for (var k = 0; k < rows.length; k++) ...[if (k > 0) const Divider(height: 1, color: line), rows[k]],
                      ]),
                    ),
                  // Pesanan (khusus pelanggan)
                  if (!isAdmin) ...[
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
                        child: Text('Pesanan Saya (${orders.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    if (orders.isEmpty)
                      const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada pesanan', style: TextStyle(color: muted)))),
                    for (final o in orders)
                      OrderCard(o: o, actions: [
                        if (o['status'] == 'pending' || o['status'] == 'approved')
                          TextButton(onPressed: () => _cancel(o['id']), child: const Text('Ajukan Batal', style: TextStyle(color: Colors.red))),
                      ]),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: brand,
                          side: const BorderSide(color: brand),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Keluar dari akun?'),
                            content: const Text('Anda harus masuk lagi untuk melanjutkan.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (ok == true) await sb.auth.signOut();
                      },
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _s(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _infoRow(IconData i, String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(i, size: 19, color: muted),
          const SizedBox(width: 12),
          Text(l, style: const TextStyle(color: muted, fontSize: 13.5)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
        ]),
      );
}