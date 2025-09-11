import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// --- Modelos de Dados ---

// Cada item da lista agora conhece o livro, a abreviação e o capítulo.
abstract class ListItem {
  final int bookId;
  final String bookName;
  final String? bookAbbreviation;
  final int chapterNumber;
  ListItem(
      this.bookId, this.bookName, this.bookAbbreviation, this.chapterNumber);
}

class BookMarker extends ListItem {
  BookMarker(String bookName, int bookId, String? bookAbbreviation)
      : super(bookId, bookName, bookAbbreviation, 1);
}

class ChapterMarker extends ListItem {
  ChapterMarker(
      int chapterNumber, int bookId, String bookName, String? bookAbbreviation)
      : super(bookId, bookName, bookAbbreviation, chapterNumber);
}

class Verse extends ListItem {
  final String verseNumber;
  final String content;
  Verse(this.verseNumber, this.content, int bookId, String bookName,
      String? bookAbbreviation, int chapterNumber)
      : super(bookId, bookName, bookAbbreviation, chapterNumber);
}

class Book {
  final int id;
  final String name;
  final String? abbreviation;
  final int chapterCount;
  Book(this.id, this.name, this.abbreviation, this.chapterCount);
}

// --- Classe Auxiliar do Banco de Dados ---
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

  // Busca todos os livros com sua respectiva contagem de capítulos e abreviação.
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

  // Carrega toda a Bíblia de uma vez para a memória.
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
  String _bottomBarText = 'Gn 1'; // Formato inicial

  SelectedContent? _selectedContent;

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

  Future<bool> _initializeAndBuildList() async {
    _allBooks = await DatabaseHelper.instance.getAllBooks();
    if (_allBooks.isEmpty) return false;

    final allVersesData = await DatabaseHelper.instance.loadAllBibleData();
    if (allVersesData.isEmpty) return false;

    int currentBookId = -1;
    int currentChapter = -1;

    for (var row in allVersesData) {
      final bookId = row['Id_book'] as int;
      final bookName = row['Name_book'] as String;
      final bookAbbreviation = row['Abbreviation_book'] as String?;
      final chapterNumber = row['Number_chapter'] as int;
      final verseNumber = row['number_verse'].toString();
      final verseContent = row['content_verse'] as String;

      if (bookId != currentBookId) {
        _displayItems.add(BookMarker(bookName, bookId, bookAbbreviation));
        currentBookId = bookId;
        currentChapter = 0;
      }

      if (chapterNumber != currentChapter) {
        final chapterKey = '$bookId-$chapterNumber';
        _chapterIndexMap[chapterKey] = _displayItems.length;
        _displayItems.add(
            ChapterMarker(chapterNumber, bookId, bookName, bookAbbreviation));
        currentChapter = chapterNumber;
      }

      _displayItems.add(Verse(verseNumber, verseContent, bookId, bookName,
          bookAbbreviation, chapterNumber));
    }

    if (mounted) {
      setState(() {
        final firstBook = _allBooks.first;
        _appBarTitle = firstBook.name;
        _bottomBarText = '${firstBook.abbreviation ?? firstBook.name} 1';
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
        final newBottomBarText =
            '${topItem.bookAbbreviation ?? topItem.bookName} ${topItem.chapterNumber}';

        if (_appBarTitle != topItem.bookName ||
            _bottomBarText != newBottomBarText) {
          setState(() {
            _appBarTitle = topItem.bookName;
            _bottomBarText = newBottomBarText;
          });
        }
      }
    } catch (e) {
      // Ignora erro
    }
  }

  void _navigateToChapter(int direction) {
    final currentBook = _allBooks.firstWhere((b) => b.name == _appBarTitle,
        orElse: () => _allBooks.first);
    final chapterString = _bottomBarText.split(' ').last;
    final currentChapterNum = int.tryParse(chapterString) ?? 1;

    int targetBookIndex = _allBooks.indexOf(currentBook);
    int targetChapterNum = currentChapterNum + direction;

    if (targetChapterNum > currentBook.chapterCount) {
      if (targetBookIndex + 1 < _allBooks.length) {
        targetBookIndex++;
        targetChapterNum = 1;
      } else {
        targetChapterNum = currentBook.chapterCount;
      }
    } else if (targetChapterNum < 1) {
      if (targetBookIndex > 0) {
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

  // FUNÇÃO DE CÓPIA TOTALMENTE REESCRITA E OTIMIZADA
  Future<void> _copySelectionWithReference() async {
    final selection = _selectedContent?.plainText;
    if (selection == null || selection.isEmpty) return;

    final currentBook = _allBooks.firstWhere((b) => b.name == _appBarTitle,
        orElse: () => _allBooks.first);
    final chapterString = _bottomBarText.split(' ').last;
    final currentChapterNum = int.tryParse(chapterString) ?? 1;

    // Busca apenas os versículos do capítulo atual para análise
    final versesInChapter = _displayItems
        .whereType<Verse>()
        .where((v) =>
            v.bookId == currentBook.id && v.chapterNumber == currentChapterNum)
        .toList();

    final List<Verse> involvedVerses = [];
    for (final verse in versesInChapter) {
      // Verifica se a seleção contém o texto completo do versículo ou vice-versa
      final verseFullText = '${verse.verseNumber} ${verse.content}';
      if (selection.contains(verseFullText) ||
          verseFullText.contains(selection)) {
        involvedVerses.add(verse);
      }
    }

    if (involvedVerses.isEmpty) {
      Clipboard.setData(ClipboardData(text: selection));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Texto copiado!')),
        );
      }
      return;
    }

    involvedVerses.sort(
        (a, b) => int.parse(a.verseNumber).compareTo(int.parse(b.verseNumber)));
    final firstVerse = involvedVerses.first;
    final lastVerse = involvedVerses.last;

    final bookAbbr = firstVerse.bookAbbreviation ?? firstVerse.bookName;
    final chapter = firstVerse.chapterNumber;

    String reference;
    if (firstVerse.verseNumber == lastVerse.verseNumber) {
      reference = '$bookAbbr $chapter:${firstVerse.verseNumber}';
    } else {
      reference =
          '$bookAbbr $chapter:${firstVerse.verseNumber}-${lastVerse.verseNumber}';
    }

    // Monta o texto copiado com o conteúdo completo dos versículos envolvidos
    final copiedText =
        involvedVerses.map((v) => '${v.verseNumber} ${v.content}').join(' ');
    final finalString = '$reference "$copiedText"';

    await Clipboard.setData(ClipboardData(text: finalString));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copiado com referência!')),
      );
    }
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
      final chapterKey = '${result['bookId']}-${result['chapter']}';
      if (_chapterIndexMap.containsKey(chapterKey)) {
        _itemScrollController.jumpTo(index: _chapterIndexMap[chapterKey]!);
      }
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
                  Text("Carregando toda a Bíblia...",
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
              SelectionArea(
                onSelectionChanged: (SelectedContent? content) {
                  setState(() {
                    _selectedContent = content;
                  });
                },
                // MENU DE CONTEXTO ATUALIZADO
                contextMenuBuilder: (context, editableTextState) {
                  final List<ContextMenuButtonItem> buttonItems =
                      editableTextState.contextMenuButtonItems;
                  // Remove o botão "Selecionar Tudo"
                  buttonItems.removeWhere(
                      (item) => item.type == ContextMenuButtonType.selectAll);

                  // Adiciona o nosso botão personalizado
                  buttonItems.insert(
                      1,
                      ContextMenuButtonItem(
                        onPressed: () {
                          _copySelectionWithReference();
                          editableTextState.hideToolbar();
                        },
                        label: 'Copiar com Referência',
                      ));

                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: buttonItems,
                  );
                },
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  itemCount: _displayItems.length,
                  itemBuilder: (context, index) {
                    return _buildListItem(_displayItems[index]);
                  },
                ),
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
                        const Color.fromRGBO(0, 0, 0, 0.7),
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
                          _buildNavButtonWithText(
                              _bottomBarText, _showBookChapterSelector),
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
        color: const Color.fromRGBO(0, 0, 0, 0.25),
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
              color: const Color.fromRGBO(0, 0, 0, 0.25),
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
      return SelectionContainer.disabled(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          alignment: Alignment.center,
          child: Text(
            item.bookName,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ),
      );
    }

    if (item is ChapterMarker) {
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
          child: Text(
            'Capítulo ${item.chapterNumber}',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E)),
            textAlign: TextAlign.center,
          ),
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
                textAlign: TextAlign.justify,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// --- WIDGET DE DIÁLOGO PARA SELECIONAR LIVRO E CAPÍTULO ---

class BookChapterSelectorDialog extends StatefulWidget {
  final List<Book> allBooks;
  final Book initialBook;

  const BookChapterSelectorDialog({
    Key? key,
    required this.allBooks,
    required this.initialBook,
  }) : super(key: key);

  @override
  BookChapterSelectorDialogState createState() =>
      BookChapterSelectorDialogState();
}

class BookChapterSelectorDialogState extends State<BookChapterSelectorDialog> {
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
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
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
                        style: const TextStyle(fontSize: 10.0),
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
