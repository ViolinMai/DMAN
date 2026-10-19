from urllib.parse import unquote, urlparse


def format_bytes(num_bytes: int) -> str:
    """
    Dynamically scales byte counts to standard B, KB, MB, GB, TB.
    Never outputs oversized numbers like 2000000 KB.
    """
    if num_bytes is None or num_bytes <= 0:
        return "0 B"

    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    size = float(num_bytes)
    unit_idx = 0

    while size >= 1024.0 and unit_idx < len(units) - 1:
        size /= 1024.0
        unit_idx += 1

    if unit_idx == 0:
        return f"{int(size)} B"
    if size >= 100.0:
        return f"{size:.1f} {units[unit_idx]}"
    return f"{size:.2f} {units[unit_idx]}"


def format_speed(bytes_per_sec: int) -> str:
    """
    Formats transfer speed using standard B/s, KB/s, MB/s, GB/s (never mbps).
    """
    if bytes_per_sec is None or bytes_per_sec <= 0:
        return "0 B/s"
    return f"{format_bytes(bytes_per_sec)}/s"


def format_eta(total_bytes: int, completed_bytes: int, speed_bps: int) -> str:
    if speed_bps <= 0 or total_bytes <= 0 or completed_bytes >= total_bytes:
        return "~"
    remaining_seconds = int((total_bytes - completed_bytes) / speed_bps)
    if remaining_seconds < 60:
        return f"{remaining_seconds}s"
    minutes, seconds = divmod(remaining_seconds, 60)
    if minutes < 60:
        return f"{minutes}m {seconds:02d}s"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h {minutes:02d}m"
    days, hours = divmod(hours, 24)
    return f"{days}d {hours}h"


def is_metadata_only_task(item: dict) -> bool:
    """
    Detects whether an aria2 item is a temporary BitTorrent [METADATA] fetch task.
    """
    files = item.get("files", [])
    if files:
        path = files[0].get("path", "")
        if path.startswith("[METADATA]"):
            return True
    if item.get("followedBy"):
        return True
    return False


def resolve_package_name(save_dir: str) -> str:
    """
    Derives the parent package group name from the target folder name,
    falling back to 'Various Files' if root or empty.
    """
    if not save_dir:
        return "Various Files"
    normalized = save_dir.replace("\\", "/").rstrip("/")
    if not normalized:
        return "Various Files"
    parts = [p for p in normalized.split("/") if p and not p.endswith(":")]
    if not parts:
        return "Various Files"
    folder = parts[-1].strip()
    return folder if folder else "Various Files"


def resolve_primary_file_path(item: dict) -> str:
    files = item.get("files", [])
    if files:
        p = files[0].get("path", "")
        if p and not p.startswith("[METADATA]"):
            return p
    return ""


def resolve_source_uri(item: dict) -> str:
    files = item.get("files", [])
    if files:
        uris = files[0].get("uris", [])
        if uris and uris[0].get("uri"):
            return uris[0]["uri"]
    info_hash = item.get("infoHash", "")
    if info_hash:
        return f"magnet:?xt=urn:btih:{info_hash}"
    return ""


def resolve_display_name(item: dict) -> str:
    bt_info = item.get("bittorrent", {}).get("info", {})
    if bt_info.get("name"):
        return bt_info["name"]

    files = item.get("files", [])
    if files:
        first_file = files[0]
        file_path = first_file.get("path", "")
        if file_path:
            if file_path.startswith("[METADATA]"):
                clean_meta = file_path.replace("[METADATA]", "").strip()
                return f"Fetching Metadata: {clean_meta}" if clean_meta else "Fetching Magnet Metadata..."
            normalized = file_path.replace("\\", "/")
            basename = normalized.split("/")[-1].strip()
            if basename:
                return basename

        uris = first_file.get("uris", [])
        if uris:
            raw_uri = uris[0].get("uri", "")
            if raw_uri:
                parsed = urlparse(raw_uri)
                url_name = unquote(parsed.path.split("/")[-1]).strip()
                if url_name:
                    return url_name
                return raw_uri

    if "bittorrent" in item:
        return "Fetching Magnet Metadata..."

    return f"Task #{item.get('gid', 'unknown')}"
