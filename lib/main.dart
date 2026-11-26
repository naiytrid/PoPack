import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core.dart';
import 'pages/home_shell.dart';
import 'fx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  sync.start();
  favs.load();
  notifs.load();
  cart.load();
  sb.auth.onAuthStateChange.listen((_) {
    favs.load();
    notifs.load();
    cart.load();
  });
  runApp(const PoPackApp());
}

class PoPackApp extends StatelessWidget {
  const PoPackApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PoPack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: brand),
          scaffoldBackgroundColor: bg,
          splashFactory: InkSparkle.splashFactory,        
          pageTransitionsTheme: fxPageTransitionsTheme,   
          appBarTheme: const AppBarTheme(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            foregroundColor: ink,
            titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        home: const HomeShell(),
      );
}