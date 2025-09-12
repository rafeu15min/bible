// lib/services/database_helper.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    String dbPath = await getDatabasesPath();
    String path = p.join(dbPath, 'bible.db');

    bool dbExists = await databaseExists(path);
    if (!dbExists) {
      try {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load(p.join('assets', 'bible.db'));
        List<int> bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) {
        // Tratar erro
      }
    }
    return await openDatabase(path, version: 1);
  }

  Future<List<Book>> getAllBooks() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT b.Id_book, b.Name_book, b.Abbreviation_book, COUNT(c.Id_chapter) as chapter_count
      FROM Book b
      LEFT JOIN Chapter c ON b.Id_book = c.Id_book
      WHERE c.Number_chapter > 0
      GROUP BY b.Id_book, b.Name_book
      ORDER BY b.Id_book ASC
    ''');
    return List.generate(maps.length, (i) {
      return Book(
        maps[i]['Id_book'],
        maps[i]['Name_book'],
        maps[i]['Abbreviation_book'],
        maps[i]['chapter_count'],
      );
    });
  }

  Future<List<Map<String, dynamic>>> loadAllBibleData() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT
        b.Id_book, b.Name_book, b.Abbreviation_book,
        c.Number_chapter,
        v.number_verse, v.content_verse
      FROM Verse v
      INNER JOIN Chapter c ON v.Id_chapter = c.Id_chapter
      INNER JOIN Book b ON c.Id_book = b.Id_book
      WHERE c.Number_chapter > 0
      ORDER BY b.Id_book ASC, c.Number_chapter ASC, CAST(v.number_verse AS INTEGER) ASC
    ''');
  }
}
