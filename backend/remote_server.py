import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Dict, Optional

from core.config import AppConfig
from core.formatters import format_bytes
from core.system_integration import SystemIntegration


class RemoteAPIServer:
    """
    Lightweight, thread-safe HTTP JSON API server built into DMAN so the static
    GitHub Pages Web App (or mobile browser) can remotely inspect disk space,
    create folders, pre-resolve AllDebrid links, enqueue downloads, and monitor live progress.
    """

    def __init__(
        self,
        get_state_fn: Callable[[], Dict[str, Any]],
        probe_links_fn: Callable[[str, str], Dict[str, Any]],
        enqueue_fn: Callable[[str, str, str, bool], Dict[str, Any]],
        action_fn: Callable[[str, str], Dict[str, Any]],
        get_token_fn: Callable[[], str],
        port: int = AppConfig.REMOTE_HTTP_PORT,
    ) -> None:
        self._get_state = get_state_fn
        self._probe_links = probe_links_fn
        self._enqueue = enqueue_fn
        self._action = action_fn
        self._get_token = get_token_fn
        self._port = port
        self._httpd: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def start(self, port: Optional[int] = None) -> None:
        if port is not None:
            self._port = port
        self.stop()

        outer = self

        class _Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: Any) -> None:
                pass  # Keep console clean

            def _send_cors_headers(self) -> None:
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-DMAN-Token")
                self.send_header("Access-Control-Allow-Private-Network", "true")

            def _send_json(self, status_code: int, payload: Dict[str, Any]) -> None:
                raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                self.send_response(status_code)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def _check_auth(self) -> bool:
                expected = (outer._get_token() or "").strip()
                if not expected:
                    return True
                hdr_token = (
                    self.headers.get("X-DMAN-Token")
                    or self.headers.get("Authorization", "").replace("Bearer ", "")
                ).strip()
                if hdr_token == expected:
                    return True
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                if qs.get("token", [""])[0].strip() == expected:
                    return True
                self._send_json(401, {"status": "error", "message": "Invalid or missing Remote API Token"})
                return False

            def do_OPTIONS(self) -> None:
                self.send_response(204)
                self._send_cors_headers()
                self.end_headers()

            def do_GET(self) -> None:
                parsed = urllib.parse.urlparse(self.path)
                route = parsed.path.rstrip("/") or "/"

                if route in ("/", "/api/ping"):
                    self._send_json(
                        200,
                        {
                            "status": "ok",
                            "app": AppConfig.APP_NAME,
                            "version": AppConfig.APP_VERSION,
                        },
                    )
                    return

                if not self._check_auth():
                    return

                if route == "/api/status":
                    self._send_json(200, {"status": "ok", "data": outer._get_state()})
                    return

                if route == "/api/disk":
                    qs = urllib.parse.parse_qs(parsed.query)
                    req_path = qs.get("path", [""])[0]
                    free_b = SystemIntegration.get_disk_free_bytes(req_path)
                    target = Path(req_path.strip() or Path.home())
                    subdirs = []
                    try:
                        base_dir = target if target.exists() and target.is_dir() else target.parent
                        if base_dir.exists():
                            subdirs = sorted(
                                [p.name for p in base_dir.iterdir() if p.is_dir() and not p.name.startswith(".")][:40]
                            )
                    except Exception:
                        pass
                    self._send_json(
                        200,
                        {
                            "status": "ok",
                            "path": str(target),
                            "exists": target.exists(),
                            "freeBytes": free_b,
                            "freeStr": format_bytes(free_b),
                            "subdirs": subdirs,
                        },
                    )
                    return

                self._send_json(404, {"status": "error", "message": "Endpoint not found"})

            def do_POST(self) -> None:
                if not self._check_auth():
                    return

                parsed = urllib.parse.urlparse(self.path)
                route = parsed.path.rstrip("/")
                length = int(self.headers.get("Content-Length", "0") or 0)
                body_raw = self.rfile.read(length).decode("utf-8", errors="replace") if length > 0 else "{}"
                try:
                    body = json.loads(body_raw) if body_raw else {}
                except Exception:
                    body = {}

                if route == "/api/probe":
                    raw_links = str(body.get("links", ""))
                    save_dir = str(body.get("saveDir", ""))
                    res = outer._probe_links(raw_links, save_dir)
                    self._send_json(200, {"status": "ok", "data": res})
                    return

                if route == "/api/add":
                    raw_links = str(body.get("links", ""))
                    save_dir = str(body.get("saveDir", ""))
                    subfolder = str(body.get("subfolder", "")).strip()
                    use_ad = bool(body.get("useAlldebrid", True))
                    res = outer._enqueue(raw_links, save_dir, subfolder, use_ad)
                    self._send_json(200, res)
                    return

                if route == "/api/action":
                    action = str(body.get("action", ""))
                    gid = str(body.get("gid", ""))
                    res = outer._action(action, gid)
                    self._send_json(200, res)
                    return

                if route == "/api/fs/list":
                    sub = str(body.get("subpath", "")).strip().strip("/\\")
                    base = Path(outer._get_state().get("defaultSaveDir", Path.home()))
                    target = (base / sub).resolve()
                    if not str(target).startswith(str(base.resolve())):
                        self._send_json(403, {"status": "error", "message": "Access denied"})
                        return
                    items = []
                    if target.exists() and target.is_dir():
                        for p in sorted(target.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower())):
                            items.append({
                                "name": p.name,
                                "isDir": p.is_dir(),
                                "size": format_bytes(p.stat().st_size) if p.is_file() else "",
                                "sizeBytes": p.stat().st_size if p.is_file() else 0,
                                "modified": int(p.stat().st_mtime)
                            })
                    self._send_json(200, {"status": "ok", "currentPath": sub, "items": items})
                    return

                if route == "/api/fs/mkdir":
                    sub = str(body.get("subpath", "")).strip().strip("/\\")
                    name = str(body.get("name", "")).strip().replace("/", "").replace("\\", "")
                    if not name:
                        self._send_json(400, {"status": "error", "message": "Folder name required"})
                        return
                    base = Path(outer._get_state().get("defaultSaveDir", Path.home()))
                    target = (base / sub / name).resolve()
                    if not str(target).startswith(str(base.resolve())):
                        self._send_json(403, {"status": "error", "message": "Access denied"})
                        return
                    target.mkdir(parents=True, exist_ok=True)
                    self._send_json(200, {"status": "ok"})
                    return

                if route == "/api/fs/rename":
                    sub = str(body.get("subpath", "")).strip().strip("/\\")
                    old_name = str(body.get("oldName", "")).strip().replace("/", "").replace("\\", "")
                    new_name = str(body.get("newName", "")).strip().replace("/", "").replace("\\", "")
                    if not old_name or not new_name:
                        self._send_json(400, {"status": "error", "message": "Invalid names"})
                        return
                    base = Path(outer._get_state().get("defaultSaveDir", Path.home()))
                    src = (base / sub / old_name).resolve()
                    dst = (base / sub / new_name).resolve()
                    if not str(src).startswith(str(base.resolve())) or not str(dst).startswith(str(base.resolve())):
                        self._send_json(403, {"status": "error", "message": "Access denied"})
                        return
                    if src.exists() and not dst.exists():
                        src.rename(dst)
                        self._send_json(200, {"status": "ok"})
                    else:
                        self._send_json(400, {"status": "error", "message": "Rename failed or target exists"})
                    return

                if route == "/api/fs/delete":
                    sub = str(body.get("subpath", "")).strip().strip("/\\")
                    name = str(body.get("name", "")).strip().replace("/", "").replace("\\", "")
                    base = Path(outer._get_state().get("defaultSaveDir", Path.home()))
                    target = (base / sub / name).resolve()
                    if not str(target).startswith(str(base.resolve())):
                        self._send_json(403, {"status": "error", "message": "Access denied"})
                        return
                    if target.is_dir():
                        self._send_json(400, {"status": "error", "message": "Folder deletion is prohibited"})
                        return
                    if target.is_file():
                        try:
                            target.unlink()
                            self._send_json(200, {"status": "ok"})
                        except Exception as e:
                            self._send_json(500, {"status": "error", "message": str(e)})
                        return
                    self._send_json(404, {"status": "error", "message": "File not found"})
                    return

                self._send_json(404, {"status": "error", "message": "Unknown POST endpoint"})

        try:
            self._httpd = ThreadingHTTPServer((AppConfig.REMOTE_HTTP_HOST, self._port), _Handler)
            self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
            self._thread.start()
        except Exception:
            self._httpd = None

    def stop(self) -> None:
        if self._httpd is not None:
            try:
                self._httpd.shutdown()
                self._httpd.server_close()
            except Exception:
                pass
            self._httpd = None
