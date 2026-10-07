"""Return an immutable plugin path so config reload detects changed binaries."""
import hashlib
import os
from pathlib import Path
import sys
import tempfile


def snapshot(source, cache_root):
    source = Path(source)
    with source.open("rb") as file:
        before = os.fstat(file.fileno())
        data = file.read()
        after = os.fstat(file.fileno())
    if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
        after.st_size, after.st_mtime_ns, after.st_ctime_ns
    ) or len(data) != after.st_size:
        raise ValueError("plugin changed while reading; finish the build, then reload")
    if not data.startswith(b"\x7fELF"):
        raise ValueError(f"not an ELF plugin: {source}")

    directory = Path(cache_root).expanduser().resolve() / source.stem
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination = directory / (hashlib.sha256(data).hexdigest() + ".so")
    if not destination.exists():
        # Publish a complete file without modifying any existing mapped inode.
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as file:
            temporary = Path(file.name)
            try:
                file.write(data)
                file.flush()
                try:
                    os.link(temporary, destination)
                except FileExistsError:
                    pass  # another session published the same content
            finally:
                temporary.unlink()
    if destination.read_bytes() != data:
        raise ValueError(f"plugin cache corrupted; refusing to overwrite: {destination}")
    return destination


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: plugin_snapshot.py PLUGIN.so")
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hypr/plugin-cache"
        print(snapshot(sys.argv[1], cache))
    except (OSError, ValueError) as error:
        sys.exit(f"plugin_snapshot: {error}")
