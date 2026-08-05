import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/geofence_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final firestoreServiceProvider = Provider((ref) => FirestoreService());
final locationServiceProvider = Provider((ref) => LocationService());
final storageServiceProvider = Provider((ref) => StorageService());
final geofenceServiceProvider = Provider((ref) => GeofenceService());
final backupServiceProvider = Provider((ref) => BackupService());

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).currentUserStream;
});

final currentGroupProvider = StreamProvider<AppGroup?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user?.groupId == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).getGroupStream(user!.groupId!);
});

final groupMembersProvider = StreamProvider<List<AppUser>>((ref) {
  final group = ref.watch(currentGroupProvider).valueOrNull;
  if (group == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).getGroupMembersStream(group.id);
});

final pendingRequestsProvider = StreamProvider<List<PendingRequest>>((ref) {
  final group = ref.watch(currentGroupProvider).valueOrNull;
  if (group == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).getPendingRequestsStream(group.id);
});

final memberLocationProvider = StreamProvider.family<LatLng?, String>((ref, uid) {
  return ref.watch(firestoreServiceProvider).getLocationStream(uid);
});

final groupAlertsProvider = StreamProvider<List<AppAlert>>((ref) {
  final group = ref.watch(currentGroupProvider).valueOrNull;
  if (group == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).getGroupAlertsStream(group.id);
});

final activeSOSProvider = StreamProvider<AppAlert?>((ref) {
  final group = ref.watch(currentGroupProvider).valueOrNull;
  if (group == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).getActiveSOSStream(group.id);
});

final geofenceZoneProvider = StreamProvider<GeofenceZone?>((ref) {
  final group = ref.watch(currentGroupProvider).valueOrNull;
  if (group == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).getGeofenceStream(group.id);
});
