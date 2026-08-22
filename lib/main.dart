import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import 'presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Paleta de colores del sistema de diseño
    const Color primaryColor = Color(0xFF58774B);
    const Color lightPrimary = Color(0xFF7A9B6C);
    const Color backgroundColor = Color(0xFFFAF6EA);
    const Color secondaryColor = Color(0xFF787D7D);
    const Color textColor = Color(0xFF2B2B2B);
    const Color errorColor = Color(0xFFC0392B);

    return MaterialApp(
      title: 'SmartMoney',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.poppins().fontFamily,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          surfaceTint: Colors.transparent,
        ).copyWith(
          primary: primaryColor,
          secondary: lightPrimary,
          surface: Colors.white,
          surfaceContainerHighest: backgroundColor,
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
          headlineLarge: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 26,
          ),
          headlineMedium: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
          titleLarge: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          bodyLarge: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w400,
            fontSize: 16,
          ),
          bodyMedium: GoogleFonts.poppins(
            color: textColor,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          bodySmall: GoogleFonts.poppins(
            color: secondaryColor,
            fontWeight: FontWeight.w400,
            fontSize: 12,
          ),
          labelLarge: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryColor, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: errorColor, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: errorColor, width: 1.5),
          ),
          labelStyle: GoogleFonts.poppins(
            color: secondaryColor,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          hintStyle: GoogleFonts.poppins(
            color: secondaryColor,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
