import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _caption = TextEditingController();
  XFile? _image;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null) setState(() => _image = picked);
  }

  Future<void> _submit() async {
    final caption = _caption.text.trim();
    if (caption.isEmpty && _image == null) {
      showErrorSnack(context, 'Isi caption atau pilih foto.');
      return;
    }
    setState(() => _busy = true);
    final api = context.read<AuthStore>().api;
    try {
      final mediaIds = <int>[];
      if (_image != null) {
        final media = await api.uploadFile(
          'media',
          filePath: _image!.path,
          purpose: 'post',
        );
        final payload = media['media'];
        if (payload is Map && payload['media_id'] != null) {
          mediaIds.add(payload['media_id'] as int);
        }
      }
      await api.post('posts', {
        'caption': caption,
        'media_ids': mediaIds,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AuthStore>().activeAccount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Post'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Bagikan'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Posting sebagai ${accountName(account)}',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            minLines: 4,
            maxLines: 8,
            maxLength: 2200,
            decoration: const InputDecoration(
              hintText: 'Apa yang terjadi di sekitar?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(_image!.path),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_image == null ? 'Pilih foto' : 'Ganti foto'),
          ),
          const SizedBox(height: 8),
          Text(
            'Maksimal 1 foto pada versi awal. Post tampil untuk kontak dan akun dalam radius 500 m.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
