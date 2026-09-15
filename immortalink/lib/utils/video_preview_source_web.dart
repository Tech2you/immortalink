// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'media_upload_policy.dart';

VideoPlayerController videoController(String url) =>
    VideoPlayerController.networkUrl(Uri.parse(url));

Future<({String url, Future<void> Function() release})> prepareVideoPreview(
  Uint8List bytes,
  String extension,
) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([bytes], MediaUploadPolicy.contentTypeForExtension(extension)),
  );
  return (url: url, release: () async => html.Url.revokeObjectUrl(url));
}
