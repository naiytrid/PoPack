import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// GANTI dengan punya lu (Supabase > Project Settings > API Keys). Pakai publishable/anon key, BUKAN secret/service_role.
const supabaseUrl = 'https://kjklvkahyombnarcjhuk.supabase.co';
const supabaseAnonKey = 'sb_publishable_6m1Jm7ZegYeFHBe5YByohg_lKn9syPI';

final sb = Supabase.instance.client;

// Warna
const brand = Color(0xFFE53935);
const brandDark = Color(0xFFB71C1C);
const amber = Color(0xFFFFB300);
const navy = Color(0xFF1F3A8A);
const ink = Color(0xFF1B1D29);
const muted = Color(0xFF6B7280);
const bg = Color(0xFFF5F6F8);
const line = Color(0xFFE5E7EB);

const cardShadow = [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 4))];
BoxDecoration cardDeco([double r = 12]) =>
    BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r), border: Border.all(color: line));
const headerGradient = LinearGradient(colors: [brand, brandDark], begin: Alignment.topLeft, end: Alignment.bottomRight);
const imgGradient = LinearGradient(colors: [Color(0xFFFFC53D), Color(0xFFF9A825)], begin: Alignment.topLeft, end: Alignment.bottomRight);

/// Angka dengan titik ribuan: 5000 -> 5.000
String nf(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String rp(num n) => 'IDR ${nf(n)}';

const statusLabel = {
  'pending': 'Diajukan',
  'approved': 'Dipesan',
  'processing': 'Diproses',
  'completed': 'Selesai',
  'cancel_requested': 'Menunggu persetujuan batal',
  'cancelled': 'Dibatalkan',
  'rejected': 'Ditolak',
};
Color statusColor(String s) => switch (s) {
      'pending' => const Color(0xFFF59E0B),
      'approved' => const Color(0xFF2563EB),
      'processing' => const Color(0xFF7C3AED),
      'completed' => const Color(0xFF16A34A),
      'cancel_requested' => const Color(0xFFEA580C),
      _ => const Color(0xFFDC2626),
    };

IconData catIcon(String n) {
  final s = n.toLowerCase();
  if (s.contains('pharma') || s.contains('lab')) return Icons.science_outlined;
  if (s.contains('medical')) return Icons.medical_services_outlined;
  if (s.contains('cosmetic') || s.contains('health')) return Icons.spa_outlined;
  if (s.contains('food')) return Icons.restaurant_outlined;
  if (s.contains('fashion')) return Icons.checkroom_outlined;
  return Icons.category_outlined;
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

Future<Map<String, dynamic>?> myProfile() async {
  final u = sb.auth.currentUser;
  if (u == null) return null;
  return await sb.from('profiles').select().eq('id', u.id).maybeSingle();
}

// ================= PRODUK =================

/// Satu jenis produk (mis. Wrapped / Unwrapped) dengan harga & minimal order sendiri.
class Tier {
  final int minQty;
  final num price;
  const Tier(this.minQty, this.price);
}

class Variant {
  final String id, name;
  final num price; // harga tier pertama
  final int minOrder; // jumlah tier pertama
  final List<Tier> tiers;
  const Variant(this.id, this.name, this.price, this.minOrder, [this.tiers = const []]);

  factory Variant.fromMap(Map m) {
    final t = [
      for (final e in ((m['variant_price_tiers'] as List?) ?? const [])) Tier((e['min_qty'] as num).toInt(), e['price'] as num)
    ]..sort((a, b) => a.minQty.compareTo(b.minQty));
    return Variant(
      '${m['id']}',
      '${m['name']}',
      t.isEmpty ? m['price'] as num : t.first.price,
      t.isEmpty ? ((m['min_order'] as num?) ?? 1).toInt() : t.first.minQty,
      t,
    );
  }

  /// Harga per pcs sesuai jumlah beli
  num priceFor(int qty) {
    num p = price;
    for (final t in tiers) {
      if (qty >= t.minQty) p = t.price;
    }
    return p;
  }
}

List<Variant> _variantsOf(Map m) {
  final raw = [...((m['product_variants'] as List?) ?? const [])]
    ..sort((a, b) => ((a['position'] ?? 0) as num).compareTo((b['position'] ?? 0) as num));
  if (raw.isEmpty) return [Variant('', '${m['name']}', m['price'] as num, 1)]; // cadangan untuk data lama
  return [for (final e in raw) Variant.fromMap(e as Map)];
}

List<String> _imagesOf(Map m) {
  final raw = [...((m['product_images'] as List?) ?? const [])]
    ..sort((a, b) => ((a['position'] ?? 0) as num).compareTo((b['position'] ?? 0) as num));
  final l = [for (final e in raw) '${e['url']}'];
  final legacy = m['image_url'];
  if (l.isEmpty && legacy is String && legacy.isNotEmpty) l.add(legacy);
  return l;
}

class Product {
  final String id, name;
  final num price; // harga terendah dari semua varian ("mulai dari")
  final int? stock, categoryId;
  final num? weight;
  final String? desc;
  final bool active;
  final List<Variant> variants;
  final List<String> images;
  Product.fromMap(Map m)
      : id = m['id'],
        name = m['name'],
        stock = m['stock'],
        weight = m['weight_gr'],
        desc = m['description'],
        categoryId = m['category_id'],
        active = m['is_active'] ?? true,
        variants = _variantsOf(m),
        images = _imagesOf(m),
        price = _variantsOf(m).map((v) => v.price).reduce((a, b) => a < b ? a : b);
  String? get image => images.isEmpty ? null : images.first;
  bool get hasVariants => variants.length > 1;
  bool get ready => stock == null || stock! > 0;
}

class CartItem {
  final Product p;
  final Variant v;
  int qty;
  CartItem(this.p, this.v, this.qty);
  String get key => '${p.id}|${v.id}';
}

class Cart extends ChangeNotifier {
  final items = <String, CartItem>{};
  RealtimeChannel? _ch;
  String? _uid;
  Timer? _deb;
  DateTime _lastWrite = DateTime(2000);

  /// Langkah tombol +/-: 1000 untuk order besar, 1 untuk order kecil.
  static int stepOf(Variant v) => v.minOrder >= 1000 ? 1000 : 1;

  int _clamp(CartItem i, int q) {
    var n = q < i.v.minOrder ? i.v.minOrder : q;
    final s = i.p.stock;
    if (s != null && n > s) n = s;
    return n;
  }

  // ---------- muat dari database ----------
  Future<void> load() async {
    final u = sb.auth.currentUser;
    if (u == null) {
      _stop();
      items.clear();
      notifyListeners();
      return;
    }
    if (u.id == _uid && _ch != null) return; // akun sama & sudah mendengarkan
    _uid = u.id;
    await _pull();
    _listen(u.id);
  }

  Future<void> _pull() async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    try {
      final rows = await sb.from('cart_items').select('product_id,variant_id,qty').eq('user_id', u.id) as List;
      final fresh = <String, CartItem>{};
      if (rows.isNotEmpty) {
        final ids = {for (final e in rows) '${e['product_id']}'}.toList();
        final res = await sb.from('products').select(_productSelect).inFilter('id', ids).eq('is_active', true) as List;
        final prods = {for (final e in res) '${e['id']}': Product.fromMap(e as Map)};
        for (final e in rows) {
          final pr = prods['${e['product_id']}'];
          if (pr == null) continue; // produk sudah dihapus / nonaktif
          final v = pr.variants.firstWhere((x) => x.id == '${e['variant_id']}', orElse: () => pr.variants.first);
          final it = CartItem(pr, v, 0);
          it.qty = _clamp(it, (e['qty'] as num).toInt());
          fresh[it.key] = it;
        }
      }
      items
        ..clear()
        ..addAll(fresh);
    } catch (e) {
      debugPrint('CART ERROR: $e');
    }
    notifyListeners();
  }

  void _listen(String uid) {
    _stop();
    _uid = uid;
    _ch = sb
        .channel('cart-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cart_items',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) {
            // abaikan "gema" dari perubahan yang baru kita tulis sendiri
            if (DateTime.now().difference(_lastWrite) < const Duration(milliseconds: 1500)) return;
            _deb?.cancel();
            _deb = Timer(const Duration(milliseconds: 400), _pull);
          },
        )
        .subscribe();
  }

  void _stop() {
    final c = _ch;
    if (c != null) sb.removeChannel(c);
    _ch = null;
    _uid = null;
  }

  // ---------- tulis ke database (UI sudah berubah duluan) ----------
  Future<void> _upsert(CartItem i) async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    _lastWrite = DateTime.now();
    try {
      await sb.from('cart_items').upsert(
        {'user_id': u.id, 'product_id': i.p.id, 'variant_id': i.v.id, 'qty': i.qty, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'user_id,product_id,variant_id',
      );
    } catch (e) {
      debugPrint('CART ERROR: $e');
    }
  }

  Future<void> _del(String productId, String variantId) async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    _lastWrite = DateTime.now();
    try {
      await sb.from('cart_items').delete().eq('user_id', u.id).eq('product_id', productId).eq('variant_id', variantId);
    } catch (e) {
      debugPrint('CART ERROR: $e');
    }
  }

  Future<void> _delAll() async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    _lastWrite = DateTime.now();
    try {
      await sb.from('cart_items').delete().eq('user_id', u.id);
    } catch (e) {
      debugPrint('CART ERROR: $e');
    }
  }

  // ---------- operasi keranjang ----------
  void add(Product p, Variant v, [int? qty]) {
    final k = '${p.id}|${v.id}';
    final it = items[k] ?? CartItem(p, v, 0);
    it.qty = _clamp(it, it.qty + (qty ?? v.minOrder));
    items[k] = it;
    notifyListeners();
    _upsert(it);
  }

  void setQty(CartItem i, int q) {
    i.qty = _clamp(i, q);
    notifyListeners();
    _upsert(i);
  }

  void inc(CartItem i) => setQty(i, i.qty + stepOf(i.v));
  void dec(CartItem i) => setQty(i, i.qty - stepOf(i.v));

  void remove(String key) {
    final it = items.remove(key);
    notifyListeners();
    if (it != null) _del(it.p.id, it.v.id);
  }

  void clear() {
    items.clear();
    notifyListeners();
    _delAll();
  }

  /// Jumlah baris di keranjang (untuk badge)
  int get count => items.length;

  /// Total pcs
  int get pcs => items.values.fold<int>(0, (a, i) => a + i.qty);
  num get total => items.values.fold<num>(0, (a, i) => a + i.v.priceFor(i.qty) * i.qty);
}

