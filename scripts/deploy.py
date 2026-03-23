#!/usr/bin/env python3
"""
TrazaBox Deploy Script
Automates APK building and deployment to Supabase Storage
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    print("Error: The 'requests' package is required but not installed.")
    print("Please install it by running: pip install requests")
    sys.exit(1)

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent
PUBSPEC_FILE = PROJECT_ROOT / "pubspec.yaml"
APK_OUTPUT = PROJECT_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
BUCKET_NAME = "app-updates"
VERSION_FILE = "version.json"
APK_FILE = "trazabox.apk"


def load_env():
    """Load environment variables from .env file"""
    env_file = PROJECT_ROOT / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    os.environ[key.strip()] = value.strip()


def get_supabase_config():
    """Get Supabase credentials from env or config file"""
    load_env()

    # Try environment variables first
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_ANON_KEY")

    if not supabase_url or not supabase_key:
        # Try reading from supabase_config.dart
        config_file = PROJECT_ROOT / "lib" / "config" / "supabase_config.dart"
        if config_file.exists():
            content = config_file.read_text()
            url_match = re.search(r"supabaseUrl\s*=\s*['\"]([^'\"]+)['\"]", content)
            key_match = re.search(r"supabaseAnonKey\s*=\s*['\"]([^'\"]+)['\"]", content)
            if url_match:
                supabase_url = url_match.group(1)
            if key_match:
                supabase_key = key_match.group(1)

    if not supabase_url or not supabase_key:
        print("Error: Supabase credentials not found. Set SUPABASE_URL and either SUPABASE_SERVICE_KEY (recommended for uploads) or SUPABASE_ANON_KEY, or configure them in lib/config/supabase_config.dart.")
        print("Create a .env file or set the environment variables above.")
        sys.exit(1)

    return supabase_url, supabase_key


def parse_pubspec_version():
    """Parse version from pubspec.yaml"""
    content = PUBSPEC_FILE.read_text()
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)", content, re.MULTILINE)
    if match:
        return match.group(1), int(match.group(2))
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)", content, re.MULTILINE)
    if match:
        return match.group(1), 1
    print("Error: Could not parse version from pubspec.yaml")
    sys.exit(1)


def update_pubspec_version(version_name, version_code):
    """Update version in pubspec.yaml"""
    content = PUBSPEC_FILE.read_text()
    new_content = re.sub(
        r"^version:\s*\d+\.\d+\.\d+(\+\d+)?",
        f"version: {version_name}+{version_code}",
        content,
        flags=re.MULTILINE
    )
    PUBSPEC_FILE.write_text(new_content)
    print(f"Updated pubspec.yaml: {version_name}+{version_code}")


def bump_version(part="build"):
    """Bump version number"""
    version_name, version_code = parse_pubspec_version()
    major, minor, patch = map(int, version_name.split("."))

    if part == "major":
        major += 1
        minor = 0
        patch = 0
        version_code += 1
    elif part == "minor":
        minor += 1
        patch = 0
        version_code += 1
    elif part == "patch":
        patch += 1
        version_code += 1
    elif part == "build":
        version_code += 1
    else:
        print(f"Unknown version part: {part}")
        sys.exit(1)

    new_version_name = f"{major}.{minor}.{patch}"
    update_pubspec_version(new_version_name, version_code)
    return new_version_name, version_code


def get_flutter_cmd():
    """Get the flutter command (handles snap installation)"""
    # Try regular flutter first
    result = subprocess.run(["which", "flutter"], capture_output=True)
    if result.returncode == 0:
        return ["flutter"]

    # Try snap
    result = subprocess.run(["which", "snap"], capture_output=True)
    if result.returncode == 0:
        return ["snap", "run", "flutter"]

    # Fallback to common paths
    paths = [
        "/snap/bin/flutter",
        os.path.expanduser("~/flutter/bin/flutter"),
        "/opt/flutter/bin/flutter",
    ]
    for path in paths:
        if os.path.exists(path):
            return [path]

    return ["flutter"]  # Will fail with clear error if not found


def build_apk():
    """Build release APK"""
    print("Building APK...")
    flutter_cmd = get_flutter_cmd()
    result = subprocess.run(
        flutter_cmd + ["build", "apk", "--release"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"Build failed:\n{result.stderr}")
        sys.exit(1)

    if not APK_OUTPUT.exists():
        print(f"APK not found at {APK_OUTPUT}")
        sys.exit(1)

    file_size = APK_OUTPUT.stat().st_size
    print(f"APK built successfully: {APK_OUTPUT}")
    print(f"Size: {file_size / (1024*1024):.1f} MB")
    return file_size


def create_version_json(version_name, version_code, file_size, release_notes=None):
    """Create version.json content"""
    if release_notes is None:
        release_notes = f"Version {version_name}"

    return {
        "versionCode": version_code,
        "versionName": version_name,
        "releaseNotes": release_notes,
        "fileSize": file_size
    }


def upload_to_supabase(version_data, apk_path):
    """Upload APK and version.json to Supabase Storage"""
    supabase_url, supabase_key = get_supabase_config()

    headers = {
        "Authorization": f"Bearer {supabase_key}",
        "x-upsert": "true"
    }

    # Upload version.json
    print("Uploading version.json...")
    version_json = json.dumps(version_data, indent=2)
    version_url = f"{supabase_url}/storage/v1/object/{BUCKET_NAME}/{VERSION_FILE}"

    response = requests.post(
        version_url,
        headers={**headers, "Content-Type": "application/json"},
        data=version_json
    )

    if response.status_code not in (200, 201):
        print(f"Failed to upload version.json: {response.text}")
        sys.exit(1)

    print("version.json uploaded successfully")

    # Upload APK
    print("Uploading APK (this may take a while)...")
    apk_url = f"{supabase_url}/storage/v1/object/{BUCKET_NAME}/{APK_FILE}"

    with open(apk_path, "rb") as f:
        response = requests.post(
            apk_url,
            headers={**headers, "Content-Type": "application/vnd.android.package-archive"},
            data=f
        )

    if response.status_code not in (200, 201):
        print(f"Failed to upload APK: {response.text}")
        sys.exit(1)

    print("APK uploaded successfully")

    # Public URLs
    public_base = f"{supabase_url}/storage/v1/object/public/{BUCKET_NAME}"
    print(f"\nDeployment complete!")
    print(f"  APK: {public_base}/{APK_FILE}")
    print(f"  Version: {public_base}/{VERSION_FILE}")
    print(f"  Version: {version_data['versionName']} ({version_data['versionCode']})")


def get_current_version():
    """Print current version"""
    version_name, version_code = parse_pubspec_version()
    print(f"Current version: {version_name}+{version_code}")


def main():
    parser = argparse.ArgumentParser(description="TrazaBox Deploy Tool")
    parser.add_argument("command", choices=["version", "bump", "build", "upload", "deploy"],
                        help="Command to execute")
    parser.add_argument("--part", "-p", choices=["major", "minor", "patch", "build"],
                        default="build", help="Version part to bump")
    parser.add_argument("--notes", "-n", help="Release notes for the version")
    parser.add_argument("--skip-build", action="store_true", help="Skip building (use existing APK)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without executing")

    args = parser.parse_args()

    if args.command == "version":
        get_current_version()

    elif args.command == "bump":
        new_version, new_code = bump_version(args.part)
        print(f"Bumped to: {new_version}+{new_code}")

    elif args.command == "build":
        build_apk()

    elif args.command == "upload":
        version_name, version_code = parse_pubspec_version()
        if not APK_OUTPUT.exists():
            print("APK not found. Run 'build' first.")
            sys.exit(1)
        file_size = APK_OUTPUT.stat().st_size
        version_data = create_version_json(version_name, version_code, file_size, args.notes)
        if args.dry_run:
            print("Would upload:")
            print(json.dumps(version_data, indent=2))
        else:
            upload_to_supabase(version_data, APK_OUTPUT)

    elif args.command == "deploy":
        # Full deploy: bump, build, upload
        new_version, new_code = bump_version(args.part)
        if args.dry_run:
            print(f"Would deploy version: {new_version}+{new_code}")
            return

        file_size = build_apk()
        version_data = create_version_json(new_version, new_code, file_size, args.notes)
        upload_to_supabase(version_data, APK_OUTPUT)


if __name__ == "__main__":
    main()
