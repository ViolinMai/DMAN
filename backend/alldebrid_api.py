import gzip
import json
import random
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import logging
import zlib
from collections import deque
from typing import Any, Dict, List, Optional, Tuple

from PySide6.QtCore import QThread, Signal

from core.config import AppConfig

_ad_logger = logging.getLogger("DMAN.AllDebrid")


class AllDebridError(Exception):
    def __init__(self, code: str, message: str, token: str = "") -> None:
        super().__init__(f"[{code}] {message}")
        self.code = code
        self.message = message
        self.token = token


class _AntiBanRateLimiter:
    """
    Strict token-bucket & sliding-window rate limiter to protect the user's AllDebrid account and IP.
    Official API limit: 12 req/sec, 600 req/min.
    Our safe limit: Max 3 req/sec (350ms min interval) and Max 90 req/min, plus circuit breaker on auth/429 errors.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._last_call_ts = 0.0
        self._minute_window: deque[float] = deque()
        self._min_interval_sec = 0.35
        self._max_per_minute = 90
        self._cooldown_until = 0.0
        self.auth_circuit_broken = False
        self.last_auth_error = ""

    def reset_circuit(self) -> None:
        with self._lock:
            self.auth_circuit_broken = False
            self.last_auth_error = ""
            self._cooldown_until = 0.0

    def trip_auth_circuit(self, reason: str) -> None:
        with self._lock:
            self.auth_circuit_broken = True
            self.last_auth_error = reason

    def trigger_cooldown(self, seconds: float = 30.0) -> None:
        with self._lock:
            self._cooldown_until = max(self._cooldown_until, time.monotonic() + seconds)

    def acquire(self, requires_auth: bool = True) -> None:
        while True:
            sleep_needed = 0.0
            with self._lock:
                if requires_auth and self.auth_circuit_broken:
                    raise AllDebridError(
                        "CIRCUIT_OPEN",
                        f"AllDebrid requests paused to protect account: {self.last_auth_error}",
                    )

                now = time.monotonic()
                if now < self._cooldown_until:
                    sleep_needed = self._cooldown_until - now
                else:
                    # Clean timestamps older than 60s
                    while self._minute_window and (now - self._minute_window[0]) > 60.0:
                        self._minute_window.popleft()

                    if len(self._minute_window) >= self._max_per_minute:
                        sleep_needed = 60.0 - (now - self._minute_window[0]) + 0.1
                    else:
                        elapsed = now - self._last_call_ts
                        if elapsed < self._min_interval_sec:
                            sleep_needed = self._min_interval_sec - elapsed
                        else:
                            self._last_call_ts = now
                            self._minute_window.append(now)
                            return

            if sleep_needed > 0:
                time.sleep(min(sleep_needed, 2.0))


class AllDebridClient:
    """
    Strictly compliant AllDebrid API v4 / v4.1 client.
    - Uses Authorization: Bearer <apikey> header
    - Uses POST with form-encoded body for action endpoints
    - Enforces anti-ban rate limiting and circuit breaking
    """

    FATAL_AUTH_CODES = {
        "AUTH_MISSING_APIKEY",
        "AUTH_BAD_APIKEY",
        "AUTH_BLOCKED",
        "AUTH_USER_BANNED",
        "ACCOUNT_INVALID",
    }

    def __init__(self, api_key: str = "") -> None:
        self._api_key = api_key.strip()
        self._limiter = _AntiBanRateLimiter()
        self._cached_user: Optional[Dict[str, Any]] = None
        self._cached_hosts_ts = 0.0
        self._cached_domains: List[str] = []

    @property
    def api_key(self) -> str:
        return self._api_key

    def set_api_key(self, api_key: str) -> None:
        cleaned = api_key.strip()
        if cleaned != self._api_key:
            self._api_key = cleaned
            self._cached_user = None
            self._limiter.reset_circuit()

    def _encode_post_params(self, params: Dict[str, Any]) -> bytes:
        pairs: List[Tuple[str, str]] = []
        for key, value in params.items():
            if value is None:
                continue
            if isinstance(value, (list, tuple)):
                for item in value:
                    pairs.append((f"{key}[]", str(item)))
            else:
                pairs.append((key, str(value)))
        return urllib.parse.urlencode(pairs).encode("utf-8")

    def _request(
        self,
        method: str,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
        requires_auth: bool = True,
    ) -> Dict[str, Any]:
        if requires_auth and not self._api_key:
            raise AllDebridError("AUTH_MISSING_APIKEY", "AllDebrid API key is not configured.")

        self._limiter.acquire(requires_auth=requires_auth)

        merged_params: Dict[str, Any] = {"agent": AppConfig.ALLDEBRID_AGENT}
        if params:
            merged_params.update(params)
        if requires_auth and self._api_key:
            merged_params.setdefault("apikey", self._api_key)

        url = f"{AppConfig.ALLDEBRID_BASE_URL}{endpoint}"
        headers = {
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate",
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
        }
        if requires_auth and self._api_key:
            headers["Authorization"] = f"Bearer {self._api_key}"

        data_bytes: Optional[bytes] = None
        if method.upper() == "POST":
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
            data_bytes = self._encode_post_params(merged_params)
        else:
            query_str = urllib.parse.urlencode(merged_params, doseq=True)
            url = f"{url}?{query_str}"

        _ad_logger.debug("API Request: %s %s", method.upper(), endpoint)
        req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method.upper())
        ssl_ctx = ssl.create_default_context()

        def _decode_response_bytes(raw_bytes: bytes, content_encoding: str) -> str:
            enc = (content_encoding or "").lower()
            if "gzip" in enc or raw_bytes.startswith(b"\x1f\x8b"):
                try:
                    raw_bytes = gzip.decompress(raw_bytes)
                except Exception:
                    pass
            elif "deflate" in enc:
                try:
                    raw_bytes = zlib.decompress(raw_bytes)
                except Exception:
                    pass
            return raw_bytes.decode("utf-8-sig", errors="replace").strip()

        try:
            with urllib.request.urlopen(req, timeout=15.0, context=ssl_ctx) as resp:
                raw_body = _decode_response_bytes(resp.read(), resp.headers.get("Content-Encoding", ""))
        except urllib.error.HTTPError as http_err:
            if http_err.code in (429, 502, 503, 504):
                self._limiter.trigger_cooldown(30.0)
                raise AllDebridError(
                    str(http_err.code),
                    f"HTTP {http_err.code}: Rate limit or temporary server overload. Cooldown activated (30s).",
                )
            try:
                err_body = _decode_response_bytes(
                    http_err.read(),
                    http_err.headers.get("Content-Encoding", "") if http_err.headers else "",
                )
                parsed_err = json.loads(err_body)
                if isinstance(parsed_err, dict) and "error" in parsed_err:
                    err_obj = parsed_err["error"]
                    code = err_obj.get("code", str(http_err.code))
                    msg = err_obj.get("message", str(http_err))
                    if code in self.FATAL_AUTH_CODES:
                        self._limiter.trip_auth_circuit(f"{code}: {msg}")
                    raise AllDebridError(code, msg, err_obj.get("token", ""))
            except AllDebridError:
                raise
            except Exception:
                pass
            raise AllDebridError(str(http_err.code), f"HTTP Error {http_err.code}")
        except Exception as exc:
            raise AllDebridError("NETWORK_ERROR", str(exc))

        if not raw_body:
            raise AllDebridError("EMPTY_RESPONSE", "Empty response received from AllDebrid.")

        # Extract JSON object if wrapped by stray whitespace or proxy notices
        if not raw_body.startswith("{") and "{" in raw_body and "}" in raw_body:
            start_idx = raw_body.find("{")
            end_idx = raw_body.rfind("}")
            if 0 <= start_idx < end_idx:
                raw_body = raw_body[start_idx : end_idx + 1]

        try:
            payload = json.loads(raw_body)
        except Exception as json_exc:
            snippet = raw_body[:240].replace("\n", " ")
            _ad_logger.error("Invalid JSON on %s (%s): %s", endpoint, json_exc, snippet)
            raise AllDebridError(
                "JSON_INVALID",
                f"Invalid JSON from AllDebrid: {snippet}",
            )

        status = payload.get("status")
        if status == "error":
            err_obj = payload.get("error", {})
            code = err_obj.get("code", "GENERIC")
            msg = err_obj.get("message", "Unknown AllDebrid error")
            token = err_obj.get("token", "")
            _ad_logger.warning("AllDebrid API Error on %s -> [%s] %s", endpoint, code, msg)
            if code in self.FATAL_AUTH_CODES:
                self._limiter.trip_auth_circuit(f"{code}: {msg}")
            elif code == "MAINTENANCE":
                self._limiter.trigger_cooldown(60.0)
            raise AllDebridError(code, msg, token)

        if status != "success":
            raise AllDebridError("GENERIC", "Unexpected response status from AllDebrid")

        return payload.get("data", {})

    # --- Public & PIN Authentication Endpoints (/v4.1/pin/get & /v4/pin/check) ---
    def get_pin(self) -> Dict[str, Any]:
        return self._request("GET", "/v4.1/pin/get", requires_auth=False)

    def check_pin(self, pin: str, check_token: str) -> Dict[str, Any]:
        return self._request(
            "POST",
            "/v4/pin/check",
            params={"pin": pin, "check": check_token},
            requires_auth=False,
        )

    # --- User & Host Endpoints (/v4/user & /v4.1/user/hosts) ---
    def get_user_info(self, force_refresh: bool = False) -> Dict[str, Any]:
        if self._cached_user is not None and not force_refresh:
            return self._cached_user
        data = self._request("GET", "/v4/user", requires_auth=True)
        self._cached_user = data.get("user", {})
        return self._cached_user

    def get_supported_domains(self) -> List[str]:
        now = time.monotonic()
        if self._cached_domains and (now - self._cached_hosts_ts) < 3600:
            return self._cached_domains
        data = self._request("GET", "/v4/hosts/domains", requires_auth=False)
        hosts = data.get("hosts", [])
        streams = data.get("streams", [])
        redirectors = data.get("redirectors", [])
        self._cached_domains = list(set(hosts + streams + redirectors))
        self._cached_hosts_ts = now
        return self._cached_domains

    # --- Link Unlocking Endpoints (/v4/link/unlock, /v4/link/redirector, /v4/link/delayed) ---
    def unlock_link(self, link: str, password: str = "") -> Dict[str, Any]:
        params: Dict[str, Any] = {"link": link}
        if password:
            params["password"] = password
        return self._request("POST", "/v4/link/unlock", params=params, requires_auth=True)

    def extract_redirector(self, link: str) -> List[str]:
        data = self._request(
            "POST",
            "/v4/link/redirector",
            params={"link": link},
            requires_auth=True,
        )
        return data.get("links", [])

    def check_delayed(self, delayed_id: int) -> Dict[str, Any]:
        return self._request(
            "POST",
            "/v4/link/delayed",
            params={"id": delayed_id},
            requires_auth=True,
        )

    # --- Magnet Endpoints (/v4/magnet/upload, /v4.1/magnet/status, /v4/magnet/files) ---
    def upload_magnets(self, magnets: List[str]) -> List[Dict[str, Any]]:
        data = self._request(
            "POST",
            "/v4/magnet/upload",
            params={"magnets": magnets},
            requires_auth=True,
        )
        return data.get("magnets", [])

    def upload_torrent_file(self, file_path: str) -> List[Dict[str, Any]]:
        """
        Uploads a local .torrent file to POST /v4/magnet/upload/file using multipart/form-data.
        """
        if not self._api_key:
            raise AllDebridError("AUTH_MISSING_APIKEY", "AllDebrid API key is not configured.")

        self._limiter.acquire(requires_auth=True)

        boundary = f"----DMANBoundary{random.randint(100000, 999999)}"
        filename = file_path.replace("\\", "/").split("/")[-1]
        with open(file_path, "rb") as f:
            file_bytes = f.read()

        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="files[0]"; filename="{filename}"\r\n'
            f"Content-Type: application/x-bittorrent\r\n\r\n"
        ).encode("utf-8") + file_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")

        url = f"{AppConfig.ALLDEBRID_BASE_URL}/v4/magnet/upload/file?agent={urllib.parse.quote(AppConfig.ALLDEBRID_AGENT)}"
        headers = {
            "Accept": "application/json",
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        }
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=20.0) as resp:
            raw_bytes = resp.read()
            if raw_bytes.startswith(b"\x1f\x8b"):
                raw_bytes = gzip.decompress(raw_bytes)
            payload = json.loads(raw_bytes.decode("utf-8-sig", errors="replace"))
        if payload.get("status") != "success":
            err = payload.get("error", {})
            raise AllDebridError(err.get("code", "UPLOAD_ERROR"), err.get("message", "Torrent upload failed"))
        return payload.get("data", {}).get("files", [])

    def get_magnet_status_live(self, session_id: int, counter: int) -> Dict[str, Any]:
        return self._request(
            "POST",
            "/v4.1/magnet/status",
            params={"session": session_id, "counter": counter},
            requires_auth=True,
        )

    def get_magnet_files(self, magnet_ids: List[int]) -> List[Dict[str, Any]]:
        data = self._request(
            "POST",
            "/v4/magnet/files",
            params={"id": [int(x) for x in magnet_ids]},
            requires_auth=True,
        )
        magnets = data.get("magnets", [])
        if isinstance(magnets, dict):
            return list(magnets.values())
        return magnets if isinstance(magnets, list) else []

    def is_host_supported(self, url: str) -> bool:
        """
        Returns True ONLY if the URL is a Magnet, local .torrent, an AllDebrid link/CDN,
        or belongs to a domain explicitly listed in AllDebrid's supported hosts.
        """
        low = url.strip().lower()
        if not low:
            return False
        if low.startswith("magnet:?") or low.endswith(".torrent"):
            return True
        if self.is_direct_cdn_link(url):
            return True
        try:
            parsed = urllib.parse.urlparse(low)
            host = (parsed.hostname or "").lower()
            if not host:
                return False
            if "alldebrid." in host or host.endswith(".debrid.it") or host.endswith(".alldeb.ovh"):
                return True
            domains = self.get_supported_domains()
            for dom in domains:
                d = dom.lower().strip()
                if d and (host == d or host.endswith("." + d)):
                    return True
        except Exception:
            pass
        return False

    @staticmethod
    def is_direct_cdn_link(url: str) -> bool:
        """
        JDownloader-style check: returns True ONLY if the URL is an already-generated
        AllDebrid CDN stream/download link (e.g. *.debrid.it/dl/*, *.alldeb.ovh/dl/*).
        Note: alldebrid.com/f/... and redirect.alldebrid.com/... are NOT direct CDN links
        and MUST be unlocked via /v4/link/unlock.
        """
        try:
            parsed = urllib.parse.urlparse(url.strip())
            host = (parsed.hostname or "").lower()
            path = parsed.path or ""
            if host.endswith(".debrid.it") or host == "debrid.it" or host.endswith(".alldeb.ovh") or host == "alldeb.ovh":
                return True
            if ("alldebrid." in host or "debrid." in host) and path.startswith("/dl/"):
                return True
        except Exception:
            pass
        return False

    @staticmethod
    def extract_url_filename(url: str) -> str:
        try:
            path = urllib.parse.urlparse(url.strip()).path
            name = urllib.parse.unquote(path.split("/")[-1]).strip()
            return name
        except Exception:
            return ""

    def get_link_infos(self, links: List[str], password: str = "") -> List[Dict[str, Any]]:
        """Calls POST /v4/link/infos to batch-query filenames and sizes without generating download tokens."""
        params: Dict[str, Any] = {"link": links}
        if password:
            params["password"] = password
        data = self._request("POST", "/v4/link/infos", params=params, requires_auth=True)
        infos = data.get("infos", [])
        return infos if isinstance(infos, list) else []

    @staticmethod
    def probe_direct_head_size(url: str) -> int:
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "Mozilla/5.0"},
                method="HEAD",
            )
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                cl = resp.headers.get("Content-Length")
                return int(cl) if cl and cl.isdigit() else 0
        except Exception:
            return 0

    def probe_links_metadata(self, links: List[str]) -> Dict[str, Any]:
        """
        Probes link names and total sizes safely using /v4/link/infos ONLY for supported
        AllDebrid hosters, and HTTP HEAD for regular direct links or CDN links.
        """
        total_bytes = 0
        items: List[Dict[str, Any]] = []
        hoster_batch: List[str] = []

        for link in links[:40]:
            low = link.lower()
            if low.startswith("magnet:?"):
                items.append({"link": link, "filename": "Magnet Link", "size": 0, "type": "magnet"})
            elif low.endswith(".torrent") and not low.startswith(("http://", "https://", "ftp://")):
                fn = link.replace("\\", "/").split("/")[-1]
                items.append({"link": link, "filename": fn, "size": 0, "type": "torrent"})
            elif self.is_direct_cdn_link(link):
                fn = self.extract_url_filename(link) or "Direct Debrid File"
                sz = self.probe_direct_head_size(link)
                total_bytes += sz
                items.append({
                    "link": link,
                    "directLink": link,
                    "filename": fn,
                    "size": sz,
                    "host": "AllDebrid CDN",
                    "type": "direct_cdn",
                })
            elif self._api_key and self.is_host_supported(link):
                hoster_batch.append(link)
            else:
                fn = self.extract_url_filename(link) or link
                sz = self.probe_direct_head_size(link)
                total_bytes += sz
                items.append({"link": link, "filename": fn, "size": sz, "type": "direct"})

        if hoster_batch and self._api_key:
            try:
                infos = self.get_link_infos(hoster_batch)
                for info in infos:
                    if "error" in info:
                        orig = info.get("link", "")
                        fn = self.extract_url_filename(orig) or orig
                        sz = self.probe_direct_head_size(orig)
                        total_bytes += sz
                        items.append({"link": orig, "filename": fn, "size": sz, "type": "direct"})
                    else:
                        sz = int(info.get("size", 0) or 0)
                        fn = info.get("filename") or self.extract_url_filename(info.get("link", ""))
                        total_bytes += sz
                        items.append({
                            "link": info.get("link", ""),
                            "filename": fn,
                            "size": sz,
                            "host": info.get("host", "AllDebrid"),
                            "type": "alldebrid",
                        })
                return {"totalBytes": total_bytes, "items": items}
            except Exception as exc:
                _ad_logger.debug("Probe /v4/link/infos fallback: %s", exc)

        for link in hoster_batch:
            fn = self.extract_url_filename(link) or link
            sz = self.probe_direct_head_size(link)
            total_bytes += sz
            items.append({"link": link, "filename": fn, "size": sz, "type": "direct"})

        return {"totalBytes": total_bytes, "items": items}

    @staticmethod
    def flatten_magnet_files_tree(nodes: List[Dict[str, Any]], parent_path: str = "") -> List[Dict[str, Any]]:
        """
        Recursively traverses AllDebrid's /v4/magnet/files tree ('n', 's', 'l', 'e')
        and returns a flat list of {'filename': ..., 'size': ..., 'link': ..., 'subpath': ...}.
        """
        extracted: List[Dict[str, Any]] = []
        for node in nodes:
            name = node.get("n", "")
            if "e" in node and isinstance(node["e"], list):
                next_parent = f"{parent_path}/{name}".strip("/") if parent_path else name
                extracted.extend(AllDebridClient.flatten_magnet_files_tree(node["e"], next_parent))
            elif "l" in node:
                extracted.append(
                    {
                        "filename": name,
                        "size": int(node.get("s", 0)),
                        "link": node["l"],
                        "subpath": parent_path,
                    }
                )
        return extracted


class AllDebridPinAuthWorker(QThread):
    pinGenerated = Signal(str, str, int)  # pin, user_url, expires_in
    pinAuthenticated = Signal(str)        # apikey
    pinError = Signal(str)

    def __init__(self, client: AllDebridClient, parent=None) -> None:
        super().__init__(parent)
        self.client = client
        self._running = True

    def stop(self) -> None:
        self._running = False
        self.wait(2000)

    def run(self) -> None:
        try:
            pin_data = self.client.get_pin()
            pin_code = pin_data.get("pin", "")
            check_token = pin_data.get("check", "")
            user_url = pin_data.get("user_url", "https://alldebrid.com/pin/")
            expires_in = int(pin_data.get("expires_in", 600))

            if not pin_code or not check_token:
                self.pinError.emit("Failed to obtain PIN from AllDebrid.")
                return

            self.pinGenerated.emit(pin_code, user_url, expires_in)

            # Poll /v4/pin/check every 5 seconds as mandated by official AllDebrid documentation
            elapsed = 0
            while self._running and elapsed < expires_in:
                self.msleep(5000)
                elapsed += 5
                if not self._running:
                    return

                res = self.client.check_pin(pin_code, check_token)
                if res.get("activated") and res.get("apikey"):
                    self.pinAuthenticated.emit(res["apikey"])
                    return

            if self._running:
                self.pinError.emit("PIN code expired before activation.")
        except Exception as exc:
            self.pinError.emit(str(exc))


class AllDebridResolverWorker(QThread):
    """
    Background worker that safely resolves links & magnets through AllDebrid v4/v4.1
    without blocking the UI or violating rate limits, then emits ready direct downloads for aria2c.
    """

    directLinkReady = Signal(str, str, str)  # direct_url, save_dir, custom_filename
    fallbackToAria2 = Signal(str, str)       # original_url_or_magnet, save_dir
    statusMessage = Signal(str, bool)        # message, is_error

    def __init__(
        self,
        client: AllDebridClient,
        links: List[str],
        save_dir: str,
        use_cloud_magnets: bool = True,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self.client = client
        self.links = links
        self.save_dir = save_dir
        self.use_cloud_magnets = use_cloud_magnets
        self._running = True

    def stop(self) -> None:
        self._running = False
        self.wait(2000)

    def _wait_delayed_link(self, delayed_id: int) -> Optional[str]:
        # Poll every 5 seconds as required by AllDebrid documentation
        for _ in range(36):  # Up to 3 minutes
            if not self._running:
                return None
            self.msleep(5000)
            res = self.client.check_delayed(delayed_id)
            status_code = int(res.get("status", 3))
            if status_code == 2 and res.get("link"):
                return res["link"]
            if status_code == 3:
                return None
        return None

    def _unlock_and_emit(self, url: str, target_dir: str) -> None:
        if AllDebridClient.is_direct_cdn_link(url):
            fn = AllDebridClient.extract_url_filename(url)
            _ad_logger.info("Direct CDN link detected -> bypassing unlock: %s (file='%s')", url, fn)
            self.directLinkReady.emit(url, target_dir, fn)
            return

        if not self.client.is_host_supported(url):
            _ad_logger.info("Direct non-AllDebrid URL detected -> handing straight to aria2c: %s", url)
            self.fallbackToAria2.emit(url, target_dir)
            return

        try:
            _ad_logger.info("Unlocking link via AllDebrid /v4/link/unlock: %s", url)
            unlocked = self.client.unlock_link(url)
            delayed_id = unlocked.get("delayed")
            filename = unlocked.get("filename", "")

            if delayed_id:
                self.statusMessage.emit(f"AllDebrid: Generating delayed link ({filename or 'file'})...", False)
                direct_url = self._wait_delayed_link(int(delayed_id))
                if direct_url:
                    self.directLinkReady.emit(direct_url, target_dir, filename)
                else:
                    self.statusMessage.emit("AllDebrid: Delayed link generation failed.", True)
                return

            direct_url = unlocked.get("link", "")
            if direct_url:
                self.directLinkReady.emit(direct_url, target_dir, filename)
            else:
                self.fallbackToAria2.emit(url, target_dir)
        except AllDebridError as ad_err:
            if ad_err.code in ("LINK_HOST_NOT_SUPPORTED", "LINK_NOT_SUPPORTED"):
                # Try redirector endpoint if it's a link protector, else pass directly to aria2
                try:
                    extracted = self.client.extract_redirector(url)
                    if extracted:
                        for sub_link in extracted:
                            if not self._running:
                                return
                            self._unlock_and_emit(sub_link, target_dir)
                        return
                except Exception:
                    pass
                # Normal direct HTTP link not needing debrid -> hand straight to aria2
                self.fallbackToAria2.emit(url, target_dir)
            else:
                self.statusMessage.emit(f"AllDebrid: {ad_err.message}", True)

    def _process_magnets(self, magnets: List[str]) -> None:
        try:
            uploaded = self.client.upload_magnets(magnets)
        except AllDebridError as exc:
            self.statusMessage.emit(f"AllDebrid Magnet Error: {exc.message}. Falling back to aria2 P2P.", True)
            for m in magnets:
                self.fallbackToAria2.emit(m, self.save_dir)
            return

        ready_ids: List[int] = []
        pending_ids: Dict[int, str] = {}

        for item in uploaded:
            if "error" in item:
                err_msg = item["error"].get("message", "Invalid magnet")
                self.statusMessage.emit(f"AllDebrid Magnet: {err_msg}", True)
                continue
            mid = int(item.get("id", 0))
            mname = item.get("name", f"Magnet #{mid}")
            if not mid:
                continue
            if item.get("ready"):
                ready_ids.append(mid)
            else:
                pending_ids[mid] = mname

        if ready_ids:
            self.statusMessage.emit(f"AllDebrid: {len(ready_ids)} magnet(s) cached & ready immediately!", False)
            self._fetch_and_unlock_magnet_files(ready_ids)

        if not pending_ids:
            return

        self.statusMessage.emit(
            f"AllDebrid: Caching {len(pending_ids)} magnet(s) in cloud (Live Mode polling every 5s)...",
            False,
        )

        # Use /v4.1/magnet/status Live Mode (session + counter) every 5s
        session_id = random.randint(10000, 999999)
        counter = 0
        magnet_states: Dict[int, Dict[str, Any]] = {}

        # Poll while magnets are active on AllDebrid cloud
        for _ in range(360):  # Up to 30 mins max in current session
            if not self._running or not pending_ids:
                break
            self.msleep(5000)
            if not self._running:
                break

            try:
                live_data = self.client.get_magnet_status_live(session_id, counter)
                counter = int(live_data.get("counter", counter + 1))
                if live_data.get("fullsync"):
                    magnet_states.clear()

                for diff in live_data.get("magnets", []):
                    mid = int(diff.get("id", 0))
                    if mid not in magnet_states:
                        magnet_states[mid] = {}
                    magnet_states[mid].update(diff)

                newly_ready: List[int] = []
                for mid in list(pending_ids.keys()):
                    st = magnet_states.get(mid, {})
                    code = int(st.get("statusCode", 0))
                    if code == 4:  # Ready!
                        newly_ready.append(mid)
                        del pending_ids[mid]
                    elif code >= 5:  # Error status codes (5..15)
                        status_desc = st.get("status", f"Error code {code}")
                        self.statusMessage.emit(f"AllDebrid Magnet #{mid} failed: {status_desc}", True)
                        del pending_ids[mid]

                if newly_ready:
                    self._fetch_and_unlock_magnet_files(newly_ready)
            except AllDebridError as exc:
                self.statusMessage.emit(f"AllDebrid status check paused: {exc.message}", True)
                break

    def _fetch_and_unlock_magnet_files(self, magnet_ids: List[int]) -> None:
        try:
            magnets_files = self.client.get_magnet_files(magnet_ids)
            for m_obj in magnets_files:
                if not self._running:
                    return
                if "error" in m_obj:
                    continue
                files_tree = m_obj.get("files", [])
                flat_files = AllDebridClient.flatten_magnet_files_tree(files_tree)
                for f_entry in flat_files:
                    if not self._running:
                        return
                    subpath = f_entry.get("subpath", "")
                    target_dir = f"{self.save_dir.rstrip('/\\')}/{subpath}" if subpath else self.save_dir
                    self._unlock_and_emit(f_entry["link"], target_dir)
        except AllDebridError as exc:
            self.statusMessage.emit(f"AllDebrid files error: {exc.message}", True)

    def _process_torrent_files(self, torrent_paths: List[str]) -> None:
        ready_ids: List[int] = []
        for tpath in torrent_paths:
            if not self._running:
                return
            try:
                uploaded_files = self.client.upload_torrent_file(tpath)
                for f_obj in uploaded_files:
                    if "error" in f_obj:
                        self.statusMessage.emit(f"AllDebrid Torrent: {f_obj['error'].get('message')}", True)
                        continue
                    tid = int(f_obj.get("id", 0))
                    if tid and f_obj.get("ready"):
                        ready_ids.append(tid)
                    elif tid:
                        self.statusMessage.emit(f"AllDebrid: Torrent #{tid} queued in cloud...", False)
            except Exception:
                self.fallbackToAria2.emit(tpath, self.save_dir)

        if ready_ids:
            self._fetch_and_unlock_magnet_files(ready_ids)

    def run(self) -> None:
        magnets = [l for l in self.links if l.lower().startswith("magnet:?")]
        local_torrents = [
            l for l in self.links
            if l.lower().endswith(".torrent") and not l.lower().startswith(("http://", "https://", "ftp://"))
        ]
        direct_urls = [
            l for l in self.links
            if l not in magnets and l not in local_torrents
        ]

        for url in direct_urls:
            if not self._running:
                return
            self._unlock_and_emit(url, self.save_dir)

        if local_torrents:
            if self.use_cloud_magnets:
                self._process_torrent_files(local_torrents)
            else:
                for t in local_torrents:
                    self.fallbackToAria2.emit(t, self.save_dir)

        if magnets:
            if self.use_cloud_magnets:
                self._process_magnets(magnets)
            else:
                for m in magnets:
                    self.fallbackToAria2.emit(m, self.save_dir)
