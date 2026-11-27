import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    this.initial,
  });

  final int conversationId;
  final Map<String, dynamic>? initial;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Map<String, dynamic>? _conversation;
  bool _loading = true;
  bool _busy = false;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get(
            'conversations/${widget.conversationId}',
          );
      if (!mounted) return;
      final conversation = data is Map ? data['conversation'] : null;
      if (conversation is Map) {
        setState(() {
          _conversation = Map<String, dynamic>.from(conversation);
        });
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _members {
    final raw = _conversation?['members'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool get _isOwner {
    final auth = context.read<AuthStore>();
    final myId = auth.user?['user_id'];
    return _members.any(
        (member) => member['user_id'] == myId && member['role'] == 'owner');
  }

  Future<void> _pickAvatar() async {
    if (!_isOwner || _avatarBusy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatarBusy = true);
    final auth = context.read<AuthStore>();
    try {
      final media = await auth.api.uploadFile(
        'media',
        filePath: picked.path,
        purpose: 'avatar',
      );
      final payload = media['media'];
      if (payload is! Map || payload['media_id'] is! int) {
        throw Exception('Upload foto grup gagal.');
      }
      await auth.api.patch(
        'conversations/${widget.conversationId}',
        {'avatar_media_id': payload['media_id']},
      );
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _rename() async {
    final controller =
        TextEditingController(text: '${_conversation?['title'] ?? ''}');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ganti nama grup'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama grup'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    await _run(() => context.read<AuthStore>().api.patch(
          'conversations/${widget.conversationId}',
          {'title': title},
        ));
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah anggota'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixText: '@',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(normalizeUsername(controller.text)),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (handle == null || handle.isEmpty || !mounted) return;
    await _run(() => context.read<AuthStore>().api.post(
          'conversations/${widget.conversationId}/members',
          {'username': handle},
        ));
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    await _run(() => context.read<AuthStore>().api.delete(
          'conversations/${widget.conversationId}/members/${member['user_id']}',
        ));
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari grup?'),
        content: const Text('Anda tidak akan menerima pesan grup ini lagi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<AuthStore>()
          .api
          .delete('conversations/${widget.conversationId}');
      if (!mounted) return;
      Navigator.of(context).pop('left');
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_conversation?['title'] ?? 'Info grup'}';
    final myId = context.read<AuthStore>().user?['user_id'];
    return Scaffold(
      appBar: AppBar(title: const Text('Info grup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickAvatar,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              _GroupAvatar(
                                mediaId:
                                    _conversation?['avatar_media_id'] as int?,
                                token:
                                    context.read<AuthStore>().api.accessToken,
                                radius: 36,
                              ),
                              if (_isOwner)
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: _avatarBusy
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.photo_camera,
                                          size: 14, color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        Text('${_members.length} anggota',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (_isOwner)
                          TextButton.icon(
                            onPressed: _busy ? null : _rename,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Ganti nama'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Anggota',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_isOwner)
                      TextButton.icon(
                        onPressed: _busy ? null : _addMember,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Tambah'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      for (final member in _members)
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person, size: 18),
                          ),
                          title: Text('${member['display_name'] ?? ''}'),
                          subtitle: Text('${member['role'] ?? 'member'}'),
                          trailing: _isOwner &&
                                  member['user_id'] != myId &&
                                  member['role'] != 'owner'
                              ? IconButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _removeMember(member),
                                  icon:
                                      const Icon(Icons.person_remove_outlined),
                                  tooltip: 'Keluarkan',
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _leave,
                  icon: Icon(Icons.logout,
                      color: Theme.of(context).colorScheme.error),
                  label: Text(
                    'Keluar dari grup',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({
    required this.mediaId,
    required this.token,
    this.radius = 24,
  });

  final int? mediaId;
  final String? token;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(Icons.groups, size: radius),
    );
    if (mediaId == null) return fallback;
    final headers = token == null || token!.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    return ClipOval(
      child: Image.network(
        AppConfig.absoluteUrl('/api/v1/media/$mediaId'),
        headers: headers,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
