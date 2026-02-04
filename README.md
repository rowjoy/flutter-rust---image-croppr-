# helloworld

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.




# Flutter + Rust Image Cropper (flutter_rust_bridge)

A step-by-step note/README for building an **Image Cropper** where:

- **Flutter** shows the UI (pick image + select crop rectangle + preview)
- **Rust** does the cropping logic (fast + safe)
- Communication via **flutter_rust_bridge (FRB)**

This guide matches **flutter_rust_bridge_codegen 2.11.1** (new config syntax).

---

## Features

- Pick image from Gallery (Flutter)
- Drag a crop rectangle on top of the image (Flutter)
- Send bytes + crop rect to Rust (FRB)
- Rust crops + returns PNG bytes
- Flutter previews the cropped image

---

## Requirements

- Flutter SDK installed (`flutter doctor` ✅)
- Rust installed (`rustc --version`)
- FRB codegen installed:

```bash
flutter_rust_bridge_codegen --version
# expected: 2.11.1

# flutter-rust---image-croppr-
