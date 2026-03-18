enum ChannelFieldType { text, password, select, number }

ChannelFieldType channelFieldTypeFromJson(String? value) {
  switch (value) {
    case 'text':
      return ChannelFieldType.text;
    case 'password':
      return ChannelFieldType.password;
    case 'select':
      return ChannelFieldType.select;
    case 'number':
      return ChannelFieldType.number;
    default:
      return ChannelFieldType.text;
  }
}

String channelFieldTypeToJson(ChannelFieldType value) {
  switch (value) {
    case ChannelFieldType.text:
      return 'text';
    case ChannelFieldType.password:
      return 'password';
    case ChannelFieldType.select:
      return 'select';
    case ChannelFieldType.number:
      return 'number';
  }
}

class ChannelSchemaField {
  final String key;
  final String label;
  final ChannelFieldType type;
  final String? placeholder;
  final bool? isRequired;
  final String? defaultValue;
  final List<String>? options;

  const ChannelSchemaField({
    required this.key,
    required this.label,
    required this.type,
    this.placeholder,
    this.isRequired,
    this.defaultValue,
    this.options,
  });

  factory ChannelSchemaField.fromJson(Map<String, dynamic> json) {
    return ChannelSchemaField(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: channelFieldTypeFromJson(json['type']?.toString()),
      placeholder: json['placeholder']?.toString(),
      isRequired: json['required'] as bool?,
      defaultValue: (json['default'] ?? json['defaultValue'])?.toString(),
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': channelFieldTypeToJson(type),
        'placeholder': placeholder,
        'required': isRequired,
        'default': defaultValue,
        'options': options,
      };
}

class ChannelMeta {
  final String channelId;
  final String displayName;
  final String icon;
  final List<ChannelSchemaField> configSchema;
  final bool enabled;
  final Map<String, dynamic> params;
  final Map<String, dynamic>? secretState;

  const ChannelMeta({
    required this.channelId,
    required this.displayName,
    required this.icon,
    required this.configSchema,
    required this.enabled,
    required this.params,
    this.secretState,
  });

  factory ChannelMeta.fromJson(Map<String, dynamic> json) {
    return ChannelMeta(
      channelId: (json['channel_id'] ?? json['channelId'])?.toString() ?? '',
      displayName:
          (json['display_name'] ?? json['displayName'])?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      configSchema: ((json['config_schema'] ?? json['configSchema'])
              as List<dynamic>? ??
          [])
          .map((e) => ChannelSchemaField.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      enabled: json['enabled'] == true,
      params: (json['params'] as Map?)?.cast<String, dynamic>() ?? {},
      secretState: (json['secret_state'] ?? json['secretState']) is Map
          ? ((json['secret_state'] ?? json['secretState']) as Map)
              .cast<String, dynamic>()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'display_name': displayName,
        'icon': icon,
        'config_schema': configSchema.map((e) => e.toJson()).toList(),
        'enabled': enabled,
        'params': params,
        'secret_state': secretState,
      };
}

class NotifyChannelsResult {
  final bool ok;
  final List<ChannelMeta>? channels;
  final String? error;

  const NotifyChannelsResult({required this.ok, this.channels, this.error});

  factory NotifyChannelsResult.fromJson(Map<String, dynamic> json) {
    return NotifyChannelsResult(
      ok: json['ok'] == true,
      channels: (json['channels'] as List<dynamic>?)
          ?.map((e) => ChannelMeta.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'channels': channels?.map((e) => e.toJson()).toList(),
        'error': error,
      };
}
