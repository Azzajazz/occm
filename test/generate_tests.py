import os
import argparse
import subprocess

import exp_files

def generate_exp_files_with_gcc(base_path: str):
    if os.path.isfile(base_path):
        generate_exp_file_with_gcc(base_path)
    else:
        for root, dirs, files in os.walk(base_path):
            if "\\valid" in root:
                for file in files:
                    if file.endswith(".c"):
                        generate_exp_file_with_gcc(os.path.join(root, file))

def generate_exp_file_with_gcc(path: str):
    compile_result = subprocess.run(["gcc", "-O0", path])
    # @HACK: If we get here, we should always be able to compile. However, the current compilation strategy doesn't always succeed.
    if compile_result.returncode != 0:
        return
    run_result = subprocess.run("a.exe", capture_output=True)
    exp_file_path = exp_files.exp_file_path_from_source_path(path)
    print(f"Generating {exp_file_path}")
    with open(exp_file_path, "w") as f:
        f.write(f"exit_code: {run_result.returncode}\n")
        f.write(f"stdout: {run_result.stdout}")
    os.remove("a.exe")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-high")
    parser.add_argument("-low")
    args = parser.parse_args()

    if args.path:
        generate_exp_files_with_gcc(args.path)
    else:
        low = 1
        if args.low: low = args.low
        high = 20
        if args.high: high = args.high
        for i in range(low, high + 1):
            generate_exp_files_with_gcc(f"chapter_{i}")

if __name__ == "__main__":
    main()
