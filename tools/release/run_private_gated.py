"""Run a hash-pinned private updater in the lease-owning process."""
import argparse
from hashlib import sha256
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fcm_writer_lease import checked, writer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--addon", type=Path, required=True)
    parser.add_argument("--updater", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()
    with writer(args.addon):
        updater = checked(args.updater.absolute())
        data = updater.read_bytes()
        if sha256(data).hexdigest() != args.sha256.lower():
            raise ValueError("Private updater SHA-256 mismatch")
        # Preserve the installed updater's own __file__ and import setup.
        sys.argv = [str(updater)]
        exec(compile(data, str(updater), "exec"), {"__name__": "__main__", "__file__": str(updater)})


if __name__ == "__main__":
    main()
