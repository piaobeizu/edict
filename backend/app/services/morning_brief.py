"""天下要闻服务。"""

from __future__ import annotations

import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse
from xml.etree import ElementTree as ET

FEEDS = {
    "政治": [
        ("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml"),
        ("Reuters World", "https://feeds.reuters.com/reuters/worldNews"),
        ("AP Top News", "https://rsshub.app/apnews/topics/ap-top-news"),
    ],
    "军事": [
        ("Defense News", "https://www.defensenews.com/rss/"),
        ("BBC World", "https://feeds.bbci.co.uk/news/world/rss.xml"),
        ("Reuters", "https://feeds.reuters.com/reuters/worldNews"),
    ],
    "经济": [
        ("Reuters Business", "https://feeds.reuters.com/reuters/businessNews"),
        ("BBC Business", "https://feeds.bbci.co.uk/news/business/rss.xml"),
        ("CNBC", "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114"),
    ],
    "AI大模型": [
        ("Hacker News", "https://hnrss.org/newest?q=AI+LLM+model&points=50"),
        ("VentureBeat AI", "https://venturebeat.com/category/ai/feed/"),
        ("MIT Tech Review", "https://www.technologyreview.com/feed/"),
    ],
}

CATEGORY_KEYWORDS = {
    "军事": ["war", "military", "troops", "attack", "missile", "army", "navy", "weapons", "战", "军", "导弹", "士兵", "ukraine", "russia", "china sea", "nato"],
    "AI大模型": ["ai", "llm", "gpt", "claude", "gemini", "openai", "anthropic", "deepseek", "machine learning", "neural", "model", "大模型", "人工智能", "chatgpt"],
}

DEFAULT_SUB_CONFIG = {
    "categories": [
        {"name": "政治", "enabled": True},
        {"name": "军事", "enabled": True},
        {"name": "经济", "enabled": True},
        {"name": "AI大模型", "enabled": True},
    ],
    "keywords": [],
    "custom_feeds": [],
    "feishu_webhook": "",
}


def _data_dir() -> Path:
    for path in [Path("/app/data"), Path.cwd() / "data"]:
        if path.exists() and path.is_dir():
            return path
    path = Path("/app/data")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def _validate_url(url: str) -> bool:
    import ipaddress
    import socket
    try:
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.hostname:
            return False
        # 检查直接 IP
        try:
            ip = ipaddress.ip_address(parsed.hostname)
            if ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_link_local:
                return False
        except ValueError:
            pass
        # DNS 解析后检查（防 SSRF）
        try:
            for family, _, _, _, sockaddr in socket.getaddrinfo(parsed.hostname, None):
                ip = ipaddress.ip_address(sockaddr[0])
                if ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_link_local:
                    return False
        except (socket.gaierror, OSError):
            return False
        return True
    except Exception:
        return False


def _curl_rss(url: str, timeout: int = 10) -> str:
    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", str(timeout), "-L", "-A", "Mozilla/5.0 (compatible; MorningBrief/1.0)", url],
            capture_output=True,
            timeout=timeout + 2,
            text=True,
        )
        return result.stdout
    except Exception:
        return ""


def _safe_parse_xml(xml_text: str, max_size: int = 5 * 1024 * 1024):
    if len(xml_text) > max_size:
        return None
    cleaned = re.sub(r"<!DOCTYPE[^>]*>", "", xml_text, flags=re.IGNORECASE)
    cleaned = re.sub(r"<!ENTITY[^>]*>", "", cleaned, flags=re.IGNORECASE)
    try:
        return ET.fromstring(cleaned)
    except ET.ParseError:
        return None


