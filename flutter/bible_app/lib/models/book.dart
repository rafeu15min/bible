// lib/models/book.dart

class Book {
  final int id;
  final String name;
  final String? abbreviation;
  final int chapterCount;

  Book(this.id, this.name, this.abbreviation, this.chapterCount);
}
