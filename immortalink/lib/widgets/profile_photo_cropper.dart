import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

Future<Uint8List?> cropProfilePhoto(
  BuildContext context,
  Uint8List bytes,
) async {
  // Decode with the platform codec (including iPhone formats), then bound the
  // editor's working image so large originals do not overwhelm the cropper.
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final factor = math.min(
    1.0,
    1024 / math.max(descriptor.width, descriptor.height),
  );
  final codec = await descriptor.instantiateCodec(
    targetWidth: math.max(1, (descriptor.width * factor).round()),
    targetHeight: math.max(1, (descriptor.height * factor).round()),
  );
  try {
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) throw StateError('Could not decode photo');
    if (!context.mounted) return null;
    return await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProfilePhotoCropper(bytes: png.buffer.asUint8List()),
      ),
    );
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

class ProfilePhotoCropper extends StatefulWidget {
  const ProfilePhotoCropper({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<ProfilePhotoCropper> createState() => _ProfilePhotoCropperState();
}

class _ProfilePhotoCropperState extends State<ProfilePhotoCropper> {
  final _controller = CropController();
  bool _ready = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Adjust profile photo'),
      actions: [
        TextButton(
          onPressed: !_ready || _saving
              ? null
              : () {
                  setState(() => _saving = true);
                  _controller.crop();
                },
          child: const Text('Save'),
        ),
      ],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: Crop(
              image: widget.bytes,
              controller: _controller,
              withCircleUi: true,
              interactive: true,
              fixCropRect: true,
              initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                size: 0.85,
                aspectRatio: 1,
              ),
              baseColor: Colors.black,
              maskColor: Colors.black.withValues(alpha: 0.65),
              cornerDotBuilder: (_, _) => const SizedBox.shrink(),
              onStatusChanged: (status) {
                if (mounted) {
                  setState(() => _ready = status == CropStatus.ready);
                }
              },
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.pop(context, croppedImage);
                  case CropFailure():
                    setState(() => _saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not crop this photo. Please try again.',
                        ),
                      ),
                    );
                }
              },
            ),
          ),
          if (_saving)
            const Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
