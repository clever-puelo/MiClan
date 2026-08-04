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
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE locations (id INTEGER PRIMARY KEY AUTOINCREMENT, lat REAL, lng REAL, timestamp TEXT, synced INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE alerts (id INTEGER PRIMARY KEY AUTOINCREMENT, alert_data TEXT, timestamp TEXT, synced INTEGER DEFAULT 0)''');
  }

  Future<void> insertLocation(double lat, double lng) async {
    final db = await database;
    await db.insert('locations', {'lat': lat, 'lng': lng, 'timestamp': DateTime.now().toIso8601String(), 'synced': 0});
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
    return await db.query('locations');
  }

  Future<List<Map<String, dynamic>>> getAllAlerts() async {
    final db = await database;
    return await db.query('alerts');
  }

  Future<void> insertAlert(String alertData) async {
    final db = await database;
    await db.insert('alerts', {'alert_data': alertData, 'timestamp': DateTime.now().toIso8601String(), 'synced': 0});
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('locations');
    await db.delete('alerts');
  }
}