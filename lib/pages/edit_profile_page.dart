import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic>? p;
  final bool isAdmin;
  const EditProfilePage({super.key, this.p, this.isAdmin = false});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.p?['full_name'] ?? '');
  late final company = TextEditingController(text: widget.p?['company'] ?? '');
  late final phone = TextEditingController(text: widget.p?['phone'] ?? '');
  late String? avatarUrl = widget.p?['avatar_url'];
  Uint8List? picked; // foto baru (belum diunggah)
  String? pickedMime;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    company.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final f = await ImagePicker().pickImage(source: src, imageQuality: 80, maxWidth: 800);
      if (f == null) return;
      final b = await f.readAsBytes();
      setState(() {
        picked = b;
        pickedMime = f.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      if (mounted) toast(context, 'Tidak bisa membuka foto: $e');
    }
  }

  void _photoMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pilih dari galeri'),
            onTap: () {
              Navigator.pop(c);
              _pick(ImageSource.gallery);
            },
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto'),
              onTap: () {
                Navigator.pop(c);
                _pick(ImageSource.camera);
              },
            ),
          if (picked != null || (avatarUrl ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Hapus foto', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  picked = null;
                  avatarUrl = null;
                });
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      var url = avatarUrl;
      if (picked != null) {
        final uid = sb.auth.currentUser!.id;
        final ext = (pickedMime ?? 'image/jpeg').split('/').last.replaceAll('jpeg', 'jpg');
        final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await sb.storage.from('avatars').uploadBinary(path, picked!, fileOptions: FileOptions(contentType: pickedMime ?? 'image/jpeg'));
        url = sb.storage.from('avatars').getPublicUrl(path);
      }
      await sb.rpc('update_my_profile', params: {
        'new_name': name.text.trim(),
        'new_company': widget.isAdmin ? '${widget.p?['company'] ?? ''}' : company.text.trim(),
        'new_phone': phone.text.trim(),
        'new_avatar': url,
      });
      if (mounted) {
        toast(context, 'Profil diperbarui');
        Navigator.pop(context, true);
      }
    } on StorageException catch (e) {
      if (mounted) toast(context, 'Gagal unggah foto: ${e.message}');
    } on PostgrestException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _avatar() {
    final nm = name.text.trim();
    final email = sb.auth.currentUser?.email ?? '';
    final initial = (nm.isNotEmpty ? nm : (email.isEmpty ? '?' : email))[0].toUpperCase();
    ImageProvider? img;
    if (picked != null) {
      img = MemoryImage(picked!);
    } else if ((avatarUrl ?? '').isNotEmpty) {
      img = NetworkImage(avatarUrl!);
    }
    return Center(
      child: GestureDetector(
        onTap: saving ? null : _photoMenu,
        child: Stack(children: [
          CircleAvatar(
            radius: 54,
            backgroundColor: const Color(0x1AE53935),
            backgroundImage: img,
            child: img == null ? Text(initial, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: brand)) : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: brand, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
              child: const Icon(Icons.photo_camera, size: 18, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _d(String l, IconData i) => InputDecoration(
        labelText: l,
        prefixIcon: Icon(i, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: brand, width: 1.5)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit Profil'), centerTitle: false),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: key,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                _avatar(),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(onPressed: saving ? null : _photoMenu, child: const Text('Ubah foto', style: TextStyle(color: brand, fontWeight: FontWeight.w700))),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: _d('Nama lengkap', Icons.person_outline),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: 14),
                if (!widget.isAdmin) ...[
                  TextFormField(controller: company, decoration: _d('Perusahaan', Icons.business_outlined)),
                  const SizedBox(height: 14),
                ],
                TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: _d('No. HP', Icons.phone_outlined)),
                const SizedBox(height: 14),
                TextFormField(
                  enabled: false,
                  initialValue: sb.auth.currentUser?.email ?? '',
                  decoration: _d('Email', Icons.mail_outline).copyWith(helperText: 'Email tidak bisa diubah'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50), backgroundColor: brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: saving ? null : _save,
                  child: saving
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Simpan', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      );
}