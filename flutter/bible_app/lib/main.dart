import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

// --- Modelos de Dados ---

// Cada item da lista agora conhece o livro ao qual pertence.
abstract class ListItem {
  final int bookId;
  final String bookName;
  ListItem(this.bookId, this.bookName);
}

class BookMarker extends ListItem {
  BookMarker(String bookName, int bookId) : super(bookId, bookName);
}

class ChapterMarker extends ListItem {
  final int chapterNumber;
  ChapterMarker(this.chapterNumber, int bookId, String bookName)
      : super(bookId, bookName);
}

class Verse extends ListItem {
  final String verseNumber;
  final String content;
  Verse(this.verseNumber, this.content, int bookId, String bookName)
      : super(bookId, bookName);
}

class Book {
  final int id;
  final String name;
  Book(this.id, this.name);
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
        // Tratar erro em um app de produção (ex: logging)
      }
    }
    return await openDatabase(path, version: 1);
  }

  // Busca todos os livros em ordem canônica
  Future<List<Book>> getAllBooks() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps =
        await db.query('Book', orderBy: 'Id_book ASC');
    return List.generate(maps.length, (i) {
      return Book(
        maps[i]['Id_book'],
        maps[i]['Name_book'],
      );
    });
  }

  // Busca os versículos de um capítulo específico
  Future<List<Map<String, dynamic>>> getVersesForChapter(
      int bookId, int chapterNumber) async {
    Database db = await instance.database;
    return await db.rawQuery('''
      SELECT v.number_verse, v.content_verse
      FROM Verse v
      INNER JOIN Chapter c ON v.Id_chapter = c.Id_chapter
      WHERE c.Id_book = ? AND c.Number_chapter = ?
      ORDER BY CAST(v.number_verse AS INTEGER)
    ''', [bookId, chapterNumber]);
  }
}

// --- Ponto de Entrada do Aplicativo ---
void main() {
  // Garante que o detector de visibilidade seja inicializado.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
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
  final ScrollController _scrollController = ScrollController();

  List<Book> _allBooks = [];
  final List<ListItem> _displayItems = [];

  bool _isLoading = false;
  bool _isInitialized = false;
  String _appBarTitle = 'Bíblia';
  int _currentAppBarBookId = 0;

  // NOVO: Conjunto para rastrear os índices de TODOS os itens visíveis.
  final Set<int> _visibleItemIndices = {};

  // Rastreia o último capítulo carregado para saber qual será o próximo.
  MapEntry<int, int> _lastLoadedChapter = const MapEntry(0, 0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _allBooks = await DatabaseHelper.instance.getAllBooks();
    if (_allBooks.isNotEmpty) {
      setState(() {
        _appBarTitle = _allBooks.first.name;
        _currentAppBarBookId = _allBooks.first.id;
        _lastLoadedChapter = MapEntry(_allBooks.first.id, 0);
        _isInitialized = true;
      });
      _loadMore(isInitialLoad: true);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500 && !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadMore({bool isInitialLoad = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    List<ListItem> newItems = [];
    int chaptersToLoadCount = isInitialLoad ? 3 : 1;

    for (int i = 0; i < chaptersToLoadCount; i++) {
      int bookIdToQuery = _lastLoadedChapter.key;
      int nextChapterNumber = _lastLoadedChapter.value + 1;

      final db = await DatabaseHelper.instance.database;
      final chapterInDb = await db.query('Chapter',
          where: 'Id_book = ? and Number_chapter = ?',
          whereArgs: [bookIdToQuery, nextChapterNumber]);

      if (chapterInDb.isNotEmpty) {
        _lastLoadedChapter = MapEntry(bookIdToQuery, nextChapterNumber);
      } else {
        final currentBookIndex =
            _allBooks.indexWhere((b) => b.id == bookIdToQuery);
        if (currentBookIndex + 1 < _allBooks.length) {
          final nextBook = _allBooks[currentBookIndex + 1];
          _lastLoadedChapter = MapEntry(nextBook.id, 1);
        } else {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      final currentBookId = _lastLoadedChapter.key;
      final currentChapterNumber = _lastLoadedChapter.value;
      final currentBook = _allBooks.firstWhere((b) => b.id == currentBookId);

      final versesMaps = await DatabaseHelper.instance
          .getVersesForChapter(currentBookId, currentChapterNumber);

      if (versesMaps.isNotEmpty) {
        if (currentChapterNumber == 1) {
          newItems.add(BookMarker(currentBook.name, currentBook.id));
        }
        newItems.add(ChapterMarker(
            currentChapterNumber, currentBook.id, currentBook.name));
        for (var map in versesMaps) {
          newItems.add(Verse(map['number_verse'].toString(),
              map['content_verse'], currentBook.id, currentBook.name));
        }
      }
    }

    if (mounted) {
      setState(() {
        _displayItems.addAll(newItems);
        _isLoading = false;
      });
    }
  }

  // LÓGICA ATUALIZADA: Esta função agora usa o item mais ao topo da tela.
  void _updateAppBarTitleFromVisibleItems() {
    if (_visibleItemIndices.isEmpty || _displayItems.isEmpty) return;

    // Encontra o menor índice na lista de visíveis (o que está mais ao topo).
    final topIndex = _visibleItemIndices.reduce((min, e) => e < min ? e : min);

    // Garante que o índice é válido
    if (topIndex >= _displayItems.length) return;

    final topItem = _displayItems[topIndex];

    // Atualiza o título apenas se o livro do topo mudou.
    if (topItem.bookId != _currentAppBarBookId) {
      setState(() {
        _currentAppBarBookId = topItem.bookId;
        _appBarTitle = topItem.bookName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_appBarTitle, style: const TextStyle(color: Colors.white70)),
        elevation: 1,
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _scrollController,
              cacheExtent: 1000.0,
              itemCount: _displayItems.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _displayItems.length) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final item = _displayItems[index];

                // NOVO: O VisibilityDetector agora envolve cada item para uma detecção precisa.
                return VisibilityDetector(
                  key: Key('item_$index'),
                  onVisibilityChanged: (info) {
                    if (info.visibleFraction > 0) {
                      _visibleItemIndices.add(index);
                    } else {
                      _visibleItemIndices.remove(index);
                    }
                    _updateAppBarTitleFromVisibleItems();
                  },
                  child: _buildListItem(item),
                );
              },
            ),
    );
  }

  // NOVO: Widget separado para construir os itens da lista, mantendo o builder limpo.
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
