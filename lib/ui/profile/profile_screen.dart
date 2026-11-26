import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/orders_screen.dart';
import 'create_account_screen.dart';
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

  Future<void> _createAccount() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateAccountScreen()),
    );
    if (created == true && mounted) {
      await context.read<AuthStore>().refresh();
      _loadedAccountId = null;
      didChangeDependencies();
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
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAccount,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Akun usaha'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await auth.refresh();
          await _load(auth.activeAccount?['account_id'] as int?);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: typeColor(type).withValues(alpha: 0.15),
                      child: Icon(typeIcon(type),
                          size: 38, color: typeColor(type)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      accountName(account),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    Text('@${account?['handle'] ?? ''}'),
                    const SizedBox(height: 4),
                    Text(
                      '${account?['type_label'] ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if ('${account?['bio'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('${account?['bio']}', textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _switchAccount,
                          icon: const Icon(Icons.switch_account, size: 18),
                          label: const Text('Ganti akun'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _createAccount,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Akun baru'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );
                        if (changed == true && mounted) {
                          _loadedAccountId = null;
                          didChangeDependencies();
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit profil'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const OrdersScreen(initialRole: 'customer'),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Pesanan saya'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const OrdersScreen(initialRole: 'provider'),
                      ),
                    ),
                    icon: const Icon(Icons.storefront, size: 18),
                    label: const Text('Pesanan masuk'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Post',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('Belum ada post')),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final media = _posts[index]['media'];
                  final first =
                      media is List && media.isNotEmpty ? media.first : null;
                  return Container(
                    color: Colors.black12,
                    child: first is Map
                        ? Image.network(
                            AppConfig.absoluteUrl('${first['url'] ?? ''}'),
                            headers: headers,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.image_not_supported),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '${_posts[index]['caption'] ?? ''}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
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
