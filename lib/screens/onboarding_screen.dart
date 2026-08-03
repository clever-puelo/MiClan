import 'package:flutter/material.dart';
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
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.group_add, size: 80, color: Colors.green),
              const SizedBox(height: 16),
              const Text('Configura tu Grupo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_circle),
                  label: const Text('Crear Grupo Familiar'),
                  onPressed: _loading ? null : () => _showCreateDialog(user?.uid ?? ''),
                ),
              ),
              const SizedBox(height: 16),
              const Text('— o —', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl, maxLength: 6, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'Código de 6 dígitos', border: OutlineInputBorder(), counterText: ''),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity, height: 50,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Unirme a un Grupo'),
                  onPressed: _loading ? null : _joinGroup,
                ),
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red))),
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
        title: const Text('Nombre del Grupo'),
        content: TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Ej: Familia Pérez')),
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
    final user = ref.read(currentUserProvider).value;
    if (user == null || _codeCtrl.text.length != 6) {
      setState(() => _error = 'Ingresa un código de 6 caracteres');
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