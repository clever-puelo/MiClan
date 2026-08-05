import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _batterySaver = false;
  final _serverKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _batterySaver = prefs.getBool('battery_saver') ?? false;
        _serverKeyCtrl.text = prefs.getString('fcm_server_key') ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final group = ref.watch(currentGroupProvider).valueOrNull;
    final geofence = ref.watch(geofenceZoneProvider).valueOrNull;
    final isAdmin = user?.uid == group?.ownerId;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Configuracion', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('Cuenta'),
          _glassTile(label: 'Nombre', value: user?.displayName ?? '-'),
          _glassTile(label: 'Email', value: user?.email ?? '-'),
          const SizedBox(height: 8),
          _divider(),
          _sectionTitle('Grupo'),
          _glassTile(label: 'Nombre', value: group?.name ?? 'Sin grupo'),
          if (isAdmin && group != null) _glassTile(label: 'Codigo', value: group.joinCode),
          const SizedBox(height: 8),
          _divider(),
          if (isAdmin) ...[
            _sectionTitle('Zona Segura'),
            if (geofence != null) ...[
              _glassTile(label: 'Zona activa', value: '${geofence.name} (${geofence.radiusMeters}m)'),
              _actionTile(icon: Icons.delete, text: 'Eliminar zona', color: Colors.red, onTap: () async {
                if (group != null) {
                  await ref.read(firestoreServiceProvider).deleteGeofence(group.id);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zona eliminada')));
                }
              }),
            ] else ...[
              _actionTile(
                icon: Icons.add_location,
                text: 'Crear zona segura',
                subtitle: 'Perimetro alrededor de tu ubicacion',
                onTap: () => _showGeofenceDialog(group?.id ?? ''),
              ),
            ],
            _divider(),
          ],
          _sectionTitle('Bateria'),
          SwitchListTile(
            title: const Text('Modo ahorro', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _batterySaver ? 'GPS cada 5 min / 200m' : 'GPS cada 1 min / 50m',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            value: _batterySaver,
            activeColor: Colors.blue,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('battery_saver', val);
              setState(() => _batterySaver = val);
            },
          ),
          _actionTile(
            icon: Icons.battery_alert,
            text: 'Desactivar optimizacion',
            subtitle: 'Evita que Android cierre la app',
            onTap: _openBatterySettings,
          ),
          _divider(),
          _sectionTitle('Notificaciones Push'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server Key FCM (opcional)',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serverKeyCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Pega aqui tu Server Key de Firebase',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.save, color: Colors.blue),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('fcm_server_key', _serverKeyCtrl.text.trim());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Server Key guardada')),
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Necesaria para notificaciones push. La encontras en Firebase Console > Project Settings > Cloud Messaging.',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                ),
              ],
            ),
          ),
          _divider(),
          _sectionTitle('Caja Negra'),
          _actionTile(icon: Icons.upload_file, text: 'Exportar backup', onTap: () async {
            await ref.read(backupServiceProvider).exportBackup();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup exportado')));
          }),
          _actionTile(icon: Icons.download, text: 'Importar backup', onTap: () async {
            final ok = await ref.read(backupServiceProvider).importBackup();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Backup importado' : 'Error')));
          }),
          _divider(),
          _sectionTitle('Grupo / Cuenta'),
          _actionTile(
            icon: Icons.exit_to_app,
            text: 'Salir del grupo',
            color: Colors.orange,
            onTap: () async {
              if (user == null || group == null) return;
              final isOwner = user.uid == group.ownerId;
              if (isOwner) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Borrar grupo?', style: TextStyle(color: Colors.white)),
                    content: const Text('Como administrador, al salir se eliminara el grupo completo. Los miembros quedaran huerfanos. Continuar?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Borrar', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
              }
              await ref.read(firestoreServiceProvider).leaveGroup(user.uid, group.id, isOwner);
              await ref.read(authServiceProvider).updateGroupId(user.uid, null);
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          _actionTile(
            icon: Icons.delete_forever,
            text: 'Eliminar cuenta permanentemente',
            color: Colors.red,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Eliminar cuenta?', style: TextStyle(color: Colors.white)),
                  content: const Text('Esta accion no se puede deshacer. Continuar?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true && user != null) {
                if (group != null) {
                  final isOwner = user.uid == group.ownerId;
                  await ref.read(firestoreServiceProvider).leaveGroup(user.uid, group.id, isOwner);
                }
                await ref.read(authServiceProvider).deleteAccount(user.uid);
              }
            },
          ),
          _divider(),
          _sectionTitle('Sesion'),
          _actionTile(
            icon: Icons.logout,
            text: 'Cerrar sesion (logout completo)',
            color: Colors.red,
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade300)),
    );
  }

  Widget _glassTile({required String label, required String value}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _actionTile({required IconData icon, required String text, String? subtitle, Color? color, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.blue.shade300),
      title: Text(text, style: TextStyle(color: color ?? Colors.white)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)) : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _divider() => Divider(color: Colors.white.withOpacity(0.08), height: 32);

  void _showGeofenceDialog(String groupId) {
    final nameCtrl = TextEditingController(text: 'Casa');
    final radiusCtrl = TextEditingController(text: '200');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nueva Zona', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: 'Nombre', labelStyle: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            TextField(
              controller: radiusCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Radio (m)', labelStyle: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final pos = await ref.read(locationServiceProvider).getCurrentPosition();
              if (pos != null) {
                final zone = GeofenceZone(
                  lat: pos.latitude,
                  lng: pos.longitude,
                  radiusMeters: double.tryParse(radiusCtrl.text) ?? 200,
                  name: nameCtrl.text.isEmpty ? 'Zona' : nameCtrl.text,
                );
                await ref.read(firestoreServiceProvider).saveGeofence(groupId, zone);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _openBatterySettings() {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.agiletask.miclan',
      );
      intent.launch();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir configuracion')),
      );
    }
  }
}
