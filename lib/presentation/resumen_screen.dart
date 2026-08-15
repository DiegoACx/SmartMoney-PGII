import 'package:flutter/material.dart';
import '../data/transacciones_repository.dart';
import '../logic/finanzas_logic.dart';

class ResumenScreen extends StatefulWidget {
  const ResumenScreen({super.key});

  @override
  State<ResumenScreen> createState() => _ResumenScreenState();
}

class _ResumenScreenState extends State<ResumenScreen> {
  final _repository = TransaccionesRepository();
  final _logic = FinanzasLogic();

  double? _totalNeto;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    // La UI no sabe cómo se calcula ni de dónde vienen los datos,
    // solo pide el dato ya calculado a la capa logic.
    final transacciones = await _repository.obtenerTransacciones();
    final total = _logic.calcularTotalNeto(transacciones);

    setState(() {
      _totalNeto = total;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen financiero')),
      body: Center(
        child: _cargando
            ? const CircularProgressIndicator()
            : Text(
                'Total neto: \$${_totalNeto?.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 24),
              ),
      ),
    );
  }
}