from pathlib import Path, PurePath
import os
import argparse
import subprocess

import exp_files
import common

def write_exp_file(exp_file_path: Path, process_result: subprocess.CompletedProcess):
    print(f"Generating {exp_file_path}")
    with open(exp_file_path, "w") as f:
        f.write(f"exit_code: {process_result.returncode}\n")
        f.write(f"stdout: {process_result.stdout}\n")
        f.write(f"stderr: {process_result.stderr}\n")

def generate_exp_files_with_gcc(base_path: Path):
    groups = common.get_test_groups(base_path)
    for group in groups:
        if common.is_test_case_of_type(group[0], "valid"):
            generate_valid_exp_file(group)
        elif common.is_test_case_of_type(group[0], "invalid"):
            generate_invalid_exp_file(group)

def generate_valid_exp_file(paths: list[Path]):
    compile_result = subprocess.run(["gcc", "-O0"] + paths)
    # @HACK: If we get here, we should always be able to compile. However, the current compilation strategy doesn't always succeed.
    if compile_result.returncode != 0:
        return
    run_result = subprocess.run("a.exe", capture_output=True)
    exp_file_path = exp_files.exp_file_path_from_source_path(paths[0])
    write_exp_file(exp_file_path, run_result)
    os.remove("a.exe")

def generate_invalid_exp_file(paths: list[Path]):
    compile_result = subprocess.run(["..\occm.exe"] + paths, capture_output=True)
    exp_file_path = exp_files.exp_file_path_from_source_path(paths[0])
    write_exp_file(exp_file_path, compile_result)
    assert(not Path(paths[0].with_suffix(".exe").name).exists())

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-high")
    parser.add_argument("-low")
    parser.add_argument("-norebuild")
    args = parser.parse_args()

    if not args.norebuild:
        common.rebuild_compiler()

    if args.path:
        generate_exp_files_with_gcc(Path(args.path))
    else:
        low = 1
        if args.low: low = int(args.low)
        high = 20
        if args.high: high = int(args.high)
        for i in range(low, high + 1):
            generate_exp_files_with_gcc(Path(f"chapter_{i}"))

if __name__ == "__main__":
    main()
