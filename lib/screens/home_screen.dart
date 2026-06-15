import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/providers/friend_req_provider.dart';
import 'package:vibetalk/screens/chart_list_screen.dart';
import 'package:vibetalk/screens/profile_screen.dart';
import 'package:vibetalk/screens/reqest_screen.dart';
import 'package:vibetalk/screens/user_list_screen.dart';

import '../theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ChatListScreen(),
    UsersListScreen(),
    RequestsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final receivedRequests = ref.watch(receivedRequestsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          backgroundColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          indicatorColor: theme.colorScheme.primary.withValues(alpha: .15),
          elevation: 0,
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: const Duration(milliseconds: 300),
          destinations: [
            NavigationDestination(
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                color: _currentIndex == 0
                    ? theme.colorScheme.primary
                    : (isDark
                          ? AppTheme.textTertiaryDark
                          : AppTheme.textTertiaryLight),
              ),
              selectedIcon: Icon(
                Icons.chat_bubble_rounded,
                color: theme.colorScheme.primary,
              ),
              label: 'Messages',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.people_outline_rounded,
                color: _currentIndex == 1
                    ? theme.colorScheme.primary
                    : (isDark
                          ? AppTheme.textTertiaryDark
                          : AppTheme.textTertiaryLight),
              ),
              selectedIcon: Icon(
                Icons.people_rounded,
                color: theme.colorScheme.primary,
              ),
              label: 'Users',
            ),
            NavigationDestination(
              icon: _buildRequestsBadge(
                context,
                theme,
                isDark,
                receivedRequests.value?.length ?? 0,
                isSelected: _currentIndex == 2,
              ),
              selectedIcon: _buildRequestsBadge(
                context,
                theme,
                isDark,
                receivedRequests.value?.length ?? 0,
                isSelected: true,
              ),
              label: 'Requests',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.person_outline_rounded,
                color: _currentIndex == 3
                    ? theme.colorScheme.primary
                    : (isDark
                          ? AppTheme.textTertiaryDark
                          : AppTheme.textTertiaryLight),
              ),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: theme.colorScheme.primary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsBadge(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    int count, {
    required bool isSelected,
  }) {
    final hasRequests = count > 0;

    return Badge(
      isLabelVisible: hasRequests,
      backgroundColor: theme.colorScheme.error,
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      offset: const Offset(10, -8),
      child: Icon(
        isSelected ? Icons.person_add_rounded : Icons.person_add_outlined,
        color: isSelected
            ? theme.colorScheme.primary
            : (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight),
      ),
    );
  }
}
