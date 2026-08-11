import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../services/firestore_service.dart';
import '../widgets/app_footer.dart';
import '../main.dart';

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
      backgroundColor: const Color(0xFF273758),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Configuración', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        // FIX: padding inferior extra (safe area + margen) para que el
        // ultimo item ("Cerrar sesion") no quede tapado por los botones
        // de navegacion de Android.
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 32),
        children: [
          _sectionTitle('Cuenta'),
          _glassTile(label: 'Nombre', value: user?.displayName ?? '-'),
          _glassTile(label: 'Email', value: user?.email ?? '-'),
          _editableGlassTile(
            label: 'Teléfono (WhatsApp)',
            value: (user?.phone == null || user!.phone!.isEmpty) ? 'No cargado' : user.phone!,
            onTap: () => _showEditPhoneDialog(user),
          ),
          const SizedBox(height: 8),
          _divider(),
          _sectionTitle('Grupo'),
          _glassTile(label: 'Nombre', value: group?.name ?? 'Sin grupo'),
          if (isAdmin && group != null) _glassTile(label: 'Código', value: group.joinCode),
          const SizedBox(height: 8),
          _divider(),
          if (isAdmin) ...[
            _sectionTitle('Zona Segura (Geofence)'),
            _glassTile(
              label: '¿Qué hace?',
              value: 'Define un perímetro circular. Si un miembro entra o sale, el grupo recibe una notificación automática.',
            ),
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
                subtitle: 'Perímetro alrededor de tu ubicación actual',
                onTap: () => _showGeofenceDialog(group?.id ?? ''),
              ),
            ],
            _divider(),
            // Mensajes rápidos configurables (solo admin)
            _sectionTitle('Mensajes Rápidos'),
            _glassTile(
              label: '¿Qué hace?',
              value: 'Define el título y el mensaje de cada botón fijo. Los miembros los ven al abrir la app.',
            ),
            _actionTile(
              icon: Icons.edit_note,
              text: 'Configurar botones de mensaje',
              subtitle: 'Modo "Todos" y modo "un miembro" (preguntas/respuestas)',
              color: Colors.purple.shade200,
              onTap: () => _showQuickMessagesDialog(context, group?.id ?? ''),
            ),
            _divider(),
            // Caja Negra del Grupo (solo admin)
            _sectionTitle('Caja Negra del Grupo'),
            _actionTile(
              icon: Icons.table_chart,
              text: 'Ver movimientos del grupo',
              subtitle: 'Historial de ubicaciones últimos 7 días',
              color: Colors.amber.shade400,
              onTap: () => _showBlackBoxDialog(context, group!, user!),
            ),
            _divider(),
            // Estado de Miembros (solo admin): monitoreo de conexion/GPS en
            // tiempo real, para diagnosticar remotamente por que un miembro
            // dejo de reportar (permisos, bateria, app cerrada) sin
            // necesitar acceso fisico a su telefono.
            _sectionTitle('Estado de Miembros'),
            _glassTile(
              label: '¿Qué hace?',
              value: 'Muestra si cada miembro tiene la app activa, en segundo plano o desconectada, y por qué (permisos, batería).',
            ),
            _actionTile(
              icon: Icons.wifi_tethering,
              text: 'Ver estado de conexión',
              subtitle: 'Activa / segundo plano / desconectado, por miembro',
              color: Colors.greenAccent.shade400,
              onTap: () => _showMemberStatusDialog(context, user!),
            ),
            _divider(),
          ],
          _sectionTitle('Batería'),
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
            text: 'Desactivar optimizacion de batería',
            subtitle: 'Evita que Android cierre la app en segundo plano',
            onTap: _openBatterySettings,
          ),
          _divider(),
          _sectionTitle('Caja Negra Local'),
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
                    backgroundColor: const Color(0xFF3A4A66),
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
                  backgroundColor: const Color(0xFF3A4A66),
                  title: const Text('Eliminar cuenta?', style: TextStyle(color: Colors.white)),
                  content: const Text('Esta acción no se puede deshacer. Continuar?', style: TextStyle(color: Colors.white70)),
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
          _sectionTitle('Sesión'),
          _actionTile(
            icon: Icons.logout,
            text: 'Cerrar sesión (logout completo)',
            color: Colors.red,
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
            },
          ),
          const SizedBox(height: 24),
          const AppCopyrightFooter(),
        ],
      ),
    );
  }

  void _showBlackBoxDialog(BuildContext context, AppGroup group, AppUser adminUser) {
    showDialog(
      context: context,
      builder: (ctx) => _BlackBoxDialog(group: group, adminUser: adminUser),
    );
  }

  void _showMemberStatusDialog(BuildContext context, AppUser adminUser) {
    showDialog(
      context: context,
      builder: (ctx) => _MemberStatusDialog(adminUser: adminUser),
    );
  }

  void _showQuickMessagesDialog(BuildContext context, String groupId) {
    if (groupId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => _QuickMessagesDialog(groupId: groupId),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade300)),
    );
  }

  Widget _editableGlassTile({required String label, required String value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
            ),
            Expanded(
              flex: 3,
              child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.edit, size: 16, color: Colors.blue.shade300),
          ],
        ),
      ),
    );
  }

  void _showEditPhoneDialog(AppUser? user) {
    if (user == null) return;
    final ctrl = TextEditingController(text: user.phone ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF3A4A66),
        title: const Text('Teléfono para WhatsApp', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Incluí el código de país, sin espacios ni guiones. Ej: 5491122334455',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Teléfono',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(authServiceProvider).updatePhone(user.uid, ctrl.text.trim());
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
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
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
          ),
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
        backgroundColor: const Color(0xFF3A4A66),
        title: const Text('Nueva Zona Segura', style: TextStyle(color: Colors.white)),
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
              decoration: InputDecoration(labelText: 'Radio (metros)', labelStyle: TextStyle(color: Colors.white.withOpacity(0.5))),
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
        const SnackBar(content: Text('No se pudo abrir configuración')),
      );
    }
  }
}