final cart = Cart();

// ================= FAVORIT =================

class Favs extends ChangeNotifier {
  Set<String> ids = {};
  bool has(String id) => ids.contains(id);

  Future<void> load() async {
    debugPrint('CART load, user=${sb.auth.currentUser?.id}');
    if (sb.auth.currentUser == null) {
      ids = {};
      notifyListeners();
      return;
    }
    try {
      final r = await sb.from('favorites').select('product_id');
      ids = {for (final e in r as List) '${e['product_id']}'};
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle(String pid) async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    final was = ids.contains(pid);
    was ? ids.remove(pid) : ids.add(pid);
    notifyListeners();
    try {
      if (was) {
        await sb.from('favorites').delete().eq('user_id', u.id).eq('product_id', pid);
      } else {
        await sb.from('favorites').insert({'user_id': u.id, 'product_id': pid});
      }
    } catch (_) {
      was ? ids.add(pid) : ids.remove(pid);
      notifyListeners();
    }
  }
}

final favs = Favs();

/// Produk favorit dipindah ke paling atas (urutan lain tetap).
List<Product> favFirst(List<Product> l) => [...l.where((p) => favs.has(p.id)), ...l.where((p) => !favs.has(p.id))];

// ================= AUTO RELOAD =================

/// Mendengarkan perubahan database (Supabase Realtime). Halaman cukup
/// `sync.addListener(...)` lalu memuat ulang datanya. Ada juga cadangan polling 60 detik.
class DataSync extends ChangeNotifier {
  RealtimeChannel? _ch;
  Timer? _debounce;
  Timer? _poll; // ignore: unused_field

