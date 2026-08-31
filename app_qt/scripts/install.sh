#!/bin/sh
set -eu

REPO="${DBS_ANNOTATOR_INSTALL_REPO:-Brain-Modulation-Lab/DBSAnnotator}"
UA="DBSAnnotator-Unix-Install/1.0 (+https://github.com/${REPO})"
export REPO UA
DRY_RUN=0
VER_TAG="${DBS_ANNOTATOR_VERSION:-}"

while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run) DRY_RUN=1; shift ;;
  -h | --help)
    echo "install.sh [--dry-run] [vX.Y.Z]"; exit 0 ;;
  --) shift; break ;;
  -*)
    echo "Unknown: $1" >&2; exit 1 ;;
  *)
    if [ -n "$VER_TAG" ]; then
      echo "Only one version tag allowed" >&2; exit 1
    fi
    VER_TAG="$1"
    shift
    ;;
  esac
done
export VER_TAG

case "$(uname -s 2>/dev/null)" in
Linux) OS_KIND=linux ;;
Darwin) OS_KIND=darwin ;;
*)
  echo "Need Linux or macOS. For Windows, use the README PowerShell one-liner." >&2; exit 1 ;;
esac
export OS_KIND

if [ "$OS_KIND" = linux ] && [ "$(uname -m)" != "x86_64" ]; then
  echo "CI ships x86_64 Linux; this machine is $(uname -m). Install from a .deb/flatpak manually or build from source." >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fSL -H "User-Agent: ${UA}" -o "$2" "$1"
  else
    wget -qO "$2" --header "User-Agent: ${UA}" "$1"
  fi
}

