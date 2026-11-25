import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';

class _TRow {
  final min = TextEditingController();
  final price = TextEditingController();
  _TRow({int? m, num? p}) {
    min.text = m == null ? '' : '$m';
    price.text = p == null ? '' : p.round().toString();
  }
  void dispose() {
    min.dispose();
    price.dispose();
  }
}

class _VRow {
  String? id; // null = jenis baru
  bool open = true;
  final name = TextEditingController();
  final List<_TRow> tiers;
  _VRow({this.id, String? n, List<Tier>? t}) : tiers = [for (final x in (t ?? const <Tier>[])) _TRow(m: x.minQty, p: x.price)] {
    name.text = n ?? '';
    if (tiers.isEmpty) tiers.add(_TRow());
  }
  void dispose() {
    name.dispose();
    for (final t in tiers) {
      t.dispose();
    }
  }
}

/// Halaman tambah/edit produk. Mengembalikan Map data produk + 'images' + 'variants'.
class ProductForm extends StatefulWidget {
  final Product? p;
  final List cats;
  const ProductForm({super.key, this.p, required this.cats});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.p?.name);
  late final stock = TextEditingController(text: widget.p?.stock?.toString());
  late final weight = TextEditingController(text: widget.p?.weight?.toString());
  late final desc = TextEditingController(text: widget.p?.desc);
  late int? cat = widget.p?.categoryId;
  late bool active = widget.p?.active ?? true;
  late final List<String> imgs = [...?widget.p?.images];
  late final List<_VRow> rows = _initRows();
  bool uploading = false;
  String? err;

  List<_VRow> _initRows() {
    final p = widget.p;
    if (p == null) return [_VRow()];
    final l = [
      for (final v in p.variants)
        _VRow(id: v.id.isEmpty ? null : v.id, n: v.name, t: v.tiers.isEmpty ? [Tier(v.minOrder, v.price)] : v.tiers)
    ];
    for (var i = 1; i < l.length; i++) {
      l[i].open = false; // jenis ke-2 dst. dilipat dulu
    }
    return l;
  }

  @override
  void dispose() {
    for (final c in [name, stock, weight, desc]) {
      c.dispose();
    }
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  InputDecoration _d(String l, {String? hint}) => InputDecoration(
        labelText: l,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;
  String? _optNum(String? v) => (v == null || v.trim().isEmpty || num.tryParse(v.trim()) != null) ? null : 'Harus angka';

  Widget _card(String title, Widget child, {String? hint}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          if (hint != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: const TextStyle(color: muted, fontSize: 12.5, height: 1.35))),
          const SizedBox(height: 14),
          child,
        ]),
      );

  // ---------- gambar ----------
  Future<void> _pick() async {
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1600);
    } catch (e) {
      setState(() => err = 'Tidak bisa membuka galeri: $e');
      return;
    }
    if (files.isEmpty) return;
    setState(() {
      uploading = true;
      err = null;
    });
    try {
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'jpg';
        final path = '${DateTime.now().microsecondsSinceEpoch}_${imgs.length}.$ext';
        await sb.storage
            .from('product-images')
            .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: f.mimeType ?? 'image/${ext == 'jpg' ? 'jpeg' : ext}'));
        imgs.add(sb.storage.from('product-images').getPublicUrl(path));
      }
    } on StorageException catch (e) {
      err = 'Gagal unggah: ${e.message}';
    } catch (e) {
      err = 'Gagal unggah: $e';
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _addUrl() async {
    final c = TextEditingController();
    final u = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Tambah gambar dari URL'),
        content: TextField(controller: c, autofocus: true, decoration: _d('URL gambar', hint: 'https://...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: brand), onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Tambah')),
        ],
      ),
    );
    c.dispose();
    if (u != null && u.startsWith('http') && !imgs.contains(u)) setState(() => imgs.add(u));
  }

  Widget _imageThumb(int i) => Container(
        key: ValueKey(imgs[i]),
        width: 84,
        height: 84,
        margin: const EdgeInsets.only(right: 8),
        child: Stack(children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imgs[i], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: bg, child: const Icon(Icons.broken_image_outlined, color: muted))),
            ),
          ),
          if (i == 0)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(10)),
                child: const Text('Sampul', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: InkWell(
              onTap: () => setState(() => imgs.removeAt(i)),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ]),
      );

  Widget _imageSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imgs.isEmpty && !uploading)
          Container(
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: const Text('Belum ada gambar', style: TextStyle(color: muted, fontSize: 13)),
          ),
        if (imgs.isNotEmpty)
          SizedBox(
            height: 84,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: true,
              itemCount: imgs.length,
              onReorderItem: (a, b) => setState(() {
                imgs.insert(b, imgs.removeAt(a));
              }),
              itemBuilder: (_, i) => _imageThumb(i),
            ),
          ),
        if (uploading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(color: brand)),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: brand, side: const BorderSide(color: brand)),
            onPressed: uploading ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Pilih gambar'),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: uploading ? null : _addUrl, child: const Text('Dari URL')),
        ]),
      ]);

  // ---------- harga & jenis ----------
  Widget _tierEditor(_VRow r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var k = 0; k < r.tiers.length; k++)
          Padding(
            key: ObjectKey(r.tiers[k]),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: r.tiers[k].min,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _d('Mulai (pcs)'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1) return 'Min. 1';
                    final dup = r.tiers.where((t) => t.min.text.trim() == v!.trim()).length > 1;
                    return dup ? 'Duplikat' : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: r.tiers[k].price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _d('Harga / pcs'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v == null || num.tryParse(v.trim()) == null) ? 'Isi angka' : null,
                ),
              ),
              if (r.tiers.length > 1)
                IconButton(
                  tooltip: 'Hapus tier',
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () => setState(() => r.tiers.removeAt(k)),
                ),
            ]),
          ),
        TextButton.icon(
          onPressed: () => setState(() => r.tiers.add(_TRow())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Tambah tier harga'),
        ),
      ]);

  void _addRow() => setState(() {
        if (rows.length > 1) {
          for (final r in rows) {
            r.open = false;
          }
        }
        rows.add(_VRow());
      });

  Widget _variantCard(int i) {
    final r = rows[i];
    final title = r.name.text.trim().isEmpty ? 'Jenis ${i + 1}' : r.name.text.trim();
    final first = r.tiers.isNotEmpty ? num.tryParse(r.tiers.first.price.text.trim()) : null;
    return Container(
      key: ObjectKey(r),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => r.open = !r.open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${r.tiers.length} tier${first != null ? '  •  mulai ${rp(first)}' : ''}', style: const TextStyle(color: muted, fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: 'Hapus jenis',
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => setState(() => rows.removeAt(i)),
              ),
              Icon(r.open ? Icons.expand_less : Icons.expand_more, color: muted),
              const SizedBox(width: 8),
            ]),
          ),
        ),
        if (r.open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: r.name,
                decoration: _d('Nama jenis', hint: 'mis. Wrapped'),
                onChanged: (_) => setState(() {}),
                validator: _req,
              ),
              const SizedBox(height: 14),
              _tierEditor(r),
            ]),
          ),
      ]),
    );
  }

  Widget _variants() {
    final addBtn = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _addRow,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Tambah jenis lain (mis. Wrapped / Unwrapped)'),
      ),
    );
    if (rows.length == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _tierEditor(rows.first),
        const Divider(height: 20, color: line),
        addBtn,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < rows.length; i++) _variantCard(i),
      addBtn,
    ]);
  }

  // ---------- simpan ----------
  bool _rowOk(_VRow r) {
    if (rows.length > 1 && r.name.text.trim().isEmpty) return false;
    final mins = <int>{};
    for (final t in r.tiers) {
      final m = int.tryParse(t.min.text.trim());
      final p = num.tryParse(t.price.text.trim());
      if (m == null || m < 1 || p == null || !mins.add(m)) return false;
    }
    return true;
  }

  void _save() {
    if (uploading) return;
    // jenis yang sedang dilipat tapi isinya belum benar: buka supaya error terlihat
    final bad = rows.where((r) => !_rowOk(r)).toList();
    if (bad.isNotEmpty) {
      setState(() {
        for (final r in bad) {
          r.open = true;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => key.currentState?.validate());
      return;
    }
    if (!key.currentState!.validate()) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final vs = <Map<String, dynamic>>[
      for (final r in rows)
        () {
          final tiers = [
            for (final t in r.tiers) {'min_qty': int.parse(t.min.text.trim()), 'price': num.parse(t.price.text.trim())}
          ]..sort((a, b) => (a['min_qty'] as int).compareTo(b['min_qty'] as int));
          return <String, dynamic>{
            if (r.id != null) 'id': r.id,
            'name': r.name.text.trim().isEmpty ? name.text.trim() : r.name.text.trim(),
            'price': tiers.first['price'],
            'min_order': tiers.first['min_qty'],
            'tiers': tiers,
          };
        }()
    ];
    Navigator.pop(context, <String, dynamic>{
      'name': name.text.trim(),
      'stock': stock.text.trim().isEmpty ? null : int.parse(stock.text.trim()),
      'weight_gr': weight.text.trim().isEmpty ? null : num.parse(weight.text.trim()),
      'description': t(desc),
      'category_id': cat,
      'is_active': active,
      'images': [...imgs],
      'variants': vs,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.p == null ? 'Tambah Produk' : 'Edit Produk'), centerTitle: false),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: key,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                _card(
                  'Informasi dasar',
                  Column(children: [
                    TextFormField(controller: name, decoration: _d('Nama produk'), validator: _req),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: cat,
                      isExpanded: true,
                      decoration: _d('Kategori'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Tanpa kategori')),
                        for (final c in widget.cats) DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'])),
                      ],
                      onChanged: (v) => setState(() => cat = v),
                    ),
                  ]),
                ),
                _card('Foto produk', _imageSection(), hint: 'Gambar pertama jadi sampul. Tahan & geser untuk mengubah urutan.'),
                _card('Harga & jenis', _variants(), hint: 'Tier pertama = minimal order. Tambah tier untuk harga lebih murah di jumlah lebih besar.'),
                _card(
                  'Stok & detail',
                  Column(children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: TextFormField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration: _d('Stok'),
                          validator: (v) => (v == null || v.trim().isEmpty || int.tryParse(v.trim()) != null) ? null : 'Bilangan bulat',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: weight, keyboardType: TextInputType.number, decoration: _d('Berat (gram)'), validator: _optNum)),
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(controller: desc, maxLines: 3, decoration: _d('Deskripsi (opsional)')),
                    const SizedBox(height: 4),
                    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tampilkan di toko'), value: active, onChanged: (v) => setState(() => active = v)),
                  ]),
                  hint: 'Kosongkan stok jika tak terbatas.',
                ),
              ]),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: cardShadow),
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50), backgroundColor: brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: uploading ? null : _save,
              child: const Text('Simpan', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
}