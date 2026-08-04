import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'database_helper.dart';

class BackupService {
  final DatabaseHelper _db = DatabaseHelper();

  Future<void> exportBackup() async {
    try {
      final locations = await _db.getAllLocations();
      final alerts = await _db.getAllAlerts();
      final backup = {'exportDate': DateTime.now().toIso8601String(), 'locations': locations, 'alerts': alerts};
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/miclan_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonEncode(backup));
      await Share.shareXFiles([XFile(file.path)], text: 'Backup MiClan - Caja Negra');
    } catch (e) { print('Error exportando: $e'); }
  }

  Future<bool> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.isEmpty) return false;
      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final backup = jsonDecode(content);
      await _db.clearAll();
      if (backup['locations'] != null) {
        for (final loc in backup['locations']) {
          await _db.insertLocation(
            loc['groupId'],
            loc['lat']?.toDouble() ?? 0,
            loc['lng']?.toDouble() ?? 0,
          );
        }
      }
      if (backup['alerts'] != null) {
        for (final alert in backup['alerts']) {
          await _db.insertAlert(
            groupId: alert['groupId'],
            alertType: alert['alertType'],
            alertData: alert['alert_data'] ?? '',
            senderId: alert['senderId'],
            senderName: alert['senderName'],
          );
        }
      }
      return true;
    } catch (e) { print('Error importando: $e'); return false; }
  }
}
