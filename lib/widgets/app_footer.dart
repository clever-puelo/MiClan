import 'package:flutter/material.dart';

/// Pie de pagina con el copyright, usado en las pantallas de bienvenida,
/// login, principal y configuracion. Letra chica pero legible, centrado.
class AppCopyrightFooter extends StatelessWidget {
  final double fontSize;
  final Color? color;

  const AppCopyrightFooter({super.key, this.fontSize = 10, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Clever Sistemas - clevergc@gmail.com - Lago Puelo - 2026',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        color: color ?? Colors.white.withOpacity(0.35),
        letterSpacing: 0.3,
      ),
    );
  }
}
