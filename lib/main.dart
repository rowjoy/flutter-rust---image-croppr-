import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:helloworld/src/rust/api.dart/api.dart';
import 'package:helloworld/src/rust/api.dart/frb_generated.dart';
import 'package:image_picker/image_picker.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: EditorScreen()));
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final picker = ImagePicker();

  Uint8List? original;
  Uint8List? preview;
  ui.Image? originalUi;

  // ops history (undo/redo)
  final List<List<Map<String, dynamic>>> history = [[]];
  int historyIndex = 0;

  // crop box in display coords
  Rect cropRect = const Rect.fromLTWH(60, 60, 220, 220);

  double brightness = 0; // -100..100
  double contrast = 0;   // -50..50

  Timer? _debounce;

  List<Map<String, dynamic>> get ops => history[historyIndex];

  Future<void> pickImage() async {
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final uiImg = await _decodeUiImage(bytes);

    setState(() {
      original = bytes;
      originalUi = uiImg;
      preview = bytes;
      history.clear();
      history.add([]);
      historyIndex = 0;
      brightness = 0;
      contrast = 0;
      cropRect = const Rect.fromLTWH(60, 60, 220, 220);
    });

    _renderPreview();
  }

  void _pushOps(List<Map<String, dynamic>> newOps) {
    // drop redo part
    history.removeRange(historyIndex + 1, history.length);
    history.add(newOps);
    historyIndex++;
    _renderPreview();
  }

  void undo() {
    if (historyIndex > 0) {
      setState(() => historyIndex--);
      _renderPreview();
    }
  }

  void redo() {
    if (historyIndex + 1 < history.length) {
      setState(() => historyIndex++);
      _renderPreview();
    }
  }

  void addRotate() {
    final newOps = [...ops, {"type": "Rotate90", "times": 1}];
    _pushOps(newOps);
  }

  void addCrop(BoxConstraints box) {
    if (originalUi == null) return;

    final mapped = _displayRectToImagePixels(cropRect, box, originalUi!);
    final newOps = [
      ...ops,
      {
        "type": "Crop",
        "x": mapped.left.floor(),
        "y": mapped.top.floor(),
        "w": mapped.width.floor(),
        "h": mapped.height.floor(),
      }
    ];
    _pushOps(newOps);
  }

  void _updateSlidersOps({required double b, required double c}) {
    // remove previous slider ops, then add latest
    final base = ops.where((e) => e["type"] != "Brightness" && e["type"] != "Contrast").toList();
    final newOps = [
      ...base,
      {"type": "Brightness", "value": b.round()},
      {"type": "Contrast", "value": c.toDouble()},
    ];
    _pushOps(newOps);
  }

  void _renderPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      if (original == null) return;

      try {
        final jsonOps = jsonEncode(ops);

        // NOTE: function name in Dart might be applyOpsPng or applyOpsPngAsync depending on codegen
        final out = await applyOpsPng(
          input: original!,
          opsJson: jsonOps,
          maxWidth: 1024,
        );

        if (!mounted) return;
        setState(() => preview = Uint8List.fromList(out));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Render error: $e")));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flutter UI + Rust Image Editor"),
        actions: [
          IconButton(onPressed: undo, icon: const Icon(Icons.undo)),
          IconButton(onPressed: redo, icon: const Icon(Icons.redo)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(onPressed: pickImage, child: const Text("Pick Image")),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: preview == null ? null : addRotate,
                  child: const Text("Rotate 90°"),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (preview == null) {
                    return const Center(child: Text("Pick an image to start"));
                  }

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: Colors.black12,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Image.memory(preview!),
                          ),
                        ),
                      ),

                      // Crop overlay (drag)
                      Positioned.fromRect(
                        rect: cropRect,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              final next = cropRect.shift(d.delta);
                              cropRect = _clampRect(next, box);
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              color: Colors.black.withOpacity(0.15),
                            ),
                            child: const Center(
                              child: Text("Drag Crop Box",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: ElevatedButton(
                          onPressed: originalUi == null ? null : () => addCrop(box),
                          child: const Text("Apply Crop"),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Sliders
            Row(
              children: [
                const SizedBox(width: 90, child: Text("Brightness")),
                Expanded(
                  child: Slider(
                    min: -100,
                    max: 100,
                    value: brightness,
                    onChanged: (v) {
                      setState(() => brightness = v);
                      _updateSlidersOps(b: brightness, c: contrast);
                    },
                  ),
                ),
                SizedBox(width: 50, child: Text(brightness.round().toString())),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 90, child: Text("Contrast")),
                Expanded(
                  child: Slider(
                    min: -50,
                    max: 50,
                    value: contrast,
                    onChanged: (v) {
                      setState(() => contrast = v);
                      _updateSlidersOps(b: brightness, c: contrast);
                    },
                  ),
                ),
                SizedBox(width: 50, child: Text(contrast.toStringAsFixed(0))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helpers

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Rect _clampRect(Rect r, BoxConstraints box) {
    final left = r.left.clamp(0.0, box.maxWidth - r.width);
    final top = r.top.clamp(0.0, box.maxHeight - r.height);
    return Rect.fromLTWH(left, top, r.width, r.height);
  }

  Rect _displayRectToImagePixels(Rect sel, BoxConstraints box, ui.Image img) {
    final ow = img.width.toDouble();
    final oh = img.height.toDouble();

    final bw = box.maxWidth;
    final bh = box.maxHeight;

    final scale = _containScale(ow, oh, bw, bh);
    final drawnW = ow * scale;
    final drawnH = oh * scale;

    final offsetX = (bw - drawnW) / 2.0;
    final offsetY = (bh - drawnH) / 2.0;

    final x = (sel.left - offsetX) / scale;
    final y = (sel.top - offsetY) / scale;
    final w = sel.width / scale;
    final h = sel.height / scale;

    final cx = x.clamp(0, ow - 1).toDouble();
    final cy = y.clamp(0, oh - 1).toDouble();
    final cw = w.clamp(1, ow - cx).toDouble();
    final ch = h.clamp(1, oh - cy).toDouble();

    return Rect.fromLTWH(cx, cy, cw, ch);
  }

  double _containScale(double iw, double ih, double bw, double bh) {
    final sx = bw / iw;
    final sy = bh / ih;
    return sx < sy ? sx : sy;
  }
}
