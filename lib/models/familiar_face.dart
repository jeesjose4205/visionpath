/// A registered familiar person.
///
/// Stores a single representative face embedding (the L2-normalized mean of
/// the samples captured during registration) plus bookkeeping metadata.
/// Embeddings are sensitive biometric data and are stored locally only — never
/// uploaded anywhere.
class FamiliarFace {
  const FamiliarFace({
    required this.id,
    required this.name,
    required this.embedding,
    required this.sampleCount,
    required this.createdAt,
    this.relationship,
  });

  /// Unique local identifier (milliseconds since epoch).
  final String id;

  /// Person's display name (e.g., "Mother").
  final String name;

  /// Optional relationship label (e.g., "Mother", "Friend", "Teacher").
  final String? relationship;

  /// L2-normalized geometric face embedding derived from the captured samples.
  final List<double> embedding;

  /// Number of valid samples captured at registration time.
  final int sampleCount;

  /// Registration timestamp (milliseconds since epoch).
  final int createdAt;

  FamiliarFace copyWith({
    String? name,
    String? relationship,
    List<double>? embedding,
    int? sampleCount,
  }) {
    return FamiliarFace(
      id: id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      embedding: embedding ?? this.embedding,
      sampleCount: sampleCount ?? this.sampleCount,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'embedding': embedding,
      'sampleCount': sampleCount,
      'createdAt': createdAt,
    };
  }

  factory FamiliarFace.fromJson(Map<String, dynamic> json) {
    return FamiliarFace(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String?,
      embedding: (json['embedding'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList(),
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 1,
      createdAt: (json['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}