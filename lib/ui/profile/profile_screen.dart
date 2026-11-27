import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../feed/post_detail_screen.dart';
import '../orders/orders_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/account_avatar.dart';
import 'business_location_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  int? _loadedAccountId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = context.watch<AuthStore>().activeAccount;
    final id = active?['account_id'] as int?;
    if (id != _loadedAccountId) {
      _loadedAccountId = id;
      _load(id);
    }
  }

  Future<void> _load(int? accountId) async {
    if (accountId == null) {
      setState(() {
        _posts = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await context
          .read<AuthStore>()
          .api
          .get('accounts/$accountId/posts', query: {'limit': '50'});
      if (!mounted || _loadedAccountId != accountId) return;
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

  Future<void> _switchAccount() async {
    final auth = context.read<AuthStore>();
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pilih akun',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final account in auth.accounts)
              ListTile(
                leading: Icon(typeIcon(account['type_code'] as String?)),
                title: Text('${account['display_name'] ?? ''}'),
                subtitle: Text('@${account['handle'] ?? ''}'),
                trailing: account['account_id'] == auth.activeAccountId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(account['account_id']),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (selected is int && mounted) {
      await auth.switchAccount(selected);
    }
  }

  Future<void> _openPost(Map<String, dynamic> post) async {
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
    try {
      final data =
          await context.read<AuthStore>().api.get('posts/${post['post_id']}');
      if (!mounted || data is! Map || data['post'] is! Map) return;
      final fresh = Map<String, dynamic>.from(data['post'] as Map);
      setState(() {
        final index =
            _posts.indexWhere((item) => item['post_id'] == post['post_id']);
        if (index >= 0) _posts[index] = fresh;
      });
    } catch (_) {
      // Keep the grid image if the refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final account = auth.activeAccount;
    final type = account?['type_code'] as String?;
    final token = auth.api.accessToken;
    final headers = token == null
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Setelan',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Setelan')),
                  body: const SettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await auth.refresh();
          await _load(auth.activeAccount?['account_id'] as int?);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
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
                                accountName(account),
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
                        if (type == 'personal')
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Edit profil',
                            onPressed: () async {
                              final changed =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen(),
                                ),
                              );
                              if (changed == true && mounted) {
                                _loadedAccountId = null;
                                didChangeDependencies();
                              }
                            },
                            icon: const Icon(Icons.edit_outlined, size: 19),
                          ),
                      ],
                    ),
                    if ('${account?['bio'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${account?['bio']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.switch_account, size: 16),
                          label: const Text('Ganti akun'),
                          labelStyle: const TextStyle(fontSize: 12),
                          onPressed: _switchAccount,
                        ),
                        if (type != 'personal')
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            avatar:
                                const Icon(Icons.settings_outlined, size: 16),
                            label: const Text('Pengaturan usaha'),
                            labelStyle: const TextStyle(fontSize: 12),
                            onPressed: () async {
                              final changed =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => BusinessLocationScreen(
                                    accountId: account!['account_id'] as int,
                                  ),
                                ),
                              );
                              if (changed == true && mounted) {
                                await auth.refresh();
                                _loadedAccountId = null;
                                didChangeDependencies();
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'Pesanan saya',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const OrdersScreen(initialRole: 'customer'),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.storefront_outlined,
                      label: 'Pesanan masuk',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const OrdersScreen(initialRole: 'provider'),
                        ),
                      ),
                    ),
                  ),
                ],
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
                  '${_posts.length} post',
                  style: TextStyle(
                    fontSize: 11,
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
