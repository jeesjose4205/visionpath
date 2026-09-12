import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// EMERGENCY SCREEN
// ============================================================

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({
    super.key,
  });

  @override
  State<EmergencyScreen> createState() =>
      _EmergencyScreenState();
}

class _EmergencyScreenState
    extends State<EmergencyScreen> {

  bool isHolding = false;

  double progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAFD),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.maxWidth;

            final height =
                constraints.maxHeight;

            return Padding(
              padding:
                  EdgeInsets.symmetric(
                horizontal:
                    width * 0.055,

                vertical: 8,
              ),

              child: Column(
                children: [

                  // ==================================================
                  // HEADER
                  // ==================================================

                  SizedBox(
                    height:
                        height * 0.07,

                    child: Row(
                      children: [

                        Semantics(
                          button: true,

                          label:
                              'Back to home',

                          child: Material(
                            color:
                                Colors.transparent,

                            child: InkWell(
                              onTap: () {
                                Navigator.of(
                                  context,
                                ).pop();
                              },

                              borderRadius:
                                  BorderRadius.circular(
                                16,
                              ),

                              child:
                                  const SizedBox(
                                width: 50,
                                height: 50,

                                child: Icon(
                                  Icons
                                      .arrow_back_rounded,

                                  size: 29,

                                  color:
                                      Color(
                                    0xFF15233D,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const Expanded(
                          child: Text(
                            'Emergency',

                            textAlign:
                                TextAlign.center,

                            style:
                                TextStyle(
                              fontSize: 23,

                              fontWeight:
                                  FontWeight.w700,

                              color:
                                  Color(
                                0xFF15233D,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          width: 50,
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // SOS INTRO
                  // ==================================================

                  Expanded(
                    flex: 25,

                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,

                      children: [

                        // SOS CIRCLE
                        Container(
                          width: 145,
                          height: 145,

                          padding:
                              const EdgeInsets.all(
                            12,
                          ),

                          decoration:
                              const BoxDecoration(
                            shape:
                                BoxShape.circle,

                            color:
                                Color(
                              0xFFFFE7E7,
                            ),
                          ),

                          child: Container(
                            decoration:
                                const BoxDecoration(
                              shape:
                                  BoxShape.circle,

                              color:
                                  Color(
                                0xFFE63B3B,
                              ),
                            ),

                            child:
                                const Center(
                              child: Text(
                                'SOS',

                                style:
                                    TextStyle(
                                  color:
                                      Colors.white,

                                  fontSize:
                                      40,

                                  fontWeight:
                                      FontWeight.w800,

                                  letterSpacing:
                                      1,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 13,
                        ),

                        const Text(
                          'Need emergency help?',

                          textAlign:
                              TextAlign.center,

                          style:
                              TextStyle(
                            fontSize: 24,

                            fontWeight:
                                FontWeight.w700,

                            letterSpacing:
                                -0.5,

                            color:
                                Color(
                              0xFF15233D,
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 6,
                        ),

                        const Text(
                          'Your current location will be shared\n'
                          'with your emergency contacts.',

                          textAlign:
                              TextAlign.center,

                          style:
                              TextStyle(
                            fontSize: 1,

                            height: 1.35,

                            color:
                                Color(
                              0xFF718096,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // HOLD SOS BUTTON
                  // ==================================================

                  Expanded(
                    flex: 13,

                    child: GestureDetector(
                      onLongPressStart:
                          (_) {
                        startSOS();
                      },

                      onLongPressEnd:
                          (_) {
                        if (isHolding) {
                          setState(() {
                            isHolding =
                                false;

                            progress =
                                0.0;
                          });
                        }
                      },

                      child: Semantics(
                        button: true,

                        label:
                            'Hold for SOS for three seconds.',

                        child: Container(
                          width:
                              double.infinity,

                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFE63B3B,
                            ),

                            borderRadius:
                                BorderRadius
                                    .circular(
                              20,
                            ),
                          ),

                          child: Stack(
                            children: [

                              // PROGRESS
                              FractionallySizedBox(
                                widthFactor:
                                    progress,

                                alignment:
                                    Alignment
                                        .centerLeft,

                                child:
                                    Container(
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        const Color(
                                      0xFFD52E2E,
                                    ),

                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      20,
                                    ),
                                  ),
                                ),
                              ),

                              // TEXT
                              const Center(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment
                                          .center,

                                  children: [

                                    Icon(
                                      Icons
                                          .touch_app_outlined,

                                      size: 35,

                                      color:
                                          Colors.white,
                                    ),

                                    SizedBox(
                                      width: 14,
                                    ),

                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .center,

                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,

                                      children: [

                                        Text(
                                          'HOLD FOR SOS',

                                          style:
                                              TextStyle(
                                            color:
                                                Colors.white,

                                            fontSize:
                                                18,

                                            fontWeight:
                                                FontWeight.w700,
                                          ),
                                        ),

                                        SizedBox(
                                          height: 3,
                                        ),

                                        Text(
                                          'Press and hold for 3 seconds',

                                          style:
                                              TextStyle(
                                            color:
                                                Colors.white,

                                            fontSize:
                                                12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  // ==================================================
                  // CALL + CONTACTS
                  // ==================================================

                  Expanded(
                    flex: 11,

                    child: Row(
                      children: [

                        Expanded(
                          child:
                              EmergencySmallCard(
                            icon:
                                Icons.phone_outlined,

                            title:
                                'Call 112',

                            subtitle:
                                'Emergency service',

                            onTap: () {
                              showMessage(
                                context,
                                'Call 112 selected',
                              );
                            },
                          ),
                        ),

                        const SizedBox(
                          width: 12,
                        ),

                        Expanded(
                          child:
                              EmergencySmallCard(
                            icon:
                                Icons
                                    .people_outline_rounded,

                            title:
                                'Notify Contacts',

                            subtitle:
                                'Share location',

                            onTap: () {
                              showMessage(
                                context,
                                'Notify contacts selected',
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

                  // ==================================================
                  // EMERGENCY CONTACTS
                  // ==================================================

                  Expanded(
                    flex: 25,

                    child:
                        const ContactsCard(),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  // ==================================================
                  // LOCATION
                  // ==================================================

                  Expanded(
                    flex: 11,

                    child:
                        const LocationCard(),
                  ),

                  const SizedBox(
                    height: 4,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // SOS TIMER
  // ============================================================

  Future<void> startSOS() async {
    if (isHolding) {
      return;
    }

    setState(() {
      isHolding = true;
      progress = 0;
    });

    for (int i = 1; i <= 30; i++) {
      await Future.delayed(
        const Duration(
          milliseconds: 100,
        ),
      );

      if (!mounted || !isHolding) {
        return;
      }

      setState(() {
        progress =
            i / 30;
      });
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isHolding = false;
      progress = 0;
    });

    showSOSActivated();
  }

  // ============================================================
  // SOS ACTIVATED
  // ============================================================

  void showSOSActivated() {
    showDialog(
      context: context,

      barrierDismissible: false,

      builder: (context) {
        return AlertDialog(
          backgroundColor:
              Colors.white,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              24,
            ),
          ),

          title: const Row(
            children: [

              Icon(
                Icons.check_circle_rounded,

                color:
                    Color(0xFF15945F),

                size: 30,
              ),

              SizedBox(
                width: 10,
              ),

              Text(
                'SOS Activated',
              ),
            ],
          ),

          content:
              const Text(
            'Emergency assistance has been activated. '
            'Your location can now be shared with your trusted contacts.',
          ),

          actions: [

            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                );
              },

              child:
                  const Text(
                'OK',
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// EMERGENCY SMALL CARD
// ============================================================

class EmergencySmallCard
    extends StatelessWidget {

  final IconData icon;

  final String title;
  final String subtitle;

  final VoidCallback onTap;

  const EmergencySmallCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,

      label:
          '$title. $subtitle.',

      child: Material(
        color:
            Colors.transparent,

        child: InkWell(
          onTap: onTap,

          borderRadius:
              BorderRadius.circular(
            18,
          ),

          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),

            decoration:
                BoxDecoration(
              color:
                  Colors.white,

              borderRadius:
                  BorderRadius.circular(
                18,
              ),

              border: Border.all(
                color:
                    const Color(
                  0xFFE3E8EF,
                ),
              ),
            ),

            child: Row(
              children: [

                Container(
                  width: 43,
                  height: 43,

                  decoration:
                      const BoxDecoration(
                    shape:
                        BoxShape.circle,

                    color:
                        Color(
                      0xFFE7F0FF,
                    ),
                  ),

                  child: Icon(
                    icon,

                    size: 22,

                    color:
                        const Color(
                      0xFF1769E0,
                    ),
                  ),
                ),

                const SizedBox(
                  width: 10,
                ),

                Expanded(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .center,

                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      Text(
                        title,

                        maxLines: 2,

                        overflow:
                            TextOverflow.ellipsis,

                        style:
                            const TextStyle(
                          fontSize: 13.5,

                          fontWeight:
                              FontWeight.w700,

                          color:
                              Color(
                            0xFF15233D,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 2,
                      ),

                      Text(
                        subtitle,

                        maxLines: 1,

                        overflow:
                            TextOverflow.ellipsis,

                        style:
                            const TextStyle(
                          fontSize: 10.5,

                          color:
                              Color(
                            0xFF718096,
                          ),
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
// CONTACTS CARD
// ============================================================

class ContactsCard extends StatefulWidget {
  const ContactsCard({
    super.key,
  });

  @override
  State<ContactsCard> createState() => _ContactsCardState();
}

class _ContactsCardState extends State<ContactsCard> {
  List<Map<String, String>> contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  // ============================================================
  // LOAD CONTACTS
  // ============================================================

  Future<void> _loadContacts() async {
    final prefs =
        await SharedPreferences.getInstance();

    final saved =
        prefs.getStringList('emergency_contacts');

    if (saved == null || saved.isEmpty) {
      return;
    }

    final loaded =
        <Map<String, String>>[];

    for (final item in saved) {
      try {
        final data =
            jsonDecode(item) as Map<String, dynamic>;

        loaded.add({
          'name': data['name']?.toString() ?? '',
          'phone': data['phone']?.toString() ?? '',
        });
      } catch (_) {
        // Ignore invalid saved contact
      }
    }

    if (!mounted) return;

    setState(() {
      contacts = loaded;
    });
  }

  // ============================================================
  // SAVE CONTACTS
  // ============================================================

  Future<void> _saveContacts() async {
    final prefs =
        await SharedPreferences.getInstance();

    final saved = contacts.map((contact) {
      return jsonEncode(contact);
    }).toList();

    await prefs.setStringList(
      'emergency_contacts',
      saved,
    );
  }

  // ============================================================
  // ADD CONTACT
  // ============================================================

  Future<void> _addContact() async {
    if (contacts.length >= 5) {
      showMessage(
        context,
        'Maximum 5 emergency contacts allowed',
      );
      return;
    }

    final result =
        await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const ContactFormDialog(
          title: 'Add Emergency Contact',
          buttonText: 'Save Contact',
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final duplicate = contacts.any(
      (contact) =>
          contact['phone'] == result['phone'],
    );

    if (duplicate) {
      showMessage(
        context,
        'This phone number is already added',
      );
      return;
    }

    setState(() {
      contacts.add(result);
    });

    await _saveContacts();

    if (!mounted) return;

    showMessage(
      context,
      '${result['name']} added successfully',
    );
  }

  // ============================================================
  // EDIT CONTACT
  // ============================================================

  Future<void> _editContact(int index) async {
    final contact = contacts[index];

    final result =
        await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ContactFormDialog(
          title: 'Edit Contact',
          buttonText: 'Save Changes',
          initialName: contact['name'] ?? '',
          initialPhone: contact['phone'] ?? '',
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    // Check duplicate phone number except
    // for the contact currently being edited.
    final duplicate = contacts.asMap().entries.any(
      (entry) {
        if (entry.key == index) {
          return false;
        }

        return entry.value['phone'] ==
            result['phone'];
      },
    );

    if (duplicate) {
      showMessage(
        context,
        'This phone number is already added',
      );
      return;
    }

    setState(() {
      contacts[index] = result;
    });

    await _saveContacts();

    if (!mounted) return;

    showMessage(
      context,
      'Contact updated',
    );
  }

  // ============================================================
  // DELETE CONTACT
  // ============================================================

  Future<void> _deleteContact(int index) async {
    final contact = contacts[index];

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Contact?',
            style: TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),

          content: Text(
            'Remove ${contact['name']} from emergency contacts?',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),

            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },

              style: TextButton.styleFrom(
                foregroundColor:
                    const Color(0xFFE63B3B),
              ),

              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      contacts.removeAt(index);
    });

    await _saveContacts();

    if (!mounted) return;

    showMessage(
      context,
      'Contact deleted',
    );
  }

  // ============================================================
  // CONTACT OPTIONS
  // ============================================================

  void _showContactOptions(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,

      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),

      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                ),

                title: const Text(
                  'Edit Contact',
                ),

                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop();

                  Future.microtask(() {
                    if (mounted) {
                      _editContact(index);
                    }
                  });
                },
              ),

              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE63B3B),
                ),

                title: const Text(
                  'Delete Contact',
                  style: TextStyle(
                    color: Color(0xFFE63B3B),
                  ),
                ),

                onTap: () {
                  Navigator.of(
                    sheetContext,
                  ).pop();

                  Future.microtask(() {
                    if (mounted) {
                      _deleteContact(index);
                    }
                  });
                },
              ),

              const SizedBox(
                height: 8,
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // VIEW ALL CONTACTS
  // ============================================================

  void _viewAllContacts() {
    if (contacts.isEmpty) {
      showMessage(
        context,
        'No emergency contacts added',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,

      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),

      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20,
            ),

            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,

                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFD8DDE6),

                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                const Text(
                  'Emergency Contacts',

                  style: TextStyle(
                    fontSize: 19,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        Color(0xFF15233D),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                ...contacts.asMap().entries.map(
                  (entry) {
                    final index =
                        entry.key;

                    final contact =
                        entry.value;

                    return Padding(
                      padding:
                          const EdgeInsets.only(
                        bottom: 8,
                      ),

                      child: ContactRow(
                        name:
                            contact['name'] ?? '',

                        subtitle:
                            contact['phone'] ?? '',

                        onMore: () {
                          Navigator.of(
                            sheetContext,
                          ).pop();

                          Future.microtask(() {
                            if (mounted) {
                              _showContactOptions(
                                index,
                              );
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(11),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color:
              const Color(0xFFE3E8EF),
        ),
      ),

      child: Column(
        children: [
          // ------------------------------------------------------
          // TITLE
          // ------------------------------------------------------

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Emergency Contacts',

                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        Color(0xFF15233D),
                  ),
                ),
              ),

              TextButton(
                onPressed:
                    _viewAllContacts,

                child: const Text(
                  'View all',
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 5,
          ),

          // ------------------------------------------------------
          // CONTACT LIST
          // ------------------------------------------------------

          if (contacts.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No emergency contacts added',

                  textAlign:
                      TextAlign.center,

                  style: TextStyle(
                    fontSize: 12,
                    color:
                        Color(0xFF8793A5),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  ContactRow(
                    name:
                        contacts[0]['name'] ?? '',

                    subtitle:
                        contacts[0]['phone'] ?? '',

                    onMore: () {
                      _showContactOptions(0);
                    },
                  ),

                  if (contacts.length > 1) ...[
                    const SizedBox(
                      height: 6,
                    ),

                    ContactRow(
                      name:
                          contacts[1]['name'] ?? '',

                      subtitle:
                          contacts[1]['phone'] ?? '',

                      onMore: () {
                        _showContactOptions(1);
                      },
                    ),
                  ],

                  const Spacer(),
                ],
              ),
            ),

          const SizedBox(
            height: 6,
          ),

          // ------------------------------------------------------
          // ADD CONTACT
          // ------------------------------------------------------

          SizedBox(
            width: double.infinity,
            height: 38,

            child: OutlinedButton.icon(
              onPressed: _addContact,

              icon: const Icon(
                Icons.add,
                size: 19,
              ),

              label: const Text(
                'Add Contact',
              ),

              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    const Color(0xFF1769E0),

                backgroundColor:
                    const Color(0xFFF3F7FF),

                side: const BorderSide(
                  color:
                      Color(0xFFDCE8FA),
                ),

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CONTACT FORM DIALOG
// ============================================================

class ContactFormDialog extends StatefulWidget {
  final String title;
  final String buttonText;
  final String initialName;
  final String initialPhone;

  const ContactFormDialog({
    super.key,
    required this.title,
    required this.buttonText,
    this.initialName = '',
    this.initialPhone = '',
  });

  @override
  State<ContactFormDialog> createState() =>
      _ContactFormDialogState();
}

class _ContactFormDialogState
    extends State<ContactFormDialog> {
  late final TextEditingController
      nameController;

  late final TextEditingController
      phoneController;

  final formKey =
      GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    nameController =
        TextEditingController(
      text: widget.initialName,
    );

    phoneController =
        TextEditingController(
      text: widget.initialPhone,
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();

    super.dispose();
  }

  // ============================================================
  // SAVE
  // ============================================================

  void _save() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final phone =
        phoneController.text
            .trim()
            .replaceAll(
              RegExp(r'[\s\-()]'),
              '',
            );

    Navigator.of(context).pop({
      'name':
          nameController.text.trim(),

      'phone': phone,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,

        style: const TextStyle(
          fontWeight:
              FontWeight.w700,
        ),
      ),

      content: Form(
        key: formKey,

        child: Column(
          mainAxisSize:
              MainAxisSize.min,

          children: [
            // ----------------------------------------------------
            // NAME
            // ----------------------------------------------------

            TextFormField(
              controller:
                  nameController,

              autofocus: true,

              textCapitalization:
                  TextCapitalization.words,

              decoration:
                  InputDecoration(
                labelText: 'Name',

                hintText:
                    'Enter contact name',

                prefixIcon:
                    const Icon(
                  Icons
                      .person_outline_rounded,
                ),

                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Enter a name';
                }

                if (value.trim().length <
                    2) {
                  return 'Enter a valid name';
                }

                return null;
              },
            ),

            const SizedBox(
              height: 14,
            ),

            // ----------------------------------------------------
            // PHONE
            // ----------------------------------------------------

            TextFormField(
              controller:
                  phoneController,

              keyboardType:
                  TextInputType.phone,

              decoration:
                  InputDecoration(
                labelText:
                    'Phone Number',

                hintText:
                    'Enter phone number',

                prefixIcon:
                    const Icon(
                  Icons.phone_outlined,
                ),

                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Enter a phone number';
                }

                final phone =
                    value.replaceAll(
                  RegExp(
                    r'[\s\-()]',
                  ),
                  '',
                );

                if (!RegExp(
                  r'^\+?[0-9]{10,15}$',
                ).hasMatch(phone)) {
                  return 'Enter a valid phone number';
                }

                return null;
              },
            ),
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },

          child:
              const Text('Cancel'),
        ),

        ElevatedButton(
          onPressed: _save,

          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                const Color(0xFF1769E0),

            foregroundColor:
                Colors.white,

            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
          ),

          child: Text(
            widget.buttonText,
          ),
        ),
      ],
    );
  }
}



// ============================================================
// CONTACT ROW
// ============================================================

class ContactRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback? onMore;

  const ContactRow({
    super.key,
    required this.name,
    required this.subtitle,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,

      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
      ),

      decoration: BoxDecoration(
        color:
            const Color(0xFFFBFCFE),

        borderRadius:
            BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,

            decoration:
                const BoxDecoration(
              shape: BoxShape.circle,

              color:
                  Color(0xFFE8EDF4),
            ),

            child: const Icon(
              Icons
                  .person_outline_rounded,

              size: 22,

              color:
                  Color(0xFF8793A5),
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  name,

                  maxLines: 1,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      const TextStyle(
                    fontSize: 13.5,

                    fontWeight:
                        FontWeight.w700,

                    color:
                        Color(0xFF15233D),
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  subtitle,

                  maxLines: 1,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      const TextStyle(
                    fontSize: 10.5,

                    color:
                        Color(0xFF718096),
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            onPressed: onMore,

            padding:
                EdgeInsets.zero,

            constraints:
                const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),

            icon: const Icon(
              Icons
                  .more_vert_rounded,

              size: 21,

              color:
                  Color(0xFF15233D),
            ),
          ),
        ],
      ),
    );
  }
}


// ============================================================
// LOCATION CARD
// ============================================================

class LocationCard
    extends StatelessWidget {

  const LocationCard({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:
          double.infinity,

      padding:
          const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 7,
      ),

      decoration:
          BoxDecoration(
        color:
            Colors.white,

        borderRadius:
            BorderRadius.circular(
          18,
        ),

        border: Border.all(
          color:
              const Color(
            0xFFE3E8EF,
          ),
        ),
      ),

      child: Row(
        children: [

          Container(
            width: 43,
            height: 43,

            decoration:
                const BoxDecoration(
              shape:
                  BoxShape.circle,

              color:
                  Color(
                0xFFE4F8EF,
              ),
            ),

            child:
                const Icon(
              Icons
                  .location_on_outlined,

              size: 24,

              color:
                  Color(
                0xFF15945F,
              ),
            ),
          ),

          const SizedBox(
            width: 11,
          ),

          const Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,

              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [

                Text(
                  'Location Ready',

                  style:
                      TextStyle(
                    fontSize: 14,

                    fontWeight:
                        FontWeight.w700,

                    color:
                        Color(
                      0xFF15233D,
                    ),
                  ),
                ),

                SizedBox(
                  height: 2,
                ),

                Text(
                  'Ready to share your current location',

                  maxLines: 1,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      TextStyle(
                    fontSize: 10.5,

                    color:
                        Color(
                      0xFF718096,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: 30,
            height: 30,

            decoration:
                const BoxDecoration(
              shape:
                  BoxShape.circle,

              color:
                  Color(
                0xFF15945F,
              ),
            ),

            child:
                const Icon(
              Icons.check_rounded,

              size: 19,

              color:
                  Colors.white,
            ),
          ),
        ],
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
