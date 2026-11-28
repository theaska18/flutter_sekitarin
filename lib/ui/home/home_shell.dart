import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../../services/push_service.dart';
import '../calls/call_log_screen.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_room_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int? _lastActiveAccountId;
  Timer? _badgePoll;
  Map<String, dynamic>? _selectedConversation;

  static const _titles = ['Chat', 'Sekitar', 'Post', 'Log Telepon'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBadgePoll();
    PushService.conversationToOpen.addListener(_openPushedConversation);
    if (PushService.conversationToOpen.value != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPushedConversation(),
      );
    }
  }

  Future<void> _openPushedConversation() async {
    final conversationId = PushService.conversationToOpen.value;
    if (conversationId == null || !mounted) return;
    PushService.conversationToOpen.value = null;
    try {
      final data = await context
          .read<AuthStore>()
          .api
          .get('conversations/$conversationId');
      final conversation = data is Map ? data['conversation'] : null;
      if (conversation is! Map || !mounted) return;
      final target = Map<String, dynamic>.from(conversation);
      if (MediaQuery.sizeOf(context).width >= 980) {
        setState(() {
          _index = 0;
          _selectedConversation = target;
        });
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(conversation: target),
        ),
      );
      if (mounted) {
        chatListRefreshTick.value++;
        context.read<AuthStore>().refresh();
      }
    } catch (_) {
      // The conversation may have been removed.
    }
  }

  void _startBadgePoll() {
    _badgePoll ??= Timer.periodic(
      const Duration(seconds: 25),
      (_) => context.read<AuthStore>().refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _badgePoll?.cancel();
      _badgePoll = null;
    } else if (state == AppLifecycleState.resumed) {
      _startBadgePoll();
      chatListRefreshTick.value++;
      context.read<AuthStore>().refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.conversationToOpen.removeListener(_openPushedConversation);
    _badgePoll?.cancel();
    super.dispose();
  }

  Future<void> _openChatTab() async {
    final auth = context.read<AuthStore>();
    await auth.markChatNotificationsRead(force: true);
    chatListRefreshTick.value++;
    await auth.refresh();
  }

  Widget _badgedIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text(count > 9 ? '9+' : '$count'),
      child: Icon(icon),
    );
  }

  void _selectTab(int value) {
    if (_index == 0 && value != 0) {
      context.read<AuthStore>().markChatNotificationsRead(force: true);
    }
    setState(() => _index = value);
    if (value == 0) _openChatTab();
  }

  List<NavigationRailDestination> _railDestinations(int chatBadge) {
    return [
      NavigationRailDestination(
        icon: _badgedIcon(Icons.chat_bubble_outline, chatBadge),
        selectedIcon: _badgedIcon(Icons.chat_bubble, chatBadge),
        label: const Text('Chat'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.public_outlined),
        selectedIcon: Icon(Icons.public),
        label: Text('Peta'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.photo_library_outlined),
        selectedIcon: Icon(Icons.photo_library),
        label: Text('Post'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.phone_in_talk_outlined),
        selectedIcon: Icon(Icons.phone_in_talk),
        label: Text('Log Telepon'),
      ),
    ];
  }

  Widget _emptyChatPane(ThemeData theme) {
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Pilih percakapan',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Percakapan dibuka di kolom ini.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet landscape: conversation list on the left, active room on the
  /// right. The room is part of the shell instead of a pushed route.
  Widget _twoPaneChat(AuthStore auth, double listWidth) {
    final conversation = _selectedConversation;
    return Row(
      children: [
        SizedBox(
          width: listWidth,
          child: ChatListScreen(
            active: _index == 0,
            selectedConversationId: conversation?['conversation_id'] as int?,
            onOpenConversation: (selected) {
              setState(() => _selectedConversation = selected);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: conversation == null
              ? _emptyChatPane(Theme.of(context))
              : ChatRoomScreen(
                  key: ValueKey(conversation['conversation_id']),
                  conversation: conversation,
                  embedded: true,
                  onClosed: () {
                    setState(() => _selectedConversation = null);
                    chatListRefreshTick.value++;
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    if (_index == 0 && auth.unreadChatNotifications > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) auth.markChatNotificationsRead();
      });
    }
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoPane = constraints.maxWidth >= 980;
          final listWidth = (constraints.maxWidth * 0.3).clamp(320.0, 420.0);
          final content = IndexedStack(
            index: _index,
            children: [
              twoPane
                  ? _twoPaneChat(auth, listWidth)
                  : ChatListScreen(active: _index == 0),
              MapScreen(active: _index == 1),
              const FeedScreen(),
              const CallLogScreen(),
            ],
          );
          // Tablets and wide screens get a left navigation rail so the
          // landscape layout uses the width instead of a bottom bar.
          if (constraints.maxWidth < 700) return content;
          final scheme = Theme.of(context).colorScheme;
          return Row(
            children: [
              Material(
                color: scheme.surface,
                child: SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _selectTab,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.92,
                    minWidth: 76,
                    destinations: _railDestinations(
                      _index == 0 ? 0 : auth.unreadChatNotifications,
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(child: content),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 700
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectTab,
              destinations: [
                NavigationDestination(
                  icon: _badgedIcon(
                    Icons.chat_bubble_outline,
                    _index == 0 ? 0 : auth.unreadChatNotifications,
                  ),
                  selectedIcon: _badgedIcon(
                    Icons.chat_bubble,
                    _index == 0 ? 0 : auth.unreadChatNotifications,
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
            )
          : null,
    );
  }
}
