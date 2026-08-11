import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'battery_optimization_service.dart';
import 'database_helper.dart';
import 'firestore_service.dart';
import 'location_config.dart';

// ============================================================================
// BACKGROUND LOCATION SERVICE - Caja negra en segundo plano
// ============================================================================
// FIX 2026-08-10: el tracking de LocationService (stream de geolocator +
// Timer de Dart) vive por completo en el isolate principal de la UI. La
// notificación de foreground que arma geolocator ayuda a que Android no
// mate el proceso de inmediato, pero en la practica muchos fabricantes
// (y el propio Android en Doze) terminan congelando ese isolate con la
// pantalla apagada o la app minimizada, y la caja negra deja de grabar.
//
// Este servicio usa flutter_background_service para levantar un Servicio
// de Android real e independiente (su propio isolate de Dart, su propio
// ciclo de vida), que sigue vivo con la app cerrada/minimizada/telefono
// dormido, y graba un punto cada 1 o 5 minutos (segun "Modo ahorro" en
// Ajustes, ver location_config.dart), salvo que la ubicación se repita
// dentro de un margen de unos metros (mismo criterio que en primer plano).
//
// HomeScreen hace el "handoff": al pasar a segundo plano detiene el
// tracking en el isolate principal y arranca este servicio; al volver a
// primer plano lo detiene y retoma el tracking normal (mas responsivo,
// por distancia recorrida) para no grabar el mismo punto dos veces.
// ============================================================================

const int _kNotificationId = 8890;
const String _kPrefUid = 'bg_tracking_uid';
const String _kPrefGroupId = 'bg_tracking_group_id';

class BackgroundLocationService {
  static bool _configured = false;

  /// Configura (sin arrancar) el servicio. Se llama una sola vez en main().
  static Future<void> initialize() async {
    if (_configured) return;
    _configured = true;

    final service = FlutterBackgroundService();
    await service.configure(
      iosConfiguration: IosConfiguration(autoStart: false),
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: kGpsTrackingNotificationChannelId,
        initialNotificationTitle: 'GPS Activo',
        initialNotificationContent: 'MiClan activa GPS',
        foregroundServiceNotificationId: _kNotificationId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
    );
  }

  /// Arranca (o actualiza) la grabación en segundo plano para el
  /// usuario/grupo indicado.
  static Future<void> start(String uid, String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefUid, uid);
    await prefs.setString(_kPrefGroupId, groupId);

    final service = FlutterBackgroundService();
    if (await service.isRunning()) return;
    await service.startService();
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
  }
}

/// Reporta el estado de conexion de este dispositivo a Firestore
/// (`deviceStatus/{uid}`) para el panel de monitoreo del admin
/// (Configuracion > Estado de Miembros). Se llama en cada tick, ANTES del
/// intento de obtener posicion (que va en su propio try/catch), para que
/// el admin sepa que el servicio de background sigue vivo y "tickeando"
/// aunque el GPS puntual falle momentaneamente -- distingue "el servicio
/// no arranca" de "el servicio arranca pero el GPS no responde".
Future<void> _reportStatus(FirestoreService firestore, String uid, String groupId) async {
  try {
    final interval = await getTrackingInterval();
    final permission = await Geolocator.checkPermission();
    final batteryOk = await BatteryOptimizationService.isIgnoring();
    await firestore.updateDeviceStatus(
      uid,
      groupId,
      appState: 'background',
      batterySaver: interval == kBatterySaverTrackingInterval,
      backgroundLocationGranted: permission == LocationPermission.always,
      batteryOptimizationIgnored: batteryOk,
      trackingIntervalMinutes: interval.inMinutes,
    );
  } catch (_) {
    // No romper el servicio si falla el reporte de estado.
  }
}

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final db = DatabaseHelper();
  final firestore = FirestoreService();
  Timer? timer;
  bool stopped = false;

  service.on('stopService').listen((event) {
    stopped = true;
    timer?.cancel();
    service.stopSelf();
  });

  Future<void> tick() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_kPrefUid);
    final groupId = prefs.getString(_kPrefGroupId);
    if (uid == null || groupId == null) return;

    unawaited(_reportStatus(firestore, uid, groupId));

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final lastRecorded = await loadLastRecordedPosition();
      final isSameLocation = isSameAsLastRecorded(lastRecorded, position.latitude, position.longitude);

      if (isSameLocation) {
        // Ubicación repetida (dentro del margen): solo "latido", no se
        // agrega un punto nuevo a la caja negra.
        await firestore.touchLocation(uid, groupId);
      } else {
        final id = await db.insertLocation(groupId, position.latitude, position.longitude);
        await saveLastRecordedPosition(position.latitude, position.longitude);
        try {
          await firestore.updateLocation(uid, groupId, position.latitude, position.longitude);
          await db.markLocationSynced(id);
        } catch (_) {
          // Sin señal: queda pendiente, se reintenta abajo y en el
          // proximo tick.
        }
      }

      // Reintenta puntos que quedaron sin subir (por ej. grabados sin
      // señal en un tick anterior).
      final pending = await db.getUnsyncedLocations();
      for (final loc in pending) {
        try {
          await firestore.updateLocation(uid, groupId, loc['lat'], loc['lng']);
          await db.markLocationSynced(loc['id']);
        } catch (_) {}
      }
    } catch (_) {
      // GPS momentaneamente no disponible: no rompe el servicio, se
      // reintenta en el siguiente tick.
    }
    // FIX 2026-08-10: antes se llamaba a setForegroundNotificationInfo en
    // cada tick para mostrar el intervalo actual en el texto. Se saco: el
    // usuario pidio que la notificación sea solo el icono fijo en la barra
    // (ya configurado como Importance.none/estatico al arrancar el
    // servicio, ver initialize()), sin re-emitir "mensajes" cada vez que
    // se graba un punto.
  }

  Future<void> loop() async {
    if (stopped) return;
    await tick();
    if (stopped) return;
    final interval = await getTrackingInterval();
    timer = Timer(interval, loop);
  }

  // Primer punto apenas arranca el servicio (no espera el intervalo
  // completo), y despues sigue con el intervalo configurado.
  await loop();
}
