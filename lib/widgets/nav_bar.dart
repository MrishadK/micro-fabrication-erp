import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Haptics

class CustomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;

  const CustomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  // Helper to handle selection with vibration
  void _handleTap(int index) {
    if (index != selectedIndex) {
      // Haptics only on mobile
      if (Platform.isAndroid || Platform.isIOS) {
        HapticFeedback.lightImpact();
      }
      onDestinationSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = const Color(0xFF1A237E);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      // 🔥 SAFE AREA: Prevents taps from colliding with the Android swipe gesture area
      child: SafeArea(
        bottom: true,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: primaryColor.withOpacity(0.1),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                );
              }
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              );
            }),
          ),
          child: NavigationBar(
            height: (Platform.isWindows || Platform.isLinux) ? 72 : 65,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            selectedIndex: selectedIndex,
            onDestinationSelected: _handleTap,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              _buildDestination(
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard,
                label: 'Jobs',
                color: primaryColor,
              ),
              _buildDestination(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: 'Clients',
                color: primaryColor,
              ),
              _buildDestination(
                icon: Icons.history_outlined,
                selectedIcon: Icons.history,
                label: 'Archive',
                color: primaryColor,
              ),
              _buildDestination(
                icon: Icons.calculate_outlined,
                selectedIcon: Icons.calculate,
                label: 'Wages',
                color: primaryColor,
              ),
              _buildDestination(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
                color: primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  NavigationDestination _buildDestination({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required Color color,
  }) {
    return NavigationDestination(
      icon: Icon(icon, color: Colors.grey.shade500),

      // 🔥 PREMIUM ICON BOUNCE ANIMATION 🔥
      selectedIcon: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween<double>(begin: 0.3, end: 1.0), // Scales from 30% to 100%
        curve: Curves.elasticOut, // Gives it that satisfying "spring" effect
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: Icon(selectedIcon, color: color),
      ),
      label: label,
    );
  }
}
