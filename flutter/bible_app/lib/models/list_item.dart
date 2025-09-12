// lib/models/list_item.dart

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
