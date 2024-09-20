import os
import subprocess

import exp_files

def generate_exp_file_with_gcc(path: str):
    compile_result = subprocess.run(["gcc", "-O0", path])
    # @HACK: If we get here, we should always be able to compile. However, the current compilation strategy doesn't always succeed.
    if compile_result.returncode != 0:
        return
    run_result = subprocess.run("a.exe")
    exp_file_path = exp_files.exp_file_path_from_source_path(path)
    print(f"Generating {exp_file_path}")
    with open(exp_file_path, "w") as f:
        f.write(f"exit_code: {run_result.returncode}")
    os.remove("a.exe")

def main():
    for root, dirs, files in os.walk("."):
        if os.path.basename(root) == "valid":
            for file in files:
                if file.endswith(".c"):
                    generate_exp_file_with_gcc(os.path.join(root, file))

if __name__ == "__main__":
    main()