  void start() {
    if (_ch != null) return;
    var c = sb.channel('db-sync');
    for (final t in ['products', 'product_variants', 'product_images', 'categories', 'orders', 'profiles']) {
      c = c.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => _bump());
    }
    _ch = c.subscribe();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _bump());
  }

  void _bump() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), notifyListeners);
  }
}

final sync = DataSync();

const _productSelect = '*, product_images(url,position), product_variants(id,name,price,min_order,position,variant_price_tiers(min_qty,price))';

// Ambil semua produk aktif sekali, lalu difilter di aplikasi (pencarian instan)
Future<List<Product>> fetchProducts() async {
  final r = await sb.from('products').select(_productSelect).eq('is_active', true).order('created_at', ascending: false);
  return (r as List).map<Product>((e) => Product.fromMap(e)).toList();
}

/// Untuk halaman admin (semua produk, termasuk nonaktif)
Future<List> fetchAdminProducts() async =>
    await sb.from('products').select(_productSelect).order('created_at', ascending: false);

// Cocok jika SEMUA kata yang diketik ada di nama/deskripsi/jenis produk
bool matchProduct(Product p, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return true;
  final hay = '${p.name} ${p.desc ?? ''} ${p.variants.map((v) => v.name).join(' ')}'.toLowerCase();
  return t.split(RegExp(r'\s+')).every(hay.contains);
}

