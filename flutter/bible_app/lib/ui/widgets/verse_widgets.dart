// lib/ui/widgets/verse_widgets.dart

import 'package:flutter/material.dart';
import '../../models/list_item.dart';

class BookMarkerView extends StatelessWidget {
  final BookMarker item;
  const BookMarkerView({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        alignment: Alignment.center,
        child: Text(
          item.bookName,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
    );
  }
}

class ChapterMarkerView extends StatelessWidget {
  final ChapterMarker item;
  const ChapterMarkerView({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
}

class VerseView extends StatelessWidget {
  final Verse item;
  const VerseView({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
}
