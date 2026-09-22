import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/formato_utils.dart';
import '../../logic/metas_logic.dart';
import '../../services/notificaciones_service.dart';
import '../registro_meta_screen.dart';

Future<void> mostrarOpcionesMeta({
  required BuildContext context,
  required Map<String, dynamic> meta,
  required VoidCallback onRecargar,
}) async {
  final nombre = meta['nombre'].toString();
  final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
  final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();
  final montoStr =
      '${FormatoUtils.moneda.format(montoActual)} de ${FormatoUtils.moneda.format(montoObjetivo)}';

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFFAF6EA),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9C2B0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              nombre,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              montoStr,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF58774B),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF58774B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF58774B),
                ),
              ),
              title: Text(
                'Editar',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RegistroMetaScreen(metaExistente: meta),
                  ),
                );
                if (result == true && context.mounted) {
                  onRecargar();
                }
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF58774B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.attach_money,
                  color: Color(0xFF58774B),
                ),
              ),
              title: Text(
                'Registrar aporte o retiro',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _mostrarDialogMovimiento(
                  context: context,
                  meta: meta,
                  onRecargar: onRecargar,
                );
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFC0392B),
                ),
              ),
              title: Text(
                'Eliminar',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) {
                    return AlertDialog(
                      backgroundColor: const Color(0xFFFAF6EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: Text(
                        '¿Eliminar meta?',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      content: Text(
                        'Esta acción no se puede deshacer.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF8C8474),
                        ),
                      ),
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogCtx, false),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    foregroundColor: const Color(0xFF8C8474),
                                  ),
                                  child: Text(
                                    'Cancelar',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogCtx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFC0392B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Eliminar',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      actionsPadding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    );
                  },
                );
                if (confirmar != true || !context.mounted) return;
                final logic = MetasLogic();
                final notificaciones = NotificacionesService();
                final metaId = meta['id'].toString();
                final error = await logic.eliminarMeta(metaId);
                await notificaciones.cancelarRecordatorio(metaId);
                if (!context.mounted) return;
                if (error == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Meta eliminada'),
                      backgroundColor: const Color(0xFF7A9B6C),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  onRecargar();
                } else {
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
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

Future<void> _mostrarDialogMovimiento({
  required BuildContext context,
  required Map<String, dynamic> meta,
  required VoidCallback onRecargar,
}) async {
  final montoController = TextEditingController();
  String? tipoSeleccionado;
  String? errorTipo;
  String? errorMonto;
  bool procesando = false;

  final mensajeResultado = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFAF6EA),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Registrar movimiento',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'Aporte',
                        label: Text('Aporte'),
                        icon: Icon(Icons.arrow_upward, color: Color(0xFF58774B)),
                      ),
                      ButtonSegment<String>(
                        value: 'Retiro',
                        label: Text('Retiro'),
                        icon: Icon(Icons.arrow_downward, color: Color(0xFFC0392B)),
                      ),
                    ],
                    selected: {
                      if (tipoSeleccionado != null) tipoSeleccionado!,
                    },
                    emptySelectionAllowed: true,
                    onSelectionChanged: (newSelection) {
                      setDialogState(() {
                        tipoSeleccionado =
                            newSelection.isEmpty ? null : newSelection.first;
                        errorTipo = null;
                      });
                    },
                  ),
                  if (errorTipo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        errorTipo!,
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFC0392B),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: montoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      MilesInputFormatter(),
                    ],
                    onChanged: (_) {
                      if (errorMonto != null) {
                        setDialogState(() => errorMonto = null);
                      }
                    },
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF2B2B2B),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Monto',
                      errorText: errorMonto,
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: const Icon(
                        Icons.attach_money,
                        color: Color(0xFFC9C2B0),
                      ),
                      border: const UnderlineInputBorder(),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFC9C2B0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: procesando
                            ? null
                            : () => Navigator.pop(dialogCtx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: const Color(0xFF8C8474),
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: procesando
                            ? null
                            : () async {
                                bool valido = true;
                                if (tipoSeleccionado == null) {
                                  setDialogState(
                                    () => errorTipo = 'Selecciona un tipo de movimiento',
                                  );
                                  valido = false;
                                }
                                final digitsOnly = montoController.text
                                    .trim()
                                    .replaceAll(RegExp(r'[^0-9]'), '');
                                final n = double.tryParse(digitsOnly);
                                if (n == null || n <= 0) {
                                  setDialogState(
                                    () => errorMonto = 'Ingresa un monto mayor a 0',
                                  );
                                  valido = false;
                                }
                                if (tipoSeleccionado == 'Retiro') {
                                  final montoActualDeLaMeta =
                                      (meta['monto_actual'] as num?)?.toDouble() ?? 0;
                                  if (n! > montoActualDeLaMeta) {
                                    setDialogState(() {
                                      errorMonto =
                                          'No puedes retirar más de lo que tienes ahorrado (máximo: '
                                          '${FormatoUtils.moneda.format(montoActualDeLaMeta)})';
                                    });
                                    valido = false;
                                  }
                                }
                                if (!valido) return;

                                setDialogState(() => procesando = true);

                                final delta =
                                    tipoSeleccionado == 'Aporte' ? n! : -n!;

                                final logic = MetasLogic();
                                final resultado =
                                    await logic.registrarMovimientoMeta(
                                  meta: meta,
                                  delta: delta,
                                );

                                if (!dialogCtx.mounted) return;

                                if (resultado.exito) {
                                  final mensaje = tipoSeleccionado == 'Aporte'
                                      ? 'Aporte registrado'
                                      : 'Retiro registrado';
                                  Navigator.pop(dialogCtx, mensaje);
                                } else {
                                  setDialogState(() {
                                    procesando = false;
                                    errorMonto = resultado.error;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF58774B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: procesando
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'Confirmar',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          );
        },
      );
    },
  );

  if (mensajeResultado != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensajeResultado),
        backgroundColor: const Color(0xFF7A9B6C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
    onRecargar();
  }
}