// ============================================================================
// DIALOG CONFIGURACION DE MENSAJES RAPIDOS (admin)
// ============================================================================
class _QuickMessagesDialog extends ConsumerStatefulWidget {
  final String groupId;
  const _QuickMessagesDialog({required this.groupId});

  @override
  ConsumerState<_QuickMessagesDialog> createState() => _QuickMessagesDialogState();
}

class _QuickMessagesDialogState extends ConsumerState<_QuickMessagesDialog> {
  final Map<String, TextEditingController> _titleCtrls = {};
  final Map<String, TextEditingController> _msgCtrls = {};
  bool _loaded = false;
  bool _saving = false;

  String _key(String group, int i) => '${group}_$i';

  void _loadFrom(QuickMessagesConfig cfg) {
    if (_loaded) return;
    _fill('all', cfg.allButtons);
    _fill('question', cfg.questionButtons);
    _fill('answer', cfg.answerButtons);
    _loaded = true;
  }

  void _fill(String group, List<QuickMessageItem> items) {
    for (var i = 0; i < items.length; i++) {
      _titleCtrls[_key(group, i)] = TextEditingController(text: items[i].title);
      _msgCtrls[_key(group, i)] = TextEditingController(text: items[i].message);
    }
  }

  List<QuickMessageItem> _readGroup(String group, List<QuickMessageItem> fallback) {
    return List.generate(fallback.length, (i) {
      final t = _titleCtrls[_key(group, i)]?.text.trim();
      final m = _msgCtrls[_key(group, i)]?.text.trim();
      return QuickMessageItem(
        title: (t == null || t.isEmpty) ? fallback[i].title : t,
        message: (m == null || m.isEmpty) ? fallback[i].message : m,
      );
    });
  }

