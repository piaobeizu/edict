import 'package:flutter/material.dart';

class PipeStage {
  final String key;
  final String dept;
  final String icon;
  final String action;

  const PipeStage({
    required this.key,
    required this.dept,
    required this.icon,
    required this.action,
  });
}

const List<PipeStage> kPipe = [
  PipeStage(key: 'Inbox', dept: '皇上', icon: '👑', action: '下旨'),
  PipeStage(key: 'Taizi', dept: '太子', icon: '🤴', action: '分拣'),
  PipeStage(key: 'Zhongshu', dept: '中书省', icon: '📜', action: '起草'),
  PipeStage(key: 'Menxia', dept: '门下省', icon: '🔍', action: '审议'),
  PipeStage(key: 'YuLan', dept: '皇上', icon: '👑', action: '御览'),
  PipeStage(key: 'Assigned', dept: '尚书省', icon: '📮', action: '派发'),
  PipeStage(key: 'Doing', dept: '六部', icon: '⚙️', action: '执行'),
  PipeStage(key: 'Review', dept: '尚书省', icon: '🔎', action: '汇总'),
  PipeStage(key: 'Done', dept: '回奏', icon: '✅', action: '完成'),
];

const Map<String, int> kPipeStateIdx = {
  'Inbox': 0,
  'Pending': 0,
  'Taizi': 1,
  'Zhongshu': 2,
  'Menxia': 3,
  'YuLan': 4,
  'Assigned': 5,
  'Next': 5,
  'Doing': 6,
  'Blocked': 6,
  'Cancelled': 6,
  'Review': 7,
  'Done': 8,
};

const Map<String, Color> kDeptColor = {
  '皇上': Color(0xFFf5c842),
  '太子': Color(0xFFf5c842),
  '中书省': Color(0xFF6a9eff),
  '门下省': Color(0xFFa07aff),
  '尚书省': Color(0xFF2ecc8a),
  '礼部': Color(0xFFff9a4a),
  '户部': Color(0xFF2ecc8a),
  '兵部': Color(0xFFff5270),
  '刑部': Color(0xFFa07aff),
  '工部': Color(0xFF4ac1ff),
  '吏部': Color(0xFFf5c842),
  '钦天监': Color(0xFF5a6b92),
};

const Map<String, String> kStateLabel = {
  'Inbox': '待分拣',
  'Pending': '待分拣',
  'Taizi': '太子分拣中',
  'Zhongshu': '中书起草中',
  'Menxia': '门下审议中',
  'YuLan': '待御览',
  'Assigned': '已派发',
  'Doing': '执行中',
  'Review': '汇总审核中',
  'Done': '已完成',
  'Blocked': '已阻塞',
  'Cancelled': '已取消',
  'Next': '待派发',
};

class DeptInfo {
  final String id;
  final String label;
  final String emoji;
  final String role;
  final int rank;

  const DeptInfo({
    required this.id,
    required this.label,
    required this.emoji,
    required this.role,
    required this.rank,
  });
}

const List<DeptInfo> kDepts = [
  DeptInfo(id: 'taizi', label: '太子', emoji: '🤴', role: '太子', rank: 1),
  DeptInfo(id: 'zhongshu', label: '中书省', emoji: '📜', role: '中书令', rank: 2),
  DeptInfo(id: 'menxia', label: '门下省', emoji: '🔍', role: '侍中', rank: 3),
  DeptInfo(id: 'shangshu', label: '尚书省', emoji: '📮', role: '尚书令', rank: 4),
  DeptInfo(id: 'libu', label: '礼部', emoji: '📝', role: '礼部尚书', rank: 5),
  DeptInfo(id: 'hubu', label: '户部', emoji: '💰', role: '户部尚书', rank: 6),
  DeptInfo(id: 'bingbu', label: '兵部', emoji: '⚔️', role: '兵部尚书', rank: 7),
  DeptInfo(id: 'xingbu', label: '刑部', emoji: '⚖️', role: '刑部尚书', rank: 8),
  DeptInfo(id: 'gongbu', label: '工部', emoji: '🔧', role: '工部尚书', rank: 9),
  DeptInfo(id: 'libu_hr', label: '吏部', emoji: '👔', role: '吏部尚书', rank: 10),
  DeptInfo(id: 'zaochao', label: '钦天监', emoji: '🌟', role: '朝报官', rank: 11),
];

