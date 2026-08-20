import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const DbsAnnotatorTabletApp());

class DbsAnnotatorTabletApp extends StatelessWidget {
  const DbsAnnotatorTabletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => ValueListenableBuilder<double>(
        valueListenable: textScale,
        builder: (context, scale, _) => MaterialApp(
          title: 'DBS Annotator',
          debugShowCheckedModeBanner: false,
          theme: dbsTheme(Brightness.light),
          darkTheme: dbsTheme(Brightness.dark),
          themeMode: mode,
          // App-wide runtime text scaling (wraps the Navigator, so dialogs
          // and all routes scale too).
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
