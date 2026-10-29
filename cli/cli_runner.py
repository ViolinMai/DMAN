import argparse
import json
import logging
import sys
import time
from pathlib import Path
from typing import List

from backend.alldebrid_api import AllDebridClient, AllDebridError
from backend.aria2_rpc import Aria2RPCClient
from core.config import AppConfig
from core.formatters import format_bytes, format_eta, format_speed
from core.link_parser import extract_smart_links
from core.settings import SettingsManager
from core.system_integration import SystemIntegration


class DMANCli:
    def __init__(self, debug: bool = False, verbose: bool = False) -> None:
        self.logger = logging.getLogger("DMAN.CLI")
        self.settings = SettingsManager()
        self.rpc_client = Aria2RPCClient(self.settings)
        self.ad_client = AllDebridClient(self.settings.get("alldebrid_api_key", ""))
        self.debug = debug
        self.verbose = verbose

    def ensure_backend(self) -> bool:
        self.logger.debug("Pinging aria2c JSON-RPC daemon on %s...", self.rpc_client.rpc_url)
        if not self.rpc_client.ensure_daemon_running():
            self.logger.error("Could not reach or spawn aria2c daemon. Ensure 'aria2c' is installed in PATH.")
            return False
        self.logger.debug("aria2c daemon is active and responsive.")
        return True

    def cmd_status(self, as_json: bool = False) -> int:
        rpc_ok = self.rpc_client.ensure_daemon_running()
        version = "Offline"
        if rpc_ok:
            try:
                ver_res = self.rpc_client.call("aria2.getVersion")
                version = ver_res.get("version", "Unknown")
            except Exception as e:
                self.logger.debug("Version call failed: %s", e)

        default_dir = self.settings.get("default_download_dir", AppConfig.get_default_download_dir())
        free_bytes = SystemIntegration.get_disk_free_bytes(default_dir)

        ad_status = "Disabled"
        ad_user = None
        if self.settings.get("alldebrid_enabled", False) and self.ad_client.api_key:
            try:
                user = self.ad_client.get_user_info(force_refresh=True)
                ad_status = f"Connected ({user.get('username')}, {'Premium' if user.get('isPremium') else 'Free'})"
                ad_user = user
            except AllDebridError as exc:
                ad_status = f"Auth Error: {exc.code}"

        payload = {
            "aria2_rpc_online": rpc_ok,
            "aria2_version": version,
            "rpc_url": self.rpc_client.rpc_url,
            "default_download_dir": default_dir,
            "disk_free_bytes": free_bytes,
            "disk_free_human": format_bytes(free_bytes),
            "alldebrid_status": ad_status,
            "alldebrid_user": ad_user,
        }

        if as_json:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            return 0

        print(f"--- DMAN System Status ---")
        print(f"aria2c RPC:        {'ONLINE' if rpc_ok else 'OFFLINE'} (v{version}) [{self.rpc_client.rpc_url}]")
        print(f"Download Directory: {default_dir}")
        print(f"Free Disk Space:    {format_bytes(free_bytes)}")
        print(f"AllDebrid Status:   {ad_status}")
        return 0 if rpc_ok else 1

    def cmd_list(self, filter_type: str = "all", as_json: bool = False) -> int:
        if not self.ensure_backend():
            return 1

        keys = [
            "gid", "status", "totalLength", "completedLength",
            "downloadSpeed", "connections", "dir", "files",
            "errorMessage", "errorCode",
        ]

        active = self.rpc_client.call("aria2.tellActive", [keys]) or []
        waiting = self.rpc_client.call("aria2.tellWaiting", [0, 1000, keys]) or []
        stopped = self.rpc_client.call("aria2.tellStopped", [0, 1000, keys]) or []
        global_stat = self.rpc_client.call("aria2.getGlobalStat", []) or {}

        all_items = active + waiting + stopped
        if filter_type != "all":
            all_items = [i for i in all_items if i.get("status") == filter_type]

        if as_json:
            print(json.dumps({"global": global_stat, "tasks": all_items}, indent=2, ensure_ascii=False))
            return 0

        print(
            f"=== Tasks: {len(all_items)} | Global Speed: {format_speed(int(global_stat.get('downloadSpeed', 0)))} "
            f"| Active: {global_stat.get('numActive', 0)} ==="
        )
        print(f"{'GID':<16} {'STATUS':<10} {'SIZE':<12} {'LOADED':<12} {'SPEED':<12} {'PROGRESS':<8} {'NAME'}")
        print("-" * 90)

        for item in all_items:
            gid = item.get("gid", "")
            status = item.get("status", "")
            total_b = int(item.get("totalLength", 0))
            comp_b = int(item.get("completedLength", 0))
            speed = int(item.get("downloadSpeed", 0))
            prog = (comp_b / total_b * 100.0) if total_b > 0 else 0.0

            name = "Unknown"
            files = item.get("files", [])
            if files:
                p = files[0].get("path", "")
                if p:
                    name = Path(p).name
                elif files[0].get("uris"):
                    name = files[0]["uris"][0].get("uri", "").split("/")[-1]

            print(
                f"{gid:<16} {status:<10} {format_bytes(total_b):<12} {format_bytes(comp_b):<12} "
                f"{format_speed(speed):<12} {prog:>5.1f}%   {name}"
            )
        return 0

    def cmd_add(self, links: List[str], save_dir: str = "", use_ad: bool = False, custom_name: str = "") -> int:
        if not self.ensure_backend():
            return 1

        extracted = []
        for raw in links:
            extracted.extend(extract_smart_links(raw))

        if not extracted:
            self.logger.error("No valid HTTP/FTP/Magnet links provided or extracted.")
            return 1

        target_dir = save_dir.strip() or self.settings.get("default_download_dir", AppConfig.get_default_download_dir())
        Path(target_dir).mkdir(parents=True, exist_ok=True)

        self.logger.info("Processing %d item(s) for directory: %s", len(extracted), target_dir)

        success_count = 0
        for link in extracted:
            resolved_url = link
            target_filename = custom_name

            if use_ad:
                if not self.ad_client.api_key:
                    self.logger.warning("AllDebrid requested but API key is missing. Falling back to direct.")
                else:
                    self.logger.info("Resolving via AllDebrid: %s", link)
                    try:
                        if link.lower().startswith("magnet:?"):
                            self.logger.info("Uploading magnet to AllDebrid cloud...")
                            up = self.ad_client.upload_magnets([link])
                            if up and up[0].get("ready"):
                                mid = up[0]["id"]
                                files_data = self.ad_client.get_magnet_files([mid])
                                if files_data:
                                    flat = AllDebridClient.flatten_magnet_files_tree(files_data[0].get("files", []))
                                    for entry in flat:
                                        self.logger.info("Enqueuing resolved file: %s", entry["filename"])
                                        gid = self.rpc_client.add_uri([entry["link"]], target_dir, entry["filename"])
                                        print(f"[OK] Added {entry['filename']} -> GID: {gid}")
                                        success_count += 1
                                    continue
                        else:
                            unlocked = self.ad_client.unlock_link(link)
                            resolved_url = unlocked.get("link", link)
                            if not target_filename:
                                target_filename = unlocked.get("filename", "")
                    except AllDebridError as exc:
                        self.logger.warning("AllDebrid resolution failed (%s). Falling back directly to aria2.", exc.message)

            try:
                gid = self.rpc_client.add_uri([resolved_url], target_dir, target_filename)
                print(f"[OK] Added -> GID: {gid} ({resolved_url[:60]}...)")
                success_count += 1
            except Exception as e:
                self.logger.error("Failed to enqueue '%s': %s", link, e)

        return 0 if success_count > 0 else 1

    def cmd_action(self, action: str, gid: str) -> int:
        if not self.ensure_backend():
            return 1

        try:
            if action == "pause":
                self.rpc_client.pause(gid)
                print(f"[OK] Paused task {gid}")
            elif action == "resume":
                self.rpc_client.unpause(gid)
                print(f"[OK] Resumed task {gid}")
            elif action == "remove":
                self.rpc_client.remove(gid, "active")
                print(f"[OK] Removed task {gid}")
            elif action == "pause-all":
                self.rpc_client.pause_all()
                print("[OK] Paused all tasks")
            elif action == "resume-all":
                self.rpc_client.unpause_all()
                print("[OK] Resumed all tasks")
            return 0
        except Exception as e:
            self.logger.error("Action '%s' failed for GID %s: %s", action, gid, e)
            return 1

    def cmd_watch(self, interval: float = 1.0) -> int:
        if not self.ensure_backend():
            return 1

        self.logger.info("Watching active downloads (Press Ctrl+C to exit)...")
        try:
            while True:
                active = self.rpc_client.call(
                    "aria2.tellActive",
                    [["gid", "totalLength", "completedLength", "downloadSpeed", "files"]],
                ) or []
                stat = self.rpc_client.call("aria2.getGlobalStat", []) or {}
                speed_str = format_speed(int(stat.get("downloadSpeed", 0)))
                sys.stdout.write(f"\r\033[K[Active: {len(active)}] Speed: {speed_str:<12} ")

                if active:
                    first = active[0]
                    t_b = int(first.get("totalLength", 0))
                    c_b = int(first.get("completedLength", 0))
                    prog = (c_b / t_b * 100.0) if t_b > 0 else 0.0
                    sys.stdout.write(f"| GID {first['gid']} progress: {prog:5.1f}%")

                sys.stdout.flush()
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\nWatch stopped.")
            return 0


