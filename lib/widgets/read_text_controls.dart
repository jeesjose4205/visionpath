import 'package:flutter/material.dart';

/// Bottom control cluster for the Read Text screen.
///
/// Always shows the primary capture button; secondary actions appear only
/// once a result exists. The whole screen is intentionally scroll-free.
class ReadTextControls extends StatelessWidget {
  final VoidCallback? onCapture;
  final bool capturing;

  final VoidCallback? onReadAloud;
  final VoidCallback? onStopReading;
  final bool isReading;

  final VoidCallback? onNewScan;
  final bool hasResult;
  final bool hasError;

  const ReadTextControls({
    super.key,
    this.onCapture,
    this.capturing = false,
    this.onReadAloud,
    this.onStopReading,
    this.isReading = false,
    this.onNewScan,
    this.hasResult = false,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 700;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: compact ? 54 : 60,
          child: ElevatedButton(
            onPressed: capturing ? null : onCapture,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1769E0),
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor: const Color(0xFF9FB9E8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: capturing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'CAPTURING...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'CAPTURE TEXT',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        if (hasResult || hasError) ...[
          SizedBox(height: compact ? 8 : 10),
          Row(
            children: [
              if (hasResult)
                Expanded(
                  child: _SecondaryButton(
                    icon: isReading
                        ? Icons.stop_rounded
                        : Icons.volume_up_outlined,
                    title: isReading ? 'Stop Reading' : 'Read Aloud',
                    onTap: isReading ? onStopReading : onReadAloud,
                    highlighted: true,
                  ),
                ),
              if (hasResult) const SizedBox(width: 10),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.refresh_rounded,
                  title: 'New Scan',
                  onTap: onNewScan,
                  highlighted: false,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool highlighted;

  const _SecondaryButton({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: highlighted
              ? const Color(0xFF1769E0)
              : const Color(0xFF40516B),
          backgroundColor: highlighted
              ? const Color(0xFFEFF5FF)
              : Colors.white,
          side: BorderSide(
            color: highlighted
                ? const Color(0xFFB9D2F7)
                : const Color(0xFFDCE4EF),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}