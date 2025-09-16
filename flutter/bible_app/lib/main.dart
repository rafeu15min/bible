// lib/main.dart

import 'package:flutter/material.dart';
import 'ui/screens/bible_reader_screen.dart';

void main() {
  runApp(const BibleApp());
}

class BibleApp extends StatelessWidget {
  const BibleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bíblia',
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
