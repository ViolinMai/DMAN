import os
from pathlib import Path
from typing import Any, Dict, List, Set

from PySide6.QtCore import (
    QAbstractListModel,
    QModelIndex,
    QSortFilterProxyModel,
    Qt,
    Slot,
)

from core.formatters import (
    format_bytes,
    format_eta,
    format_speed,
    is_metadata_only_task,
    resolve_display_name,
    resolve_package_name,
    resolve_primary_file_path,
    resolve_source_uri,
)


class DownloadModel(QAbstractListModel):
    """
    Hierarchical Package + Child File Model flattened for high-performance QML ListView.
    Groups files added together under a parent Package Row named after the target folder
    (or 'Various Files' as fallback). Also verifies disk file availability.
    """

    GidRole = Qt.UserRole + 1
    NameRole = Qt.UserRole + 2
    SizeStrRole = Qt.UserRole + 3
    CompletedStrRole = Qt.UserRole + 4
    StatusRole = Qt.UserRole + 5
    StatusDisplayRole = Qt.UserRole + 6
    SpeedStrRole = Qt.UserRole + 7
    EtaStrRole = Qt.UserRole + 8
    ProgressRole = Qt.UserRole + 9
    SaveDirRole = Qt.UserRole + 10
    ConnectionsRole = Qt.UserRole + 11
    ErrorMsgRole = Qt.UserRole + 12
    RawTotalBytesRole = Qt.UserRole + 13
    RawCompletedBytesRole = Qt.UserRole + 14
    IsPackageRole = Qt.UserRole + 15
    PackageKeyRole = Qt.UserRole + 16
    IsExpandedRole = Qt.UserRole + 17
    ChildCountRole = Qt.UserRole + 18
    SourceUriRole = Qt.UserRole + 19
    FileExistsRole = Qt.UserRole + 20

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._rows: List[Dict[str, Any]] = []
        self._collapsed_packages: Set[str] = set()
        self._source_uri_cache: Dict[str, str] = {}

    def roleNames(self) -> Dict[int, bytes]:
        return {
            self.GidRole: b"gid",
            self.NameRole: b"name",
            self.SizeStrRole: b"sizeStr",
            self.CompletedStrRole: b"completedStr",
            self.StatusRole: b"status",
            self.StatusDisplayRole: b"statusDisplay",
            self.SpeedStrRole: b"speedStr",
            self.EtaStrRole: b"etaStr",
            self.ProgressRole: b"progress",
            self.SaveDirRole: b"saveDir",
            self.ConnectionsRole: b"connections",
            self.ErrorMsgRole: b"errorMsg",
            self.RawTotalBytesRole: b"rawTotalBytes",
            self.RawCompletedBytesRole: b"rawCompletedBytes",
            self.IsPackageRole: b"isPackage",
            self.PackageKeyRole: b"packageKey",
            self.IsExpandedRole: b"isExpanded",
            self.ChildCountRole: b"childCount",
            self.SourceUriRole: b"sourceUri",
            self.FileExistsRole: b"fileExists",
        }

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self._rows)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole) -> Any:
        if not index.isValid() or not (0 <= index.row() < len(self._rows)):
            return None

        item = self._rows[index.row()]
        role_map = {
            self.GidRole: "gid",
            self.NameRole: "name",
            self.SizeStrRole: "sizeStr",
            self.CompletedStrRole: "completedStr",
            self.StatusRole: "status",
            self.StatusDisplayRole: "statusDisplay",
            self.SpeedStrRole: "speedStr",
            self.EtaStrRole: "etaStr",
            self.ProgressRole: "progress",
            self.SaveDirRole: "saveDir",
            self.ConnectionsRole: "connections",
            self.ErrorMsgRole: "errorMsg",
            self.RawTotalBytesRole: "rawTotalBytes",
            self.RawCompletedBytesRole: "rawCompletedBytes",
            self.IsPackageRole: "isPackage",
            self.PackageKeyRole: "packageKey",
            self.IsExpandedRole: "isExpanded",
            self.ChildCountRole: "childCount",
            self.SourceUriRole: "sourceUri",
            self.FileExistsRole: "fileExists",
        }
        key = role_map.get(role)
        return item.get(key) if key else None

    @Slot(str)
    def togglePackageExpanded(self, package_key: str) -> None:
        if package_key in self._collapsed_packages:
            self._collapsed_packages.remove(package_key)
        else:
            self._collapsed_packages.add(package_key)
        for row_idx, r in enumerate(self._rows):
            if r.get("packageKey") == package_key:
                if r.get("isPackage"):
                    r["isExpanded"] = package_key not in self._collapsed_packages
                idx = self.index(row_idx, 0)
                self.dataChanged.emit(idx, idx)

    def is_package_collapsed(self, package_key: str) -> bool:
        return package_key in self._collapsed_packages

    def register_source_uri(self, gid: str, uri: str) -> None:
        if gid and uri:
            self._source_uri_cache[gid] = uri

    def _transform_child(self, raw: Dict[str, Any]) -> Dict[str, Any]:
        gid = raw.get("gid", "")
        status = raw.get("status", "waiting")
        total_bytes = int(raw.get("totalLength", 0))
        completed_bytes = int(raw.get("completedLength", 0))
        speed_bps = int(raw.get("downloadSpeed", 0))
        connections = int(raw.get("connections", 0))
        save_dir = raw.get("dir", "")
        error_msg = raw.get("errorMessage", "")
        is_meta = is_metadata_only_task(raw)

        primary_path = resolve_primary_file_path(raw)
        file_exists = True
        if primary_path and status in ("complete", "paused"):
            file_exists = Path(primary_path).exists() or Path(primary_path + ".aria2").exists()

        source_uri = resolve_source_uri(raw) or self._source_uri_cache.get(gid, "")
        if source_uri and gid:
            self._source_uri_cache[gid] = source_uri

        if total_bytes > 0:
            progress = min(100.0, (completed_bytes / total_bytes) * 100.0)
        elif status == "complete":
            progress = 100.0
        else:
            progress = 0.0

        status_labels = {
            "active": "Fetching Metadata" if is_meta else "Downloading",
            "waiting": "Queued",
            "paused": "Paused (Resumable)" if file_exists else "Paused (Missing File)",
            "complete": "Finished" if file_exists else "Missing on Disk",
            "error": f"Error ({raw.get('errorCode', '?')})",
            "removed": "Removed",
        }

        pkg_key = save_dir.replace("\\", "/").rstrip("/") or "default"

        return {
            "gid": gid,
            "name": resolve_display_name(raw),
            "sizeStr": format_bytes(total_bytes) if total_bytes > 0 else ("Metadata" if is_meta else "Resolving..."),
            "completedStr": format_bytes(completed_bytes),
            "status": "missing" if (status == "complete" and not file_exists) else status,
            "statusDisplay": status_labels.get(status, status.capitalize()),
            "speedStr": format_speed(speed_bps) if status == "active" else "",
            "etaStr": format_eta(total_bytes, completed_bytes, speed_bps) if (status == "active" and not is_meta) else "~",
            "progress": round(progress, 1),
            "saveDir": save_dir,
            "connections": connections,
            "errorMsg": error_msg,
            "rawTotalBytes": total_bytes,
            "rawCompletedBytes": completed_bytes,
            "rawSpeedBps": speed_bps,
            "isPackage": False,
            "packageKey": pkg_key,
            "isExpanded": True,
            "childCount": 0,
            "sourceUri": source_uri,
            "fileExists": file_exists,
        }

    def _build_package_header(self, pkg_key: str, children: List[Dict[str, Any]]) -> Dict[str, Any]:
        save_dir = children[0]["saveDir"] if children else ""
        pkg_name = resolve_package_name(save_dir)
        total_bytes = sum(c["rawTotalBytes"] for c in children)
        completed_bytes = sum(c["rawCompletedBytes"] for c in children)
        speed_bps = sum(c["rawSpeedBps"] for c in children)
        connections = sum(c["connections"] for c in children)

        statuses = {c["status"] for c in children}
        if "active" in statuses:
            agg_status = "active"
            agg_display = f"Downloading ({sum(1 for c in children if c['status'] == 'active')}/{len(children)})"
        elif "error" in statuses or "missing" in statuses:
            agg_status = "error"
            agg_display = "Attention / Error"
        elif "paused" in statuses:
            agg_status = "paused"
            agg_display = "Paused"
        elif statuses == {"complete"}:
            agg_status = "complete"
            agg_display = "Finished"
        else:
            agg_status = "waiting"
            agg_display = "Queued"

        progress = min(100.0, (completed_bytes / total_bytes) * 100.0) if total_bytes > 0 else (
            100.0 if agg_status == "complete" else 0.0
        )

        return {
            "gid": f"PKG::{pkg_key}",
            "name": pkg_name,
            "sizeStr": f"[{len(children)}] {format_bytes(total_bytes)}",
            "completedStr": format_bytes(completed_bytes),
            "status": agg_status,
            "statusDisplay": agg_display,
            "speedStr": format_speed(speed_bps) if speed_bps > 0 else "",
            "etaStr": format_eta(total_bytes, completed_bytes, speed_bps) if speed_bps > 0 else "~",
            "progress": round(progress, 1),
            "saveDir": save_dir,
            "connections": connections,
            "errorMsg": "",
            "rawTotalBytes": total_bytes,
            "rawCompletedBytes": completed_bytes,
            "rawSpeedBps": speed_bps,
            "isPackage": True,
            "packageKey": pkg_key,
            "isExpanded": pkg_key not in self._collapsed_packages,
            "childCount": len(children),
            "sourceUri": "",
            "fileExists": True,
        }

    def sync_items(self, raw_items: List[Dict[str, Any]]) -> None:
        filtered_raw = [
            r for r in raw_items
            if not (is_metadata_only_task(r) and r.get("status") in ("complete", "removed"))
        ]
        children = [self._transform_child(r) for r in filtered_raw]

        packages_map: Dict[str, List[Dict[str, Any]]] = {}
        for child in children:
            pk = child["packageKey"]
            if pk not in packages_map:
                packages_map[pk] = []
            packages_map[pk].append(child)

        new_rows: List[Dict[str, Any]] = []
        for pk, pkg_children in packages_map.items():
            new_rows.append(self._build_package_header(pk, pkg_children))
            new_rows.extend(pkg_children)

        new_gids = [r["gid"] for r in new_rows]
        old_gids = [r["gid"] for r in self._rows]

        if new_gids != old_gids:
            self.beginResetModel()
            self._rows = new_rows
            self.endResetModel()
            return

        for idx, new_row in enumerate(new_rows):
            if self._rows[idx] != new_row:
                self._rows[idx] = new_row
                m_idx = self.index(idx, 0)
                self.dataChanged.emit(m_idx, m_idx)

    @Slot(str, result="QVariantMap")
    def get_by_gid(self, gid: str) -> Dict[str, Any]:
        for item in self._rows:
            if item["gid"] == gid:
                return item
        return {}

    def get_children_for_package(self, package_key: str) -> List[Dict[str, Any]]:
        return [r for r in self._rows if not r.get("isPackage") and r.get("packageKey") == package_key]

    def get_all_child_items(self) -> List[Dict[str, Any]]:
        return [r for r in self._rows if not r.get("isPackage")]


