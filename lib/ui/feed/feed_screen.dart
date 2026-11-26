import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import 'comments_sheet.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

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
    final auth = context.read<AuthStore>();
    final api = auth.api;
    try {
      final position =
          auth.locationConsent ? await LocationService.current() : null;
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
    if (!mounted) return;
    await _reloadPost(post['post_id'] as int);
  }

  Future<void> _reloadPost(int postId) async {
    try {
      final data = await context.read<AuthStore>().api.get('posts/$postId');
      if (!mounted || data is! Map || data['post'] is! Map) return;
      final fresh = Map<String, dynamic>.from(data['post'] as Map);
      setState(() {
        final index = _posts.indexWhere((item) => item['post_id'] == postId);
        if (index >= 0) {
          _posts[index] = fresh;
        }
      });
    } catch (_) {
      // Keep the existing card if the refresh fails.
    }
  }

  bool _isOwnPost(Map<String, dynamic> post) {
    final account = post['account'];
    if (account is! Map) return false;
    final accountId = account['account_id'];
    return context.read<AuthStore>().accounts.any(
          (item) => item['account_id'] == accountId,
        );
  }

  Future<void> _editPost(Map<String, dynamic> post) async {
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
    if (caption == null || !mounted) return;
    try {
      final data = await context
          .read<AuthStore>()
          .api
          .patch('posts/${post['post_id']}', {'caption': caption});
      if (!mounted) return;
      if (data['post'] is Map) {
        final fresh = Map<String, dynamic>.from(data['post'] as Map);
        setState(() {
          final index =
              _posts.indexWhere((item) => item['post_id'] == post['post_id']);
          if (index >= 0) _posts[index] = fresh;
        });
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
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
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AuthStore>().api.delete('posts/${post['post_id']}');
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((item) => item['post_id'] == post['post_id']);
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> post) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => PostDetailScreen(
          postId: post['post_id'] as int,
          initial: post,
        ),
      ),
    );
    if (!mounted) return;
    if (result is Map && result['action'] == 'deleted') {
      setState(() {
        _posts.removeWhere((item) => item['post_id'] == post['post_id']);
      });
      return;
    }
    await _reloadPost(post['post_id'] as int);
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
      floatingActionButton: FloatingActionButton(
        onPressed: _createPost,
        tooltip: 'Buat post',
        child: const Icon(Icons.add_a_photo_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _posts.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 110),
                  Icon(Icons.photo_library_outlined, size: 44),
                  SizedBox(height: 10),
                  Center(child: Text('Belum ada post di sekitar')),
                  SizedBox(height: 4),
                  Center(
                    child: Text('Post dari kontak dan akun dalam radius 500 m.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 92),
                itemCount: _posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  final own = _isOwnPost(post);
                  return _PostCard(
                    post: post,
                    onLike: () => _toggleLike(post),
                    onComments: () => _openComments(post),
                    onOpen: () => _openDetail(post),
                    onEdit: own ? () => _editPost(post) : null,
                    onDelete: own ? () => _deletePost(post) : null,
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
    required this.onOpen,
    this.onEdit,
    this.onDelete,
  });

  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
    final type = account['type_code'] as String?;
    final source = post['feed_source'] as String?;
    final distance = post['distance_m'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: typeColor(type).withValues(alpha: 0.15),
                  child: Icon(typeIcon(type), size: 18, color: typeColor(type)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${account['display_name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '@${account['handle'] ?? ''} · ${timeAgo(post['created_at'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (source != null)
                  _FeedSourceBadge(source: source, distance: distance as int?),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: 'Aksi post',
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit caption'),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Hapus post'),
                        ),
                    ],
                  ),
              ],
            ),
            if ('${post['caption'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 7),
              GestureDetector(
                onTap: onOpen,
                child: Text(
                  '${post['caption']}',
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onOpen,
                child: ClipRRect(
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
              ),
              if (media.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+${media.length - 1} foto',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ],
            const SizedBox(height: 2),
            Row(
              children: [
                _ActionButton(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.red : null,
                  count: '${post['like_count'] ?? 0}',
                  onTap: onLike,
                ),
                const SizedBox(width: 14),
                _ActionButton(
                  icon: Icons.mode_comment_outlined,
                  count: '${post['comment_count'] ?? 0}',
                  onTap: onComments,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedSourceBadge extends StatelessWidget {
  const _FeedSourceBadge({required this.source, required this.distance});

  final String source;
  final int? distance;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    if (source == 'nearby') {
      final meters = distance ?? 0;
      label = meters >= 1000
          ? 'Sekitar ${(meters / 1000).toStringAsFixed(1)} km'
          : 'Sekitar $meters m';
      color = Theme.of(context).colorScheme.primary;
    } else if (source == 'own') {
      label = 'Akunmu';
      color = const Color(0xFFB45309);
    } else {
      label = 'Kontak';
      color = Colors.blueGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.count,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String count;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 4),
            Text(
              count,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
