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

  late final List<Widget> _paginas = [
    HomeScreen(key: _homeScreenKey),
    const IaScreen(),
    const EducacionFinancieraScreen(),
    const IngresoMontosScreen(),
    const MetasScreen(),
    const PerfilScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
            onDestinationSelected: (i) {
              final cambioDePestana = i != _index;
              if (!cambioDePestana) return;
              setState(() => _index = i);
              if (i == 0) {
                _homeScreenKey.currentState?.cargarTransacciones();
              }
            },
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
