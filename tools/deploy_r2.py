#!/usr/bin/env python3
"""Publish the web export to the Cloudflare R2 bucket that serves the game.

The export in `build/web-mobile` is 122 MiB of binary (84.0 MiB `index.pck` +
37.7 MiB `index.wasm`) and Godot asks the browser for it by name, so the only
way to cut what a visitor downloads is to store those two objects brotli
compressed and let `Content-Encoding: br` do the decoding in the browser.  R2
serves that header straight from object metadata, which is why this host was
chosen over Cloudflare Pages: Pages and Workers cap a single static asset at
25 MiB, and both of our big files are over it.

Wire cost per cold visit after this tool has run:

    index.pck  84.0 MiB -> 42.9 MiB   (brotli q9, Content-Encoding: br)
    index.wasm 37.7 MiB ->  7.6 MiB   (brotli q9, Content-Encoding: br)
    branding-*.png       0.8 MiB     (the loading screen's art, revalidated)

Quality 9, not 11: q11 is roughly twenty times slower on this payload for a few
percent, the same trade the export report already documents.

Credentials
-----------
`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` hold an R2 API token with Object
Read & Write on the bucket.  They are read from the environment and, when the
environment does not set them, from `.env` beside the repo root, so a release
never needs a secret pasted into a shell or a transcript.  `.env` is
git-ignored: never commit it.  The older fallback mints one-hour S3 keys from a
`cf auth login` session, but it needs `--parent-access-key-id`, meaning a parent
R2 key this account does not have, so `.env` is the path that works; `--no-cf`
switches that attempt off.

Environment (a variable already set wins over `.env`)
----------------------------------------------------
    R2_ACCOUNT_ID         the Cloudflare account id holding the bucket
    R2_BUCKET             bucket name (default: livery-web)
    R2_HOST               public host for --check, e.g. play.example.com
    R2_ACCESS_KEY_ID      R2 API token id, Object Read & Write on the bucket
    R2_SECRET_ACCESS_KEY  R2 API token secret

Usage
-----
    python3 tools/deploy_r2.py --dry-run        # sizes and headers, no upload
    python3 tools/deploy_r2.py                  # compress and upload
    python3 tools/deploy_r2.py --check          # assert the live host is right
    python3 tools/deploy_r2.py --only index.pck # one object, after a rebuild

The custom domain has to be attached to the bucket in the R2 dashboard first
(bucket -> Settings -> Public access -> Custom domain); this tool uploads to the
S3 endpoint and cannot create the domain.  A bucket with no domain yet can be
smoke-tested through its r2.dev development URL by passing `--host`, but r2.dev
is rate-limited and must not become the address players use.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "build" / "web-mobile"
DEFAULT_BUCKET = "livery-web"

# name -> (content type, cache control, brotli?)
OBJECTS: dict[str, tuple[str, str, bool]] = {
    "index.html": ("text/html; charset=utf-8", "no-cache", False),
    "index.js": ("text/javascript; charset=utf-8", "no-cache", False),
    "index.audio.worklet.js": ("text/javascript; charset=utf-8", "no-cache", False),
    "index.audio.position.worklet.js": ("text/javascript; charset=utf-8", "no-cache", False),
    # The two big binaries: stored compressed, so the browser downloads 50.5 MiB
    # instead of 121.7 and decodes on the fly.  Revalidated, not cached blind:
    # an hour of max-age meant a phone that had played kept the previous pck
    # after a gameplay fix shipped, so a device test could silently run the old
    # build.  R2 answers If-None-Match with 304, so a repeat visit still costs no
    # download, and a deploy lands on the next load.
    "index.pck": ("application/octet-stream", "no-cache", True),
    "index.wasm": ("application/wasm", "no-cache", True),
    "index.png": ("image/png", "public, max-age=86400", False),
    "index.icon.png": ("image/png", "public, max-age=86400", False),
    "index.apple-touch-icon.png": ("image/png", "public, max-age=86400", False),
    # The loading screen's own art, copied into the export by
    # tools/export_web_mobile.py from tools/web_shell/art/.  Revalidated rather
    # than reused blind: the marks change with a release, and a day of max-age
    # would show a phone the previous logo.  Both are small next to the
    # binaries (about 0.8 MiB together), and they are only fetched while the
    # screen is up.
    "branding-ginger-games.png": ("image/png", "no-cache", False),
    "branding-livery.png": ("image/png", "no-cache", False),
}

# Everything except the icons is revalidated.  The pck and wasm are large, so an
# hour of blind reuse looked economical, but it meant a phone kept the previous
# build after a gameplay fix shipped: the device test then measured code that
# was already replaced.  A conditional request is one round trip and a 304, and
# the icons stay on a day of blind reuse because they cannot change.
PFX = "[deploy]"

# Cloudflare's bot protection answers an unadvertised UA (urllib's default) with
# `error code: 1010` and a 403 on this host, so the checker has to look like the
# browser whose response it is asserting.
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36"


def log(message: str) -> None:
    print(f"{PFX} {message}", flush=True)


def mib(size: int) -> str:
    return f"{size / 1048576:6.1f} MiB"


def load_env_file(path: Path) -> int:
    """Read `.env` into os.environ, leaving anything already set alone.

    Keeps the R2 token out of the shell and off the command line, which is where
    it ended up the first several times this tool was run.  Only simple
    KEY=value lines are understood: comments and blank lines are skipped, quotes
    around a value are stripped, and a real environment variable always wins.
    """
    if not path.exists():
        return 0
    loaded = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if not key or key in os.environ:
            continue
        os.environ[key] = value.strip().strip('"').strip("'")
        loaded += 1
    return loaded


def wanted_files(src: Path, only: list[str]) -> list[str]:
    names = [n for n in OBJECTS if (src / n).exists()]
    if only:
        names = [n for n in names if n in only]
    missing = sorted(set(only) - set(names))
    if missing:
        log(f"refusing: {', '.join(missing)} not found in {src}")
    return names


def brotli_copies(src: Path, names: list[str], work: Path) -> dict[str, Path]:
    """Compress the flagged objects at q9, streaming so nothing large is held twice."""
    import brotli

    out: dict[str, Path] = {}
    for name in names:
        if not OBJECTS[name][2]:
            continue
        target = work / f"{name}.br"
        source_size = (src / name).stat().st_size
        stream = brotli.Compressor(quality=9, lgwin=22)
        written = 0
        with (src / name).open("rb") as reader, target.open("wb") as writer:
            for chunk in iter(lambda: reader.read(4 << 20), b""):
                data = stream.process(chunk)
                written += len(data)
                writer.write(data)
            tail = stream.finish()
            written += len(tail)
            writer.write(tail)
        log(f"brotli {name:18s} {mib(source_size)} -> {mib(written)}")
        out[name] = target
    return out


def mint_credentials(bucket: str) -> tuple[str, str]:
    """Ask the cf CLI for short-lived S3 keys instead of holding a permanent token."""
    exe = shutil.which("cf")
    if exe is None:
        raise SystemExit(
            f"{PFX} no cf on PATH and no R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY; "
            "install the CLI (npm install -g cf) and run `cf auth login`"
        )
    command = [
        exe,
        "r2",
        "temporary-credentials",
        "create",
        "--bucket",
        bucket,
        "--permission",
        "object-read-write",
        "--ttl-seconds",
        "3600",
    ]
    log("minting short-lived R2 credentials from the cf session")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        hint = ""
        if "Node.js v22" in detail:
            hint = " (cf picked an old node: put its nvm bin directory first on PATH)"
        raise SystemExit(f"{PFX} cf could not mint credentials{hint}: {detail}")
    # The response shape is a CLI detail, so look for the fields rather than
    # trusting one nesting: this keeps working if cf renames its wrapper.
    def find(payload: object, *wanted: str) -> str | None:
        if isinstance(payload, dict):
            for key, value in payload.items():
                flat = key.replace("_", "").replace("-", "").lower()
                if flat in wanted and isinstance(value, str) and value:
                    return value
            for value in payload.values():
                found = find(value, *wanted)
                if found:
                    return found
        elif isinstance(payload, list):
            for value in payload:
                found = find(value, *wanted)
                if found:
                    return found
        return None

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"{PFX} cf returned non-JSON credentials: {result.stdout.strip()[:400]}")
    key = find(payload, "accesskeyid")
    secret = find(payload, "secretaccesskey")
    if not key or not secret:
        raise SystemExit(f"{PFX} could not find key/secret in cf output: {json.dumps(payload)[:400]}")
    return key, secret


def client(account: str, bucket: str, use_cf: bool):
    import boto3

    key = os.environ.get("R2_ACCESS_KEY_ID")
    secret = os.environ.get("R2_SECRET_ACCESS_KEY")
    if not key or not secret:
        if not use_cf:
            raise SystemExit(f"{PFX} --no-cf given but R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY are unset")
        key, secret = mint_credentials(bucket)
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=key,
        aws_secret_access_key=secret,
        region_name="auto",
        config=_s3_config(),
    )


def _s3_config():
    from botocore.config import Config

    # R2 is S3-compatible but not S3: checksum negotiation and the newer
    # flexible checksums are not implemented and produce 501s on upload.
    return Config(
        signature_version="s3v4",
        retries={"max_attempts": 3, "mode": "standard"},
        request_checksum_calculation="when_required",
        response_checksum_validation="when_required",
        s3={"addressing_style": "path"},
    )


def upload(args, src: Path, names: list[str], compressed: dict[str, Path]) -> float:
    total = 0.0
    s3 = client(args.account, args.bucket, not args.no_cf)
    for name in names:
        content_type, cache_control, br = OBJECTS[name]
        path = compressed.get(name, src / name)
        extra = {"ContentType": content_type, "CacheControl": cache_control}
        if br:
            extra["ContentEncoding"] = "br"
        size = path.stat().st_size
        s3.put_object(Bucket=args.bucket, Key=name, Body=path.read_bytes(), **extra)
        total += size
        log(f"put {name:18s} {mib(size)}  {content_type}  {cache_control}"
            + ("  content-encoding: br" if br else ""))
    return total


def check(args, names: list[str], compressed: dict[str, Path]) -> int:
    """Assert the live host answers with the headers the loader depends on."""
    host = args.host or os.environ.get("R2_HOST", "")
    if not host:
        raise SystemExit(f"{PFX} --check needs --host or R2_HOST (e.g. play.example.com)")
    base = host if host.startswith("http") else f"https://{host}"
    failures = 0

    def probe(key: str, headers: dict[str, str] | None = None):
        # R2 only hands back the stored brotli representation to a client that
        # advertises support for it; a client that does not gets the edge's
        # decoded (raw, chunked) copy instead.  Browsers always send br, so the
        # check has to ask for it or it measures the uncompressed bytes and
        # reports a length mismatch on every binary.
        request = urllib.request.Request(
            f"{base.rstrip('/')}/{key}",
            headers={"Accept-Encoding": "br", "User-Agent": UA, **(headers or {})},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read()

    for name in names:
        content_type, _, br = OBJECTS[name]
        expected = compressed[name].stat().st_size if br else (args.dir / name).stat().st_size
        status, headers, _ = probe(name)
        got_type = headers.get("Content-Type", "")
        got_len = int(headers.get("Content-Length", "0") or 0)
        got_enc = headers.get("Content-Encoding", "")
        problems = []
        if status != 200:
            problems.append(f"status {status}")
        if not got_type.startswith(content_type.split(";")[0]):
            problems.append(f"content-type {got_type!r}")
        if br and got_enc != "br":
            problems.append(f"content-encoding {got_enc!r}")
        if abs(got_len - expected) > max(2048, expected // 100):
            problems.append(f"length {got_len} != {expected}")
        if problems:
            failures += 1
            log(f"FAIL {name:18s} " + "; ".join(problems))
        else:
            log(f"ok   {name:18s} {mib(got_len)}  {got_type}" + (f"  {got_enc}" if got_enc else ""))

    # The loading screen is stamped with the build it belongs to, so the live
    # page can be held against the export on disk.  This is the check that
    # answers "am I actually playing the build I just published" instead of
    # trusting that an upload replaced what a browser cached.
    if "index.html" in names:
        local_index = (args.dir / "index.html").read_text(encoding="utf-8", errors="replace")
        stamp = re.search(r'id="build-version"[^>]*>([^<]+)<', local_index)
        _, _, live_body = probe("index.html")
        live_html = live_body.decode("utf-8", "replace")
        if stamp is None:
            log("warn index.html has no build stamp (export predates the stamp)")
        elif stamp.group(1).strip() and stamp.group(1).strip() in live_html:
            log(f"ok   index.html build stamp {stamp.group(1).strip()}")
        else:
            failures += 1
            log(f"FAIL index.html is not serving the local build stamp {stamp.group(1).strip()!r}")

    # Range and conditional support matter for a 43 MiB object on a tablet.
    status, headers, _ = probe(names[0], {"Range": "bytes=0-15"})
    if status not in (206, 200):
        failures += 1
        log(f"FAIL range request on {names[0]} returned {status}")
    else:
        log(f"ok   range on {names[0]} -> {status}")

    status, headers, _ = probe(names[0])
    etag = headers.get("ETag")
    if etag:
        status, _, _ = probe(names[0], {"If-None-Match": etag})
        if status not in (304, 200):
            failures += 1
            log(f"FAIL conditional request returned {status}")
        else:
            log(f"ok   if-none-match on {names[0]} -> {status}")

    # The bucket root has to serve the game, not a 404: public buckets do not
    # guarantee an index document, and if this fails the fix is a one-line
    # Redirect Rule from / to /index.html.
    status, _, body = probe("", {})
    if status == 200 and b"<canvas" in body[:4096].lower():
        log("ok   / serves the game shell")
    else:
        failures += 1
        log(f"FAIL / returned {status}; point a Redirect Rule from / to /index.html")

    if failures:
        log(f"{failures} check(s) failed")
        return 1
    log("all checks passed")
    return 0


def main() -> int:
    # Before the parser is built: --account, --bucket and --host default from
    # the environment, so .env has to be loaded first.
    env_loaded = load_env_file(ROOT / ".env")
    if env_loaded:
        log(f"settings: {env_loaded} value(s) from .env")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=str(DEFAULT_DIR), help="export directory (default: build/web-mobile)")
    parser.add_argument("--bucket", default=os.environ.get("R2_BUCKET", DEFAULT_BUCKET), help="R2 bucket name")
    parser.add_argument("--account", default=os.environ.get("R2_ACCOUNT_ID", ""), help="Cloudflare account id")
    parser.add_argument("--host", default=os.environ.get("R2_HOST", ""), help="public host, for --check")
    parser.add_argument("--dry-run", action="store_true", help="compress and report sizes; upload nothing")
    parser.add_argument("--check", action="store_true", help="verify the live host and exit")
    parser.add_argument("--only", action="append", default=[], metavar="NAME", help="limit to these objects")
    parser.add_argument("--no-cf", action="store_true", help="require env credentials; do not call the cf CLI")
    args = parser.parse_args()
    args.dir = Path(args.dir).resolve()

    if not (args.dir / "index.html").exists():
        log(f"no export at {args.dir}; run tools/export_web_mobile.py first")
        return 1
    names = wanted_files(args.dir, args.only)
    if not names:
        log("nothing to upload")
        return 1

    work = Path(tempfile.mkdtemp(prefix="r2-deploy-"))
    try:
        compressed = brotli_copies(args.dir, names, work)
        raw = sum((args.dir / n).stat().st_size for n in names)
        wire = sum(compressed[n].stat().st_size if n in compressed else (args.dir / n).stat().st_size for n in names)
        log(f"{len(names)} objects, {mib(raw)} on disk -> {mib(wire)} over the wire")

        if args.dry_run:
            for name in names:
                content_type, cache_control, br = OBJECTS[name]
                path = compressed.get(name, args.dir / name)
                log(
                    f"would put {name:18s} {mib(path.stat().st_size)}  {content_type}  "
                    f"{cache_control}" + ("  content-encoding: br" if br else "")
                )
            log(f"would upload to r2://{args.bucket}/ on account {args.account or '(unset)'}")
            return 0

        if args.check:
            return check(args, names, compressed)

        if not args.account:
            raise SystemExit(f"{PFX} R2_ACCOUNT_ID (or --account) is required to upload")
        total = upload(args, args.dir, names, compressed)
        log(f"uploaded {mib(total)} in total: that is what a cold visit now downloads")
        if args.host:
            log(f"verify with: python3 tools/deploy_r2.py --check --host {args.host}")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
