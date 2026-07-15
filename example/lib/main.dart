import 'dart:io';

import 'package:clipshot/clipshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ClipshotExampleApp());

class ClipshotExampleApp extends StatelessWidget {
  const ClipshotExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clipshot example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ClipshotExamplePage(),
    );
  }
}

class ClipshotExamplePage extends StatefulWidget {
  const ClipshotExamplePage({super.key});

  @override
  State<ClipshotExamplePage> createState() => _ClipshotExamplePageState();
}

class _ClipshotExamplePageState extends State<ClipshotExamplePage> {
  final _clipshot = Clipshot();
  final _pathController = TextEditingController();
  final _secondsController = TextEditingController(text: '1');
  var _format = ClipshotImageFormat.jpeg;
  var _isLoading = false;
  String? _error;
  List<ClipshotThumbnail> _thumbnails = const [];

  @override
  void dispose() {
    _pathController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  Future<void> _extract({required bool batch}) async {
    final seconds = double.tryParse(_secondsController.text);
    if (seconds == null || seconds < 0) {
      setState(() => _error = 'Enter a non-negative timestamp.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final position = Duration(microseconds: (seconds * 1000000).round());
      final results = batch
          ? await _clipshot.extractThumbnails(
              videoPath: _pathController.text,
              positions: <Duration>[Duration.zero, position, position * 2],
              maxWidth: 720,
              format: _format,
            )
          : <ClipshotThumbnail>[
              await _clipshot.extractThumbnail(
                videoPath: _pathController.text,
                position: position,
                maxWidth: 720,
                format: _format,
              ),
            ];
      if (!mounted) return;
      setState(() => _thumbnails = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _useBundledSample() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await rootBundle.load('assets/sample.mp4');
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'clipshot_example_sample.mp4',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      setState(() => _pathController.text = file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not prepare sample video: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGeneratedFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _clipshot.deleteThumbnails(_thumbnails.map((item) => item.path));
      if (!mounted) return;
      setState(() => _thumbnails = const []);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clipshot example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Enter an app-accessible local video file path.'),
          const SizedBox(height: 12),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Video path',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isLoading ? null : _useBundledSample,
              child: const Text('Use bundled sample video'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secondsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Timestamp (seconds)',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ClipshotImageFormat>(
            segments: const <ButtonSegment<ClipshotImageFormat>>[
              ButtonSegment(
                value: ClipshotImageFormat.jpeg,
                label: Text('JPEG'),
              ),
              ButtonSegment(value: ClipshotImageFormat.png, label: Text('PNG')),
            ],
            selected: <ClipshotImageFormat>{_format},
            onSelectionChanged: _isLoading
                ? null
                : (selection) => setState(() => _format = selection.single),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: _isLoading ? null : () => _extract(batch: false),
                child: const Text('Extract one'),
              ),
              OutlinedButton(
                onPressed: _isLoading ? null : () => _extract(batch: true),
                child: const Text('Extract three'),
              ),
              OutlinedButton(
                onPressed: _isLoading || _thumbnails.isEmpty
                    ? null
                    : _deleteGeneratedFiles,
                child: const Text('Delete thumbnails'),
              ),
            ],
          ),
          if (_isLoading) ...const <Widget>[
            SizedBox(height: 16),
            LinearProgressIndicator(),
          ],
          if (_error case final error?) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          for (final thumbnail in _thumbnails) ...<Widget>[
            const SizedBox(height: 20),
            Image.file(File(thumbnail.path), height: 220, fit: BoxFit.contain),
            SelectableText(
              'Path: ${thumbnail.path}\n'
              'Requested: ${thumbnail.requestedPosition}\n'
              'Actual: ${thumbnail.actualPosition}\n'
              'Dimensions: ${thumbnail.width} × ${thumbnail.height}\n'
              'Size: ${thumbnail.sizeBytes} bytes\n'
              'Format: ${thumbnail.format.name}',
            ),
          ],
        ],
      ),
    );
  }
}
