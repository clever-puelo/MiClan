import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _waitingForApproval = false;

  @override
  void initState() {
    super.initState();
    // Escuchar cuando el admin aprueba y nos asigna groupId
    ref.listenManual(currentUserProvider, (prev, next) {
      final prevUser = prev?.value;
      final nextUser = next.value;
      if (prevUser?.groupId == null && nextUser?.groupId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud aprobada! Bienvenido al grupo.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        context.go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF273758),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [Colors.green.withOpacity(0.4), Colors.teal.withOpacity(0.3)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                  boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 25)],
                ),
                child: const Icon(Icons.group_add, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('Configura tu Grupo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                user != null ? 'Hola ${user.displayName}' : '',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 32),

              if (_waitingForApproval) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.green),
                      const SizedBox(height: 16),
                      const Text(
                        'Solicitud enviada',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Esperando aprobación del administrador...\nTe notificaremos cuando seas aceptado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Crear Grupo', style: TextStyle(fontSize: 16)),
                    onPressed: _loading ? null : () => _showCreateDialog(user?.uid ?? ''),
                  ),
                ),
                const SizedBox(height: 20),
                Text('— o —', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _codeCtrl,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Código de 6 caracteres',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.login),
                          label: const Text('Solicitar unirme'),
                          onPressed: _loading ? null : _requestJoin,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog(String uid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF3A4A66),
        title: const Text('Nombre del Grupo', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ej: Familia Perez',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              try {
                await ref.read(firestoreServiceProvider).createGroup(_nameCtrl.text.trim(), uid);
              } catch (e) {
                setState(() => _error = e.toString());
              } finally {
                setState(() => _loading = false);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestJoin() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _codeCtrl.text.length != 6) {
      setState(() => _error = 'Ingresa un código de 6 caracteres');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await ref.read(firestoreServiceProvider).requestJoinGroup(
            _codeCtrl.text.toUpperCase(),
            user.uid,
            user.displayName,
          );
      if (!ok) {
        setState(() => _error = 'Código no encontrado o ya sos miembro');
      } else {
        setState(() {
          _error = null;
          _waitingForApproval = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud enviada. Espera la aprobación del administrador.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }
}
