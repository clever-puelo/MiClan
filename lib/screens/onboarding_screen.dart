import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
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
              const SizedBox(height: 32),
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
                  label: const Text('Crear Grupo Familiar', style: TextStyle(fontSize: 16)),
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
                        label: const Text('Unirme a un Grupo'),
                        onPressed: _loading ? null : _joinGroup,
                      ),
                    ),
                  ],
                ),
              ),
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
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nombre del Grupo', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ej: Familia Pérez',
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

  Future<void> _joinGroup() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _codeCtrl.text.length != 6) {
      setState(() => _error = 'Ingresá un código de 6 caracteres');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final group = await ref.read(firestoreServiceProvider).joinGroup(_codeCtrl.text.toUpperCase(), user.uid);
      if (group == null) setState(() => _error = 'Código no encontrado');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }
}
