import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';

Future<bool> requireLogin(BuildContext c) async {
  if (sb.auth.currentUser != null) return true;
  await Navigator.push(c, MaterialPageRoute(builder: (_) => const AuthPage()));
  return sb.auth.currentUser != null;
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  bool login = true, busy = false, hide = true;
  final email = TextEditingController(), pass = TextEditingController();
  final name = TextEditingController(), company = TextEditingController(), phone = TextEditingController();

  @override
  void dispose() {
    for (final c in [email, pass, name, company, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String _msg(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'Email atau password salah';
    if (s.contains('already registered')) return 'Email sudah terdaftar, silakan masuk';
    if (s.contains('rate limit')) return 'Terlalu banyak percobaan, coba lagi nanti';
    if (s.contains('password')) return 'Password minimal 8 karakter';
    return m;
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (login) {
        await sb.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
        if (mounted) Navigator.pop(context);
      } else {
        final res = await sb.auth.signUp(email: email.text.trim(), password: pass.text, data: {
          'full_name': name.text.trim(),
          'company': company.text.trim(),
          'phone': phone.text.trim(),
        });
        if (!mounted) return;
        if (res.session != null) {
          toast(context, 'Pendaftaran berhasil, selamat datang!');
          Navigator.pop(context);
        } else {
          toast(context, 'Pendaftaran berhasil. Silakan masuk.');
          setState(() => login = true);
        }
      }
    } on AuthException catch (e) {
      if (mounted) toast(context, _msg(e.message));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool pw = false, TextInputType? k, String? Function(String?)? v}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        obscureText: pw && hide,
        keyboardType: k,
        validator: v ?? (x) => (x == null || x.trim().isEmpty) ? '$label wajib diisi' : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: pw
              ? IconButton(
                  icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => hide = !hide))
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: _border(line),
          focusedBorder: _border(brand, 1.5),
          errorBorder: _border(Colors.red.shade400),
          focusedErrorBorder: _border(Colors.red.shade400, 1.5),
        ),
      ),
    );
  }

  Widget _tab(String t, bool selected, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: selected ? brand : line, width: selected ? 2 : 1))),
            child: Text(t,
                style: TextStyle(fontWeight: FontWeight.w700, color: selected ? brand : muted, fontSize: 14.5)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: bg, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Brand
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Image.asset('assets/images/logo.png', height: 36),
                  const SizedBox(width: 10),
                  const Text('PoPack', style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 20),
                // Card
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: line),
                    boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: Form(
                    key: form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        _tab('Masuk', login, () => setState(() => login = true)),
                        _tab('Daftar', !login, () => setState(() => login = false)),
                      ]),
                      const SizedBox(height: 22),
                      Text(login ? 'Selamat datang kembali' : 'Buat akun baru',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                      const SizedBox(height: 4),
                      Text(
                          login
                              ? 'Masuk untuk memesan kemasan dan memantau status pesanan Anda.'
                              : 'Daftarkan perusahaan Anda untuk mulai memesan kemasan.',
                          style: const TextStyle(color: muted, height: 1.4, fontSize: 13.5)),
                      const SizedBox(height: 20),
                      if (!login) ...[
                        _field(name, 'Nama lengkap', Icons.person_outline),
                        _field(company, 'Perusahaan', Icons.business_outlined),
                        _field(phone, 'No. HP', Icons.phone_outlined, k: TextInputType.phone),
                      ],
                      _field(email, 'Email', Icons.mail_outline, k: TextInputType.emailAddress, v: (x) {
                        final t = x?.trim() ?? '';
                        if (t.isEmpty) return 'Email wajib diisi';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Format email tidak valid';
                        return null;
                      }),
                      _field(pass, login ? 'Password' : 'Password (minimal 8 karakter)', Icons.lock_outline, pw: true, v: (x) {
                        if (x == null || x.isEmpty) return 'Password wajib diisi';
                        if (x.length < 8) return 'Password minimal 8 karakter';
                        return null;
                      }),
                      const SizedBox(height: 4),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: brand,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Text(login ? 'Masuk' : 'Daftar', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(login ? 'Belum punya akun? ' : 'Sudah punya akun? ', style: const TextStyle(color: muted, fontSize: 13.5)),
                          GestureDetector(
                            onTap: () => setState(() => login = !login),
                            child: Text(login ? 'Daftar' : 'Masuk', style: const TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 13.5)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_outline, size: 14, color: muted),
                  SizedBox(width: 6),
                  Text('Data Anda tersimpan dengan aman', style: TextStyle(color: muted, fontSize: 12.5)),
                ]),
              ]),
            ),
          ),
        ),
      );
}