bool authLocked = false; // true saat membuat akun admin, supaya HomeShell tidak reset tab

// ================= NOTIFIKASI =================

class Notifs extends ChangeNotifier {
  List<Map<String, dynamic>> items = [];
  RealtimeChannel? _ch;
  String? _uid;

  int get unread => items.where((e) => e['read'] != true).length;

  Future<void> load() async {
    final u = sb.auth.currentUser;
    if (u == null) {
      _stop();
      items = [];
      notifyListeners();
      return;
    }
    try {
      final r = await sb.from('notifications').select().eq('user_id', u.id).order('created_at', ascending: false).limit(50);
      items = [for (final e in (r as List)) Map<String, dynamic>.from(e as Map)];
    } catch (_) {}
    notifyListeners();
    _listen(u.id);
  }

  void _listen(String uid) {
    if (_uid == uid && _ch != null) return;
    _stop();
    _uid = uid;
    _ch = sb
        .channel('notif-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => load(),
        )
        .subscribe();
  }

  void _stop() {
    final c = _ch;
    if (c != null) sb.removeChannel(c);
    _ch = null;
    _uid = null;
  }

  Future<void> markRead(int id) async {
    final i = items.indexWhere((e) => e['id'] == id);
    if (i < 0 || items[i]['read'] == true) return;
    items[i]['read'] = true; // langsung berubah di layar
    notifyListeners();
    try {
      await sb.from('notifications').update({'read': true}).eq('id', id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final u = sb.auth.currentUser;
    if (u == null || unread == 0) return;
    for (final e in items) {
      e['read'] = true;
    }
    notifyListeners();
    try {
      await sb.from('notifications').update({'read': true}).eq('user_id', u.id).eq('read', false);
    } catch (_) {}
  }
}

final notifs = Notifs();