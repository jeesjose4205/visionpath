class FamiliarFace {
  const FamiliarFace({
    required this.id,
    required this.name,
    required this.embedding,
    required this.sampleCount,
    required this.createdAt,
    this.relationship,
    this.templates,
    this.model,
  });

  final String id;
  final String name;
  final String? relationship;
  final List<double> embedding;
  final int sampleCount;
  final int createdAt;
  final List<List<double>>? templates;
  final String? model;

  FamiliarFace copyWith({
    String? name,
    String? relationship,
    List<double>? embedding,
    int? sampleCount,
    List<List<double>>? templates,
    String? model,
  }) {
    return FamiliarFace(
      id: id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      embedding: embedding ?? this.embedding,
      sampleCount: sampleCount ?? this.sampleCount,
      createdAt: createdAt,
      templates: templates ?? this.templates,
      model: model ?? this.model,
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
      'templates': templates,
      'model': model,
    };
  }

  factory FamiliarFace.fromJson(Map<String, dynamic> json) {
    final embedding = (json['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const <double>[];
    final templatesRaw = json['templates'] as List?;
    final templates = templatesRaw?.map((t) => (t as List).map((e) => (e as num).toDouble()).toList()).toList() ?? <List<double>>[];
    final model = json['model'] as String?;
    return FamiliarFace(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String?,
      embedding: embedding,
      sampleCount: json['sampleCount'] as int,
      createdAt: json['createdAt'] as int,
      templates: templates.isEmpty ? [embedding] : templates,
      model: model,
    );
  }
}
