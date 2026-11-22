"""Rehearse a persistent gate with cooperating Windows task and manual launchers."""
import errno
import json
from contextlib import contextmanager

import overlay

TASKS = {
    "FCM Auction House Price Refresh", "FCM ForeverDB Build Check",
    "FCM-AHHistory", "FCM-Private365-Update",
}
FENCE = ".fcm-maintenance.json"


class Busy(RuntimeError):
    pass


@contextmanager
def lease(root):
    # Use a different lock from overlay's installer-to-installer lock.
    path = overlay.location(root, ".fcm-writer.lock")
    with path.open("a+b") as stream:
        stream.seek(0)
        try:
            if overlay.os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            if error.errno in {errno.EACCES, errno.EAGAIN, errno.EDEADLK}:
                raise Busy("An active writer or maintenance process owns the gate") from error
            raise
        yield


def require_fixture(root):
    overlay.rehearsal_guard(root, lambda: {"complete": True, "writers": [], "unfenced": []})


@contextmanager
def writer(root, name):
    require_fixture(root)
    if name not in TASKS | {"manual"}:
        raise ValueError("Unknown writer")
    with lease(root):
        if overlay.location(root, FENCE).exists():
            raise Busy("Maintenance is active or requires recovery")
        yield


def transact(root, recovery, task_inventory, payload=None, baseline=None, hook=lambda _: None):
    """Apply or recover while denying all participating writers."""
    require_fixture(root)
    recovery = recovery.absolute()
    if recovery.is_relative_to(root) or not recovery.is_relative_to(root.parent):
        raise ValueError("Recovery must stay within the disposable parent directory")
    if set(task_inventory()) != TASKS:
        raise ValueError("Task inventory is incomplete")
    with lease(root):
        fence = overlay.location(root, FENCE)
        if payload is None:
            state = json.loads(fence.read_bytes())
            if state["recovery"] != str(recovery) or state["tasks"] != task_inventory():
                raise ValueError("Recovery identity or task definitions changed")
        else:
            if fence.exists() or recovery.exists():
                raise Busy("An unfinished transaction requires recovery")
            state = {"recovery": str(recovery), "tasks": task_inventory()}
            if set(state["tasks"]) != TASKS:
                raise ValueError("Task inventory is incomplete")
            overlay.record(fence, state)

        def probe():
            intact = json.loads(fence.read_bytes()) == state and task_inventory() == state["tasks"]
            return {"complete": intact, "writers": [], "unfenced": []}

        complete = False
        try:
            if payload is None:
                journal = json.loads(overlay.location(recovery, "journal.json").read_bytes())
                if journal["phase"] == "restored":
                    overlay.check(root, journal["original"])
                else:
                    overlay.restore(root, recovery, probe)
            else:
                overlay.apply(root, payload, baseline, recovery, probe, hook)
            complete = True
        finally:
            # A failed verification, absent journal, or failed rollback keeps the durable fence.
            journal_path = overlay.location(recovery, "journal.json")
            if journal_path.exists():
                journal = json.loads(journal_path.read_bytes())
                if (journal["phase"] == "restored" or
                        complete and journal["phase"] == "committed") and probe()["complete"]:
                    expected = journal["original"].copy()
                    if journal["phase"] == "committed":
                        expected.update({key: value["after"] for key, value in journal["operations"].items()})
                    overlay.check(root, expected)
                    fence.unlink()
