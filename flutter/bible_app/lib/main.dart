import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// --- Modelos de Dados ---

// Cada item da lista agora conhece o livro e capítulo ao qual pertence.
abstract class ListItem {
  final int bookId;
  final String bookName;
  final int chapterNumber;
  ListItem(this.bookId, this.bookName, this.chapterNumber);
}

class BookMarker extends ListItem {
  BookMarker(String bookName, int bookId) : super(bookId, bookName, 1);
}

class ChapterMarker extends ListItem {
  ChapterMarker(int chapterNumber, int bookId, String bookName)
      : super(bookId, bookName, chapterNumber);
}

class Verse extends ListItem {
  final String verseNumber;
  final String content;
  Verse(this.verseNumber, this.content, int bookId, String bookName,
      int chapterNumber)
      : super(bookId, bookName, chapterNumber);
}

class Book {
  final int id;
  final String name;
  final int chapterCount;
  Book(this.id, this.name, this.chapterCount);
}

// --- Classe Auxiliar do Banco de Dados ---
class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    String dbPath = await getDatabasesPath();
    String path = join(dbPath, 'bible.db');

    bool dbExists = await databaseExists(path);
    if (!dbExists) {
      try {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load(join('assets', 'bible.db'));
        List<int> bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) {
        // Tratar erro
      }
    }
    return await openDatabase(path, version: 1);
  }

  // Busca todos os livros com sua respectiva contagem de capítulos.
  Future<List<Book>> getAllBooks() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT b.Id_book, b.Name_book, COUNT(c.Id_chapter) as chapter_count
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
        maps[i]['chapter_count'],
      );
    });
  }

  // NOVO: Carrega toda a Bíblia de uma vez para a memória.
  Future<List<Map<String, dynamic>>> loadAllBibleData() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT
        b.Id_book, b.Name_book,
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

// --- Ponto de Entrada do Aplicativo ---
void main() {
  runApp(const BibleApp());
}

class BibleApp extends StatelessWidget {
  const BibleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leitor da Bíblia',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          elevation: 4,
          titleTextStyle: TextStyle(color: Colors.white70, fontSize: 20),
          iconTheme: IconThemeData(color: Colors.white70),
        ),
      ),
      home: const BibleReaderScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Tela Principal do Aplicativo ---
class BibleReaderScreen extends StatefulWidget {
  const BibleReaderScreen({Key? key}) : super(key: key);

  @override
  BibleReaderScreenState createState() => BibleReaderScreenState();
}

