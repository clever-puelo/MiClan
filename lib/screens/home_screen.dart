import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _myLocation;
  bool _mapReady = false;
  bool _locationChecked = false;
  String _selectedReceiver = 'all';

  @override
  void initState() {
    super.initState();
    _checkLocationAndInit();
  }

  Future<void> _checkLocationAndInit() async {
    // Pedir permisos explicitamente
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      _showLocationDialog('GPS apagado', 'Activa la ubicacion para usar el mapa.');
      setState(() => _locationChecked = true);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied && mounted) {
        _showLocationDialog('Permiso denegado', 'La app necesita acceso a tu ubicacion para mostrarte en el mapa.');
        setState(() => _locationChecked = true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      _showLocationDialog('Permiso bloqueado', 'Ve a configuracion y habilita la ubicacion para MiClan.');
      setState(() => _locationChecked = true);
      return;
    }

    await _initLocation();
    setState(() => _locationChecked = true);
  }

  Future<void> _initLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;

      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));

      // Mover mapa si ya esta listo
      if (_mapReady && _myLocation != null) {
        _mapController.move(_myLocation!, 16);
      }

      final user = ref.read(currentUserProvider).valueOrNull;
      if (user?.groupId != null) {
        ref.read(locationServiceProvider).startTracking(user!.uid, user.groupId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error GPS: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showLocationDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    } else {
      _checkLocationAndInit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final membersAsync = ref.watch(groupMembersProvider);
    final groupAsync = ref.watch(currentGroupProvider);
    final activeSOS = ref.watch(activeSOSProvider).valueOrNull;

    if (!_locationChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return _errorScaffold('No hay usuario activo');
        }
        return membersAsync.when(
          data: (members) => groupAsync.when(
            data: (group) => _buildUI(context, user, members, group, activeSOS),
            loading: () => _loadingScaffold(),
            error: (e, _) => _errorScaffold('Error grupo: $e'),
          ),
          loading: () => _loadingScaffold(),
          error: (e, _) => _errorScaffold('Error miembros: $e'),
        );
      },
      loading: () => _loadingScaffold(),
      error: (e, _) => _errorScaffold('Error usuario: $e'),
    );
  }

  Widget _loadingScaffold() => const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );

  Widget _errorScaffold(String msg) => Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(child: Text(msg, style: const TextStyle(color: Colors.white70))),
      );

  Widget _buildUI(BuildContext context, AppUser user, List<AppUser> members, AppGroup? group, AppAlert? activeSOS) {
    final isAdmin = user.uid == group?.ownerId;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${user.displayName} - ${group?.name ?? "MiClan"}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          _glassButton(icon: Icons.logout, onTap: _logout),
          _glassButton(icon: Icons.settings, onTap: () => context.push('/settings')),
          _glassButton(icon: Icons.chat, onTap: () => context.push('/chat')),
          _glassButton(icon: Icons.people, onTap: () => _showMembersSheet(context, members, isAdmin, group, user)),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            top: MediaQuery.of(context).padding.top + 60,
            bottom: 220 + bottomPad,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _myLocation ?? const LatLng(-34.6037, -58.3816),
                  initialZoom: _myLocation != null ? 16.0 : 12.0,
                  onMapReady: () {
                    _mapReady = true;
                    if (_myLocation != null) {
                      _mapController.move(_myLocation!, 16);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.agiletask.miclan',
                  ),
                  _buildMarkersLayer(members, user),
                ],
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            right: 16,
            child: _sosButton(user, activeSOS),
          ),

          Positioned(
            right: 24,
            bottom: 240 + bottomPad,
            child: _glassFAB(
              icon: Icons.my_location,
              color: _myLocation != null ? Colors.blue.shade400 : Colors.grey,
              onTap: _centerOnMe,
            ),
          ),

          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + bottomPad,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.black.withOpacity(0.5),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReceiverSelector(members, user),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _quickBtn('Llegue', Colors.green, user)),
                      const SizedBox(width: 8),
                      Expanded(child: _quickBtn('Todo bien', Colors.blue, user)),
                      const SizedBox(width: 8),
                      Expanded(child: _quickBtn('Volviendo', Colors.orange, user)),
                      const SizedBox(width: 8),
                      Expanded(child: _customMsgBtn(user)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiverSelector(List<AppUser> members, AppUser currentUser) {
    final items = [
      const DropdownMenuItem(value: 'all', child: Text('Todos', style: TextStyle(color: Colors.white))),
      ...members.where((m) => m.uid != currentUser.uid).map((m) => DropdownMenuItem(
            value: m.uid,
            child: Text(m.displayName, style: const TextStyle(color: Colors.white)),
          )),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.08),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedReceiver,
          dropdownColor: const Color(0xFF1E293B),
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          onChanged: (val) => setState(() => _selectedReceiver = val!),
          items: items,
        ),
      ),
    );
  }

  Widget _sosButton(AppUser user, AppAlert? activeSOS) {
    final bool hasActiveSOS = activeSOS != null;
    return GestureDetector(
      onTap: () => hasActiveSOS ? _cancelSOS(activeSOS, user.uid) : _sendSOS(user),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: hasActiveSOS
                ? [Colors.orange.shade700, Colors.orange.shade900]
                : [Colors.red.shade600, Colors.red.shade900],
          ),
          border: Border.all(
            color: hasActiveSOS ? Colors.orange.shade200.withOpacity(0.4) : Colors.red.shade200.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: hasActiveSOS ? Colors.orange.withOpacity(0.4) : Colors.red.withOpacity(0.4),
              blurRadius: 25,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasActiveSOS ? Icons.stop_circle : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              hasActiveSOS ? 'CANCELAR S.O.S' : 'S.O.S',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkersLayer(List<AppUser> members, AppUser currentUser) {
    return Consumer(
      builder: (context, ref, child) {
        final markers = <Marker>[];

        for (var member in members) {
          final loc = ref.watch(memberLocationProvider(member.uid)).value;
          if (loc == null) continue;

          final isMe = member.uid == currentUser.uid;
          final isAdmin = member.uid == ref.watch(currentGroupProvider).valueOrNull?.ownerId;
          if (isMe) _myLocation = loc;

          Color pinColor;
          IconData pinIcon;
          if (isMe) {
            pinColor = Colors.red;
            pinIcon = Icons.person_pin_circle;
          } else if (isAdmin == true) {
            pinColor = Colors.green;
            pinIcon = Icons.admin_panel_settings;
          } else {
            pinColor = Colors.blue;
            pinIcon = Icons.person_pin_circle;
          }

          markers.add(Marker(
            point: loc,
            width: 120,
            height: 100,
            child: GestureDetector(
              onTap: () => _onMarkerTap(context, currentUser, member),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pinColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                      boxShadow: [BoxShadow(color: pinColor.withOpacity(0.4), blurRadius: 10)],
                    ),
                    child: Text(
                      isMe ? 'Yo (${member.displayName})' : member.displayName,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(pinIcon, color: pinColor, size: 36, shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
                ],
              ),
            ),
          ));
        }
        return MarkerLayer(markers: markers);
      },
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withOpacity(0.1),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _glassFAB({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.2),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 15)],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _quickBtn(String text, Color color, AppUser user) {
    return GestureDetector(
      onTap: () {
        ref.read(firestoreServiceProvider).sendAlert(
              user,
              _selectedReceiver,
              'quick_message',
              text,
            );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviado: $text'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _customMsgBtn(AppUser user) {
    return GestureDetector(
      onTap: () => _showCustomMessageDialog(user),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.purple.withOpacity(0.15),
          border: Border.all(color: Colors.purple.withOpacity(0.4)),
        ),
        child: const Text(
          '...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.purple, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showCustomMessageDialog(AppUser user) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Mensaje personalizado', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Escribi tu mensaje...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                ref.read(firestoreServiceProvider).sendAlert(
                      user,
                      _selectedReceiver,
                      'custom',
                      ctrl.text.trim(),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  void _sendSOS(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Activar S.O.S?', style: TextStyle(color: Colors.white)),
        content: const Text('Se enviara una alerta de panico a todo el grupo.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(firestoreServiceProvider).sendAlert(
                    user,
                    'all',
                    'SOS',
                    'ALERTA DE PANICO ACTIVADA!',
                  );
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('ENVIAR S.O.S', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelSOS(AppAlert sos, String myUid) async {
    final group = ref.read(currentGroupProvider).valueOrNull;
    if (group == null) return;
    await ref.read(firestoreServiceProvider).cancelSOS(group.id, sos.id, myUid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('S.O.S cancelado'), backgroundColor: Colors.orange),
      );
    }
  }

  void _logout() async {
    await ref.read(authServiceProvider).signOut();
  }

  void _showMembersSheet(BuildContext context, List<AppUser> members, bool isAdmin, AppGroup? group, AppUser currentUser) {
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final pendingAsync = ref.watch(pendingRequestsProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Miembros', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 12),
                    ...members.map((m) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: m.uid == group?.ownerId ? Colors.green : Colors.blue,
                            child: Icon(m.uid == group?.ownerId ? Icons.admin_panel_settings : Icons.person, color: Colors.white, size: 18),
                          ),
                          title: Text(m.displayName, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(m.uid == group?.ownerId ? 'Administrador' : 'Miembro', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          trailing: isAdmin && m.uid != currentUser.uid
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  onPressed: () => _confirmRemoveMember(m, group!, currentUser.displayName),
                                )
                              : null,
                        )),
                    if (isAdmin) ...[
                      const Divider(color: Colors.white24),
                      const Text('Solicitudes pendientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      pendingAsync.when(
                        data: (requests) {
                          if (requests.isEmpty) return const Text('No hay solicitudes', style: TextStyle(color: Colors.white38));
                          return Column(
                            children: requests.map((req) => ListTile(
                                  title: Text(req.displayName, style: const TextStyle(color: Colors.white)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check_circle, color: Colors.green),
                                        onPressed: () async {
                                          await ref.read(firestoreServiceProvider).approveRequest(group!.id, req.uid);
                                          messenger.showSnackBar(
                                            SnackBar(content: Text('${req.displayName} aprobado'), backgroundColor: Colors.green),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.red),
                                        onPressed: () async {
                                          await ref.read(firestoreServiceProvider).rejectRequest(group!.id, req.uid);
                                          messenger.showSnackBar(
                                            SnackBar(content: Text('${req.displayName} rechazado'), backgroundColor: Colors.red),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                )).toList(),
                          );
                        },
                        loading: () => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                        error: (_, __) => const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemoveMember(AppUser member, AppGroup group, String adminName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Expulsar a ${member.displayName}?', style: const TextStyle(color: Colors.white)),
        content: const Text('El miembro sera eliminado del grupo y recibira una notificacion.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Expulsar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(firestoreServiceProvider).removeMember(group.id, member.uid, adminName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} expulsado del grupo'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _onMarkerTap(BuildContext context, AppUser currentUser, AppUser tapped) {
    if (currentUser.uid == tapped.uid) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enviar a ${tapped.displayName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _cmdBtn('Llamame', currentUser, tapped.uid),
                _cmdBtn('Llegaste?', currentUser, tapped.uid),
                _cmdBtn('Todo bien?', currentUser, tapped.uid),
                _cmdBtn('Volve', currentUser, tapped.uid),
                _cmdBtn('Donde estas?', currentUser, tapped.uid),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cmdBtn(String text, AppUser sender, String receiverId) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {
        ref.read(firestoreServiceProvider).sendAlert(sender, receiverId, 'command_message', text);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado: $text')));
      },
      child: Text(text),
    );
  }
}
