import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String familyId;

  const FamilyTreeScreen({super.key, required this.familyId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _loadFamilyVaults() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final res = await _supabase
        .from('vaults')
        .select('id, name, owner_id, family_id, created_at')
        .eq('family_id', widget.familyId)
        .order('created_at', ascending: false);

    return (res as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    // Must match pubspec EXACTLY
    const logoPath = 'assets/images/immortalink_logo.png';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Family Tree'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadFamilyVaults(),
        builder: (context, snapshot) {
          final vaults = snapshot.data ?? [];
          final userId = _supabase.auth.currentUser?.id;

          Map<String, dynamic>? yourVault;
          if (userId != null) {
            for (final v in vaults) {
              if (v['owner_id'] == userId) {
                yourVault = v;
                break;
              }
            }
          }

          final yourVaultName = (yourVault?['name'] as String?) ?? 'Your vault';

          return Stack(
            children: [
              // Background watermark (restored, not tiny)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: 0.10,
                      child: Image.asset(
                        logoPath,
                        width: 520,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              // Foreground content
              ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Bring logo DOWN (less empty space, less scroll)
                  const SizedBox(height: 18),

                  Center(
                    child: Image.asset(
                      logoPath,
                      width: 110, // bigger than the tiny one, but not huge
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Center(
                    child: Text(
                      'Your Family Tree (MVP)',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: Text(
                      'Family ID: ${widget.familyId}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Tree layout
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TreeLinesPainter(),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  _TreeSlotCard(text: 'Parent vault (slot)'),
                                  _TreeSlotCard(text: 'Parent vault (slot)'),
                                ],
                              ),
                              const SizedBox(height: 34),
                              _TreeMainCard(text: yourVaultName),
                              const SizedBox(height: 34),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  _TreeSlotCard(text: 'Child vault (slot)'),
                                  _TreeSlotCard(text: 'Child vault (slot)'),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Bottom vines
                  SizedBox(
                    height: 54,
                    child: CustomPaint(
                      painter: _BottomVinesPainter(),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Center(
                    child: Text(
                      'Your tree grows as more people are added.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.50),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Debug list
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                      color: Colors.white.withOpacity(0.30),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vaults in this family (debug list)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Text('Loading...')
                        else if (vaults.isEmpty)
                          const Text('No vaults found for this family yet.')
                        else
                          ...vaults.map((v) {
                            final name = (v['name'] as String?) ?? 'Unnamed';
                            final isYou = userId != null && v['owner_id'] == userId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.person,
                                      size: 18, color: Colors.black.withOpacity(0.6)),
                                  const SizedBox(width: 10),
                                  Text(isYou ? '$name (you)' : name),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TreeSlotCard extends StatelessWidget {
  final String text;
  const _TreeSlotCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 70,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.35),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: Colors.black.withOpacity(0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeMainCard extends StatelessWidget {
  final String text;
  const _TreeMainCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      height: 90,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.40),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.22)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midX = size.width / 2;

    // Stop lines BEFORE the boxes so they don’t enter them
    final parentY = 35.0;
    final mainY = 35.0 + 34.0 + 45.0; // approx center of main card
    final childY = 35.0 + 34.0 + 90.0 + 34.0 + 35.0;

    // Parent bracket curve
    final parentPath = Path()
      ..moveTo(135, parentY + 55)
      ..quadraticBezierTo(midX, parentY + 105, size.width - 135, parentY + 55);
    canvas.drawPath(parentPath, paint);

    // Connector down (ends above main card)
    canvas.drawLine(
      Offset(midX, parentY + 105),
      Offset(midX, mainY - 32),
      paint,
    );

    // Child bracket curve
    final childPath = Path()
      ..moveTo(185, childY + 5)
      ..quadraticBezierTo(midX, childY - 28, size.width - 185, childY + 5);
    canvas.drawPath(childPath, paint);

    // Connector from main down (starts below main card)
    canvas.drawLine(
      Offset(midX, mainY + 32),
      Offset(midX, childY - 28),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BottomVinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final p2 = Paint()
      ..color = Colors.black.withOpacity(0.10)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final y1 = size.height * 0.55;
    final y2 = size.height * 0.72;

    final path1 = Path()
      ..moveTo(0, y1)
      ..cubicTo(size.width * 0.22, y1 - 10, size.width * 0.38, y1 + 14, size.width * 0.52, y1)
      ..cubicTo(size.width * 0.70, y1 - 16, size.width * 0.84, y1 + 10, size.width, y1);

    final path2 = Path()
      ..moveTo(0, y2)
      ..cubicTo(size.width * 0.18, y2 + 8, size.width * 0.42, y2 - 12, size.width * 0.60, y2)
      ..cubicTo(size.width * 0.78, y2 + 14, size.width * 0.92, y2 - 6, size.width, y2);

    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
