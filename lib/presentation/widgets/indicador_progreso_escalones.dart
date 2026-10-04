import 'package:flutter/material.dart';

import '../../logic/educacion_logic.dart';

class IndicadorProgresoEscalones extends StatelessWidget {
  final List<EscalonConEstado> escalones;
  final Color colorNivel;

  const IndicadorProgresoEscalones({
    super.key,
    required this.escalones,
    required this.colorNivel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < escalones.length; i++) ...[
              _buildIndicadorEscalon(escalones[i]),
              if (i < escalones.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIndicadorEscalon(EscalonConEstado escalon) {
    if (escalon.tipo == 'evaluacion') {
      return Icon(
        Icons.menu_book,
        size: 12,
        color: escalon.completado ? colorNivel : const Color(0xFFC9C2B0),
      );
    }
    if (escalon.completado) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: colorNivel,
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorNivel, width: 1.2),
      ),
    );
  }
}
