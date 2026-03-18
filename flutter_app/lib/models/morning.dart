class MorningNewsItem {
  final String title;
  final String? summary;
  final String? desc;
  final String link;
  final String source;
  final String? image;
  final String? pubDate;

  const MorningNewsItem({
    required this.title,
    this.summary,
    this.desc,
    required this.link,
    required this.source,
    this.image,
    this.pubDate,
  });

  factory MorningNewsItem.fromJson(Map<String, dynamic> json) {
    return MorningNewsItem(
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString(),
      desc: json['desc']?.toString(),
      link: json['link']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      image: json['image']?.toString(),
      pubDate: (json['pub_date'] ?? json['pubDate'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'desc': desc,
        'link': link,
        'source': source,
        'image': image,
        'pub_date': pubDate,
      };
}

class MorningBrief {
  final String? date;
  final String? generatedAt;
  final Map<String, List<MorningNewsItem>> categories;

  const MorningBrief({this.date, this.generatedAt, required this.categories});

  factory MorningBrief.fromJson(Map<String, dynamic> json) {
    final raw = (json['categories'] as Map?)?.cast<String, dynamic>() ?? {};
    return MorningBrief(
      date: json['date']?.toString(),
      generatedAt: (json['generated_at'] ?? json['generatedAt'])?.toString(),
      categories: raw.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>? ?? [])
              .map((e) => MorningNewsItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'generated_at': generatedAt,
        'categories': categories.map(
          (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
        ),
      };

  @override
  String toString() => 'MorningBrief(date: $date, categories: ${categories.length})';
}

class SubCategoryConfig {
  final String name;
  final bool enabled;

  const SubCategoryConfig({required this.name, required this.enabled});

  factory SubCategoryConfig.fromJson(Map<String, dynamic> json) {
    return SubCategoryConfig(
      name: json['name']?.toString() ?? '',
      enabled: json['enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'enabled': enabled,
      };
}

class CustomFeed {
  final String name;
  final String url;
  final String category;

  const CustomFeed({
    required this.name,
    required this.url,
    required this.category,
  });

  factory CustomFeed.fromJson(Map<String, dynamic> json) {
    return CustomFeed(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'category': category,
      };
}

class SubConfig {
  final List<SubCategoryConfig> categories;
  final List<String> keywords;
  final List<CustomFeed> customFeeds;
  final String feishuWebhook;

  const SubConfig({
    required this.categories,
    required this.keywords,
    required this.customFeeds,
    required this.feishuWebhook,
  });

  factory SubConfig.fromJson(Map<String, dynamic> json) {
    return SubConfig(
      categories: (json['categories'] as List<dynamic>? ?? [])
          .map((e) => SubCategoryConfig.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      keywords: (json['keywords'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      customFeeds: ((json['custom_feeds'] ?? json['customFeeds'])
              as List<dynamic>? ??
          [])
          .map((e) => CustomFeed.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      feishuWebhook:
          (json['feishu_webhook'] ?? json['feishuWebhook'])?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories.map((e) => e.toJson()).toList(),
        'keywords': keywords,
        'custom_feeds': customFeeds.map((e) => e.toJson()).toList(),
        'feishu_webhook': feishuWebhook,
      };
}
