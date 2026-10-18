#!/usr/bin/env python3
"""Apply the Theos-recommended static arm64e ABI conversion and re-sign locally."""
import pathlib
import subprocess
import sys
import tempfile

package, converter, signer = map(pathlib.Path, sys.argv[1:])
package = package.resolve()
with tempfile.TemporaryDirectory(prefix="lineageqs-package-") as directory:
    stage = pathlib.Path(directory) / "stage"
    subprocess.run(["dpkg-deb", "-R", str(package), str(stage)], check=True)
    binaries = [
        stage / "var/jb/Library/MobileSubstrate/DynamicLibraries/LineageQS.dylib",
        stage / "var/jb/Library/PreferenceBundles/LineageQSPrefs.bundle/LineageQSPrefs",
        stage / "var/jb/usr/bin/lqsctl",
    ]
    log = package.with_suffix(".abi-conversion.log")
    with log.open("w") as output:
        for binary in binaries:
            if binary.name == "lqsctl":
                # Executables do not need arm64e. Remove that slice from old
                # builds too; converter support is for injected Obj-C dylibs.
                if binary.read_bytes()[:4] == b"\xca\xfe\xba\xbe":
                    thin = binary.with_suffix(".arm64")
                    subprocess.run([str(signer.parent / "lipo"), str(binary), "-thin", "arm64", "-output", str(thin)], check=True)
                    thin.replace(binary)
            else:
                result = subprocess.run([str(converter), str(binary)], capture_output=True, text=True, check=True)
                output.write(result.stdout + result.stderr)
                if "ERROR:" in result.stdout + result.stderr:
                    raise RuntimeError(f"ABI conversion failed for {binary}; see {log}")
            subprocess.run([str(signer), "-s", str(binary)], check=True)
            subprocess.run([str(signer), "-S", str(binary)], check=True)
    rebuilt = pathlib.Path(directory) / package.name
    subprocess.run(["dpkg-deb", "--root-owner-group", "-Zxz", "-b", str(stage), str(rebuilt)], check=True)
    package.write_bytes(rebuilt.read_bytes())
    print(f"Converted two dylibs, selected arm64 CLI, and re-signed three binaries: {package}")
