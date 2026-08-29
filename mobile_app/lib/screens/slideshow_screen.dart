import 'package:flutter/material.dart';

/// Placeholder slideshow screen. The real implementation will host
/// [SlideshowEngine] and render the current [PhotoItem].
class SlideshowScreen extends StatelessWidget {
  const SlideshowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Slideshow placeholder',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
