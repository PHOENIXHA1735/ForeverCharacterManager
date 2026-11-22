"""WinPE-only, fail-closed NTFS owner/group/DACL preservation (ACL4 method).

The DACL is inherited by a newly created scratch file in the destination
directory. ONLY its owner and group are adjusted to match the approved original.
A byte-identical owner/group/DACL descriptor must be observed before and after
the replacement. Never change security on an existing installed file.
"""
import ctypes
import os
from pathlib import Path

OWNER_GROUP = 0x1 | 0x2
OWNER_GROUP_DACL = OWNER_GROUP | 0x4


def _advapi():
    if os.name != "nt":
        raise RuntimeError("Windows ACL APIs required; no POSIX fallback")
    return ctypes.WinDLL("advapi32", use_last_error=True)


def acl(path):
    """Read exact self-relative owner/group/DACL security descriptor."""
    call = _advapi().GetFileSecurityW
    call.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_void_p,
                     ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32)]
    call.restype = ctypes.c_int
    size = ctypes.c_uint32()
    call(str(path), OWNER_GROUP_DACL, None, 0, ctypes.byref(size))
    if not 20 <= size.value <= 65536:
        raise ctypes.WinError(ctypes.get_last_error())
    data = ctypes.create_string_buffer(size.value)
    if not call(str(path), OWNER_GROUP_DACL, data, size.value, ctypes.byref(size)):
        raise ctypes.WinError(ctypes.get_last_error())
    return data.raw[:size.value]


def set_acl(path, descriptor):
    """Set ONLY owner+group on a newly created scratch file, NOT its DACL.

    Deliberately retains NTFS inherited DACL flags. Requires a byte-perfect
    match after setting. Any non-equivalent inherited DACL fails closed.
    This is not an authorization to change installed files' security.
    """
    if not isinstance(descriptor, bytes) or not 20 <= len(descriptor) <= 65536:
        raise ValueError("Invalid approved security descriptor")
    path = Path(path)
    if not path.is_file() or not path.name.startswith(
            (".fcm-permission-check-", ".fcm-overlay-")):
        raise ValueError("Security change is restricted to a temporary file")
    call = _advapi().SetFileSecurityW
    call.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_void_p]
    call.restype = ctypes.c_int
    data = ctypes.create_string_buffer(descriptor)
    if not call(str(path), OWNER_GROUP, data):
        raise ctypes.WinError(ctypes.get_last_error())
    if acl(path) != descriptor:
        raise ValueError(f"Temporary file could not retain approved NTFS security: {path}")


def replace_file(original, replacement):
    """Same-volume rename tested by ACL4; only caller-reviewed temporary."""
    if os.name != "nt":
        raise RuntimeError("Windows-only ACL-preserving rename required")
    original = Path(original)
    replacement = Path(replacement)
    if replacement.parent != original.parent or not replacement.name.startswith(".fcm-overlay-"):
        raise ValueError("Replacement must be a reviewed same-folder temporary file")
    os.replace(replacement, original)
