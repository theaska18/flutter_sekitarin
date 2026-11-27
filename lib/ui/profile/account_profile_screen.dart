import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';
import '../feed/post_detail_screen.dart';
import '../widgets/account_avatar.dart';

/// Read-only profile for another account. Mirrors the post grid on the
/// owner's Profile tab and is used from posts and comments.
class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    super.key,
    required this.accountId,
    this.initialName,
  });

  final int accountId;
  final String? initialName;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

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
        _error = null;
        _account = account is Map ? Map<String, dynamic>.from(account) : null;
        _posts = posts is List
            ? posts
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
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

  Future<void> _openPost(Map<String, dynamic> post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          postId: post['post_id'] as int,
          initial: post,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final token = context.read<AuthStore>().api.accessToken;
    final headers = token == null
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    final type = account?['type_code'] as String?;
    final name = accountName(account) == 'Akun'
        ? (widget.initialName ?? 'Profil')
        : accountName(account);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AccountAvatar(
                          account: account,
                          radius: 32,
                          token: token,
                          fallbackIcon: typeIcon(type),
                          backgroundColor:
                              typeColor(type).withValues(alpha: 0.15),
                          foregroundColor: typeColor(type),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '@${account?['handle'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${account?['type_label'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  if (account?['verified'] == true) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.verified,
                                      size: 13,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if ('${account?['bio'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('${account?['bio']}'),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _chat,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Kirim pesan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Post',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${_posts.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(_error!)),
              )
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Belum ada post')),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  final media = post['media'];
                  final first =
                      media is List && media.isNotEmpty ? media.first : null;
                  return InkWell(
                    onTap: () => _openPost(post),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: first is Map
                          ? Image.network(
                              AppConfig.absoluteUrl('${first['url'] ?? ''}'),
                              headers: headers,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.black12,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            )
                          : Container(
                              color: Colors.black12,
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                '${post['caption'] ?? ''}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
