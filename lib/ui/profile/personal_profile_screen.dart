import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';
import '../feed/post_detail_screen.dart';
import '../widgets/account_avatar.dart';

class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({
    super.key,
    required this.accountId,
    this.initialName,
  });

  final int accountId;
  final String? initialName;

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthStore>().api;
    try {
      final results = await Future.wait([
        api.get('accounts/${widget.accountId}'),
        api.get(
          'accounts/${widget.accountId}/posts',
          query: {'limit': '50'},
        ),
      ]);
      if (!mounted) return;
      final account = results[0] is Map ? results[0]['account'] : null;
      final posts = results[1] is Map ? results[1]['data'] : null;
      setState(() {
        _account = account is Map ? Map<String, dynamic>.from(account) : null;
        _posts = posts is List
            ? posts
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chat() async {
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': widget.accountId,
      });
      final conversation = data['conversation'];
      if (!mounted || conversation is! Map) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            conversation: Map<String, dynamic>.from(conversation),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final name =
        '${account?['display_name'] ?? widget.initialName ?? 'Profil'}';
    final handle = account?['handle'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: AccountAvatar(
                    account: account ?? {'avatar_media_id': null},
                    radius: 44,
                    token: context.read<AuthStore>().api.accessToken,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (handle != null)
                  Center(
                    child: Text(
                      '@$handle',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 14),
                Center(
                  child: FilledButton.icon(
                    onPressed: _chat,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Kirim pesan'),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Post',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Belum ada post')),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      final media = post['media'] is List
                          ? post['media'] as List
                          : const [];
                      final mediaId = media.isEmpty
                          ? null
                          : (media.first is Map
                              ? (media.first as Map)['media_id']
                              : null);
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PostDetailScreen(
                              postId: post['post_id'] as int,
                              initial: post,
                            ),
                          ),
                        ),
                        child: Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: mediaId is int
                              ? Image.network(
                                  AppConfig.absoluteUrl(
                                    '/api/v1/media/$mediaId',
                                  ),
                                  headers: context
                                              .read<AuthStore>()
                                              .api
                                              .accessToken ==
                                          null
                                      ? null
                                      : {
                                          'Authorization':
                                              'Bearer ${context.read<AuthStore>().api.accessToken}',
                                        },
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    '${post['caption'] ?? ''}',
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
