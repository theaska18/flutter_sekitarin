import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import 'comments_sheet.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = context.read<AuthStore>().api;
    try {
      final position = await LocationService.current();
      final query = <String, String>{'limit': '20'};
      if (position != null) {
        query['lat'] = '${position.latitude}';
        query['lng'] = '${position.longitude}';
        query['radius'] = '500';
      }
      final data = await api.get('feed', query: query);
      if (!mounted) return;
      setState(() {
        _posts = data is Map && data['data'] is List
            ? (data['data'] as List)
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

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final liked = post['liked'] == true;
    final api = context.read<AuthStore>().api;
    try {
      final data = liked
          ? await api.delete('posts/${post['post_id']}/like')
          : await api.post('posts/${post['post_id']}/like');
      if (!mounted) return;
      setState(() {
        post['liked'] = data['liked'] == true;
        post['like_count'] = data['like_count'] ?? post['like_count'];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommentsSheet(post: post),
    );
    if (mounted) _load();
  }

  Future<void> _createPost() async {
    if (context.read<AuthStore>().activeAccount == null) {
      showErrorSnack(context, 'Pilih akun terlebih dahulu.');
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPost,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Post'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _posts.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 140),
                  Icon(Icons.photo_library_outlined, size: 48),
                  SizedBox(height: 12),
                  Center(child: Text('Belum ada post di sekitar')),
                  SizedBox(height: 4),
                  Center(
                    child: Text('Post dari kontak dan akun dalam radius 500 m.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return _PostCard(
                    post: post,
                    onLike: () => _toggleLike(post),
                    onComments: () => _openComments(post),
                  );
                },
              ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onLike,
    required this.onComments,
  });

  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final account = post['account'] is Map
        ? Map<String, dynamic>.from(post['account'] as Map)
        : <String, dynamic>{};
    final media = post['media'] is List ? post['media'] as List : const [];
    final token = context.read<AuthStore>().api.accessToken;
    final headers = token == null
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    final liked = post['liked'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: typeColor(account['type_code'] as String?)
                      .withValues(alpha: 0.15),
                  child: Icon(
                    typeIcon(account['type_code'] as String?),
                    color: typeColor(account['type_code'] as String?),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${account['display_name'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          '@${account['handle'] ?? ''} • ${formatWhen(post['created_at'])}',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
            if ('${post['caption'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${post['caption']}'),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  AppConfig.absoluteUrl('${media.first['url'] ?? ''}'),
                  headers: headers,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.black12,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: onLike,
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.red : null,
                  ),
                ),
                Text('${post['like_count'] ?? 0}'),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: onComments,
                  icon: const Icon(Icons.mode_comment_outlined),
                ),
                Text('${post['comment_count'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