class BibleReaderScreenState extends State<BibleReaderScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late Future<bool> _initializationFuture;
  List<Book> _allBooks = [];
  final List<ListItem> _displayItems = [];
  final Map<String, int> _chapterIndexMap = {};

  String _appBarTitle = 'Bíblia';
  String _bottomBarText = 'Gênesis: 1';

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_updateUIFromScroll);
    _initializationFuture = _initializeAndBuildList();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_updateUIFromScroll);
    super.dispose();
  }

  // LÓGICA ATUALIZADA: Carrega e processa tudo de uma vez.
  Future<bool> _initializeAndBuildList() async {
    _allBooks = await DatabaseHelper.instance.getAllBooks();
    if (_allBooks.isEmpty) return false;

    final allVersesData = await DatabaseHelper.instance.loadAllBibleData();
    if (allVersesData.isEmpty) return false;

    int currentBookId = -1;
    int currentChapter = -1;

    for (var i = 0; i < allVersesData.length; i++) {
      final row = allVersesData[i];
      final bookId = row['Id_book'] as int;
      final bookName = row['Name_book'] as String;
      final chapterNumber = row['Number_chapter'] as int;
      final verseNumber = row['number_verse'].toString();
      final verseContent = row['content_verse'] as String;

      if (bookId != currentBookId) {
        _displayItems.add(BookMarker(bookName, bookId));
        currentBookId = bookId;
        currentChapter = 0;
      }

      if (chapterNumber != currentChapter) {
        final chapterKey = '$bookId-$chapterNumber';
        _chapterIndexMap[chapterKey] = _displayItems.length;
        _displayItems.add(ChapterMarker(chapterNumber, bookId, bookName));
        currentChapter = chapterNumber;
      }

      _displayItems.add(
          Verse(verseNumber, verseContent, bookId, bookName, chapterNumber));
    }

    if (mounted) {
      setState(() {
        _appBarTitle = _allBooks.first.name;
        _bottomBarText = '${_allBooks.first.name}: 1';
      });
    }

    return true;
  }

  void _updateUIFromScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    try {
      final firstVisibleItemIndex = positions
          .where((pos) => pos.itemLeadingEdge < 1)
          .map((pos) => pos.index)
          .reduce((min, e) => e < min ? e : min);

      if (firstVisibleItemIndex < _displayItems.length) {
        final topItem = _displayItems[firstVisibleItemIndex];
        if (_appBarTitle != topItem.bookName ||
            _bottomBarText != '${topItem.bookName}: ${topItem.chapterNumber}') {
          setState(() {
            _appBarTitle = topItem.bookName;
            _bottomBarText = '${topItem.bookName}: ${topItem.chapterNumber}';
          });
        }
      }
    } catch (e) {
      // Ignora erro
    }
  }

  void _navigateToChapter(int direction) {
    final parts = _bottomBarText.split(': ');
    if (parts.length < 2) return;

    final currentBookName = parts[0];
    final currentChapterNum = int.tryParse(parts[1]) ?? 1;
    final currentBookIndex =
        _allBooks.indexWhere((b) => b.name == currentBookName);
    if (currentBookIndex == -1) return;

    final currentBook = _allBooks[currentBookIndex];
    int targetBookIndex = currentBookIndex;
    int targetChapterNum = currentChapterNum + direction;

    if (targetChapterNum > currentBook.chapterCount) {
      if (currentBookIndex + 1 < _allBooks.length) {
        targetBookIndex++;
        targetChapterNum = 1;
      } else {
        targetChapterNum = currentBook.chapterCount;
      }
    } else if (targetChapterNum < 1) {
      if (currentBookIndex > 0) {
        targetBookIndex--;
        targetChapterNum = _allBooks[targetBookIndex].chapterCount;
      } else {
        targetChapterNum = 1;
      }
    }

    final targetBook = _allBooks[targetBookIndex];
    final chapterKey = '${targetBook.id}-$targetChapterNum';

    if (_chapterIndexMap.containsKey(chapterKey)) {
      _itemScrollController.jumpTo(index: _chapterIndexMap[chapterKey]!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
      ),
      body: FutureBuilder<bool>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Carregando...", style: TextStyle(fontSize: 16)),
                  Text("(Isso pode levar alguns segundos)"),
                ],
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == false) {
            return const Center(
                child: Text("Erro ao carregar o banco de dados."));
          }

          return Stack(
            children: [
              ScrollablePositionedList.builder(
                itemScrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                itemCount: _displayItems.length,
                itemBuilder: (context, index) {
                  return _buildListItem(_displayItems[index]);
                },
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                          stops: const [
                        0.0,
                        1.0
                      ])),
                  child: BottomAppBar(
                    color: Colors.transparent,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildNavButton(
                              Icons.chevron_left, () => _navigateToChapter(-1)),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withOpacity(0.9),
                            ),
                            child: Text(
                              _bottomBarText,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildNavButton(
                              Icons.chevron_right, () => _navigateToChapter(1)),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white70, size: 30),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildListItem(ListItem item) {
    if (item is BookMarker) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        alignment: Alignment.center,
        child: Text(
          item.bookName,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      );
    }

    if (item is ChapterMarker) {
      return Padding(
        padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
        child: Text(
          'Capítulo ${item.chapterNumber}',
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E)),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (item is Verse) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.verseNumber} ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  fontSize: 16),
            ),
            Expanded(
              child: Text(
                item.content,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
