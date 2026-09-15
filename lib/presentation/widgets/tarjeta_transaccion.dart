import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/formato_utils.dart';

class TarjetaTransaccion extends StatelessWidget {
  final Map<String, dynamic> transaccion;
  final String nombreCategoria;
  final String? nota;
  final String? metodoPago;
  final double monto;
  final String fechaDia;
  final VoidCallback? onTap;

  const TarjetaTransaccion({
    super.key,
    required this.transaccion,
    required this.nombreCategoria,
    required this.nota,
    required this.metodoPago,
    required this.monto,
    required this.fechaDia,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tipo = transaccion['tipo'] as String;
    final esIngreso = tipo == 'ingreso';
    final colorBorde =
        esIngreso ? const Color(0xFF58774B) : const Color(0xFFC0392B);
    final signo = esIngreso ? '+' : '-';
    final colorMonto =
        esIngreso ? const Color(0xFF58774B) : const Color(0xFFC0392B);

    final tieneNota = nota != null;
    final tieneMetodo = metodoPago != null;

    final content = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
        border: Border(
          left: BorderSide(color: colorBorde, width: 5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categoría + fecha
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          nombreCategoria,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2B2B2B),
                          ),
                        ),
                      ),
                      Text(
                        fechaDia,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF8C8474),
                        ),
                      ),
                    ],
                  ),
                  if (tieneNota) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 13,
                            color: Color(0xFFC9C2B0),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            nota!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF8C8474),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (tieneMetodo) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          metodoPago == 'efectivo'
                              ? Icons.payments_outlined
                              : Icons.account_balance_outlined,
                          size: 14,
                          color: const Color(0xFFC9C2B0),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          metodoPago == 'efectivo'
                              ? 'Efectivo'
                              : 'Transferencia',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF8C8474),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$signo ${FormatoUtils.moneda.format(monto)}',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorMonto,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
