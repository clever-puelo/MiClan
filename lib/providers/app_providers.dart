import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/geofence_service.dart';
import '../services/backup_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final firestoreServiceProvider = Provider((ref) => FirestoreService());
final locationServiceProvider = Provider((ref) => LocationService());
final storageServiceProvider = Provider((ref) => StorageService());
final geofenceServiceProvider = Provider((ref) => GeofenceService());
final backupServiceProvider = Provider((ref) => BackupService());

final currentUserProvider = StreamProvider<AppUser>((ref) => ref.watch(authServiceProvider).currentUserStream);

final currentGroupProvider = StreamProvider<AppGroup?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user?.groupId == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).getGroupStream(user!.groupId!);
});

final groupMembersProvider = StreamProvider<List<AppUser>>((ref) {
  final group = ref.watch(currentGroupProvider).value;
  if (group == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).getGroupMembersStream(group.id);
});

final memberLocationProvider = StreamProvider.family<LatLng?, String>((ref, uid) {
  return ref.watch(firestoreServiceProvider).getLocationStream(uid);
});

final groupAlertsProvider = StreamProvider<List<AppAlert>>((ref) {
  final group = ref.watch(currentGroupProvider).value;
  if (group == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).getGroupAlertsStream(group.id);
});

final geofenceZoneProvider = StreamProvider<GeofenceZone?>((ref) {
  final group = ref.watch(currentGroupProvider).value;
  if (group == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).getGeofenceStream(group.id);
});