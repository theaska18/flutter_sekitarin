import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../ui/common.dart';

/// Downloads an authenticated chat attachment to a temporary file and opens it
/// with the platform's viewer.
Future<void> openChatMedia(
  BuildContext context,
  int mediaId,
  String? token, {
  String? filename,
}) async {
  try {
    final safeName = (filename == null || filename.trim().isEmpty)
        ? 'lampiran-$mediaId'
        : filename.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$safeName');
    if (!await file.exists() || await file.length() == 0) {
      final request = http.Request(
        'GET',
        Uri.parse(AppConfig.absoluteUrl('/api/v1/media/$mediaId')),
      );
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Lampiran tidak dapat diunduh.');
      }
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      await sink.flush();
      await sink.close();
    }
    await OpenFilex.open(file.path);
  } catch (error) {
    if (context.mounted) showErrorSnack(context, error);
  }
}