  @override
  void dispose() {
    for (final c in _titleCtrls.values) c.dispose();
    for (final c in _msgCtrls.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quickMsgsAsync = ref.watch(groupQuickMessagesProvider);

    return Dialog(
      backgroundColor: const Color(0xFF273758),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        child: quickMsgsAsync.when(
          data: (cfg) {
            _loadFrom(cfg);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note, color: Colors.purple.shade200, size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Mensajes Rápidos', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _groupSubtitle('Modo "Todos" (4 botones)'),
                        _itemFields('all', 4),
                        const SizedBox(height: 16),
                        _groupSubtitle('Modo "un miembro" — preguntas (arriba)'),
                        _itemFields('question', 3),
                        const SizedBox(height: 16),
                        _groupSubtitle('Modo "un miembro" — respuestas (abajo)'),
                        _itemFields('answer', 3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            final newCfg = QuickMessagesConfig(
                              allButtons: _readGroup('all', cfg.allButtons),
                              questionButtons: _readGroup('question', cfg.questionButtons),
                              answerButtons: _readGroup('answer', cfg.answerButtons),
                            );
                            await ref.read(firestoreServiceProvider).saveQuickMessages(widget.groupId, newCfg);
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Mensajes rápidos guardados')),
                              );
                            }
                          },
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar'),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(height: 100, child: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red)))),
        ),
      ),
    );
  }

  Widget _groupSubtitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(color: Colors.blue.shade200, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _itemFields(String group, int count) {
    return Column(
      children: List.generate(count, (i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _titleCtrls[_key(group, i)],
                  maxLength: 14,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Título botón',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _msgCtrls[_key(group, i)],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Mensaje enviado',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ============================================================================
// DIALOG CAJA NEGRA - Admin preseleccionado + boton Mapa
// ============================================================================
class _BlackBoxDialog extends ConsumerStatefulWidget {
  final AppGroup group;
  final AppUser adminUser;

  const _BlackBoxDialog({required this.group, required this.adminUser});

  @override
  ConsumerState<_BlackBoxDialog> createState() => _BlackBoxDialogState();
}

class _BlackBoxDialogState extends ConsumerState<_BlackBoxDialog> {
  // FIX: admin preseleccionado por defecto
  late String? _selectedMemberUid = widget.adminUser.uid;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider);

    return Dialog(
      backgroundColor: const Color(0xFF273758),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart, color: Colors.amber.shade400, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Caja Negra del Grupo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Movimientos últimos 7 días',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 16),

            membersAsync.when(
              data: (members) {
                final items = members
                    .where((m) => m.uid != widget.adminUser.uid)
                    .map((m) => DropdownMenuItem(
                          value: m.uid,
                          child: Text(m.displayName, style: const TextStyle(color: Colors.white)),
                        ))
                    .toList();

                items.insert(
                  0,
                  DropdownMenuItem(
                    value: widget.adminUser.uid,
                    child: Text('${widget.adminUser.displayName} (Yo - Admin)', style: const TextStyle(color: Colors.white)),
                  ),
                );

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withOpacity(0.05),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          dropdownColor: const Color(0xFF3A4A66),
                          hint: const Text('Seleccionar miembro...', style: TextStyle(color: Colors.white54)),
                          value: _selectedMemberUid,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          onChanged: (val) => setState(() => _selectedMemberUid = val),
                          items: items,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Boton Ver en mapa
                    if (_selectedMemberUid != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: Icon(Icons.map, color: Colors.blue.shade300, size: 18),
                          label: Text('Ver recorrido en mapa', style: TextStyle(color: Colors.blue.shade300)),
                          onPressed: () => _showRouteMapFromBlackBox(context, _selectedMemberUid!, members),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Error cargando miembros', style: TextStyle(color: Colors.red)),
            ),

            const SizedBox(height: 12),

            if (_selectedMemberUid != null)
              Expanded(child: _buildMovementsList(_selectedMemberUid!))
            else
              Expanded(
                child: Center(
                  child: Text(
                    'Selecciona un miembro para ver sus movimientos',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRouteMapFromBlackBox(BuildContext context, String memberUid, List<AppUser> members) {
    final member = members.firstWhere((m) => m.uid == memberUid, orElse: () => widget.adminUser);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BlackBoxRouteMapModal(
        memberUid: memberUid,
        memberName: member.displayName,
        groupId: widget.group.id,
      ),
    );
  }

  Widget _buildMovementsList(String memberUid) {
    final since = DateTime.now().subtract(const Duration(days: 7));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('locations')
          .doc(memberUid)
          .collection('history')
          .where('groupId', isEqualTo: widget.group.id)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final movements = snapshot.data?.docs ?? [];
        if (movements.isEmpty) {
          return Center(
            child: Text(
              'No hay movimientos registrados\npara este miembro en los últimos 7 días.',
              style: TextStyle(color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Fecha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Hora', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text('Coordenada', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: movements.length,
                itemBuilder: (ctx, i) {
                  final m = movements[i].data() as Map<String, dynamic>;
                  final ts = m['timestamp'];
                  DateTime dt;
                  if (ts is Timestamp) {
                    dt = ts.toDate();
                  } else if (ts is String) {
                    dt = DateTime.tryParse(ts) ?? DateTime.now();
                  } else {
                    dt = DateTime.now();
                  }

                  final lat = (m['lat'] as num?)?.toDouble() ?? 0.0;
                  final lng = (m['lng'] as num?)?.toDouble() ?? 0.0;
                  final isEven = i % 2 == 0;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isEven ? Colors.white.withOpacity(0.03) : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            DateFormat('dd/MM/yy').format(dt),
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            DateFormat('HH:mm').format(dt),
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: Colors.amber.shade300,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.centerRight,
              child: Text(
                '${movements.length} registros',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// MODAL DE MAPA DESDE CAJA NEGRA
// ============================================================================
// FIX 2026-08-08: se sube ~20mm (margen inferior extra) y se agregan dos
// sliders en la cabecera para elegir fecha/hora "desde" y "hasta" del
// muestreo (antes era un rango fijo de 7 días).
const double _kMmToLogicalPxBlackBox = 3.78;

class _BlackBoxRouteMapModal extends ConsumerStatefulWidget {
  final String memberUid;
  final String memberName;
  final String groupId;

  const _BlackBoxRouteMapModal({
    required this.memberUid,
    required this.memberName,
    required this.groupId,
  });

  @override
  ConsumerState<_BlackBoxRouteMapModal> createState() => _BlackBoxRouteMapModalState();
}

class _BlackBoxRouteMapModalState extends ConsumerState<_BlackBoxRouteMapModal> {
  late final DateTime _minDate = DateTime.now().subtract(const Duration(days: 30));
  late final DateTime _maxDate = DateTime.now();
  late double _fromMs = _maxDate.subtract(const Duration(days: 7)).millisecondsSinceEpoch.toDouble();
  late double _toMs = _maxDate.millisecondsSinceEpoch.toDouble();
  final MapController _mapController = MapController();
  int _lastFitCount = -1;

  DateTime get _desde => DateTime.fromMillisecondsSinceEpoch(_fromMs.round());
  DateTime get _hasta => DateTime.fromMillisecondsSinceEpoch(_toMs.round());

  /// Ajusta el zoom/centro para ver el recorrido completo (en vez del zoom
  /// fijo anterior).
  void _fitToRoute(List<LatLng> points) {
    if (points.length == _lastFitCount) return;
    _lastFitCount = points.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 16);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  /// Marcadores en cada punto del recorrido (muestreados si hay demasiados).
  /// El area tocable es mas grande que el punto visible para que sea facil
  /// de tocar con el dedo.
  List<Marker> _timeMarkers(List<Map<String, dynamic>> docs, Color color) {
    if (docs.isEmpty) return [];
    const maxMarkers = 40;
    final step = (docs.length / maxMarkers).ceil().clamp(1, docs.length);
    final markers = <Marker>[];
    for (var i = 0; i < docs.length; i += step) {
      final data = docs[i];
      final ts = data['timestamp'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      final point = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
      markers.add(
        Marker(
          point: point,
          width: 32,
          height: 32,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showPointTime(dt),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  // FIX 2026-08-09: se muestra dentro del bento del mapa (no SnackBar, que
  // quedaba tapado por el propio modal).
  DateTime? _selectedPointTime;

  void _showPointTime(DateTime? dt) {
    setState(() => _selectedPointTime = dt);
  }

  @override
  Widget build(BuildContext context) {
    final raise = 20 * _kMmToLogicalPxBlackBox;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 16 + raise),
      height: MediaQuery.of(context).size.height * 0.68,
      decoration: BoxDecoration(
        color: AppColors.modalBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.route, color: Colors.amber.shade400, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recorrido: ${widget.memberName}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _dateTimeField(label: 'Desde', value: _desde, onTap: () => _pickDateTime(isFrom: true))),
                      const SizedBox(width: 8),
                      Expanded(child: _dateTimeField(label: 'Hasta', value: _hasta, onTap: () => _pickDateTime(isFrom: false))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _presetChip('24h', const Duration(hours: 24)),
                      const SizedBox(width: 6),
                      _presetChip('2 días', const Duration(days: 2)),
                      const SizedBox(width: 6),
                      _presetChip('7 días', const Duration(days: 7)),
                      const SizedBox(width: 6),
                      _presetChip('30 días', const Duration(days: 30)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ref.read(firestoreServiceProvider).getLocationHistoryRangeStream(widget.memberUid, _desde, _hasta),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white70)));
                      }

                      final docs = (snapshot.data ?? []).where((d) => d['groupId'] == widget.groupId).toList();
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No hay recorrido registrado\npara este miembro en el rango seleccionado.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          ),
                        );
                      }

                      final points = docs.map((data) {
                        return LatLng(
                          (data['lat'] as num).toDouble(),
                          (data['lng'] as num).toDouble(),
                        );
                      }).toList();

                      _fitToRoute(points);

                      final center = points.isNotEmpty ? points[points.length ~/ 2] : const LatLng(-34.6, -58.38);

                      return FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.agiletask.miclan',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: points,
                                color: Colors.amber.withOpacity(0.9),
                                strokeWidth: 4,
                              ),
                            ],
                          ),
                          MarkerLayer(markers: _timeMarkers(docs, Colors.amber.shade400)),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: points.first,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
                              ),
                              Marker(
                                point: points.last,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_on, color: Colors.red, size: 32),
                              ),
                            ],
                          ),
                    ],
                  );
                },
              ),
                  if (_selectedPointTime != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.access_time, color: Colors.amber.shade200, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd/MM/yyyy HH:mm:ss').format(_selectedPointTime!),
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() => _selectedPointTime = null),
                              child: const Icon(Icons.close, color: Colors.white54, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: ref.read(firestoreServiceProvider).getLocationHistoryRangeStream(widget.memberUid, _desde, _hasta),
                builder: (context, snapshot) {
                  final count = (snapshot.data ?? []).where((d) => d['groupId'] == widget.groupId).length;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$count puntos de ruta',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.trip_origin, color: Colors.green, size: 14),
                          const SizedBox(width: 4),
                          Text('Inicio', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                          const SizedBox(width: 12),
                          const Icon(Icons.location_on, color: Colors.red, size: 14),
                          const SizedBox(width: 4),
                          Text('Fin', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTimeField({required String label, required DateTime value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                Text(
                  DateFormat('dd/MM/yy HH:mm').format(value),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Icon(Icons.edit_calendar, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  /// FIX 2026-08-09: se reemplazan los sliders (poco precisos en pantallas
  /// chicas) por selectores nativos de fecha+hora, mas chips de rango rapido.
  Future<void> _pickDateTime({required bool isFrom}) async {
    final current = isFrom ? _desde : _hasta;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: _minDate,
      lastDate: _maxDate,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    var picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(_minDate)) picked = _minDate;
    if (picked.isAfter(_maxDate)) picked = _maxDate;
    setState(() {
      if (isFrom) {
        _fromMs = picked.millisecondsSinceEpoch.toDouble();
        if (_fromMs > _toMs) _toMs = _fromMs;
      } else {
        _toMs = picked.millisecondsSinceEpoch.toDouble();
        if (_toMs < _fromMs) _fromMs = _toMs;
      }
    });
  }

  Widget _presetChip(String label, Duration span) {
    return GestureDetector(
      onTap: () => setState(() {
        _toMs = _maxDate.millisecondsSinceEpoch.toDouble();
        final from = _maxDate.subtract(span);
        _fromMs = (from.isBefore(_minDate) ? _minDate : from).millisecondsSinceEpoch.toDouble();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.amber.withOpacity(0.15),
          border: Border.all(color: Colors.amber.withOpacity(0.35)),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ============================================================================
// DIALOG ESTADO DE MIEMBROS (admin) - monitor de conexion/GPS
// ============================================================================
// Panel de monitoreo pedido tras reportarse un caso real de un miembro sin
// ningun movimiento registrado en horas: junta groupMembersProvider (lista
// de miembros) con groupDeviceStatusProvider (lo que cada dispositivo
// reporta de si mismo, ver DeviceStatus / FirestoreService.updateDeviceStatus)
// para que el admin pueda ver, sin acceso fisico al telefono de nadie:
// - Si la app de ese miembro esta activa, en segundo plano, o no reporta
//   hace rato (posible causa real del problema, no solo un sintoma).
// - Si tiene el permiso de ubicacion "todo el tiempo" otorgado (sin el,
//   Android corta el GPS en cuanto la app deja de estar en primer plano).
// - Si tiene la optimizacion de bateria activa (puede matar el servicio de
//   background en fabricantes agresivos).
// - Modo ahorro y hace cuanto se actualizo por ultima vez.
// ============================================================================
class _MemberStatusDialog extends ConsumerWidget {
  final AppUser adminUser;
  const _MemberStatusDialog({required this.adminUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider);
    final statusAsync = ref.watch(groupDeviceStatusProvider);

    return Dialog(
      backgroundColor: const Color(0xFF273758),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.greenAccent.shade400, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Estado de Miembros',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Quién está conectado y cómo está grabando su ubicación ahora mismo',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: membersAsync.when(
                data: (members) {
                  final all = [adminUser, ...members.where((m) => m.uid != adminUser.uid)];
                  final statuses = statusAsync.valueOrNull ?? [];
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: all.length,
                    itemBuilder: (ctx, i) {
                      final member = all[i];
                      DeviceStatus? status;
                      for (final s in statuses) {
                        if (s.uid == member.uid) {
                          status = s;
                          break;
                        }
                      }
                      return _memberStatusCard(member, status, member.uid == adminUser.uid);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Error cargando miembros', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberStatusCard(AppUser member, DeviceStatus? status, bool isSelf) {
    final now = DateTime.now();
    final updatedAt = status?.updatedAt;
    final age = updatedAt != null ? now.difference(updatedAt) : null;
    // Umbral de "reciente": el intervalo configurado (1 o 5 min) x 3, con
    // piso de 6 min, para no marcar "desconectado" por una demora normal
    // de un ciclo (ej. sin señal momentánea).
    final expectedMinutes = status?.trackingIntervalMinutes ?? 1;
    final staleThresholdMin = (expectedMinutes * 3).clamp(6, 30);
    final isStale = age == null || age.inMinutes > staleThresholdMin;

    late final String estadoLabel;
    late final Color estadoColor;
    late final IconData estadoIcon;
    if (status == null) {
      estadoLabel = 'Sin datos (nunca reportó)';
      estadoColor = Colors.white38;
      estadoIcon = Icons.help_outline;
    } else if (isStale) {
      estadoLabel = 'Desconectado / sin señal reciente';
      estadoColor = Colors.redAccent;
      estadoIcon = Icons.cloud_off;
    } else if (status.appState == 'foreground') {
      estadoLabel = 'App activa (primer plano)';
      estadoColor = Colors.greenAccent.shade400;
      estadoIcon = Icons.smartphone;
    } else {
      estadoLabel = 'Segundo plano';
      estadoColor = Colors.blue.shade300;
      estadoIcon = Icons.cloud_done;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: estadoColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(estadoIcon, color: estadoColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSelf ? '${member.displayName} (Yo)' : member.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(estadoLabel, style: TextStyle(color: estadoColor, fontSize: 12, fontWeight: FontWeight.w600)),
          if (status != null) ...[
            const SizedBox(height: 8),
            _statusRow('Modo ahorro', status.batterySaver ? 'Sí (cada 5 min)' : 'No (cada 1 min)'),
            _statusRow(
              'Permiso ubicación 2do plano',
              status.backgroundLocationGranted ? 'Otorgado' : 'NO otorgado',
              ok: status.backgroundLocationGranted,
            ),
            _statusRow(
              'Optimización de batería',
              status.batteryOptimizationIgnored ? 'Ignorada (bien)' : 'Activa (puede matar el GPS)',
              ok: status.batteryOptimizationIgnored,
            ),
            _statusRow('Última actualización', _agoText(age)),
          ],
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, {bool? ok}) {
    final color = ok == null ? Colors.white70 : (ok ? Colors.white70 : Colors.orangeAccent);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.45))),
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _agoText(Duration? d) {
    if (d == null) return '—';
    if (d.inMinutes < 1) return 'ahora mismo';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }
}
