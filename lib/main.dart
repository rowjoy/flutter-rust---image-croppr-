import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:helloworld/src/rust/api.dart/api.dart';

import 'package:helloworld/src/rust/api.dart/frb_generated.dart';
import 'package:image_picker/image_picker.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init(); // IMPORTANT: loads librust.so
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: CropScreen());
  }
}

class CropScreen extends StatefulWidget {
  const CropScreen({super.key});
  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final ImagePicker picker = ImagePicker();

  Uint8List? originalBytes;
  Uint8List? croppedBytes;

  // selection rect in "display coordinates"
  Rect selection = const Rect.fromLTWH(60, 60, 200, 200);

  ui.Image? decodedImage; // to know original width/height

  Future<void> pickImage() async {
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final img = await _decodeUiImage(bytes);

    setState(() {
      originalBytes = bytes;
      decodedImage = img;
      croppedBytes = null;
      selection = const Rect.fromLTWH(60, 60, 200, 200);
    });
  }

  Future<void> doCrop(BoxConstraints box) async {
    if (originalBytes == null || decodedImage == null) return;

    final ow = decodedImage!.width.toDouble();
    final oh = decodedImage!.height.toDouble();

    // image is drawn with BoxFit.contain inside the available box
    final bw = box.maxWidth;
    final bh = box.maxHeight;

    final scale = _containScale(ow, oh, bw, bh);
    final drawnW = ow * scale;
    final drawnH = oh * scale;

    final offsetX = (bw - drawnW) / 2.0;
    final offsetY = (bh - drawnH) / 2.0;

    // Convert selection (display coords) -> image pixel coords
    final sx = (selection.left - offsetX) / scale;
    final sy = (selection.top - offsetY) / scale;
    final sw = selection.width / scale;
    final sh = selection.height / scale;

    // Clamp to image bounds
    final x = sx.clamp(0, ow - 1).floor();
    final y = sy.clamp(0, oh - 1).floor();
    final w = sw.clamp(1, ow - x).floor();
    final h = sh.clamp(1, oh - y).floor();

    try {
      // ✅ call Rust
      final out = await cropPng(
        input: originalBytes!,
        x: x,
        y: y,
        w: w,
        h: h,
      );
      setState(() => croppedBytes = Uint8List.fromList(out));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Crop failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rust Crop UI")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(onPressed: pickImage, child: const Text("Pick Image")),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    originalBytes == null ? "No image selected" : "Drag to select crop area, then press Crop",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (originalBytes == null) {
                    return const Center(child: Text("Pick an image first"));
                  }

                  return Stack(
                    children: [
                      // Image display
                      Positioned.fill(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Image.memory(originalBytes!),
                        ),
                      ),

                      // Selection overlay (drag to move)
                      Positioned.fromRect(
                        rect: selection,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              final next = selection.shift(d.delta);
                              selection = _clampRectToBox(next, box);
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(width: 3, color: Colors.white),
                              color: Colors.black.withOpacity(0.15),
                            ),
                            child: const Center(
                              child: Text(
                                "Drag",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Crop button
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: ElevatedButton(
                          onPressed: () => doCrop(box),
                          child: const Text("Crop (Rust)"),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            if (croppedBytes != null) ...[
              const Align(alignment: Alignment.centerLeft, child: Text("Cropped Result:")),
              const SizedBox(height: 8),
              SizedBox(height: 160, child: Image.memory(croppedBytes!, fit: BoxFit.contain)),
            ],
          ],
        ),
      ),
    );
  }

  // Helpers

  double _containScale(double iw, double ih, double bw, double bh) {
    final sx = bw / iw;
    final sy = bh / ih;
    return sx < sy ? sx : sy;
  }

  Rect _clampRectToBox(Rect r, BoxConstraints box) {
    final left = r.left.clamp(0.0, box.maxWidth - r.width);
    final top = r.top.clamp(0.0, box.maxHeight - r.height);
    return Rect.fromLTWH(left, top, r.width, r.height);
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
