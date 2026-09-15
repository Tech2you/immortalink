import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

VideoPlayerController videoController(String url) =>
    Uri.parse(url).scheme == 'file'
    ? VideoPlayerController.file(File.fromUri(Uri.parse(url)))
    : VideoPlayerController.networkUrl(Uri.parse(url));

Future<({String url, Future<void> Function() release})> prepareVideoPreview(
  Uint8List bytes,
  String extension,
) async {
  final directory = await Directory.systemTemp.createTemp('everroots-video-');
  try {
    final file = File('${directory.path}/preview.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return (
      url: file.uri.toString(),
      release: () async {
        if (await directory.exists()) await directory.delete(recursive: true);
      },
    );
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}
