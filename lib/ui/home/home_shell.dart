import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../calls/call_log_screen.dart';
import '../chat/chat_list_screen.dart';
import '../contacts/contacts_screen.dart';
import '../feed/feed_screen.dart';
import '../map/map_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../widgets/account_type_avatar.dart';
import '../widgets/sekitarin_logo.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int? _lastActiveAccountId;
  Timer? _badgePoll;

  static const _titles = ['Chat', 'Sekitar', 'Post', 'Log Telepon'];

  @override
  void initState() {
    super.initState();
    _badgePoll = Timer.periodic(
      const Duration(seconds: 25),
      (_) => context.read<AuthStore>().refresh(),
    );
  }

  @override
  void dispose() {
    _badgePoll?.cancel();
    super.dispose();
  }

  Future<void> _openChatTab() async {
    final auth = context.read<AuthStore>();
    auth.clearChatBadge();
    chatListRefreshTick.value++;
    try {
      await auth.api.post('notifications/read-chat');
    } catch (_) {
      // Clearing the badge locally is enough when offline.
    }
    await auth.refresh();
  }

  Widget _badgedIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text(count > 9 ? '9+' : '$count'),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    if (_lastActiveAccountId != auth.activeAccountId) {
      _lastActiveAccountId = auth.activeAccountId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chatListRefreshTick.value++;
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SekitarinLogo(height: 24, showWordmark: false),
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 18,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(width: 10),
            Text(
              _titles[_index],
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          if (_index == 0)
            IconButton(
              icon: const Icon(Icons.contacts_outlined),
              tooltip: 'Kontak',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ContactsScreen(),
                ),
              ),
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                tooltip: 'Notifikasi',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  if (context.mounted) {
                    await context.read<AuthStore>().refresh();
                  }
                },
              ),
              if (auth.unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      auth.unreadNotifications > 9
                          ? '9+'
                          : '${auth.unreadNotifications}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Tooltip(
            message: 'Profil',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfileScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AccountTypeAvatar(
                  account: auth.activeAccount,
                  radius: 15,
                  token: auth.api.accessToken,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          ChatListScreen(),
          MapScreen(),
          FeedScreen(),
          CallLogScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 0) _openChatTab();
        },
        destinations: [
          NavigationDestination(
            icon: _badgedIcon(
              Icons.chat_bubble_outline,
              auth.unreadChatNotifications,
            ),
            selectedIcon: _badgedIcon(
              Icons.chat_bubble,
              auth.unreadChatNotifications,
            ),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Peta',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Post',
          ),
          const NavigationDestination(
            icon: Icon(Icons.phone_in_talk_outlined),
            selectedIcon: Icon(Icons.phone_in_talk),
            label: 'Log Telepon',
          ),
        ],
      ),
    );
  }
}
