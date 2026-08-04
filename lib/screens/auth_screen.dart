import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  bool _isLogin = true;
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo cristal
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: [Colors.blue.withOpacity(0.4), Colors.purple.withOpacity(0.3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 5),
                    ],
                  ),
                  child: const Icon(Icons.family_restroom, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  _isLogin ? 'Bienvenido' : 'Crear Cuenta',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin ? 'Ingresá tu nombre y PIN' : 'Elegí tu nombre y PIN',
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
                ),
                const SizedBox(height: 32),
                // Card cristal
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
                  ),
                  child: Column(
                    children: [
                      _buildField(
                        controller: _nameCtrl,
                        label: 'Tu nombre',
                        icon: Icons.person,
                        keyboard: TextInputType.name,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _pinCtrl,
                        label: 'PIN (6 dígitos)',
                        icon: Icons.lock,
                        keyboard: TextInputType.number,
                        obscure: true,
                        maxLength: 6,
                        formatter: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _pinConfirmCtrl,
                          label: 'Repetir PIN',
                          icon: Icons.lock_outline,
                          keyboard: TextInputType.number,
                          obscure: true,
                          maxLength: 6,
                          formatter: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isLogin ? 'Entrar' : 'Registrarse',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => setState(() {
                    _isLogin = !_isLogin;
                    _error = null;
                  }),
                  child: Text(
                    _isLogin ? '¿No tenés cuenta? Registrate' : '¿Ya tenés cuenta? Entrá',
                    style: TextStyle(color: Colors.blue.shade300),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType keyboard,
    bool obscure = false,
    int? maxLength,
    List<TextInputFormatter>? formatter,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      maxLength: maxLength,
      inputFormatters: formatter,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
        ),
        counterText: '',
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (name.isEmpty || pin.length != 6) {
      setState(() => _error = 'Ingresá tu nombre y un PIN de 6 dígitos');
      return;
    }

    if (!_isLogin && pin != _pinConfirmCtrl.text.trim()) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await ref.read(authServiceProvider).signIn(name, pin);
      } else {
        await ref.read(authServiceProvider).signUp(name, pin);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim());
    } finally {
      setState(() => _loading = false);
    }
  }
}
