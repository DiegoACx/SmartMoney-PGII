import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/formato_utils.dart';
import '../../logic/transacciones_logic.dart';
import '../registro_transaccion_screen.dart';

Future<void> mostrarOpcionesTransaccion({
  required BuildContext context,
  required Map<String, dynamic> transaccion,
  required String nombreCategoria,
  required double monto,
  required VoidCallback onRecargar,
}) async {
  final tipo = transaccion['tipo'] as String;
  final esIngreso = tipo == 'ingreso';
  final signo = esIngreso ? '+' : '-';
  final colorMonto =
      esIngreso ? const Color(0xFF58774B) : const Color(0xFFC0392B);
  final montoStr = FormatoUtils.moneda.format(monto.abs());

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
              nombreCategoria,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$signo $montoStr',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colorMonto,
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
                    builder: (_) => RegistroTransaccionScreen(
                      transaccionExistente: transaccion,
                    ),
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
                        '¿Eliminar transacción?',
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
                final logic = TransaccionesLogic();
                final error = await logic.eliminarTransaccion(
                  transaccion['id'].toString(),
                );
                if (!context.mounted) return;
                if (error == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Transacción eliminada'),
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
