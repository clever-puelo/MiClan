import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../main.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../services/background_location_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/location_service.dart';
import '../widgets/app_footer.dart';

/// Conversion aproximada de milimetros a pixeles logicos de Flutter, usada
/// para "subir" la ventana de recorrido ~20mm segun lo pedido (no existe una
/// unidad de mm nativa en Flutter, se aproxima con la densidad estandar).
const double _kMmToLogicalPx = 3.78;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  LatLng? _myLocation;
  bool _mapReady = false;
  bool _locationChecked = false;
  String _selectedReceiver = 'all';
  String? _selectedMemberUid;
  StreamSubscription<Position>? _localPositionSub;
  bool? _batteryOptIgnored;
  bool? _bgLocationGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationAndInit();
    _checkBatteryOptimization();
    _checkBackgroundLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localPositionSub?.cancel();
    super.dispose();
  }

  // FIX 2026-08-09: al volver del segundo plano (por ej. despues de ir a
  // Ajustes a otorgar "todo el tiempo" o desactivar la optimización de
  // batería), se vuelven a chequear los permisos para que el cartel de
  // arriba se borre solo, sin necesidad de recargar la app entera.
  //
  // FIX 2026-08-10: "handoff" de la grabación de ubicación segun el ciclo
  // de vida. En primer plano se usa LocationService (stream de geolocator,
  // responsivo por distancia recorrida). Al pasar a segundo plano (pantalla
  // apagada, telefono dormido, o la app minimizada) ese tracking deja de
  // grabar apenas Android congela el isolate principal, asi que se detiene
  // y se arranca BackgroundLocationService: un servicio de Android real e
  // independiente que sigue grabando un punto cada 1 o 5 min (segun lo
  // configurado) hasta que la app vuelve a primer plano.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBackgroundLocation();
      _checkBatteryOptimization();
      _resumeForegroundTracking();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _handoffToBackgroundTracking();
    }
  }

  Future<void> _handoffToBackgroundTracking() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.groupId == null) return;
    await ref.read(locationServiceProvider).stopTracking();
    await BackgroundLocationService.start(user!.uid, user.groupId!);
  }

  Future<void> _resumeForegroundTracking() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.groupId == null) return;
    await BackgroundLocationService.stop();
    await ref.read(locationServiceProvider).startTracking(user!.uid, user.groupId!);
  }

  Future<void> _checkBatteryOptimization() async {
    final ignored = await BatteryOptimizationService.isIgnoring();
    if (mounted) setState(() => _batteryOptIgnored = ignored);
  }

  Future<void> _requestBatteryOptimization() async {
    final granted = await BatteryOptimizationService.request();
    if (mounted) setState(() => _batteryOptIgnored = granted);
  }

  // FIX: el GPS solo sigue grabando con el telefono dormido si el usuario
  // otorgo el permiso de ubicación "todo el tiempo" (background), no solo
  // "mientras se usa la app". Este banner guia al usuario a habilitarlo.
  Future<void> _checkBackgroundLocation() async {
    final granted = await ref.read(locationServiceProvider).hasBackgroundPermission();
    if (mounted) setState(() => _bgLocationGranted = granted);
  }

  Future<void> _requestBackgroundLocation() async {
    // En Android 11+ el sistema solo ofrece "Permitir todo el tiempo" en
    // Ajustes una vez que ya se tiene el permiso de primer plano; por eso
    // se pide de nuevo y, si no alcanza, se abre la configuracion de la app.
    await Geolocator.requestPermission();
    final granted = await ref.read(locationServiceProvider).hasBackgroundPermission();
    if (mounted) setState(() => _bgLocationGranted = granted);
    if (!granted) {
      await Geolocator.openAppSettings();
      if (mounted) _checkBackgroundLocation();
    }
  }

  Future<void> _checkLocationAndInit() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      _showLocationDialog('GPS apagado', 'Activa la ubicación para usar el mapa.');
      setState(() => _locationChecked = true);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // FIX: timeout de seguridad. El permiso de notificaciones ya se
      // resolvio antes en main() (ver comentario ahi), asi que este pedido
      // ya no deberia competir con otro dialogo nativo; el timeout es solo
      // un resguardo extra para nunca dejar la pantalla colgada.
      try {
        permission = await Geolocator.requestPermission().timeout(const Duration(seconds: 30));
      } on TimeoutException {
        permission = await Geolocator.checkPermission();
      }
      if (permission == LocationPermission.denied && mounted) {
        _showLocationDialog('Permiso denegado', 'La app necesita acceso a tu ubicación.');
        setState(() => _locationChecked = true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      _showLocationDialog('Permiso bloqueado', 'Ve a configuración y habilita la ubicación.');
      setState(() => _locationChecked = true);
      return;
    }
    await _initLocation();
    if (mounted) setState(() => _locationChecked = true);
    _checkBackgroundLocation();
  }

  Future<void> _initLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_mapReady && _myLocation != null) {
        _mapController.move(_myLocation!, 16);
      }
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user?.groupId != null) {
        ref.read(locationServiceProvider).startTracking(user!.uid, user.groupId!);
      }

      _localPositionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (!mounted) return;
        setState(() => _myLocation = LatLng(position.latitude, position.longitude));
      });
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
        backgroundColor: AppColors.modalBg,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _centerOnMe() {
    setState(() {
      _selectedMemberUid = null;
      _selectedReceiver = 'all';
    });
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17);
    } else {
      _checkLocationAndInit();
    }
  }

  void _centerOnMember(AppUser member, LatLng location) {
    setState(() {
      _selectedMemberUid = member.uid;
      if (member.uid != ref.read(currentUserProvider).valueOrNull?.uid) {
        _selectedReceiver = member.uid;
      }
    });
    _mapController.move(location, 16);
  }

  void _onReceiverChanged(String? val, AppUser currentUser) {
    setState(() {
      _selectedReceiver = val!;
      if (val != 'all' && val != currentUser.uid) {
        _selectedMemberUid = val;
      } else {
        _selectedMemberUid = null;
      }
    });
  }

  void _showRouteMap(BuildContext context, AppUser currentUser) {
    final targetUid = _selectedReceiver != 'all' ? _selectedReceiver : currentUser.uid;
    final targetName = _selectedReceiver != 'all'
        ? ref.read(groupMembersProvider).valueOrNull?.firstWhere((m) => m.uid == targetUid, orElse: () => currentUser).displayName
        : currentUser.displayName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RouteMapModal(
        memberUid: targetUid,
        memberName: targetName ?? 'Miembro',
        groupId: currentUser.groupId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final membersAsync = ref.watch(groupMembersProvider);
    final groupAsync = ref.watch(currentGroupProvider);
    final activeSOS = ref.watch(activeSOSProvider).valueOrNull;

    if (!_locationChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return _errorScaffold(onRetry: () => ref.invalidate(currentUserProvider));
        }
        return membersAsync.when(
          data: (members) => groupAsync.when(
            data: (group) => _buildUI(context, user, members, group, activeSOS),
            loading: () => _loadingScaffold(),
            error: (e, _) => _errorScaffold(onRetry: () => ref.invalidate(currentGroupProvider)),
          ),
          loading: () => _loadingScaffold(),
          error: (e, _) => _errorScaffold(onRetry: () => ref.invalidate(groupMembersProvider)),
        );
      },
      loading: () => _loadingScaffold(),
      error: (e, _) => _errorScaffold(onRetry: () => ref.invalidate(currentUserProvider)),
    );
  }

  Widget _loadingScaffold() => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );

  // FIX 2026-08-09: si igual llega a fallar un listener de Firestore (ej.
  // red muy lenta, mas alla del margen que ya da _ensureFreshToken en
  // AuthService), antes esta pantalla dejaba al usuario sin salida: los
  // StreamProvider de Riverpod no se reintentan solos, asi que quedaba
  // "pegada" hasta cerrar y reabrir la app. Ahora se agrega un botón de
  // reintentar que invalida solo el provider que efectivamente fallo.
  //
  // FIX 2026-08-10, a pedido del usuario:
  // - Ya no se muestra el error tecnico crudo ("Error grupo: $e", con la
  //   excepción de Firestore/Dart completa): es lo primero que aparecia
  //   justo despues de autorizar el GPS en una instalación nueva (mientras
  //   el doc del usuario/grupo todavia se estaba creando en Firestore), y
  //   se veia como un error grave aunque era transitorio. Ahora es un
  //   aviso generico y corto.
  // - "Reintentar" ya NO reinvalida `currentUserProvider` cuando el que
  //   fallo fue el grupo o los miembros: antes siempre re-suscribia los 3
  //   providers (incluido el de usuario), lo que disparaba de nuevo todo
  //   el flujo pesado de login (guardar token FCM, chequeo de sesión,
  //   etc.) dando la sensación de "vuelve a pedir el login". Ahora cada
  //   pantalla de error reintenta unicamente el stream que se rompio.
  Widget _errorScaffold({required VoidCallback onRetry}) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white38, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Problemas de comunicación, reintentá.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

  Widget _buildUI(BuildContext context, AppUser user, List<AppUser> members, AppGroup? group, AppAlert? activeSOS) {
    final isAdmin = user.uid == group?.ownerId;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final showBatteryBanner = _batteryOptIgnored == false;
    final showBgLocationBanner = _bgLocationGranted == false;
    final bannersShown = (showBatteryBanner ? 1 : 0) + (showBgLocationBanner ? 1 : 0);
    final bannersHeight = bannersShown * 56;

    return Scaffold(
      backgroundColor: AppColors.background,
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
            top: MediaQuery.of(context).padding.top + 60 + bannersHeight,
            bottom: 260 + bottomPad,
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
            ),
          ),

          if (showBatteryBanner)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 12,
              right: 12,
              child: _warningBanner(
                icon: Icons.battery_alert,
                text: 'Optimización de batería activa. Toca para permitir notificaciones y GPS en segundo plano.',
                onTap: _requestBatteryOptimization,
              ),
            ),

          if (showBgLocationBanner)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60 + (showBatteryBanner ? 56 : 0),
              left: 12,
              right: 12,
              child: _warningBanner(
                icon: Icons.location_on,
                text: 'Falta permitir la ubicación "todo el tiempo". Toca para habilitarla y que el GPS siga grabando con el teléfono dormido.',
                onTap: _requestBackgroundLocation,
              ),
            ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 60 + bannersHeight,
            left: 16,
            right: 16,
            child: _sosButton(user, activeSOS),
          ),

          Positioned(
            right: 24,
            bottom: 280 + bottomPad,
            child: _glassFAB(
              icon: Icons.my_location,
              color: _myLocation != null ? Colors.blue.shade400 : Colors.grey,
              onTap: _centerOnMe,
            ),
          ),

          // Bento inferior
          Positioned(
            left: 12,
            right: 12,
            bottom: 50 + bottomPad,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: AppColors.modalBg.withOpacity(0.95),
                border: Border.all(color: AppColors.borderGlass),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildReceiverSelector(members, user)),
                      const SizedBox(width: 8),
                      _glassMiniButton(
                        icon: Icons.map,
                        onTap: () => _showRouteMap(context, user),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildMemberChips(members, user),
                  const SizedBox(height: 12),
                  _buildQuickMessagesArea(members, user),
                ],
              ),
            ),
          ),

          // Pie de copyright, en el hueco entre el bento y el borde inferior.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + 6,
            child: const Center(child: AppCopyrightFooter(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Widget _warningBanner({required IconData icon, required String text, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.amber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: Colors.amber.shade100, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.amber, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberChips(List<AppUser> members, AppUser currentUser) {
    // FIX: se quita al propio usuario ("miembro local") de estos chips,
    // igual que ya estaba excluido del combo de destinatario: no tiene
    // sentido enviarse un mensaje a uno mismo ni centrar el mapa en "mi"
    // chip cuando ya existe el boton dedicado "Mi ubicación".
    final otherMembers = members.where((m) => m.uid != currentUser.uid).toList();
    if (otherMembers.isEmpty) {
      return SizedBox(
        height: 40,
        child: Center(
          child: Text(
            'Todavía no hay otros miembros en el grupo',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
          ),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: otherMembers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final member = otherMembers[index];
          final isSelected = member.uid == _selectedMemberUid;
          final loc = member.uid == currentUser.uid
              ? _myLocation
              : ref.read(memberLocationProvider(member.uid)).value;
          final hasLocation = loc != null;

          return ActionChip(
            avatar: CircleAvatar(
              radius: 10,
              backgroundColor: hasLocation ? AppColors.accentGreen : Colors.grey,
            ),
            label: Text(
              member.displayName,
              style: TextStyle(
                color: isSelected ? AppColors.accentBlue : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            backgroundColor: isSelected
                ? AppColors.accentBlue.withOpacity(0.2)
                : Colors.white.withOpacity(0.08),
            side: BorderSide(
              color: isSelected ? AppColors.accentBlue : Colors.white.withOpacity(0.1),
            ),
            onPressed: hasLocation
                ? () {
                    _centerOnMember(member, loc);
                  }
                : null,
          );
        },
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
          dropdownColor: AppColors.modalBg,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          onChanged: (val) => _onReceiverChanged(val, currentUser),
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
            Icon(hasActiveSOS ? Icons.stop_circle : Icons.warning_amber_rounded, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Text(
              hasActiveSOS ? 'CANCELAR S.O.S' : 'S.O.S',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 2),
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
          LatLng? loc;
          if (member.uid == currentUser.uid) {
            loc = _myLocation;
          } else {
            loc = ref.watch(memberLocationProvider(member.uid)).value;
          }
          if (loc == null) continue;

          final isMe = member.uid == currentUser.uid;
          final isAdmin = member.uid == ref.watch(currentGroupProvider).valueOrNull?.ownerId;

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

  Widget _glassMiniButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
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

  // ==========================================================================
  // MENSAJES RAPIDOS
  // --------------------------------------------------------------------------
  // - Combo en "Todos": 4 botones preestablecidos y configurables.
  //   FIX 2026-08-09: antes eran 3 preestablecidos + un 4to boton fijo
  //   "(...)" de mensaje manual, que quedaba duplicado con el "(...)" del
  //   bento lateral (siempre visible, arriba de "WP"). Se saco ese
  //   duplicado; el 4to lugar ahora sale de la configuracion del admin
  //   (cfg.allButtons[3], ver Configuracion > Mensajes Rapidos).
  // - Combo en un miembro: 6 botones (3 preguntas arriba + 3 respuestas
  //   abajo), tomados de la configuracion del admin (groupQuickMessagesProvider).
  // - Bento lateral fijo (siempre visible) con "..." (mensaje manual) arriba
  //   y "WP" (enlace a WhatsApp del miembro seleccionado) abajo.
  // ==========================================================================
  Widget _buildQuickMessagesArea(List<AppUser> members, AppUser user) {
    final quickMsgs = ref.watch(groupQuickMessagesProvider).valueOrNull ?? QuickMessagesConfig.defaultConfig;
    final isAllMode = _selectedReceiver == 'all';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isAllMode
                ? _buildAllModeGrid(quickMsgs, user)
                : _buildMemberModeGrid(quickMsgs, user),
          ),
          const SizedBox(width: 8),
          _buildSideBento(user, members),
        ],
      ),
    );
  }

  Widget _buildAllModeGrid(QuickMessagesConfig cfg, AppUser user) {
    return Row(
      children: [
        Expanded(child: _presetBtn(cfg.allButtons[0], Colors.green, user)),
        const SizedBox(width: 8),
        Expanded(child: _presetBtn(cfg.allButtons[1], Colors.blue, user)),
        const SizedBox(width: 8),
        Expanded(child: _presetBtn(cfg.allButtons[2], Colors.orange, user)),
        const SizedBox(width: 8),
        Expanded(child: _presetBtn(cfg.allButtons[3], Colors.red, user)),
      ],
    );
  }

  Widget _buildMemberModeGrid(QuickMessagesConfig cfg, AppUser user) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _presetBtn(cfg.questionButtons[0], Colors.purple, user)),
              const SizedBox(width: 8),
              Expanded(child: _presetBtn(cfg.questionButtons[1], Colors.purple, user)),
              const SizedBox(width: 8),
              Expanded(child: _presetBtn(cfg.questionButtons[2], Colors.purple, user)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _presetBtn(cfg.answerButtons[0], Colors.teal, user)),
              const SizedBox(width: 8),
              Expanded(child: _presetBtn(cfg.answerButtons[1], Colors.teal, user)),
              const SizedBox(width: 8),
              Expanded(child: _presetBtn(cfg.answerButtons[2], Colors.teal, user)),
            ],
          ),
        ),
      ],
    );
  }

  /// Bento lateral fijo: "..." (mensaje manual) arriba y "WP" (WhatsApp) abajo.
  Widget _buildSideBento(AppUser user, List<AppUser> members) {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          Expanded(
            child: _sideBentoBtn(
              label: '(...)',
              color: Colors.purple,
              onTap: () => _showCustomMessageDialog(user),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _sideBentoBtn(
              label: 'WP',
              color: Colors.green,
              onTap: () => _sendViaWhatsApp(members),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBentoBtn({required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.28),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Abre WhatsApp con un mensaje prellenado hacia el miembro seleccionado
  /// en el combo, usando su telefono cargado en "Cuenta" (Configuración).
  void _sendViaWhatsApp(List<AppUser> members) {
    if (_selectedReceiver == 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un miembro del combo para enviarle un WhatsApp')),
      );
      return;
    }
    final member = members.where((m) => m.uid == _selectedReceiver).toList();
    final phone = member.isNotEmpty ? member.first.phone?.trim() : null;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.isNotEmpty ? member.first.displayName : "Este miembro"} no tiene un teléfono cargado')),
      );
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final text = Uri.encodeComponent('Hola! Te escribo desde MiClan');
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: 'https://wa.me/$digits?text=$text',
      );
      intent.launch();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  Widget _presetBtn(QuickMessageItem item, Color color, AppUser user) {
    return GestureDetector(
      onTap: () {
        ref.read(firestoreServiceProvider).sendAlert(user, _selectedReceiver, 'quick_message', item.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enviado: ${item.title}'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withOpacity(0.28),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: Text(
          item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _showCustomMessageDialog(AppUser user) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.modalBg,
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
                ref.read(firestoreServiceProvider).sendAlert(user, _selectedReceiver, 'custom', ctrl.text.trim());
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
        backgroundColor: AppColors.modalBg,
        title: const Text('Activar S.O.S?', style: TextStyle(color: Colors.white)),
        content: const Text('Se enviara una alerta de pánico a todo el grupo.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'SOS', 'ALERTA DE Pánico ACTIVADA!');
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

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.modalBg,
        title: const Text('Cerrar sesión?', style: TextStyle(color: Colors.white)),
        content: const Text('Volveras a la pantalla de login.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) await ref.read(authServiceProvider).signOut();
  }

  void _showMembersSheet(BuildContext context, List<AppUser> members, bool isAdmin, AppGroup? group, AppUser currentUser) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.modalBg,
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
                                          messenger.showSnackBar(SnackBar(content: Text('${req.displayName} aprobado'), backgroundColor: Colors.green));
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.red),
                                        onPressed: () async {
                                          await ref.read(firestoreServiceProvider).rejectRequest(group!.id, req.uid);
                                          messenger.showSnackBar(SnackBar(content: Text('${req.displayName} rechazado'), backgroundColor: Colors.red));
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
        backgroundColor: AppColors.modalBg,
        title: Text('Expulsar a ${member.displayName}?', style: const TextStyle(color: Colors.white)),
        content: const Text('El miembro sera eliminado del grupo.', style: TextStyle(color: Colors.white70)),
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
          SnackBar(content: Text('${member.displayName} expulsado'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _onMarkerTap(BuildContext context, AppUser currentUser, AppUser tapped) {
    if (currentUser.uid == tapped.uid) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.modalBg,
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

// ============================================================================
// MODAL DE RECORRIDO EN MAPA (Bento flotante)
// ============================================================================
// FIX 2026-08-08:
// - La ventana se sube ~20mm (via margin inferior extra) para que no quede
//   pegada al borde de la pantalla.
// - Se agregan dos sliders en la cabecera para elegir fecha/hora "desde" y
//   "hasta" del muestreo (antes era un rango fijo de 24hs).
// ============================================================================
class _RouteMapModal extends ConsumerStatefulWidget {
  final String memberUid;
  final String memberName;
  final String groupId;

  const _RouteMapModal({
    required this.memberUid,
    required this.memberName,
    required this.groupId,
  });

  @override
  ConsumerState<_RouteMapModal> createState() => _RouteMapModalState();
}

class _RouteMapModalState extends ConsumerState<_RouteMapModal> {
  late final DateTime _minDate = DateTime.now().subtract(const Duration(days: 30));
  late final DateTime _maxDate = DateTime.now();
  late double _fromMs = _maxDate.subtract(const Duration(hours: 24)).millisecondsSinceEpoch.toDouble();
  late double _toMs = _maxDate.millisecondsSinceEpoch.toDouble();
  final MapController _mapController = MapController();
  int _lastFitCount = -1;

  DateTime get _desde => DateTime.fromMillisecondsSinceEpoch(_fromMs.round());
  DateTime get _hasta => DateTime.fromMillisecondsSinceEpoch(_toMs.round());

  // FIX 2026-08-09: la fecha/hora del punto tocado se muestra en un cartel
  // fijo dentro del propio bento del mapa (abajo), no como SnackBar: el
  // SnackBar aparecia detras del modal y quedaba tapado.
  DateTime? _selectedPointTime;

  /// Marcadores en cada punto del recorrido (se muestran cada pocos puntos
  /// si hay demasiados, para no saturar el mapa). El area tocable es mas
  /// grande que el punto visible para que sea facil de tocar.
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
          // FIX: area tocable mas grande (32x32) que el punto visible (10x10)
          // para que sea mas facil "embocarle" con el dedo.
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

  void _showPointTime(DateTime? dt) {
    setState(() => _selectedPointTime = dt);
  }

  /// Ajusta el zoom/centro para que se vea el recorrido completo (ampliado
  /// a los limites de los puntos cargados), en vez del zoom fijo anterior.
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

  @override
  Widget build(BuildContext context) {
    // "Subir 20mm la ventana de recorrido": margen inferior extra ademas
    // del margen simetrico habitual, para despegarla del borde inferior.
    final raise = 20 * _kMmToLogicalPx;

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
            // Header con titulo + sliders de fecha/hora desde-hasta
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
                      Icon(Icons.route, color: Colors.blue.shade300, size: 22),
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
            // Mapa
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

                      final docs = (snapshot.data ?? [])
                          .where((d) => d['groupId'] == widget.groupId)
                          .toList();
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
                                color: Colors.blue.withOpacity(0.8),
                                strokeWidth: 4,
                              ),
                            ],
                          ),
                          MarkerLayer(markers: _timeMarkers(docs, Colors.blue.shade300)),
                          MarkerLayer(
                            markers: [
                              // Inicio
                              Marker(
                                point: points.first,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
                              ),
                              // Fin
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
                  // Cartel de fecha/hora del punto tocado, dentro del bento
                  // del mapa (no un SnackBar, que quedaba tapado por el modal).
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
                            Icon(Icons.access_time, color: Colors.blue.shade200, size: 16),
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
            // Footer con contador
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

  /// FIX 2026-08-09: se reemplazan los sliders (poco precisos para elegir
  /// fecha/hora en pantallas chicas) por selectores nativos de fecha+hora,
  /// mas chips de rango rapido.
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
          color: Colors.blue.withOpacity(0.15),
          border: Border.all(color: Colors.blue.withOpacity(0.35)),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
