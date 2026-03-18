class SkillContentResult {
  final bool ok;
  final String? name;
  final String? agent;
  final String? content;
  final String? path;
  final String? error;

  const SkillContentResult({
    required this.ok,
    this.name,
    this.agent,
    this.content,
    this.path,
    this.error,
  });

  factory SkillContentResult.fromJson(Map<String, dynamic> json) {
    return SkillContentResult(
      ok: json['ok'] == true,
      name: json['name']?.toString(),
      agent: json['agent']?.toString(),
      content: json['content']?.toString(),
      path: json['path']?.toString(),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'name': name,
        'agent': agent,
        'content': content,
        'path': path,
        'error': error,
      };
}

class RemoteSkillItem {
  final String skillName;
  final String agentId;
  final String sourceUrl;
  final String description;
  final String localPath;
  final String addedAt;
  final String lastUpdated;
  final String status;

  const RemoteSkillItem({
    required this.skillName,
    required this.agentId,
    required this.sourceUrl,
    required this.description,
    required this.localPath,
    required this.addedAt,
    required this.lastUpdated,
    required this.status,
  });

  factory RemoteSkillItem.fromJson(Map<String, dynamic> json) {
    return RemoteSkillItem(
      skillName: json['skillName']?.toString() ?? '',
      agentId: json['agentId']?.toString() ?? '',
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      addedAt: json['addedAt']?.toString() ?? '',
      lastUpdated: json['lastUpdated']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'skillName': skillName,
        'agentId': agentId,
        'sourceUrl': sourceUrl,
        'description': description,
        'localPath': localPath,
        'addedAt': addedAt,
        'lastUpdated': lastUpdated,
        'status': status,
      };
}

class RemoteSkillsListResult {
  final bool ok;
  final List<RemoteSkillItem>? remoteSkills;
  final int? count;
  final String? listedAt;
  final String? error;

  const RemoteSkillsListResult({
    required this.ok,
    this.remoteSkills,
    this.count,
    this.listedAt,
    this.error,
  });

  factory RemoteSkillsListResult.fromJson(Map<String, dynamic> json) {
    return RemoteSkillsListResult(
      ok: json['ok'] == true,
      remoteSkills: (json['remoteSkills'] as List<dynamic>?)
          ?.map((e) => RemoteSkillItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      count: (json['count'] as num?)?.toInt(),
      listedAt: json['listedAt']?.toString(),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'remoteSkills': remoteSkills?.map((e) => e.toJson()).toList(),
        'count': count,
        'listedAt': listedAt,
        'error': error,
      };
}
