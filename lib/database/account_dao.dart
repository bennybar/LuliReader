import '../database/database_helper.dart';
import '../models/account.dart';

class AccountDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insert(Account account) async {
    final db = await _dbHelper.database;
    return await db.insert('account', account.toMap());
  }

  Future<Account?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'account',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Account.fromMap(maps.first);
  }

  Future<List<Account>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('account', orderBy: 'id ASC');
    return maps.map((map) => Account.fromMap(map)).toList();
  }

  Future<int> update(Account account) async {
    final db = await _dbHelper.database;
    return await db.update(
      'account',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'account',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

