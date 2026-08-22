import 'dart:convert';
import 'dart:io';

import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> viewSupportingDocument(
  BuildContext context, {
  required String? documentDataUrl,
}) async {
  final value = documentDataUrl?.trim();
  if (value == null || value.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No supporting document attached.')),
    );
    return;
  }

  final imageBytes = dataUriBytes(value);
  if (imageBytes != null) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                maxWidth: MediaQuery.sizeOf(context).width,
              ),
              child: InteractiveViewer(
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    return;
  }

  if (!value.toLowerCase().startsWith('data:application/pdf')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open this document.')),
    );
    return;
  }

  final commaIndex = value.indexOf(',');
  if (commaIndex < 0 || commaIndex == value.length - 1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open this document.')),
    );
    return;
  }

  try {
    final bytes = base64Decode(value.substring(commaIndex + 1));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'leave_supporting_document.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'Supporting document',
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the PDF document.')),
    );
  }
}
