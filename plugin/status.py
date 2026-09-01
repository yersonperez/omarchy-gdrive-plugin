import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path.home() / ".config" / "rclone" / "rclone.conf"
MOUNT_PATH = Path.home() / "GoogleDrive"
SERVICE = "rclone-gdrive.service"
SNAPSHOT_PATH = Path.home() / ".local" / "state" / "omarchy" / "gdrive-snapshot.json"
RECENT_AGE_DAYS = 180
MAX_DEPTH = 3


def command_output(command, timeout=10):
  try:
    completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
  except (OSError, subprocess.TimeoutExpired):
    return 1, ""
  return completed.returncode, (completed.stdout + completed.stderr).strip()


def rclone_remote_configured():
  if not CONFIG_PATH.exists():
    return False
  try:
    text = CONFIG_PATH.read_text(encoding="utf-8")
  except OSError:
    return False
  return re.search(r"^\s*\[gdrive\]\s*$", text, re.MULTILINE) is not None


def mount_active():
  exit_code, _ = command_output(["systemctl", "--user", "is-active", SERVICE])
  return exit_code == 0


def parse_about(output):
  used = 0
  quota = 0
  for line in output.splitlines():
    line = line.strip()
    if not line:
      continue
    m = re.match(r"^(Total|Used|Free|Trashed|Other):\s+([\d.,]+)\s*(\w+)", line)
    if not m:
      continue
    label, amount, unit = m.groups()
    value = float(amount.replace(",", ""))
    multiplier = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4, "PiB": 1024 ** 5}
    bytes_value = int(value * multiplier.get(unit, 1))
    if label == "Used":
      used = bytes_value
    elif label == "Total":
      quota = bytes_value
  return used, quota


def parse_lsl(output):
  rows = []
  for line in output.splitlines():
    m = re.match(r"^\s*(-?\d+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[\d.]*\s+(.*)$", line)
    if not m:
      continue
    size, ts, path = m.groups()
    try:
      from datetime import datetime
      modified = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S").timestamp()
    except ValueError:
      continue
    name = os.path.basename(path)
    folder = os.path.dirname(path)
    rows.append({
      "name": name,
      "path": str(MOUNT_PATH / path),
      "folder": "/" if folder in ("", ".") else "/" + folder,
      "modifiedTs": int(modified),
      "sizeBytes": int(size),
    })
  return rows


def load_snapshot():
  if not SNAPSHOT_PATH.exists():
    return set()
  try:
    with SNAPSHOT_PATH.open("r", encoding="utf-8") as handle:
      return set(json.load(handle))
  except (OSError, json.JSONDecodeError):
    return set()


def save_snapshot(paths):
  try:
    SNAPSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with SNAPSHOT_PATH.open("w", encoding="utf-8") as handle:
      json.dump(sorted(paths), handle, ensure_ascii=False)
  except OSError:
    pass


def main():
  limit = 25
  if len(sys.argv) > 1:
    try:
      limit = max(1, min(100, int(sys.argv[1])))
    except ValueError:
      limit = 25

  rclone_cli = shutil.which("rclone")
  installed = rclone_cli is not None
  authenticated = rclone_remote_configured()
  active = installed and authenticated and mount_active()

  used = 0
  quota = 0
  files = []
  if authenticated:
    _, about_output = command_output([rclone_cli, "about", "gdrive:"])
    used, quota = parse_about(about_output)
    _, lsl_output = command_output([
      rclone_cli, "lsl", "gdrive:",
      "--max-age", str(RECENT_AGE_DAYS) + "d",
      "--max-depth", str(MAX_DEPTH),
    ], timeout=40)
    rows = parse_lsl(lsl_output)
    rows.sort(key=lambda r: r["modifiedTs"], reverse=True)
    files = rows[:limit]
    current_paths = {r["path"] for r in rows}
    previous_paths = load_snapshot()
    added = []
    removed = []
    if previous_paths and current_paths:
      added = [r for r in rows if r["path"] in current_paths - previous_paths]
      removed_paths = previous_paths - current_paths
      removed = [{"name": os.path.basename(p), "path": p, "folder": os.path.dirname(p)} for p in sorted(removed_paths)]
    save_snapshot(current_paths)

  usage_percent = (used / quota * 100) if quota > 0 else 0

  status_text = "Mounted" if active else ("Configured" if authenticated else "Not connected")

  print(json.dumps({
    "ok": True,
    "installed": installed,
    "running": active,
    "authenticated": authenticated,
    "statusText": status_text,
    "accountPath": str(MOUNT_PATH),
    "plan": "Google Drive",
    "usedBytes": used,
    "quotaBytes": quota,
    "usagePercent": usage_percent,
    "quotaKnown": quota > 0,
    "files": files,
    "added": added,
    "removed": removed,
  }))


if __name__ == "__main__":
  main()