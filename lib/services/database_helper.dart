import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  _initDB() async {
    String path = join(await getDatabasesPath(), 'miclan_cajanegra.db');
    return await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        groupId TEXT,
        lat REAL,
        lng REAL,
        timestamp TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        groupId TEXT,
        alertType TEXT,
        alertData TEXT,
        senderId TEXT,
        senderName TEXT,
        timestamp TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');
  }

  _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE locations ADD COLUMN groupId TEXT');
      await db.execute('ALTER TABLE alerts ADD COLUMN groupId TEXT');
      await db.execute('ALTER TABLE alerts ADD COLUMN alertType TEXT');
      await db.execute('ALTER TABLE alerts ADD COLUMN senderId TEXT');
      await db.execute('ALTER TABLE alerts ADD COLUMN senderName TEXT');
    }
  }

  Future<void> insertLocation(String? groupId, double lat, double lng) async {
    final db = await database;
    await db.insert('locations', {
      'groupId': groupId,
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': 0,
    });
    await _rotateLocations(groupId);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLocations() async {
    final db = await database;
    return await db.query('locations', where: 'synced = ?', whereArgs: [0]);
  }

  Future<void> markLocationSynced(int id) async {
    final db = await database;
    await db.update('locations', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllLocations() async {
    final db = await database;
    return await db.query('locations', orderBy: 'timestamp DESC');
  }

  /// NUEVO: Obtener ubicaciones de los ultimos N dias (local).
  Future<List<Map<String, dynamic>>> getLocationsLastDays(int days) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return await db.query(
      'locations',
      where: 'timestamp >= ?',
      whereArgs: [since],
      orderBy: 'timestamp DESC',
    );
  }

  Future<void> _rotateLocations(String? groupId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM locations WHERE groupId = ?',
      [groupId],
    )) ?? 0;
    if (count > 300) {
      final toDelete = count - 300;
      final rows = await db.query(
        'locations',
        where: 'groupId = ?',
        whereArgs: [groupId],
        orderBy: 'timestamp ASC',
        limit: toDelete,
      );
      for (final row in rows) {
        await db.delete('locations', where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  Future<void> insertAlert({
    String? groupId,
    String? alertType,
    required String alertData,
    String? senderId,
    String? senderName,
  }) async {
    final db = await database;
    await db.insert('alerts', {
      'groupId': groupId,
      'alertType': alertType,
      'alertData': alertData,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': 0,
    });
    await _rotateAlerts(groupId);
  }

  Future<List<Map<String, dynamic>>> getAllAlerts() async {
    final db = await database;
    return await db.query('alerts', orderBy: 'timestamp DESC');
  }

  Future<void> _rotateAlerts(String? groupId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM alerts WHERE groupId = ?',
      [groupId],
    )) ?? 0;
    if (count > 300) {
      final toDelete = count - 300;
      final rows = await db.query(
        'alerts',
        where: 'groupId = ?',
        whereArgs: [groupId],
        orderBy: 'timestamp ASC',
        limit: toDelete,
      );
      for (final row in rows) {
        await db.delete('alerts', where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('locations');
    await db.delete('alerts');
  }
}