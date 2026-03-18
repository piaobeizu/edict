class SkillInfo {
  final String name;
  final String description;
  final String path;

  const SkillInfo({
    required this.name,
    required this.description,
    required this.path,
  });

  factory SkillInfo.fromJson(Map<String, dynamic> json) {
    return SkillInfo(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'path': path,
      };
}

class AgentInfo {
  final String id;
  final String label;
  final String emoji;
  final String role;
  final String model;
  final List<SkillInfo> skills;

  const AgentInfo({
    required this.id,
    required this.label,
    required this.emoji,
    required this.role,
    required this.model,
    required this.skills,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) {
    return AgentInfo(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      skills: (json['skills'] as List<dynamic>? ?? [])
          .map((e) => SkillInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'emoji': emoji,
        'role': role,
        'model': model,
        'skills': skills.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() => 'AgentInfo(id: $id, label: $label, model: $model)';
}

class KnownModel {
  final String id;
  final String label;
  final String provider;

  const KnownModel({
    required this.id,
    required this.label,
    required this.provider,
  });

  factory KnownModel.fromJson(Map<String, dynamic> json) {
    return KnownModel(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'provider': provider,
      };
}

class AgentConfig {
  final List<AgentInfo> agents;
  final List<KnownModel>? knownModels;

  const AgentConfig({required this.agents, this.knownModels});

  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      agents: (json['agents'] as List<dynamic>? ?? [])
          .map((e) => AgentInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      knownModels: (json['knownModels'] as List<dynamic>?)
          ?.map((e) => KnownModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'agents': agents.map((e) => e.toJson()).toList(),
        'knownModels': knownModels?.map((e) => e.toJson()).toList(),
      };
}

class ChangeLogEntry {
  final String at;
  final String agentId;
  final String oldModel;
  final String newModel;
  final bool? rolledBack;

  const ChangeLogEntry({
    required this.at,
    required this.agentId,
    required this.oldModel,
    required this.newModel,
    this.rolledBack,
  });

  factory ChangeLogEntry.fromJson(Map<String, dynamic> json) {
    return ChangeLogEntry(
      at: json['at']?.toString() ?? '',
      agentId: json['agentId']?.toString() ?? '',
      oldModel: json['oldModel']?.toString() ?? '',
      newModel: json['newModel']?.toString() ?? '',
      rolledBack: json['rolledBack'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at,
        'agentId': agentId,
        'oldModel': oldModel,
        'newModel': newModel,
        'rolledBack': rolledBack,
      };
}
