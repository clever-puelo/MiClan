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

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final pos = await ref.read(locationServiceProvider).getCurrentPosition();
    if (pos != null) {
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      final user = ref.read(currentUserProvider).value;
      if (user?.groupId != null) {
        ref.read(locationServiceProvider).startTracking(user!.uid, user.groupId!);
      }
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
          data: (group) => _buildUI(context, user, members, group),
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
        ),
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildUI(BuildContext context, AppUser user, List<AppUser> members, AppGroup? group) {
    final isCentral = user.currentRole == 'central';
    final centralMember = members.where((m) => m.currentRole == 'central').firstOrNull;

    List<Marker> markers = [];
    LatLng? centralLoc;

    for (var member in members) {
      final loc = ref.watch(memberLocationProvider(member.uid)).value;
      if (loc == null) continue;

      if (member.uid == user.uid) _myLocation = loc;
      final isThisCentral = member.currentRole == 'central';
      if (isThisCentral) centralLoc = loc;

      markers.add(Marker(
        point: loc, width: 100, height: 80,
        child: GestureDetector(
          onTap: () => _onMarkerTap(context, user, member),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isThisCentral ? Icons.star : Icons.person_pin_circle,
                color: isThisCentral ? Colors.amber : Colors.blue,
                size: 40,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  member.displayName,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: isThisCentral ? Colors.amber.shade800 : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }

    final mapCenter = centralLoc ?? _myLocation ?? LatLng(-34.6037, -58.3816);

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? 'MiClan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat), tooltip: 'Chat del Grupo',
            onPressed: () => context.push('/chat'),
          ),
          IconButton(
            icon: Icon(isCentral ? Icons.admin_panel_settings : Icons.person),
            tooltip: 'Cambiar Rol',
            onPressed: () => _toggleRole(user),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: mapCenter, initialZoom: 15.0),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.agiletask.miclan'),
              MarkerLayer(markers: markers),
            ],
          ),

          Positioned(
            right: 16, bottom: 120,
            child: Column(
              children: [
                if (!isCentral && centralLoc != null)
                  _mapButton('¿Dónde está\nCentral?', Icons.star, Colors.amber, () => _mapController.move(centralLoc!, 17.0)),
                const SizedBox(height: 8),
                if (_myLocation != null)
                  _mapButton('¿Dónde\nestoy?', Icons.my_location, Colors.blue, () => _mapController.move(_myLocation!, 17.0)),
              ],
            ),
          ),

          if (!isCentral)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center, spacing: 6, runSpacing: 6,
                  children: [
                    _quickBtn('✅ Llegué', Colors.green, user),
                    _quickBtn('👍 Estoy bien', Colors.blue, user),
                    _quickBtn('🚶 Volviendo', Colors.orange, user),
                    _quickBtn('📞 Llámame', Colors.purple, user),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red.shade700,
        onPressed: () => _sendSOS(user),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
        label: const Text('S.O.S', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }

  Widget _mapButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return FloatingActionButton.small(
      heroTag: label, backgroundColor: color,
      onPressed: onTap,
      child: Icon(icon, color: Colors.white),
    );
  }

  Widget _quickBtn(String text, Color color, AppUser user) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () {
        ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'quick_message', text);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado: $text'), duration: const Duration(seconds: 1)));
      },
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  void _onMarkerTap(BuildContext context, AppUser currentUser, AppUser tapped) {
    if (currentUser.uid == tapped.uid) return;
    if (currentUser.currentRole != 'central') return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enviar a ${tapped.displayName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
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
      onPressed: () {
        ref.read(firestoreServiceProvider).sendAlert(sender, receiverId, 'command_message', text);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado: $text')));
      },
      child: Text(text),
    );
  }

  void _toggleRole(AppUser user) {
    final newRole = user.currentRole == 'central' ? 'miembro' : 'central';
    ref.read(firestoreServiceProvider).updateUserRole(user.uid, newRole);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rol cambiado a: ${newRole == 'central' ? 'Central' : 'Miembro'}')),
    );
  }

  void _sendSOS(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚨 ¿Activar S.O.S?'),
        content: const Text('Se enviará una alerta de pánico a todo el grupo.'),
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