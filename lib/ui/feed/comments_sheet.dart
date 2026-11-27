import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/provider_screen.dart';
import '../profile/personal_profile_screen.dart';
import '../widgets/account_avatar.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});

  final Map<String, dynamic> post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _controller = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context
          .read<AuthStore>()
          .api
          .get('posts/${widget.post['post_id']}/comments');
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(data is Map && data['data'] is List
              ? (data['data'] as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
              : const <Map<String, dynamic>>[]);
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AuthStore>().api.post(
        'posts/${widget.post['post_id']}/comments',
        {'body': text},
      );
      _controller.clear();
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Komentar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? const Center(child: Text('Belum ada komentar'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            final mine = comment['user_id'] ==
                                context.read<AuthStore>().user?['user_id'];
                            final accountId = comment['account_id'];
                            final isPersonal =
                                comment['handle_scope'] != 'business';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: accountId is int
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => isPersonal
                                              ? PersonalProfileScreen(
                                                  accountId: accountId,
                                                  initialName:
                                                      '${comment['display_name'] ?? ''}',
                                                )
                                              : ProviderScreen(
                                                  accountId: accountId,
                                                  initialName:
                                                      '${comment['display_name'] ?? ''}',
                                                ),
                                        ),
                                      )
                                  : null,
                              leading: AccountAvatar(
                                account: {
                                  'avatar_media_id': comment['avatar_media_id'],
                                },
                                radius: 16,
                                token:
                                    context.read<AuthStore>().api.accessToken,
                              ),
                              title: Text('${comment['display_name'] ?? ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text('${comment['body'] ?? ''}'),
                              trailing: mine
                                  ? PopupMenuButton<String>(
                                      iconSize: 18,
                                      onSelected: (_) async {
                                        await context
                                            .read<AuthStore>()
                                            .api
                                            .delete(
                                              'comments/${comment['comment_id']}',
                                            );
                                        await _load();
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Hapus komentar'),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Tulis komentar…',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
