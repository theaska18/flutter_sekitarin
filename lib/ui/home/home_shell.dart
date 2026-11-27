import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../chat/chat_list_screen.dart';
import '../contacts/add_contact_screen.dart';
import '../feed/feed_screen.dart';
import '../map/map_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/sekitarin_logo.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Timer? _badgePoll;

  static const _titles = ['Chat', 'Sekitar', 'Post', 'Profil', 'Setelan'];

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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SekitarinLogo(height: 24),
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
                  builder: (_) => const AddContactScreen(),
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
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          ChatListScreen(),
          MapScreen(),
          FeedScreen(),
          ProfileScreen(),
          SettingsScreen(),
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Setelan',
          ),
        ],
      ),
    );
  }
}
