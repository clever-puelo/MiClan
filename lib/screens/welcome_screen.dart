import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/app_footer.dart';

/// Pantalla de bienvenida (splash). Se muestra mientras la app resuelve el
/// estado de sesion/permisos en el arranque (ver main.dart). El logo
/// "explota" desde el centro (onda expansiva + rebote) y despues aparece
/// el texto. Permanece en pantalla 2.5-3 segundos en total.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  // FIX 2026-08-09: duracion total mas larga (2.8s) y curva con overshoot
  // pronunciado para que se sienta como una "explosion" del logo, no un
  // simple fade. Antes duraba ~0.9-1.4s y pasaba desapercibida.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  // Onda expansiva detras del logo: crece y se desvanece rapido, al
  // arranque de la animacion (efecto "explosion").
  late final Animation<double> _burstScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
  );
  late final Animation<double> _burstFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.05, 0.4, curve: Curves.easeOut),
  );

  // Logo: aparece agrandandose desde un punto, con rebote (overshoot).
  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.45, curve: Curves.elasticOut),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
  );

  late final Animation<double> _textFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 0.65, curve: Curves.easeIn),
  );
  late final Animation<Offset> _textSlide = Tween<Offset>(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.65, curve: Curves.easeOut)));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Onda expansiva ("explosion"): crece y se
                          // desvanece rapido apenas arranca la animacion.
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              final burstProgress = _burstScale.value;
                              final burstOpacity = (1.0 - _burstFade.value).clamp(0.0, 1.0);
                              return Opacity(
                                opacity: burstOpacity,
                                child: Transform.scale(
                                  scale: 0.3 + (burstProgress * 1.4),
                                  child: Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.blue.withOpacity(0.35),
                                          Colors.blue.withOpacity(0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Logo: aparece agrandandose desde el centro, con rebote.
                          ScaleTransition(
                            scale: _logoScale,
                            child: FadeTransition(
                              opacity: _logoFade,
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                width: 140,
                                height: 140,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            const Text(
                              'MiClan V.2.0',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Monitoreo Grupal Activo',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: AppCopyrightFooter(),
            ),
          ],
        ),
      ),
    );
  }
}
