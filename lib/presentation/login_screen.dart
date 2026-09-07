import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../logic/auth_logic.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';

class _CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    final firstControl = Offset(size.width * 0.25, size.height + 20);
    final firstEnd = Offset(size.width * 0.5, size.height - 30);
    path.quadraticBezierTo(
      firstControl.dx,
      firstControl.dy,
      firstEnd.dx,
      firstEnd.dy,
    );
    final secondControl = Offset(size.width * 0.75, size.height - 80);
    final secondEnd = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
      secondControl.dx,
      secondControl.dy,
      secondEnd.dx,
      secondEnd.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();
  bool _obscureContrasena = true;
  bool _isLoading = false;

  final _auth = AuthLogic();

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await _auth.iniciarSesion(
      correo: _correoController.text.trim(),
      contrasena: _contrasenaController.text,
    );

    if (!mounted) return;

    if (error == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ===== Encabezado decorativo =====
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.25,
                width: double.infinity,
                child: ClipPath(
                  clipper: _CurvedHeaderClipper(),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF58774B),
                          Color(0xFF7A9B6C),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'SmartMoney',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ===== Contenido del formulario =====
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título y subtítulo
                    Text(
                      'Bienvenido de nuevo',
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ingresa a tu cuenta para continuar',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF8C8474),
                      ),
                    ),
                    const SizedBox(height: 32),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Campo correo
                          Material(
                            elevation: 1,
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.transparent,
                            child: TextFormField(
                              controller: _correoController,
                              keyboardType: TextInputType.emailAddress,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ingresa tu correo';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: 'Correo electrónico',
                                prefixIcon: const Icon(
                                  Icons.email_outlined,
                                  color: Color(0xFFC9C2B0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Campo contraseña
                          Material(
                            elevation: 1,
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.transparent,
                            child: TextFormField(
                              controller: _contrasenaController,
                              obscureText: _obscureContrasena,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFFC9C2B0),
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscureContrasena = !_obscureContrasena;
                                    });
                                  },
                                  icon: Icon(
                                    _obscureContrasena
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: const Color(0xFFC9C2B0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Enlace ¿Olvidaste tu contraseña?
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF58774B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ===== Botón principal =====
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF58774B),
                              Color(0xFF7A9B6C),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Iniciar sesión',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ===== Enlace a registro =====
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                );
                              },
                        child: RichText(
                          text: TextSpan(
                            text: '¿No tienes cuenta? ',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF8C8474),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: 'Regístrate',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF58774B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
