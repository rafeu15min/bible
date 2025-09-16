// lib/ui/screens/bible_reader_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/rendering.dart';
import '../../models/book.dart';
import '../../models/list_item.dart';
import '../../services/database_helper.dart';
import '../widgets/book_chapter_selector_dialog.dart';
import '../widgets/verse_widgets.dart';

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
  String _bottomBarText = 'Gn 1';

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

  // lib/ui/screens/bible_reader_screen.dart

  // lib/ui/screens/bible_reader_screen.dart

  // lib/ui/screens/bible_reader_screen.dart

  // lib/ui/screens/bible_reader_screen.dart

  // lib/ui/screens/bible_reader_screen.dart

  void _copySelectionWithReference() {
    final selection = _selectedContent?.plainText;
    if (selection == null || selection.isEmpty) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final firstVisibleIndex =
        positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final lastVisibleIndex =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);

    final startIndex =
        (firstVisibleIndex - 10).clamp(0, _displayItems.length - 1);
    final endIndex = (lastVisibleIndex + 10).clamp(0, _displayItems.length - 1);

    final List<Verse> localVerses = _displayItems
        .sublist(startIndex, endIndex + 1)
        .whereType<Verse>()
        .toList();

    if (localVerses.isEmpty) return;

    final normalizedSelection = selection
        .replaceAll(RegExp(r'\d+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    List<Verse> involvedVerses = [];

    // --- LÓGICA PRECISA BASEADA NA SUA SUGESTÃO ---

    // Passo 1: Encontrar o "núcleo" de versículos totalmente contidos na seleção.
    final List<int> fullyContainedIndices = [];
    for (int i = 0; i < localVerses.length; i++) {
      if (normalizedSelection.contains(localVerses[i].content)) {
        fullyContainedIndices.add(i);
      }
    }

    if (fullyContainedIndices.isNotEmpty) {
      int firstIndex = fullyContainedIndices.first;
      int lastIndex = fullyContainedIndices.last;

      // Passo 2: Verificar a borda esquerda (o versículo anterior).
      if (firstIndex > 0) {
        final previousVerse = localVerses[firstIndex - 1];
        // Verifica se a seleção contém o FINAL do versículo anterior.
        final endChunk = previousVerse.content
            .substring((previousVerse.content.length / 2).round());
        if (normalizedSelection.contains(endChunk)) {
          firstIndex--; // Expande o intervalo para a esquerda.
        }
      }

      // Passo 3: Verificar a borda direita (o versículo seguinte).
      if (lastIndex < localVerses.length - 1) {
        final nextVerse = localVerses[lastIndex + 1];
        // Verifica se a seleção contém o COMEÇO do versículo seguinte.
        final startChunk = nextVerse.content
            .substring(0, (nextVerse.content.length / 2).round());
        if (normalizedSelection.contains(startChunk)) {
          lastIndex++; // Expande o intervalo para a direita.
        }
      }
      involvedVerses = localVerses.sublist(firstIndex, lastIndex + 1);
    } else {
      // Passo 4: Se não há núcleo, a seleção está contida em um ou mais versículos parciais.
      for (int i = 0; i < localVerses.length; i++) {
        final verse = localVerses[i];
        // Cenário A: A seleção está inteiramente dentro de UM versículo.
        if (verse.content.contains(normalizedSelection)) {
          involvedVerses = [verse];
          break;
        }

        // Cenário B: A seleção "toca" em algum versículo (início ou fim).
        final startChunk =
            verse.content.substring(0, (verse.content.length / 2).round());
        final endChunk =
            verse.content.substring((verse.content.length / 2).round());

        if (normalizedSelection.contains(startChunk) ||
            normalizedSelection.contains(endChunk)) {
          involvedVerses.add(verse);
        }
      }
    }

    if (involvedVerses.isEmpty) {
      Clipboard.setData(ClipboardData(text: selection));
      return;
    }

    // O resto da função para montar o texto final permanece o mesmo.
    final firstVerse = involvedVerses.first;
    final lastVerse = involvedVerses.last;
    final bookAbbr = firstVerse.bookAbbreviation ?? firstVerse.bookName;
    final chapter = firstVerse.chapterNumber;

    String reference;
    if (firstVerse.bookId == lastVerse.bookId &&
        firstVerse.chapterNumber == lastVerse.chapterNumber) {
      if (firstVerse.verseNumber == lastVerse.verseNumber) {
        reference = '$bookAbbr $chapter, ${firstVerse.verseNumber}';
      } else {
        reference =
            '$bookAbbr $chapter, ${firstVerse.verseNumber}-${lastVerse.verseNumber}';
      }
    } else {
      final lastBookAbbr = lastVerse.bookAbbreviation ?? lastVerse.bookName;
      reference =
          '$bookAbbr $chapter, ${firstVerse.verseNumber} - $lastBookAbbr ${lastVerse.chapterNumber}, ${lastVerse.verseNumber}';
    }

    final copiedText =
        involvedVerses.map((v) => '${v.verseNumber} ${v.content}').join(' ');
    final finalString = '"$copiedText"\n($reference)';

    Clipboard.setData(ClipboardData(text: finalString));
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
              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: SelectionArea(
                    onSelectionChanged: (SelectedContent? content) {
                      setState(() {
                        _selectedContent = content;
                      });
                    },
                    contextMenuBuilder: (context, editableTextState) {
                      final List<ContextMenuButtonItem> buttonItems =
                          editableTextState.contextMenuButtonItems;
                      buttonItems.removeWhere((item) =>
                          item.type == ContextMenuButtonType.selectAll);

                      buttonItems.insert(
                        1,
                        ContextMenuButtonItem(
                          onPressed: () {
                            _copySelectionWithReference();
                            editableTextState.hideToolbar();
                          },
                          label: 'Copiar com Referência',
                        ),
                      );

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
                    )),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
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
      return BookMarkerView(item: item);
    }
    if (item is ChapterMarker) {
      return ChapterMarkerView(item: item);
    }
    if (item is Verse) {
      return VerseView(item: item);
    }
    return const SizedBox.shrink();
  }
}