def _parse_rss(xml_text: str) -> list[dict]:
    items = []
    root = _safe_parse_xml(xml_text)
    if root is None:
        return items
    ns = {"media": "http://search.yahoo.com/mrss/"}
    for item in root.findall(".//item")[:8]:
        def _get(tag: str) -> str:
            el = item.find(tag)
            return (el.text or "").strip() if el is not None else ""
        title = _get("title")
        desc = re.sub(r"<[^>]+>", "", _get("description"))[:200]
        link = _get("link")
        pub_date = _get("pubDate")
        image = ""
        enclosure = item.find("enclosure")
        if enclosure is not None and "image" in (enclosure.get("type") or ""):
            image = enclosure.get("url", "")
        media = item.find("media:thumbnail", ns) or item.find("media:content", ns)
        if media is not None:
            image = media.get("url", image)
        items.append({"title": title, "desc": desc, "link": link, "pub_date": pub_date, "image": image})
    return items


def _match_category(item: dict, category: str) -> bool:
    keywords = CATEGORY_KEYWORDS.get(category, [])
    if not keywords:
        return True
    text = (item.get("title", "") + " " + item.get("desc", "")).lower()
    return any(keyword in text for keyword in keywords)


def _fetch_category(category: str, feeds: list[tuple[str, str]], max_items: int = 5) -> list[dict]:
    seen_urls = set()
    results = []
    for source_name, url in feeds:
        if len(results) >= max_items:
            break
        xml = _curl_rss(url)
        if not xml:
            continue
        for item in _parse_rss(xml):
            if not item.get("title") or item.get("link") in seen_urls:
                continue
            if category in CATEGORY_KEYWORDS and not _match_category(item, category):
                continue
            seen_urls.add(item["link"])
            results.append({
                "title": item["title"],
                "summary": item["desc"] or item["title"],
                "link": item["link"],
                "pub_date": item["pub_date"],
                "image": item["image"],
                "source": source_name,
            })
            if len(results) >= max_items:
                break
    return results


def load_latest() -> dict:
    return _read_json(_data_dir() / "morning_brief.json", {})


def load_by_date(date_clean: str) -> dict:
    return _read_json(_data_dir() / f"morning_brief_{date_clean}.json", {})


def load_config() -> dict:
    return _read_json(_data_dir() / "morning_brief_config.json", DEFAULT_SUB_CONFIG)


def save_config(body: dict) -> dict:
    _write_json(_data_dir() / "morning_brief_config.json", body)
    return {"ok": True, "message": "订阅配置已保存"}


def refresh(force: bool = False) -> dict:
    data_dir = _data_dir()
    today = dt.date.today().strftime("%Y%m%d")
    lock_file = data_dir / f"morning_brief_{today}.lock"
    if lock_file.exists() and not force:
        age = dt.datetime.now().timestamp() - lock_file.stat().st_mtime
        if age < 3600:
            return {"ok": True, "message": "今日已采集，跳过"}
    config = load_config()
    enabled_categories = set()
    if config.get("categories"):
        for category in config["categories"]:
            if category.get("enabled", True):
                enabled_categories.add(category["name"])
    else:
        enabled_categories = set(FEEDS.keys())
    user_keywords = [str(keyword).lower() for keyword in config.get("keywords", [])]
    merged_feeds = {category: list(feeds) for category, feeds in FEEDS.items() if category in enabled_categories}
    for custom_feed in config.get("custom_feeds", []):
        category = custom_feed.get("category", "")
        url = custom_feed.get("url", "")
        if category in enabled_categories and url and _validate_url(url):
            merged_feeds.setdefault(category, []).append((custom_feed.get("name", "自定义"), url))
    payload = {"date": today, "generated_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "categories": {}}
    for category, feeds in merged_feeds.items():
        items = _fetch_category(category, feeds)
        if user_keywords:
            for item in items:
                text = (item.get("title", "") + " " + item.get("summary", "")).lower()
                item["_kw_hits"] = sum(1 for keyword in user_keywords if keyword in text)
            items.sort(key=lambda item: item.get("_kw_hits", 0), reverse=True)
            for item in items:
                item.pop("_kw_hits", None)
        payload["categories"][category] = items
    _write_json(data_dir / f"morning_brief_{today}.json", payload)
    _write_json(data_dir / "morning_brief.json", payload)
    lock_file.touch()
    total = sum(len(items) for items in payload["categories"].values())
    return {"ok": True, "message": f"采集完成，共 {total} 条", "payload": payload}
