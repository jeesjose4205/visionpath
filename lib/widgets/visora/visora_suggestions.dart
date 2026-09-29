import 'package:flutter/material.dart';

/// Suggested prompt chips shown on the Visora idle state.
class VisoraSuggestions extends StatelessWidget {
  const VisoraSuggestions({
    super.key,
    required this.onSelected,
  });

  final ValueChanged<String> onSelected;

  static const List<String> prompts = [
    'What can you do?',
    'Explain machine learning',
    'Help me write an email',
    'Ideas for a project',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final prompt in prompts)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => onSelected(prompt),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFD9E5FF)),
                ),
                child: Text(
                  prompt,
                  style: const TextStyle(
                    color: Color(0xFF175CD3),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}