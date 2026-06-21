import 'package:air_pointer_example/src/netflix_canvas.dart';
import 'package:air_pointer_example/src/sandbox_canvas.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'air_pointer example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: const _HomePage(),
      );
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _tab == 0 ? const Color(0xFF141414) : kCanvasBackground,
      body: IndexedStack(
        index: _tab,
        children: const [
          NetflixCanvas(),
          SandboxCanvas(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFFE50914),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Netflix Demo',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Sandbox',
          ),
        ],
      ),
    );
  }
}
