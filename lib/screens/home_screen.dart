import 'package:flutter/material.dart';
import 'navigate_screen.dart';
import 'emergency_screen.dart';
import 'read_text_screen.dart';

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.05,
                vertical: 8,
              ),

              child: Column(
                children: [

                  // ==================================================
                  // HEADER
                  // ==================================================

                  SizedBox(
                    height: height * 0.075,

                    child: Row(
                      children: [

                        // MENU
                        HeaderButton(
                          icon: Icons.menu_rounded,
                          semanticLabel: 'Menu',

                          onTap: () {
                            showMessage(
                              context,
                              'Menu',
                            );
                          },
                        ),

                        // LOGO
                        Expanded(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,

                            children: [

                              RichText(
                                text: const TextSpan(
                                  children: [

                                    TextSpan(
                                      text: 'Vision',
                                      style: TextStyle(
                                        color:
                                            Color(0xFF15233D),
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),

                                    TextSpan(
                                      text: 'Path',
                                      style: TextStyle(
                                        color:
                                            Color(0xFF1769E0),
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),

                                    TextSpan(
                                      text: ' AI',
                                      style: TextStyle(
                                        color:
                                            Color(0xFF15233D),
                                        fontSize: 24,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 2),

                              const Text(
                                'SEE BEYOND TOGETHER',

                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight:
                                      FontWeight.w600,
                                  letterSpacing: 2,
                                  color:
                                      Color(0xFF718096),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // SETTINGS
                        HeaderButton(
                          icon:
                              Icons.settings_outlined,
                          semanticLabel:
                              'Settings',

                          onTap: () {
                            showMessage(
                              context,
                              'Accessibility Settings',
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // GREETING
                  // ==================================================

                  Expanded(
                    flex: 14,

                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,

                      children: [

                        Text(
                          'Good Morning',

                          style: TextStyle(
                            fontSize:
                                width * 0.082,

                            fontWeight:
                                FontWeight.w700,

                            letterSpacing: -1.2,

                            color:
                                const Color(
                              0xFF15233D,
                            ),
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          'How can I help you today?',

                          style: TextStyle(
                            fontSize:
                                width * 0.041,

                            color:
                                const Color(
                              0xFF718096,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // LOOK & DETECT
                  // ==================================================

                  Expanded(
                    flex: 27,

                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          showMessage(
                            context,
                            'Camera activated',
                          );
                        },

                        child: Semantics(
                          button: true,

                          label:
                              'Look and Detect. Identify objects, people and surroundings.',

                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,

                            children: [

                              Container(
                                width: 130,
                                height: 130,

                                padding:
                                    const EdgeInsets.all(
                                  10,
                                ),

                                decoration:
                                    const BoxDecoration(
                                  shape:
                                      BoxShape.circle,

                                  color:
                                      Color(0xFFE4EEFF),
                                ),

                                child: Container(
                                  decoration:
                                      const BoxDecoration(
                                    shape:
                                        BoxShape.circle,

                                    color:
                                        Color(0xFF1769E0),
                                  ),

                                  child:
                                      const Icon(
                                    Icons
                                        .camera_alt_outlined,

                                    size: 52,

                                    color:
                                        Colors.white,
                                  ),
                                ),
                              ),

                              const SizedBox(
                                height: 9,
                              ),

                              const Text(
                                'Look & Detect',

                                style:
                                    TextStyle(
                                  fontSize: 24,

                                  fontWeight:
                                      FontWeight.w700,

                                  color:
                                      Color(0xFF15233D),
                                ),
                              ),

                              const SizedBox(
                                height: 3,
                              ),

                              const Text(
                                'Identify objects, people and surroundings',

                                textAlign:
                                    TextAlign.center,

                                style:
                                    TextStyle(
                                  fontSize: 14,

                                  color:
                                      Color(0xFF718096),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // FEATURE CARDS
                  // ==================================================

                  Expanded(
                    flex: 32,

                    child: Column(
                      children: [

                        // ---------------- TOP ROW ----------------

                        Expanded(
                          child: Row(
                            children: [

                              Expanded(
                                child:
                                    FeatureCard(
                                  icon:
                                      Icons
                                          .description_outlined,

                                  iconColor:
                                      const Color(
                                    0xFF1769E0,
                                  ),

                                  iconBackground:
                                      const Color(
                                    0xFFE7F0FF,
                                  ),

                                  title:
                                      'Read Text',

                                  subtitle:
                                      'Scan and listen to text',

                                  onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const ReadTextScreen(),
    ),
  );
},
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child:
                                    FeatureCard(
                                  icon:
                                      Icons
                                          .navigation_outlined,

                                  iconColor:
                                      const Color(
                                    0xFF15805A,
                                  ),

                                  iconBackground:
                                      const Color(
                                    0xFFE4F8EF,
                                  ),

                                  title: 'Navigate',

                                  subtitle: 'Get voice directions',

                                  onTap: () {
                                    Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const NavigateScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        // ---------------- BOTTOM ROW ----------------

                        Expanded(
                          child: Row(
                            children: [

                              Expanded(
                                child:
                                    FeatureCard(
                                  icon:
                                      Icons
                                          .chat_bubble_outline_rounded,

                                  iconColor:
                                      const Color(
                                    0xFF7652D5,
                                  ),

                                  iconBackground:
                                      const Color(
                                    0xFFF0E9FF,
                                  ),

                                  title:
                                      'AI Assistant',

                                  subtitle:
                                      'Ask anything',

                                  onTap: () {
                                    showMessage(
                                      context,
                                      'AI Assistant opened',
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              // ==================================================
                              // EMERGENCY CARD
                              // ==================================================

                              Expanded(
                                child:
                                    FeatureCard(
                                  icon:
                                      Icons
                                          .phone_outlined,

                                  iconColor:
                                      const Color(
                                    0xFFE63B3B,
                                  ),

                                  iconBackground:
                                      const Color(
                                    0xFFFFE8E8,
                                  ),

                                  title:
                                      'Emergency',

                                  subtitle:
                                      'Get help quickly',

                                  showSOS: true,

                                  // IMPORTANT:
                                  // This navigates to EmergencyScreen
                                  onTap: () {
                                    Navigator.of(
                                      context,
                                    ).push(
                                      MaterialPageRoute(
                                        builder:
                                            (context) {
                                          return const EmergencyScreen();
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // VOICE BUTTON
                  // ==================================================

                  Expanded(
                    flex: 13,

                    child: Padding(
                      padding:
                          const EdgeInsets.only(
                        top: 12,
                        bottom: 4,
                      ),

                      child: VoiceButton(
                        onTap: () {
                          showMessage(
                            context,
                            'I am listening...',
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// HEADER BUTTON
// ============================================================

class HeaderButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const HeaderButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,

      child: Material(
        color: Colors.transparent,

        child: InkWell(
          onTap: onTap,

          borderRadius:
              BorderRadius.circular(16),

          child: SizedBox(
            width: 50,
            height: 50,

            child: Icon(
              icon,
              size: 28,
              color:
                  const Color(0xFF15233D),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FEATURE CARD
// ============================================================

class FeatureCard extends StatelessWidget {
  final IconData icon;

  final Color iconColor;
  final Color iconBackground;

  final String title;
  final String subtitle;

  final VoidCallback onTap;

  final bool showSOS;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showSOS = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,

      label:
          '$title. $subtitle.',

      child: Material(
        color: Colors.transparent,

        child: InkWell(
          onTap: onTap,

          borderRadius:
              BorderRadius.circular(20),

          child: Container(
            width: double.infinity,
            height: double.infinity,

            padding:
                const EdgeInsets.all(14),

            decoration:
                BoxDecoration(
              color: Colors.white,

              borderRadius:
                  BorderRadius.circular(20),

              border: Border.all(
                color:
                    const Color(0xFFE3E8EF),

                width: 1.1,
              ),

              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withOpacity(
                    0.025,
                  ),

                  blurRadius: 10,

                  offset:
                      const Offset(0, 3),
                ),
              ],
            ),

            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              mainAxisAlignment:
                  MainAxisAlignment.center,

              children: [

                // ICON
                Stack(
                  clipBehavior:
                      Clip.none,

                  children: [

                    Container(
                      width: 48,
                      height: 48,

                      decoration:
                          BoxDecoration(
                        color:
                            iconBackground,

                        shape:
                            BoxShape.circle,
                      ),

                      child: Icon(
                        icon,

                        size: 25,

                        color:
                            iconColor,
                      ),
                    ),

                    // SOS LABEL
                    if (showSOS)
                      Positioned(
                        top: -5,
                        right: -7,

                        child: Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),

                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFFF5C63,
                            ),

                            borderRadius:
                                BorderRadius
                                    .circular(
                              8,
                            ),
                          ),

                          child:
                              const Text(
                            'SOS',

                            style:
                                TextStyle(
                              color:
                                  Colors.white,

                              fontSize: 8,

                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(
                  height: 9,
                ),

                // TITLE
                Text(
                  title,

                  maxLines: 1,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      const TextStyle(
                    fontSize: 16,

                    fontWeight:
                        FontWeight.w700,

                    color:
                        Color(0xFF15233D),
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                // SUBTITLE
                Text(
                  subtitle,

                  maxLines: 2,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      const TextStyle(
                    fontSize: 11.5,

                    height: 1.2,

                    color:
                        Color(0xFF718096),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// VOICE BUTTON
// ============================================================

class VoiceButton extends StatelessWidget {
  final VoidCallback onTap;

  const VoiceButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,

      label:
          'Tap to speak. Activate voice assistant.',

      child: Material(
        color: Colors.transparent,

        child: InkWell(
          onTap: onTap,

          borderRadius:
              BorderRadius.circular(28),

          child: Container(
            width: double.infinity,

            decoration:
                BoxDecoration(
              color:
                  const Color(0xFF1B2739),

              borderRadius:
                  BorderRadius.circular(28),
            ),

            child: Row(
              children: [

                const SizedBox(
                  width: 18,
                ),

                Container(
                  width: 54,
                  height: 54,

                  decoration:
                      const BoxDecoration(
                    shape:
                        BoxShape.circle,

                    color:
                        Color(0xFF1769E0),
                  ),

                  child: const Icon(
                    Icons.mic_none_rounded,

                    size: 29,

                    color:
                        Colors.white,
                  ),
                ),

                const SizedBox(
                  width: 15,
                ),

                Container(
                  width: 1,
                  height: 38,

                  color:
                      Colors.white24,
                ),

                const SizedBox(
                  width: 15,
                ),

                const Expanded(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      Text(
                        'Tap to speak',

                        style:
                            TextStyle(
                          color:
                              Colors.white,

                          fontSize: 16,

                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),

                      SizedBox(
                        height: 2,
                      ),

                      Text(
                        'I\'m listening...',

                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFFAEB9C8,
                          ),

                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// GLOBAL MESSAGE
// ============================================================

void showMessage(
  BuildContext context,
  String message,
) {
  ScaffoldMessenger.of(context)
      .clearSnackBars();

  ScaffoldMessenger.of(context)
      .showSnackBar(
    SnackBar(
      content:
          Text(message),

      behavior:
          SnackBarBehavior.floating,

      margin:
          const EdgeInsets.all(18),

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),

      duration:
          const Duration(
        seconds: 2,
      ),
    ),
  );
}
