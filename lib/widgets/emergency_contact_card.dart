import 'package:flutter/material.dart';

import '../models/emergency_contact.dart';

class EmergencyContactCard extends StatelessWidget {
  const EmergencyContactCard({
    super.key,
    required this.contact,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
    this.height = 48,
  });

  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double height;

  @override
  Widget build(BuildContext context) {
    final compact = height <= 38;
    final initials = contact.name.trim().isEmpty
        ? '?'
        : contact.name.trim().characters.first.toUpperCase();

    return SizedBox(
      height: height,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAF0F7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A1A2333),
              blurRadius: 7,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 32 : 38,
              height: compact ? 32 : 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFF0EE),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: const Color(0xFFE63B3B),
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF15233D),
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    contact.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF718096),
                      fontSize: compact ? 10.5 : 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _ActionCircle(
              tooltip: 'Call ${contact.name}',
              icon: Icons.call_rounded,
              background: const Color(0xFFE4F8EF),
              color: const Color(0xFF15805A),
              size: compact ? 29 : 33,
              iconSize: compact ? 14 : 16,
              onTap: onCall,
            ),
            const SizedBox(width: 6),
            _ActionCircle(
              tooltip: 'Edit ${contact.name}',
              icon: Icons.edit_rounded,
              background: const Color(0xFFE7F0FF),
              color: const Color(0xFF1769E0),
              size: compact ? 29 : 33,
              iconSize: compact ? 14 : 16,
              onTap: onEdit,
            ),
            const SizedBox(width: 6),
            _ActionCircle(
              tooltip: 'Delete ${contact.name}',
              icon: Icons.delete_rounded,
              background: const Color(0xFFFFE8E8),
              color: const Color(0xFFE63B3B),
              size: compact ? 29 : 33,
              iconSize: compact ? 14 : 16,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.color,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color color;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, color: color, size: iconSize),
        ),
      ),
    );
  }
}