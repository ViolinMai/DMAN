import re
from typing import Dict, List

# Matches http://, https://, ftp://, or magnet:?xt=... even when multiple links are pasted on the same line
_URL_MAGNET_REGEX = re.compile(
    r"(?:https?://|ftp://|magnet:\?xt=urn:[a-zA-Z0-9]+:)[^\s\"'<>\]\)]+",
    re.IGNORECASE,
)

# Standalone 40-char SHA1 hex torrent infohash
_INFOHASH_HEX_REGEX = re.compile(r"\b[a-fA-F0-9]{40}\b")

# Local .torrent file paths
_LOCAL_TORRENT_REGEX = re.compile(r"(?:[a-zA-Z]:[\\/]|/)[^\n\r\"'<>]+\.torrent", re.IGNORECASE)


def extract_smart_links(raw_text: str) -> List[str]:
    """
    Intelligently extracts and deduplicates multiple download links from arbitrary text.
    Handles:
      - Newline, space, comma, or tab-separated URLs
      - Multiple URLs pasted side-by-side on the same line
      - Concatenated 'http...http...' strings
      - Magnet URIs and standalone 40-char torrent infohashes
    """
    if not raw_text or not raw_text.strip():
        return []

    # Separate accidentally concatenated protocols like "https://a.com/1.ziphttps://b.com/2.zip"
    normalized = re.sub(
        r"(?<!^)(?<!\s)(https?://|ftp://|magnet:\?xt=)",
        r" \1",
        raw_text,
        flags=re.IGNORECASE,
    )

    results: List[str] = []
    seen = set()

    for match in _URL_MAGNET_REGEX.finditer(normalized):
        candidate = match.group(0).rstrip(".,;)")
        if candidate and candidate not in seen:
            seen.add(candidate)
            results.append(candidate)

    for match in _LOCAL_TORRENT_REGEX.finditer(raw_text):
        tpath = match.group(0).strip()
        if tpath and tpath not in seen:
            seen.add(tpath)
            results.append(tpath)

    # Check remaining tokens for raw 40-char BitTorrent infohashes
    stripped_text = _URL_MAGNET_REGEX.sub(" ", normalized)
    for match in _INFOHASH_HEX_REGEX.finditer(stripped_text):
        ihash = match.group(0).lower()
        magnet_uri = f"magnet:?xt=urn:btih:{ihash}"
        if magnet_uri not in seen and ihash not in seen:
            seen.add(magnet_uri)
            seen.add(ihash)
            results.append(magnet_uri)

    return results


def classify_links(links: List[str]) -> Dict[str, List[str]]:
    magnets: List[str] = []
    torrents: List[str] = []
    direct_urls: List[str] = []
    for link in links:
        low = link.lower()
        if low.startswith("magnet:?"):
            magnets.append(link)
        elif low.endswith(".torrent"):
            torrents.append(link)
        else:
            direct_urls.append(link)
    return {"magnets": magnets, "torrents": torrents, "urls": direct_urls}