class DownloadFilterProxyModel(QSortFilterProxyModel):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._search_text = ""
        self._status_filter = "all"
        self.setDynamicSortFilter(True)

    @Slot(str)
    def setSearchText(self, text: str) -> None:
        cleaned = text.strip().lower()
        if self._search_text != cleaned:
            self._search_text = cleaned
            self.invalidateFilter()

    @Slot(str)
    def setStatusFilter(self, status: str) -> None:
        cleaned = status.strip().lower()
        if self._status_filter != cleaned:
            self._status_filter = cleaned
            self.invalidateFilter()

    @Slot(str)
    def togglePackage(self, package_key: str) -> None:
        src = self.sourceModel()
        if isinstance(src, DownloadModel):
            src.togglePackageExpanded(package_key)
            self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        model = self.sourceModel()
        if not isinstance(model, DownloadModel):
            return True

        idx = model.index(source_row, 0, source_parent)
        is_pkg = bool(model.data(idx, DownloadModel.IsPackageRole))
        pkg_key = model.data(idx, DownloadModel.PackageKeyRole) or ""
        name = (model.data(idx, DownloadModel.NameRole) or "").lower()
        status = (model.data(idx, DownloadModel.StatusRole) or "").lower()

        if is_pkg:
            children = model.get_children_for_package(pkg_key)
            if self._status_filter != "all":
                if not any(c["status"] == self._status_filter for c in children):
                    return False
            if self._search_text:
                if self._search_text not in name and not any(self._search_text in c["name"].lower() for c in children):
                    return False
            return True

        # Hide child rows when parent package is collapsed (unless actively searching)
        if not self._search_text and model.is_package_collapsed(pkg_key):
            return False

        if self._status_filter != "all" and status != self._status_filter:
            return False

        if self._search_text and self._search_text not in name:
            return False

        return True
