import 'package:flutter/material.dart';

import '../logic/auth_logic.dart';
import '../logic/recorrido_logic.dart';
import '../services/preferencias_service.dart';
import 'educacion_financiera_screen.dart';
import 'home_screen.dart';
import 'ia_screen.dart';
import 'ingreso_montos_screen.dart';
import 'metas_screen.dart';
import 'perfil_screen.dart';
import 'widgets/boton_asistente.dart';
import 'widgets/recorrido_guiado.dart';

/// Shell principal de la app: Scaffold con BottomNavigationBar de 6 tabs
/// y IndexedStack para mantener estado de cada pestaña.
///
/// También orquesta dos experiencias transversales:
/// - el globo periódico del asistente (una sola sesión para toda la app), y
/// - el recorrido guiado de bienvenida (una vez por usuario).
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

  final _authLogic = AuthLogic();
  final _preferencias = PreferenciasService();

  /// Estado del globo del asistente, compartido por todas las pestañas.
  final _asistente = AsistenteSesion();

  /// Estado del recorrido guiado.
  final _recorrido = RecorridoLogic();

  // Claves de los elementos que el recorrido puede resaltar.
  final _resumenKey = GlobalKey();
  final _navbarKey = GlobalKey();
  final _fabKey = GlobalKey();

  /// Una clave por ítem de la barra inferior, en el orden de las pestañas.
  /// El recorrido las usa para medir cada pestaña (ícono y texto) con su
  /// propio `RenderBox` y ajustar el recorte exactamente a ella.
  final List<GlobalKey> _destinosKeys = List.generate(6, (_) => GlobalKey());

  /// Evita consultar el "ya visto" más de una vez por sesión.
  bool _recorridoComprobado = false;

  late final List<Widget> _paginas = [
    HomeScreen(
      key: _homeScreenKey,
      onCambiarPestana: _irAPestana,
      claveResumen: _resumenKey,
      claveBotonAsistente: _fabKey,
      onCargadoInicial: _comprobarRecorrido,
    ),
    IaScreen(onCambiarPestana: _irAPestana),
    EducacionFinancieraScreen(
      key: _educacionScreenKey,
      onCambiarPestana: _irAPestana,
    ),
    IngresoMontosScreen(onCambiarPestana: _irAPestana),
    MetasScreen(onCambiarPestana: _irAPestana),
    PerfilScreen(
      key: _perfilScreenKey,
      onCambiarPestana: _irAPestana,
      onVerRecorrido: _verRecorridoDesdePerfil,
    ),
  ];

  Map<String, GlobalKey> get _clavesRecorrido => {
        'resumen': _resumenKey,
        'navbar': _navbarKey,
        'fab': _fabKey,
      };

  @override
  void initState() {
    super.initState();
    // El globo solo se calla cuando el recorrido está activo, el teclado está
    // abierto o hay una ruta encima (diálogo o hoja inferior).
    _asistente.permitido = _puedeMostrarGlobo;
    _asistente.activar();
  }

  @override
  void dispose() {
    _asistente.dispose();
    _recorrido.dispose();
    super.dispose();
  }

  bool _puedeMostrarGlobo() {
    if (_recorrido.visible) return false;
    if (!mounted) return false;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return false;
    final ruta = ModalRoute.of(context);
    if (ruta != null && !ruta.isCurrent) return false;
    return true;
  }

  /// Cambia de pestaña desde el `NavigationBar` o desde el propio contenido
  /// (por ejemplo las recomendaciones del Dashboard).
  void _irAPestana(int i) {
    if (i < 0 || i >= _paginas.length) return;
    final cambioDePestana = i != _index;
    if (!cambioDePestana) return;
    setState(() => _index = i);
    _asistente.cambiarPestana(i);
    if (i == 0) {
      _homeScreenKey.currentState?.cargarTransacciones();
    } else if (i == 2) {
      _educacionScreenKey.currentState?.recargarYCentrar();
    } else if (i == 5) {
      _perfilScreenKey.currentState?.recargar();
    }
  }

  // ===== Recorrido guiado =====

  /// Se ejecuta cuando el Inicio ya cargó su contenido. Muestra el recorrido
  /// la primera vez que el usuario entra a la app.
  Future<void> _comprobarRecorrido() async {
    if (_recorridoComprobado) return;
    _recorridoComprobado = true;

    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;

    final visto = await _preferencias.leerRecorridoVisto(usuarioId);
    if (!mounted || visto) return;
    _abrirRecorrido();
  }

  void _abrirRecorrido() {
    _recorrido.iniciar();
    _asistente.pausar();
  }

  /// Muestra el recorrido a pedido del usuario desde el Perfil.
  void _verRecorridoDesdePerfil() {
    if (_index != 0) _irAPestana(0);
    _abrirRecorrido();
  }

  Future<void> _marcarRecorridoVisto() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;
    await _preferencias.guardarRecorridoVisto(usuarioId, true);
  }

  /// Cierra el recorrido sin terminar (botón "Saltar" o botón atrás).
  void _cerrarRecorrido() {
    _recorrido.saltar();
    _marcarRecorridoVisto();
    _asistente.reanudar();
  }

  /// Cierra el recorrido al terminarlo y lleva al usuario a registrar su
  /// primer movimiento (pestaña Ingresos).
  void _finalizarRecorrido() {
    _recorrido.finalizar();
    _marcarRecorridoVisto();
    _asistente.reanudar();
    _irAPestana(3);
  }

  @override
  Widget build(BuildContext context) {
    // Etiquetas de la barra en una sola línea: con 6 pestañas a 360 px cada
    // una dispone de ~60 px, por lo que se reduce el tamaño de letra (y se
    // quita el espaciado entre caracteres heredado de M3) para que "Educación"
    // no se parta en dos líneas.
    final baseLabelStyle = Theme.of(context).textTheme.labelMedium ??
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

    return ListenableBuilder(
      listenable: _recorrido,
      builder: (context, _) => AsistenteScope(
        sesion: _asistente,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PopScope(
              // Mientras el recorrido está visible, el botón atrás lo cierra
              // (equivale a "Saltar") en lugar de salir de la app.
              canPop: !_recorrido.visible,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _cerrarRecorrido();
              },
              child: Scaffold(
                body: IndexedStack(
                  index: _index,
                  children: _paginas,
                ),
                bottomNavigationBar: Container(
                  key: _navbarKey,
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
                        final seleccionado =
                            states.contains(WidgetState.selected);
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
                      destinations: [
                        NavigationDestination(
                          key: _destinosKeys[0],
                          icon: const Icon(Icons.home_outlined),
                          selectedIcon: const Icon(Icons.home),
                          label: 'Inicio',
                        ),
                        NavigationDestination(
                          key: _destinosKeys[1],
                          icon: const Icon(Icons.auto_awesome_outlined),
                          selectedIcon: const Icon(Icons.auto_awesome),
                          label: 'IA',
                        ),
                        NavigationDestination(
                          key: _destinosKeys[2],
                          icon: const Icon(Icons.school_outlined),
                          selectedIcon: const Icon(Icons.school),
                          label: 'Educación',
                        ),
                        NavigationDestination(
                          key: _destinosKeys[3],
                          icon: const Icon(Icons.swap_horiz_outlined),
                          selectedIcon: const Icon(Icons.swap_horiz),
                          label: 'Ingresos',
                        ),
                        NavigationDestination(
                          key: _destinosKeys[4],
                          icon: const Icon(Icons.flag_outlined),
                          selectedIcon: const Icon(Icons.flag),
                          label: 'Metas',
                        ),
                        NavigationDestination(
                          key: _destinosKeys[5],
                          icon: const Icon(Icons.person_outlined),
                          selectedIcon: const Icon(Icons.person),
                          label: 'Perfil',
                        ),
                      ],
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                    ),
                  ),
                ),
              ),
            ),
            if (_recorrido.visible)
              Positioned.fill(
                child: RecorridoGuiado(
                  paso: _recorrido.paso,
                  pasoActual: _recorrido.pasoActual,
                  totalPasos: _recorrido.totalPasos,
                  claves: _clavesRecorrido,
                  clavesDestinos: _destinosKeys,
                  onAnterior: _recorrido.retroceder,
                  onSiguiente: _recorrido.siguiente,
                  onSaltar: _cerrarRecorrido,
                  onFinalizar: _finalizarRecorrido,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
