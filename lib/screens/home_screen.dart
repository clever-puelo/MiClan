import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final pos = await ref.read(locationServiceProvider).getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_mapReady) {
        _mapController.move(_myLocation!, 16);
      }
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user?.groupId != null) {
        ref.read(locationServiceProvider).startTracking(user!.uid, user.groupId!);
      }
    }
  }

  void _centerOnMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final membersAsync = ref.watch(groupMembersProvider);
    final groupAsync = ref.watch(currentGroupProvider);

    return userAsync.when(
      data: (user) => membersAsync.when(
        data: (members) => groupAsync.when(
          data: (group) => _buildUI(context, user!, members, group),
          loading: () => _loadingScaffold(),
          error: (e, _) => _errorScaffold('Error grupo: \$e'),
        ),
        loading: () => _loadingScaffold(),
        error: (e, _) => _errorScaffold('Error miembros: \$e'),
      ),
      loading: () => _loadingScaffold(),
      error: (e, _) => _errorScaffold('Error usuario: \$e'),
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

  Widget _buildUI(BuildContext context, AppUser user, List<AppUser> members, AppGroup? group) {
    final isCentral = user.currentRole == 'central';
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '\${user.displayName} - \${group?.name ?? "MiClan"}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          _glassButton(icon: Icons.chat, onTap: () => context.push('/chat')),
          _glassButton(icon: Icons.settings, onTap: () => context.push('/settings')),
        ],
      ),
      body: Stack(
        children: [
          // Mapa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(-34.6037, -58.3816),
              initialZoom: _myLocation != null ? 16.0 : 12.0,
              onMapReady: () {
                _mapReady = true;
                if (_myLocation != null) _mapController.move(_myLocation!, 16);
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

          // SOS ARRIBA - separado, grande
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            right: 16,
            child: _sosButton(user),
          ),

          // Botón centrador (mi ubicación)
          Positioned(
            right: 16,
            bottom: isCentral ? 24 : 180 + bottomPad,
            child: _glassFAB(
              icon: Icons.my_location,
              color: Colors.blue.shade400,
              onTap: _centerOnMe,
            ),
          ),

          // Botones de CENTRAL (arriba a la izquierda)
          if (isCentral)
            Positioned(
              left: 16,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _centralCmdBtn('📍 ¿Dónde estás?', Colors.teal, user, members),
                  const SizedBox(height: 8),
                  _centralCmdBtn('🔙 Volvé', Colors.orange, user, members),
                  const SizedBox(height: 8),
                  _centralCmdBtn('📞 Llámame', Colors.purple, user, members),
                  const SizedBox(height: 8),
                  _centralCmdBtn('✋ Quedate ahí', Colors.indigo, user, members),
                ],
              ),
            ),

          // Botones rápidos MIEMBRO (abajo centrado)
          if (!isCentral)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + bottomPad,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.black.withOpacity(0.4),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _bentoBtn('✅ Llegué', Colors.green, user),
                    _bentoBtn('👍 Estoy bien', Colors.blue, user),
                    _bentoBtn('🚶 Volviendo', Colors.orange, user),
                    _bentoBtn('📞 Llámame', Colors.purple, user),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sosButton(AppUser user) {
    return GestureDetector(
      onTap: () => _sendSOS(user),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.red.shade600, Colors.red.shade900],
          ),
          border: Border.all(color: Colors.red.shade200.withOpacity(0.4), width: 2),
          boxShadow: [
            BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 25, spreadRadius: 2),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'S.O.S',
              style: TextStyle(
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

          final isThisCentral = member.currentRole == 'central';
          final isMe = member.uid == currentUser.uid;
          if (isMe) _myLocation = loc;

          markers.add(Marker(
            point: loc,
            width: 120,
            height: 100,
            child: GestureDetector(
              onTap: () => _onMarkerTap(context, currentUser, member),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pin con nombre arriba
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isThisCentral
                          ? Colors.amber.shade600.withOpacity(0.9)
                          : Colors.blue.shade600.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: (isThisCentral ? Colors.amber : Colors.blue).withOpacity(0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      isMe ? 'Yo (\${member.displayName})' : member.displayName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    isThisCentral ? Icons.star : Icons.person_pin_circle,
                    color: isThisCentral ? Colors.amber : Colors.blue,
                    size: 36,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
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

  Widget _bentoBtn(String text, Color color, AppUser user) {
    return GestureDetector(
      onTap: () {
        ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'quick_message', text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviado: \$text'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10)],
        ),
        child: Text(
          text,
          style: TextStyle(color: color.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _centralCmdBtn(String text, Color color, AppUser user, List<AppUser> members) {
    return GestureDetector(
      onTap: () {
        // Enviar a todos los miembros no-central
        for (final m in members) {
          if (m.uid != user.uid) {
            ref.read(firestoreServiceProvider).sendAlert(user, m.uid, 'command_message', text);
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviado a todos: \$text'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.2),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12)],
        ),
        child: Text(
          text,
          style: TextStyle(color: color.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _onMarkerTap(BuildContext context, AppUser currentUser, AppUser tapped) {
    if (currentUser.uid == tapped.uid) return;
    if (currentUser.currentRole != 'central') return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enviar a \${tapped.displayName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _cmdBtn('📞 Llámame', currentUser, tapped.uid),
                _cmdBtn('✅ ¿Llegaste?', currentUser, tapped.uid),
                _cmdBtn('👍 ¿Todo bien?', currentUser, tapped.uid),
                _cmdBtn('🔙 Volvé', currentUser, tapped.uid),
                _cmdBtn('📍 ¿Dónde estás?', currentUser, tapped.uid),
                _cmdBtn('📷 Envía foto', currentUser, tapped.uid),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado: \$text')));
      },
      child: Text(text),
    );
  }

  void _sendSOS(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('🚨 ¿Activar S.O.S?', style: TextStyle(color: Colors.white)),
        content: const Text('Se enviará una alerta de pánico a todo el grupo.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'SOS', '¡ALERTA DE PÁNICO ACTIVADA!');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🚨 S.O.S ENVIADO'), backgroundColor: Colors.red),
              );
            },
            child: const Text('ENVIAR S.O.S', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
