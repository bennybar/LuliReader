import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/group.dart';
import '../models/feed.dart';

class GroupDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Group group) async {
    final db = await _dbHelper.database;
    await db.insert('group', group.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Group?> getById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'group',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Group.fromMap(maps.first);
  }

  Future<List<Group>> getAll(int accountId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'group',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Group.fromMap(map)).toList();
  }

  Future<int> update(Group group) async {
    final db = await _dbHelper.database;
    return await db.update(
      'group',
      group.toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  Future<int> delete(String id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'group',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<GroupWithFeed>> getAllWithFeeds(int accountId) async {
    final db = await _dbHelper.database;
    final groups = await getAll(accountId);
    final List<GroupWithFeed> result = [];

    for (final group in groups) {
      final feedMaps = await db.query(
        'feed',
        where: 'groupId = ?',
        whereArgs: [group.id],
        orderBy: 'name ASC',
      );
      final feeds = feedMaps.map((map) => Feed.fromMap(map) as dynamic).toList();
      result.add(GroupWithFeed(group: group, feeds: feeds));
    }

    return result;
  }

  String getDefaultGroupId(int accountId) {
    return '$accountId\$default';
  }
}

