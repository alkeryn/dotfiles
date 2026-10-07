"""Build a missing local CMake plugin, then reload only the requesting instance."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def build_missing(source_dir, output, target, log):
    output.parent.mkdir(parents=True, exist_ok=True)
    # Different sessions may request the same build. Recheck after taking the lock.
    with Path(str(output) + ".build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if output.exists():
            return
        if not (source_dir / "CMakeLists.txt").is_file():
            raise FileNotFoundError(f"missing CMake project: {source_dir}")
        staging = output.parent / (".autobuild-" + target)
        subprocess.run([
            "cmake", "-S", str(source_dir), "-B", str(staging), "-G", "Ninja",
            "-DCMAKE_CXX_COMPILER=clang++", "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_TESTING=OFF",
        ], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        subprocess.run([
            "cmake", "--build", str(staging), "--parallel", "2", "--target", target,
        ], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        artifact = staging / output.name
        with artifact.open("rb") as file:
            if file.read(4) != b"\x7fELF":
                raise ValueError(f"build did not produce an ELF plugin: {artifact}")
        # Never expose a partially linked file or replace a concurrently built one.
        with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as file:
            temporary = Path(file.name)
        try:
            shutil.copyfile(artifact, temporary)
            temporary.chmod(0o755)
            try:
                os.link(temporary, output)
            except FileExistsError:
                pass
        finally:
            temporary.unlink()


def reload_instance(instance, log):
    # An initial build can finish before startup has created the IPC socket.
    socket = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / instance / ".socket.sock"
    deadline = time.monotonic() + 30
    while not socket.exists():
        if time.monotonic() >= deadline:
            raise TimeoutError(f"instance socket unavailable: {socket}; reload manually")
        time.sleep(0.1)
    subprocess.run(["hyprctl", "-i", instance, "reload"], check=True,
                   stdout=log, stderr=subprocess.STDOUT, timeout=15)


def run(source_dir, output, target, instance):
    output = Path(output).absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Deduplicate repeated reloads of one session, while letting other sessions
    # wait for the shared build and then reload their own configs too.
    suffix = hashlib.sha256(instance.encode()).hexdigest()[:16]
    with Path(str(output) + "." + suffix + ".build.lock").open("a") as job_lock:
        try:
            fcntl.flock(job_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        with Path(str(output) + ".build.log").open("a", buffering=1) as log:
            try:
                print(f"\nBuilding if missing: {output} (instance {instance})", file=log)
                build_missing(Path(source_dir).absolute(), output, target, log)
                print("Plugin ready; requesting config reload", file=log)
                reload_instance(instance, log)
            except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
                print(f"Build/reload failed: {error}", file=log)
                raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--instance", required=True)
    args = parser.parse_args()
    if not args.instance or "/" in args.instance or args.instance in (".", ".."):
        parser.error("invalid instance signature")
    if not args.target or "/" in args.target or args.target in (".", ".."):
        parser.error("invalid CMake target")
    run(args.source_dir, args.output, args.target, args.instance)
