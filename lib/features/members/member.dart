class Member {
  final String id;
  final String name;
  final String reason;
  final String goal;
  final String precautions;
  final String report;
  final String observation;
  final String memo;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Member({
    required this.id,
    required this.name,
    this.reason = '',
    this.goal = '',
    this.precautions = '',
    this.report = '',
    this.observation = '',
    this.memo = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'reason': reason,
    'goal': goal,
    'precautions': precautions,
    'report': report,
    'observation': observation,
    'memo': memo,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
  factory Member.fromMap(Map<String, Object?> m) => Member(
    id: m['id'] as String,
    name: m['name'] as String,
    reason: m['reason'] as String,
    goal: m['goal'] as String,
    precautions: m['precautions'] as String,
    report: m['report'] as String,
    observation: m['observation'] as String,
    memo: m['memo'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );
}
