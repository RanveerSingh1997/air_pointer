import 'package:air_pointer_example/src/sandbox_canvas.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'air_pointer example',
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SandboxCanvas()),
      );
}
