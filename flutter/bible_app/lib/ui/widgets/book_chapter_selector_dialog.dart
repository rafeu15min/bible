// lib/ui/widgets/book_chapter_selector_dialog.dart

import 'package:flutter/material.dart';
import '../../models/book.dart';

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
