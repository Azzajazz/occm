from pathlib import Path
import os
import subprocess

def is_test_case_of_type(path: Path, ty: str) -> bool:
    return f"\\{ty}" in str(path) 

def rebuild_compiler():
    os.chdir("..")
    build_result = subprocess.run(
            ["odin", "build", "."],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )               
    if build_result.returncode != 0:
        print("ABORT: Compiler build failed")
        return
    os.chdir("test")
