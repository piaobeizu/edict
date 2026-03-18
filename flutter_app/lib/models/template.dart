enum TemplateParamType { text, textarea, select }

TemplateParamType templateParamTypeFromJson(String? value) {
  switch (value) {
    case 'text':
      return TemplateParamType.text;
    case 'textarea':
      return TemplateParamType.textarea;
    case 'select':
      return TemplateParamType.select;
    default:
      return TemplateParamType.text;
  }
}

String templateParamTypeToJson(TemplateParamType value) {
  switch (value) {
    case TemplateParamType.text:
      return 'text';
    case TemplateParamType.textarea:
      return 'textarea';
    case TemplateParamType.select:
      return 'select';
  }
}

class TemplateParam {
  final String key;
  final String label;
  final TemplateParamType type;
  final String? defaultValue;
  final bool? isRequired;
  final List<String>? options;

  const TemplateParam({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.isRequired,
    this.options,
  });

  factory TemplateParam.fromJson(Map<String, dynamic> json) {
    return TemplateParam(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: templateParamTypeFromJson(json['type']?.toString()),
      defaultValue: (json['default'] ?? json['defaultValue'])?.toString(),
      isRequired: json['required'] as bool?,
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': templateParamTypeToJson(type),
        'default': defaultValue,
        'required': isRequired,
        'options': options,
      };
}

class Template {
  final String id;
  final String cat;
  final String icon;
  final String name;
  final String desc;
  final List<String> depts;
  final String est;
  final String cost;
  final List<TemplateParam> params;
  final String command;

  const Template({
    required this.id,
    required this.cat,
    required this.icon,
    required this.name,
    required this.desc,
    required this.depts,
    required this.est,
    required this.cost,
    required this.params,
    required this.command,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id']?.toString() ?? '',
      cat: json['cat']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
      depts: (json['depts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      est: json['est']?.toString() ?? '',
      cost: json['cost']?.toString() ?? '',
      params: (json['params'] as List<dynamic>? ?? [])
          .map((e) => TemplateParam.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      command: json['command']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cat': cat,
        'icon': icon,
        'name': name,
        'desc': desc,
        'depts': depts,
        'est': est,
        'cost': cost,
        'params': params.map((e) => e.toJson()).toList(),
        'command': command,
      };
}

class CreateTaskPayload {
  final String title;
  final String org;
  final String? targetDept;
  final String? priority;
  final String? templateId;
  final Map<String, String>? params;

  const CreateTaskPayload({
    required this.title,
    required this.org,
    this.targetDept,
    this.priority,
    this.templateId,
    this.params,
  });

  factory CreateTaskPayload.fromJson(Map<String, dynamic> json) {
    return CreateTaskPayload(
      title: json['title']?.toString() ?? '',
      org: json['org']?.toString() ?? '',
      targetDept: json['targetDept']?.toString(),
      priority: json['priority']?.toString(),
      templateId: json['templateId']?.toString(),
      params: (json['params'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'org': org,
        'targetDept': targetDept,
        'priority': priority,
        'templateId': templateId,
        'params': params,
      };
}