def build_parser() -> argparse.ArgumentParser:
    # Common flags inherited by all subcommands so --debug / --verbose work anywhere
    parent_parser = argparse.ArgumentParser(add_help=False)
    parent_parser.add_argument("--debug", action="store_true", help="Enable verbose debug tracing")
    parent_parser.add_argument("--verbose", action="store_true", help="Print extended detailed output")

    parser = argparse.ArgumentParser(
        prog="dman",
        description="DMAN CLI & Test Automation Controller",
        parents=[parent_parser],
    )

    subparsers = parser.add_subparsers(dest="command", help="CLI Subcommands")

    # status
    p_status = subparsers.add_parser("status", parents=[parent_parser], help="Print backend, daemon & account health status")
    p_status.add_argument("--json", action="store_true", help="Output machine-readable JSON")

    # list
    p_list = subparsers.add_parser("list", parents=[parent_parser], help="List active, waiting, and stopped downloads")
    p_list.add_argument(
        "--filter",
        choices=["all", "active", "waiting", "paused", "complete", "error"],
        default="all",
        help="Filter downloads by status",
    )
    p_list.add_argument("--json", action="store_true", help="Output machine-readable JSON")

    # add
    p_add = subparsers.add_parser("add", parents=[parent_parser], help="Add one or more download links / magnets")
    p_add.add_argument("links", nargs="+", help="Direct URLs, Magnet URIs, or .torrent files")
    p_add.add_argument("-d", "--dir", default="", help="Custom destination folder")
    p_add.add_argument("-o", "--out", default="", help="Custom output filename")
    p_add.add_argument("--alldebrid", action="store_true", help="Route links via AllDebrid unrestrictor")

    # control actions
    p_pause = subparsers.add_parser("pause", parents=[parent_parser], help="Pause task by GID")
    p_pause.add_argument("gid", help="Task GID")

    p_resume = subparsers.add_parser("resume", parents=[parent_parser], help="Resume task by GID")
    p_resume.add_argument("gid", help="Task GID")

    p_remove = subparsers.add_parser("remove", parents=[parent_parser], help="Remove task by GID")
    p_remove.add_argument("gid", help="Task GID")

    subparsers.add_parser("pause-all", parents=[parent_parser], help="Pause all ongoing tasks")
    subparsers.add_parser("resume-all", parents=[parent_parser], help="Resume all paused tasks")

    # watch
    p_watch = subparsers.add_parser("watch", parents=[parent_parser], help="Live stream download progress in terminal")
    p_watch.add_argument("--interval", type=float, default=1.0, help="Refresh interval in seconds")

    return parser


def run_cli(args: List[str]) -> int:
    parser = build_parser()
    parsed = parser.parse_args(args)

    from cli.logger import setup_cli_logging
    setup_cli_logging(debug=parsed.debug, verbose=parsed.verbose)

    cli = DMANCli(debug=parsed.debug, verbose=parsed.verbose)

    if parsed.command == "status":
        return cli.cmd_status(as_json=parsed.json)
    elif parsed.command == "list":
        return cli.cmd_list(filter_type=parsed.filter, as_json=parsed.json)
    elif parsed.command == "add":
        return cli.cmd_add(parsed.links, save_dir=parsed.dir, use_ad=parsed.alldebrid, custom_name=parsed.out)
    elif parsed.command in ("pause", "resume", "remove"):
        return cli.cmd_action(parsed.command, parsed.gid)
    elif parsed.command in ("pause-all", "resume-all"):
        return cli.cmd_action(parsed.command, "")
    elif parsed.command == "watch":
        return cli.cmd_watch(interval=parsed.interval)
    else:
        parser.print_help()
        return 0
