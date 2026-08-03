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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _batterySaver = prefs.getBool('battery_saver') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final group = ref.watch(currentGroupProvider).value;
    final geofence = ref.watch(geofenceZoneProvider).value;
    final isCentral = user?.currentRole == 'central';

    return Scaffold(
      appBar: AppBar(title: const Text('Configuraci車n')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Cuenta'),
          _infoTile('Email', user?.email ?? '-'),
          _infoTile('Rol actual', user?.currentRole == 'central' ? '?? Central' : '?? Miembro'),
          const Divider(),
          _sectionTitle('Grupo'),
          _infoTile('Nombre', group?.name ?? 'Sin grupo'),
          if (isCentral && group != null) _infoTile('C車digo de uni車n', group.joinCode),
          const Divider(),
          if (isCentral) ...[
            _sectionTitle('?? Zona Segura (Geofencing)'),
            if (geofence != null) ...[
              _infoTile('Zona', '${geofence.name} (${geofence.radiusMeters}m)'),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar zona'),
                onTap: () async {
                  if (group != null) {
                    await ref.read(firestoreServiceProvider).deleteGeofence(group.id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zona eliminada')));
                  }
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.add_location),
                title: const Text('Crear zona segura'),
                subtitle: const Text('Define un per赤metro alrededor de tu ubicaci車n actual'),
                onTap: () => _showGeofenceDialog(group?.id ?? ''),
              ),
            ],
            const Divider(),
          ],
          _sectionTitle('?? Bater赤a'),
          SwitchListTile(
            title: const Text('Modo ahorro de bater赤a'),
            subtitle: Text(_batterySaver ? 'GPS cada 5 min / 200m (ahorro)' : 'GPS cada 1 min / 50m (precisi車n)'),
            value: _batterySaver,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('battery_saver', val);
              setState(() => _batterySaver = val);
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_alert),
            title: const Text('Desactivar optimizaci車n de bater赤a'),
            subtitle: const Text('Evita que Android mate la app en segundo plano'),
            onTap: _openBatterySettings,
          ),
          const Divider(),
          _sectionTitle('?? Caja Negra'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exportar backup'),
            onTap: () async {
              await ref.read(backupServiceProvider).exportBackup();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup exportado')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importar backup'),
            onTap: () async {
              final ok = await ref.read(backupServiceProvider).importBackup();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Backup importado' : 'Error al importar')));
              }
            },
          ),
          const Divider(),
          _sectionTitle('Sesi車n'),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Cambiar de grupo'),
            onTap: () async {
              if (user != null) {
                await ref.read(firestoreServiceProvider).leaveGroup(user.uid);
                if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar sesi車n', style: TextStyle(color: Colors.red)),
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
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15)),
    );
  }

  void _showGeofenceDialog(String groupId) {
    final nameCtrl = TextEditingController(text: 'Casa');
    final radiusCtrl = TextEditingController(text: '200');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Zona Segura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: radiusCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radio (metros)')),
            const SizedBox(height: 8),
            const Text('La zona se centrar芍 en tu ubicaci車n actual', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final pos = await ref.read(locationServiceProvider).getCurrentPosition();
              if (pos != null) {
                final zone = GeofenceZone(
                  lat: pos.latitude, lng: pos.longitude,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir configuraci車n de bater赤a')));
    }
  }
}