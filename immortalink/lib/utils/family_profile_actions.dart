import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/profile_photo_cropper.dart';
import 'image_upload_optimizer.dart';
import 'media_upload_policy.dart';

Future<bool> changeFamilyPhoto(BuildContext context, String familyId) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return false;
  final bytes = picked.files.first.bytes;
  if (bytes == null) throw Exception('No image data');
  final cropped = await cropProfilePhoto(context, bytes);
  if (cropped == null) return false;
  final image = await ImageUploadOptimizer.optimize(
    cropped,
    kind: MediaUploadKind.avatarPhoto,
    fileName: 'profile.png',
  );
  if (image.bytes.length > 5242880) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a family photo smaller than 5 MB.'),
        ),
      );
    }
    return false;
  }
  await Supabase.instance.client.storage
      .from('family_avatars')
      .uploadBinary(
        '$familyId/avatar',
        image.bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: image.contentType,
          cacheControl: '0',
        ),
      );
  return true;
}

Future<String?> promptFamilyName(
  BuildContext context,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  final formKey = GlobalKey<FormState>();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit family name'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Family name'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Enter a family name.' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Keep the controller alive until the dialog's exit animation completes.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return name;
}