const Map<String, int> kStateOrder = {
  'YuLan': 0,
  'Doing': 1,
  'Review': 2,
  'Menxia': 3,
  'Zhongshu': 4,
  'Assigned': 5,
  'Next': 5,
  'Taizi': 6,
  'Inbox': 7,
  'Pending': 7,
  'Blocked': 8,
  'Cancelled': 9,
  'Done': 10,
};

class TemplateParam {
  final String key;
  final String label;
  final String type;
  final String? defaultValue;
  final bool required;
  final List<String> options;

  const TemplateParam({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.required = false,
    this.options = const [],
  });
}

class TemplateInfo {
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

  const TemplateInfo({
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
}

const List<TemplateInfo> kTemplates = [
  TemplateInfo(
    id: 'tpl-weekly-report',
    cat: '日常办公',
    icon: '📝',
    name: '周报生成',
    desc: '基于本周看板数据和各部产出，自动生成结构化周报',
    depts: ['户部', '礼部'],
    est: '~10分钟',
    cost: '¥0.5',
    params: [
      TemplateParam(
        key: 'date_range',
        label: '报告周期',
        type: 'text',
        defaultValue: '本周',
        required: true,
      ),
      TemplateParam(
        key: 'focus',
        label: '重点关注（逗号分隔）',
        type: 'text',
        defaultValue: '项目进展,下周计划',
      ),
      TemplateParam(
        key: 'format',
        label: '输出格式',
        type: 'select',
        options: ['Markdown', '飞书文档'],
        defaultValue: 'Markdown',
      ),
    ],
    command: '生成{date_range}的周报，重点覆盖{focus}，输出为{format}格式',
  ),
  TemplateInfo(
    id: 'tpl-code-review',
    cat: '工程开发',
    icon: '🔍',
    name: '代码审查',
    desc: '对指定代码仓库/文件进行质量审查，输出问题清单和改进建议',
    depts: ['兵部', '刑部'],
    est: '~20分钟',
    cost: '¥2',
    params: [
      TemplateParam(key: 'repo', label: '仓库/文件路径', type: 'text', required: true),
      TemplateParam(
        key: 'scope',
        label: '审查范围',
        type: 'select',
        options: ['全量', '增量(最近commit)', '指定文件'],
        defaultValue: '增量(最近commit)',
      ),
      TemplateParam(
        key: 'focus',
        label: '重点关注（可选）',
        type: 'text',
        defaultValue: '安全漏洞,错误处理,性能',
      ),
    ],
    command: '对 {repo} 进行代码审查，范围：{scope}，重点关注：{focus}',
  ),
  TemplateInfo(
    id: 'tpl-api-design',
    cat: '工程开发',
    icon: '⚡',
    name: 'API 设计与实现',
    desc: '从需求描述到 RESTful API 设计、实现、测试一条龙',
    depts: ['中书省', '兵部'],
    est: '~45分钟',
    cost: '¥3',
    params: [
      TemplateParam(key: 'requirement', label: '需求描述', type: 'textarea', required: true),
      TemplateParam(
        key: 'tech',
        label: '技术栈',
        type: 'select',
        options: ['Python/FastAPI', 'Node/Express', 'Go/Gin'],
        defaultValue: 'Python/FastAPI',
      ),
      TemplateParam(
        key: 'auth',
        label: '鉴权方式',
        type: 'select',
        options: ['JWT', 'API Key', '无'],
        defaultValue: 'JWT',
      ),
    ],
    command: '设计并实现一个 {tech} 的 RESTful API：{requirement}。鉴权方式：{auth}',
  ),
  TemplateInfo(
    id: 'tpl-competitor',
    cat: '数据分析',
    icon: '📊',
    name: '竞品分析',
    desc: '爬取竞品网站数据，分析对比，生成结构化报告',
    depts: ['兵部', '户部', '礼部'],
    est: '~60分钟',
    cost: '¥5',
    params: [
      TemplateParam(key: 'targets', label: '竞品名称/URL（每行一个）', type: 'textarea', required: true),
      TemplateParam(
        key: 'dimensions',
        label: '分析维度',
        type: 'text',
        defaultValue: '产品功能,定价策略,用户评价',
      ),
      TemplateParam(
        key: 'format',
        label: '输出格式',
        type: 'select',
        options: ['Markdown报告', '表格对比'],
        defaultValue: 'Markdown报告',
      ),
    ],
    command: '对以下竞品进行分析：\n{targets}\n\n分析维度：{dimensions}，输出格式：{format}',
  ),
  TemplateInfo(
    id: 'tpl-data-report',
    cat: '数据分析',
    icon: '📈',
    name: '数据报告',
    desc: '对给定数据集进行清洗、分析、可视化，输出分析报告',
    depts: ['户部', '礼部'],
    est: '~30分钟',
    cost: '¥2',
    params: [
      TemplateParam(key: 'data_source', label: '数据源描述/路径', type: 'text', required: true),
      TemplateParam(key: 'questions', label: '分析问题（每行一个）', type: 'textarea'),
      TemplateParam(
        key: 'viz',
        label: '是否需要可视化图表',
        type: 'select',
        options: ['是', '否'],
        defaultValue: '是',
      ),
    ],
    command: '对数据 {data_source} 进行分析。{questions}\n需要可视化：{viz}',
  ),
  TemplateInfo(
    id: 'tpl-blog',
    cat: '内容创作',
    icon: '✍️',
    name: '博客文章',
    desc: '给定主题和要求，生成高质量博客文章',
    depts: ['礼部'],
    est: '~15分钟',
    cost: '¥1',
    params: [
      TemplateParam(key: 'topic', label: '文章主题', type: 'text', required: true),
      TemplateParam(key: 'audience', label: '目标读者', type: 'text', defaultValue: '技术人员'),
      TemplateParam(
        key: 'length',
        label: '期望字数',
        type: 'select',
        options: ['~1000字', '~2000字', '~3000字'],
        defaultValue: '~2000字',
      ),
      TemplateParam(
        key: 'style',
        label: '风格',
        type: 'select',
        options: ['技术教程', '观点评论', '案例分析'],
        defaultValue: '技术教程',
      ),
    ],
    command: '写一篇关于「{topic}」的博客文章，面向{audience}，{length}，风格：{style}',
  ),
  TemplateInfo(
    id: 'tpl-deploy',
    cat: '工程开发',
    icon: '🚀',
    name: '部署方案',
    desc: '生成完整的部署检查单、Docker配置、CI/CD流程',
    depts: ['兵部', '工部'],
    est: '~25分钟',
    cost: '¥2',
    params: [
      TemplateParam(key: 'project', label: '项目名称/描述', type: 'text', required: true),
      TemplateParam(
        key: 'env',
        label: '部署环境',
        type: 'select',
        options: ['Docker', 'K8s', 'VPS', 'Serverless'],
        defaultValue: 'Docker',
      ),
      TemplateParam(
        key: 'ci',
        label: 'CI/CD 工具',
        type: 'select',
        options: ['GitHub Actions', 'GitLab CI', '无'],
        defaultValue: 'GitHub Actions',
      ),
    ],
    command: '为项目「{project}」生成{env}部署方案，CI/CD使用{ci}',
  ),
  TemplateInfo(
    id: 'tpl-email',
    cat: '内容创作',
    icon: '📧',
    name: '邮件/通知文案',
    desc: '根据场景和目的，生成专业邮件或通知文案',
    depts: ['礼部'],
    est: '~5分钟',
    cost: '¥0.3',
    params: [
      TemplateParam(
        key: 'scenario',
        label: '使用场景',
        type: 'select',
        options: ['商务邮件', '产品发布', '客户通知', '内部公告'],
        defaultValue: '商务邮件',
      ),
      TemplateParam(key: 'purpose', label: '目的/内容', type: 'textarea', required: true),
      TemplateParam(
        key: 'tone',
        label: '语调',
        type: 'select',
        options: ['正式', '友好', '简洁'],
        defaultValue: '正式',
      ),
    ],
    command: '撰写一封{scenario}，{tone}语调。内容：{purpose}',
  ),
  TemplateInfo(
    id: 'tpl-standup',
    cat: '日常办公',
    icon: '🗓️',
    name: '每日站会摘要',
    desc: '汇总各部今日进展和明日计划，生成站会摘要',
    depts: ['尚书省'],
    est: '~5分钟',
    cost: '¥0.3',
    params: [
      TemplateParam(
        key: 'range',
        label: '汇总范围',
        type: 'select',
        options: ['今天', '最近24小时', '昨天+今天'],
        defaultValue: '今天',
      ),
    ],
    command: '汇总{range}各部工作进展和待办，生成站会摘要',
  ),
];
