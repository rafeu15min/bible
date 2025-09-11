import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart'
    as p; // CORREÇÃO: Import com apelido para evitar conflito.
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
    // CORREÇÃO: Usa o apelido 'p' para a função join.
    String path = p.join(dbPath, 'bible.db');

    bool dbExists = await databaseExists(path);
    if (!dbExists) {
      try {
        // CORREÇÃO: Usa o apelido 'p' para a função dirname.
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
  // Controladores para a lista rolável
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  Future<bool>? _initializationFuture;
  List<Book> _allBooks = [];
  final List<ListItem> _displayItems = [];
  final Map<String, int> _chapterIndexMap = {};

  bool _isLoading = false;

  String _appBarTitle = 'Bíblia';
  String _bottomBarText = 'Gênesis: 1';

  MapEntry<int, int> _lastLoadedChapter = const MapEntry(0, 0);

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_updateUIFromScroll);
    _initializationFuture = _initialize();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_updateUIFromScroll);
    super.dispose();
  }

  Future<bool> _initialize() async {
    _allBooks = await DatabaseHelper.instance.getAllBooks();
    if (_allBooks.isNotEmpty) {
      _lastLoadedChapter = MapEntry(_allBooks.first.id, 0);
      await _loadMore(isInitialLoad: true);
      return true;
    }
    return false;
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

  Future<void> _loadMore({bool isInitialLoad = false}) async {
    if (_isLoading) return;
    if (mounted)
      setState(() {
        _isLoading = true;
      });

    final newItemsBatch = <ListItem>[];
    int chaptersToLoadCount = isInitialLoad ? 10 : 5;

    try {
      for (int i = 0; i < chaptersToLoadCount; i++) {
        int bookIdToQuery = _lastLoadedChapter.key;
        int nextChapterNumber = _lastLoadedChapter.value + 1;

        final currentBookIndex =
            _allBooks.indexWhere((b) => b.id == bookIdToQuery);
        if (currentBookIndex == -1) break;

        final currentBook = _allBooks[currentBookIndex];

        if (nextChapterNumber > currentBook.chapterCount) {
          if (currentBookIndex + 1 < _allBooks.length) {
            final nextBook = _allBooks[currentBookIndex + 1];
            _lastLoadedChapter = MapEntry(nextBook.id, 0);
            continue;
          } else {
            break;
          }
        } else {
          _lastLoadedChapter = MapEntry(bookIdToQuery, nextChapterNumber);
        }

        final currentBookId = _lastLoadedChapter.key;
        final currentChapterNumber = _lastLoadedChapter.value;
        final bookForDisplay =
            _allBooks.firstWhere((b) => b.id == currentBookId);

        final chapterKey = '$currentBookId-$currentChapterNumber';
        _chapterIndexMap[chapterKey] =
            _displayItems.length + newItemsBatch.length;

        final versesMaps = await DatabaseHelper.instance
            .getVersesForChapter(currentBookId, currentChapterNumber);
        if (versesMaps.isNotEmpty) {
          if (currentChapterNumber == 1) {
            newItemsBatch
                .add(BookMarker(bookForDisplay.name, bookForDisplay.id));
          }
          newItemsBatch.add(ChapterMarker(
              currentChapterNumber, bookForDisplay.id, bookForDisplay.name));
          for (var map in versesMaps) {
            newItemsBatch.add(Verse(
                map['number_verse'].toString(),
                map['content_verse'],
                bookForDisplay.id,
                bookForDisplay.name,
                currentChapterNumber));
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _displayItems.addAll(newItemsBatch);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _jumpToChapter(int bookId, int chapterNum) async {
    final chapterKey = '$bookId-$chapterNum';

    if (_chapterIndexMap.containsKey(chapterKey)) {
      _itemScrollController.jumpTo(index: _chapterIndexMap[chapterKey]!);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _displayItems.clear();
          _chapterIndexMap.clear();
          _lastLoadedChapter = MapEntry(bookId, chapterNum - 1);
        });
      }
      await _loadMore(isInitialLoad: true);
    }
  }

  void _navigateToChapterByDirection(int direction) {
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
    _jumpToChapter(targetBook.id, targetChapterNum);
  }

  void _showBookChapterSelector() async {
    if (_allBooks.isEmpty) return;

    final currentBook = _allBooks.firstWhere((b) => b.name == _appBarTitle,
        orElse: () => _allBooks.first);

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (BuildContext context) => BookChapterSelectorDialog(
        allBooks: _allBooks,
        initialBook: currentBook,
      ),
    );

    if (result != null &&
        result.containsKey('bookId') &&
        result.containsKey('chapter')) {
      _jumpToChapter(result['bookId']!, result['chapter']!);
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
                  Text("Carregando a Bíblia...",
                      style: TextStyle(fontSize: 16)),
                  Text("(Isso pode levar alguns segundos na primeira vez)"),
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
                itemCount: _displayItems.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _displayItems.length) {
                    if (!_isLoading) {
                      Future.microtask(() => _loadMore());
                    }
                    return const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
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
                          _buildNavButton(Icons.chevron_left,
                              () => _navigateToChapterByDirection(-1)),
                          _buildNavButtonWithText(
                              _bottomBarText, _showBookChapterSelector),
                          _buildNavButton(Icons.chevron_right,
                              () => _navigateToChapterByDirection(1)),
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

  Widget _buildNavButtonWithText(String text, VoidCallback onPressed) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Center(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
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

// --- NOVO WIDGET: A caixa de diálogo para selecionar Livro e Capítulo ---

class BookChapterSelectorDialog extends StatefulWidget {
  final List<Book> allBooks;
  final Book initialBook;

  const BookChapterSelectorDialog({
    Key? key,
    required this.allBooks,
    required this.initialBook,
  }) : super(key: key);

  @override
  _BookChapterSelectorDialogState createState() =>
      _BookChapterSelectorDialogState();
}

class _BookChapterSelectorDialogState extends State<BookChapterSelectorDialog> {
  late Book _selectedBook;

  @override
  void initState() {
    super.initState();
    _selectedBook = widget.initialBook;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar Passagem'),
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seletor de Livros
            DropdownButtonFormField<Book>(
              value: _selectedBook,
              isExpanded: true,
              items: widget.allBooks.map((book) {
                return DropdownMenuItem<Book>(
                  value: book,
                  child: Text(book.name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (Book? newBook) {
                if (newBook != null) {
                  setState(() {
                    _selectedBook = newBook;
                  });
                }
              },
              decoration: const InputDecoration(
                labelText: 'Livro',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Grade de Capítulos
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _selectedBook.chapterCount,
                itemBuilder: (context, index) {
                  final chapterNumber = index + 1;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop({
                        'bookId': _selectedBook.id,
                        'chapter': chapterNumber,
                      });
                    },
                    child: Center(
                      child: Text(
                        '$chapterNumber',
                        style: TextStyle(fontSize: 10.0),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