resolve_asset() {
  VER_TAG="${VER_TAG:-}" python3 <<'PY'
import os, re, sys, urllib.request, urllib.parse

def pick(urls, os_kind):
  def m(pat):
    for n, u in urls.items():
      if re.search(pat, n, re.I):
        return u
    return None

  if os_kind == "darwin":
    u = m(r"DBSAnnotator-.+-macos-arm64-raw\.tar\.gz$")
    if u:
      return "tar", u
    u = m(r"DBSAnnotator-.+\.dmg$")
    if u:
      return "dmg", u
  else:
    u = m(r"dbs-annotator_.+_linux_x86_64-raw\.tar\.gz$")
    if u:
      return "tar", u
    u = m(r"dbs-annotator_.+\.deb$")
    if u:
      return "deb", u
  return None, None

def main():
  repo = os.environ["REPO"]
  os_kind = os.environ["OS_KIND"]
  ver = (os.environ.get("VER_TAG") or "").strip()
  base = f"https://api.github.com/repos/{repo}/releases"
  token = os.environ.get("GITHUB_TOKEN", "")
  ua = os.environ.get("UA", "DBSAnnotator-install")
  headers = {
    "User-Agent": ua,
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  }
  if token:
    headers["Authorization"] = f"Bearer {token}"
  if ver:
    path = f"{base}/tags/{urllib.parse.quote(ver)}"
    req = urllib.request.Request(path, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
      rel = __import__("json").load(r)
    names = {a["name"]: a["browser_download_url"] for a in rel.get("assets", []) if a.get("name") and a.get("browser_download_url")}
    k, u = pick(names, os_kind)
    if u:
      print(k)
      print(u)
      return
    print("No suitable asset in that release for this OS", file=sys.stderr)
    raise SystemExit(1)
  for page in (1, 2, 3):
    path = f"{base}?per_page=30&page={page}"
    req = urllib.request.Request(path, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
      batch = __import__("json").load(r)
    if not batch:
      break
    for rel in batch:
      if rel.get("draft"):
        continue
      names = {a["name"]: a["browser_download_url"] for a in rel.get("assets", []) if a.get("name") and a.get("browser_download_url")}
      k, u = pick(names, os_kind)
      if u:
        print(k)
        print(u)
        return
  print("No .tar.gz / .deb / .dmg found in recent releases", file=sys.stderr)
  raise SystemExit(1)
main()
PY
}

linux_pick_exe() {
  _p=$1
  for _n in dbs-annotator dbs_annotator DBSAnnotator; do
    for _d in "$_p/src" "$_p/bin" "$_p"; do
      _c="$_d/$_n"
      if [ -f "$_c" ] || [ -L "$_c" ]; then
        [ -x "$_c" ] || chmod u+x "$_c" 2>/dev/null || true
        if [ -x "$_c" ]; then
          echo "$_c"
          return 0
        fi
      fi
    done
  done
  _f=$(find "$_p" -type f \( -name dbs-annotator -o -name dbs_annotator -o -name DBSAnnotator \) 2>/dev/null | head -n 1) || true
  if [ -n "$_f" ]; then
    [ -x "$_f" ] || chmod u+x "$_f" 2>/dev/null || true
  fi
  if [ -n "$_f" ] && [ -x "$_f" ]; then
    echo "$_f"
  fi
  return 0
}

install_mac_tar() {
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  tar -xzf "$1" -C "$work"
  app=$(find "$work" -name "DBSAnnotator.app" -type d | head -n 1)
  if [ -z "$app" ]; then
    echo "DBSAnnotator.app not in archive" >&2; exit 1
  fi
  if [ -n "${INSTALL_APPS_DIR:-}" ]; then
    dest_for_app="${INSTALL_APPS_DIR}"
  elif [ -w /Applications ] 2>/dev/null; then
    dest_for_app="/Applications"
  else
    dest_for_app="${HOME}/Applications"
    mkdir -p "$dest_for_app"
  fi
  rm -rf "$dest_for_app/DBSAnnotator.app" 2>/dev/null || true
  cp -R "$app" "$dest_for_app/"
  echo "Installed: $dest_for_app/DBSAnnotator.app"
  if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "x86_64" ]; then
    xattr -dr com.apple.quarantine "$dest_for_app/DBSAnnotator.app" 2>/dev/null || true
  fi
}

install_mac_dmg() {
  mp=$(mktemp -d "${TMPDIR:-/tmp}/dbs-dmg-XXXXXX")
  hdiutil attach -nobrowse -mountpoint "$mp" "$1"
  a=$(find "$mp" -name "DBSAnnotator.app" -type d -maxdepth 5 | head -n 1)
  if [ -z "$a" ]; then
    hdiutil detach "$mp" 2>/dev/null || true
    echo "DBSAnnotator.app not in DMG" >&2; exit 1
  fi
  destd="${HOME}/Applications"
  if [ -w /Applications ] 2>/dev/null; then destd="/Applications"; fi
  if [ -n "${INSTALL_APPS_DIR:-}" ]; then destd="${INSTALL_APPS_DIR}"; fi
  mkdir -p "$destd"
  rm -rf "$destd/DBSAnnotator.app" 2>/dev/null || true
  cp -R "$a" "$destd/"
  hdiutil detach -quiet "$mp" 2>/dev/null || hdiutil detach "$mp" 2>/dev/null || true
  rmdir "$mp" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$destd/DBSAnnotator.app" 2>/dev/null || true
  echo "Installed: $destd/DBSAnnotator.app"
}

install_linux_tar() {
  prefix=${INSTALL_PREFIX:-"$HOME/.local/lib/dbs-annotator"}
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  tar -xzf "$1" -C "$work"
  if [ -d "$work/app" ]; then
    src="$work/app"
  else
    src=$(find "$work" -type d -name app | head -n 1)
  fi
  if [ -z "$src" ] || [ ! -d "$src" ]; then
    echo "Expected app/ tree in archive" >&2; exit 1
  fi
  rm -rf "$prefix" 2>/dev/null || true
  mkdir -p "$(dirname "$prefix")"
  mv "$src" "$prefix"
  bin_dir="${HOME}/.local/bin"
  mkdir -p "$bin_dir"
  exe=$(linux_pick_exe "$prefix")
  if [ -z "$exe" ] || [ ! -x "$exe" ]; then
    if [ -f "$prefix/dbs_annotator/__main__.py" ] && [ ! -d "$prefix/bin" ]; then
      echo "Could not find Briefcase launcher under $prefix (missing bin/ stub). Raw .tar.gz for this version is source-only; use the .deb from the same release, or a release built after the raw-tar workflow fix." >&2
    else
      echo "Could not find executable under $prefix" >&2
    fi
    exit 1
  fi
  ln -sf "$exe" "$bin_dir/dbs-annotator"
  echo "Installed tree: $prefix"
  echo "Symlink:        $bin_dir/dbs-annotator"
  if ! echo "${PATH}" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    echo "Add to PATH:  export PATH=\"\${HOME}/.local/bin:\${PATH}\"" >&2
  fi
}

install_linux_deb() {
  if [ "$(id -u)" = 0 ]; then
    dpkg -i "$1" || apt-get install -f -y
  else
    if ! command -v sudo >/dev/null 2>&1; then
      echo "Need root or sudo to install .deb" >&2; exit 1
    fi
    sudo dpkg -i "$1" || sudo apt-get install -f -y
  fi
  echo "Installed system package from .deb"
}

main() {
  if ! out=$(resolve_asset); then
    exit 1
  fi
  _kind=$(printf '%s' "$out" | head -n 1)
  _url=$(printf '%s' "$out" | tail -n 1)

  if [ "$DRY_RUN" = 1 ]; then
    echo "Would install: kind=$_kind"
    echo "  URL: $_url"
    exit 0
  fi
  tbase=$(mktemp "${TMPDIR:-/tmp}/dbs-annotator.XXXXXX")
  case "$_kind" in
  tar) tmp="${tbase}.tar.gz" ;;
  deb) tmp="${tbase}.deb" ;;
  dmg) tmp="${tbase}.dmg" ;;
  esac
  rm -f "$tbase" 2>/dev/null || true
  echo "Downloading..."
  download "$_url" "$tmp"
  case "$_kind" in
  tar)
    if [ "$OS_KIND" = darwin ]; then
      install_mac_tar "$tmp"
    else
      install_linux_tar "$tmp"
    fi
    ;;
  deb) install_linux_deb "$tmp" ;;
  dmg) install_mac_dmg "$tmp" ;;
  esac
  rm -f "$tmp"
}
main
