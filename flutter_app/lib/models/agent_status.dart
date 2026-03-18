enum AgentRuntimeStatus { running, idle, offline, unconfigured }

AgentRuntimeStatus agentRuntimeStatusFromJson(String? value) {
  switch (value) {
    case 'running':
      return AgentRuntimeStatus.running;
    case 'idle':
      return AgentRuntimeStatus.idle;
    case 'offline':
      return AgentRuntimeStatus.offline;
    case 'unconfigured':
      return AgentRuntimeStatus.unconfigured;
    default:
      return AgentRuntimeStatus.offline;
  }
}

String agentRuntimeStatusToJson(AgentRuntimeStatus value) {
  switch (value) {
    case AgentRuntimeStatus.running:
      return 'running';
    case AgentRuntimeStatus.idle:
      return 'idle';
    case AgentRuntimeStatus.offline:
      return 'offline';
    case AgentRuntimeStatus.unconfigured:
      return 'unconfigured';
  }
}

class AgentStatusInfo {
  final String id;
  final String label;
  final String emoji;
  final String role;
  final AgentRuntimeStatus status;
  final String statusLabel;
  final String? lastActive;

  const AgentStatusInfo({
    required this.id,
    required this.label,
    required this.emoji,
    required this.role,
    required this.status,
    required this.statusLabel,
    this.lastActive,
  });

  factory AgentStatusInfo.fromJson(Map<String, dynamic> json) {
    return AgentStatusInfo(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      status: agentRuntimeStatusFromJson(json['status']?.toString()),
      statusLabel: json['statusLabel']?.toString() ?? '',
      lastActive: json['lastActive']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'emoji': emoji,
        'role': role,
        'status': agentRuntimeStatusToJson(status),
        'statusLabel': statusLabel,
        'lastActive': lastActive,
      };
}

class GatewayStatus {
  final bool alive;
  final bool probe;
  final String status;

  const GatewayStatus({
    required this.alive,
    required this.probe,
    required this.status,
  });

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    return GatewayStatus(
      alive: json['alive'] == true,
      probe: json['probe'] == true,
      status: json['status']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'alive': alive,
        'probe': probe,
        'status': status,
      };
}

class AgentsStatusData {
  final bool ok;
  final GatewayStatus gateway;
  final List<AgentStatusInfo> agents;
  final String checkedAt;

  const AgentsStatusData({
    required this.ok,
    required this.gateway,
    required this.agents,
    required this.checkedAt,
  });

  factory AgentsStatusData.fromJson(Map<String, dynamic> json) {
    return AgentsStatusData(
      ok: json['ok'] == true,
      gateway: json['gateway'] is Map<String, dynamic>
          ? GatewayStatus.fromJson(json['gateway'] as Map<String, dynamic>)
          : const GatewayStatus(alive: false, probe: false, status: 'unknown'),
      agents: (json['agents'] as List<dynamic>? ?? [])
          .map((e) => AgentStatusInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      checkedAt: json['checkedAt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'gateway': gateway.toJson(),
        'agents': agents.map((e) => e.toJson()).toList(),
        'checkedAt': checkedAt,
      };

  @override
  String toString() =>
      'AgentsStatusData(ok: $ok, agents: ${agents.length}, checkedAt: $checkedAt)';
}
