import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    this.initial,
  });

  final int postId;
  final Map<String, dynamic>? initial;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _comment = TextEditingController();
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthStore>().api;
    try {
      final results = await Future.wait([
        api.get('posts/${widget.postId}'),
        api.get('posts/${widget.postId}/comments'),
      ]);
      if (!mounted) return;
      final postData = results[0];
      final commentData = results[1];
      setState(() {
        if (postData is Map && postData['post'] is Map) {
          _post = Map<String, dynamic>.from(postData['post'] as Map);
        }
        _comments = commentData is Map && commentData['data'] is List
            ? (commentData['data'] as List)
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

  bool get _isOwner {
    final post = _post;
    if (post == null || post['account'] is! Map) return false;
    final accountId = (post['account'] as Map)['account_id'];
    return context.read<AuthStore>().accounts.any(
          (account) => account['account_id'] == accountId,
        );
  }

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;
    final api = context.read<AuthStore>().api;
    try {
      final liked = post['liked'] == true;
      final data = liked
          ? await api.delete('posts/${widget.postId}/like')
          : await api.post('posts/${widget.postId}/like');
      if (!mounted) return;
      setState(() {
        post['liked'] = data['liked'] == true;
        post['like_count'] = data['like_count'] ?? post['like_count'];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _editPost() async {
    final post = _post;
    if (post == null) return;
    final controller = TextEditingController(text: '${post['caption'] ?? ''}');
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit post'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: 2200,
          decoration: const InputDecoration(labelText: 'Caption'),
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
    if (caption == null) return;
    try {
      final data = await context
          .read<AuthStore>()
          .api
          .patch('posts/${widget.postId}', {'caption': caption});
      if (!mounted) return;
      setState(() {
        if (data['post'] is Map) {
          _post = Map<String, dynamic>.from(data['post'] as Map);
        }
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus post?'),
        content: const Text('Post akan dihapus dari feed dan profil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<AuthStore>().api.delete('posts/${widget.postId}');
      if (!mounted) return;
      Navigator.of(context)
          .pop({'action': 'deleted', 'post_id': widget.postId});
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context
          .read<AuthStore>()
          .api
          .post('posts/${widget.postId}/comments', {'body': text});
      _comment.clear();
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    try {
      await context
          .read<AuthStore>()
          .api
          .delete('comments/${comment['comment_id']}');
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    if (_loading && post == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post')),
        body: const Center(child: Text('Post tidak ditemukan')),
      );
    }
    final account = post['account'] is Map
        ? Map<String, dynamic>.from(post['account'] as Map)
        : <String, dynamic>{};
    final media = post['media'] is List ? post['media'] as List : const [];
    final token = context.read<AuthStore>().api.accessToken;
    final headers = token == null
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    final myUserId = context.read<AuthStore>().user?['user_id'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          if (_isOwner)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editPost();
                if (value == 'delete') _deletePost();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit caption'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Hapus post'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                Row(
                  children: [
                    AccountAvatar(
                      account: account,
                      radius: 17,
                      token: token,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${account['display_name'] ?? ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              '@${account['handle'] ?? ''} · ${timeAgo(post['created_at'])}',
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if ('${post['caption'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${post['caption']}'),
                ],
                if (media.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(
                        AppConfig.absoluteUrl('${media.first['url'] ?? ''}'),
                        headers: headers,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black12,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _toggleLike,
                      icon: Icon(
                        post['liked'] == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 20,
                        color: post['liked'] == true ? Colors.red : null,
                      ),
                    ),
                    Text('${post['like_count'] ?? 0}'),
                    const SizedBox(width: 14),
                    const Icon(Icons.mode_comment_outlined, size: 19),
                    const SizedBox(width: 4),
                    Text('${post['comment_count'] ?? 0}'),
                  ],
                ),
                const Divider(height: 16),
                Text('Komentar',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('Belum ada komentar')),
                  )
                else
                  for (final comment in _comments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 14,
                        child: Icon(Icons.person, size: 15),
                      ),
                      title: Text(
                        '${comment['display_name'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text('${comment['body'] ?? ''}',
                          style: const TextStyle(fontSize: 13)),
                      trailing: (comment['user_id'] == myUserId || _isOwner)
                          ? IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteComment(comment),
                              icon: const Icon(Icons.delete_outline, size: 17),
                            )
                          : null,
                    ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      decoration: const InputDecoration(
                        hintText: 'Tulis komentar…',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendComment,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, size: 19),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
