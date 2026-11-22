"""Interoperable FCM writer admission for Windows launchers."""
from contextlib import contextmanager
from pathlib import Path
import os
import stat


def checked(path):
    for part in (path, *path.parents):
        try:
            item = part.lstat()
        except FileNotFoundError:
            continue
        if (stat.S_ISLNK(item.st_mode) or getattr(item, "st_file_attributes", 0) & 1024
                or stat.S_ISREG(item.st_mode) and item.st_nlink != 1):
            raise ValueError(f"Linked writer lease path: {part}")
    return path


def present(path):
    try:
        path.lstat()
    except FileNotFoundError:
        return False
    return True


@contextmanager
def acquire(addon):
    root = checked(Path(addon).absolute())
    if not root.is_dir():
        raise ValueError("FCM writer root is not a directory")
    with checked(root / ".fcm-writer.lock").open("a+b") as handle:
        handle.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


@contextmanager
def writer(addon):
    with acquire(addon):
        if present(Path(addon) / ".fcm-maintenance.json"):
            raise RuntimeError("FCM maintenance is active or requires recovery")
        yield
