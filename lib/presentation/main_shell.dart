import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'ia_screen.dart';
import 'educacion_financiera_screen.dart';
import 'ingreso_montos_screen.dart';
import 'metas_screen.dart';
import 'perfil_screen.dart';

/// Shell principal de la app: Scaffold con BottomNavigationBar de 6 tabs
/// y IndexedStack para mantener estado de cada pestaña.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _homeScreenKey = GlobalKey<HomeScreenState>();
  final _educacionScreenKey = GlobalKey<EducacionFinancieraScreenState>();
  final _perfilScreenKey = GlobalKey<PerfilScreenState>();

  late final List<Widget> _paginas = [
    HomeScreen(key: _homeScreenKey, onCambiarPestana: _irAPestana),
    IaScreen(onCambiarPestana: _irAPestana),
    EducacionFinancieraScreen(
      key: _educacionScreenKey,
      onCambiarPestana: _irAPestana,
    ),
    IngresoMontosScreen(onCambiarPestana: _irAPestana),
    MetasScreen(onCambiarPestana: _irAPestana),
    PerfilScreen(key: _perfilScreenKey, onCambiarPestana: _irAPestana),
  ];

  /// Cambia de pestaña desde el `NavigationBar` o desde el propio contenido
  /// (por ejemplo las recomendaciones del Dashboard).
  void _irAPestana(int i) {
    if (i < 0 || i >= _paginas.length) return;
    final cambioDePestana = i != _index;
    if (!cambioDePestana) return;
    setState(() => _index = i);
    if (i == 0) {
      _homeScreenKey.currentState?.cargarTransacciones();
    } else if (i == 2) {
      _educacionScreenKey.currentState?.recargarYCentrar();
    } else if (i == 5) {
      _perfilScreenKey.currentState?.recargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Etiquetas de la barra en una sola línea: con 6 pestañas a 360 px cada
    // una dispone de ~60 px, por lo que se reduce el tamaño de letra (y se
    // quita el espaciado entre caracteres heredado de M3) para que "Educación"
    // no se parta en dos líneas.
    final baseLabelStyle = Theme.of(context).textTheme.labelMedium ??
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _paginas,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 64,
            selectedIndex: _index,
            backgroundColor: Colors.white,
            indicatorColor:
                const Color(0xFF58774B).withValues(alpha: 0.12),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final seleccionado = states.contains(WidgetState.selected);
              return baseLabelStyle.copyWith(
                fontSize: 10,
                letterSpacing: 0,
                fontWeight: FontWeight.w600,
                color: seleccionado
                    ? const Color(0xFF2B2B2B)
                    : const Color(0xFF8C8474),
              );
            }),
            onDestinationSelected: _irAPestana,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'IA',
              ),
              NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: 'Educación',
              ),
              NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz),
                label: 'Ingresos',
              ),
              NavigationDestination(
                icon: Icon(Icons.flag_outlined),
                selectedIcon: Icon(Icons.flag),
                label: 'Metas',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outlined),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
        ),
      ),
    );
  }
}
