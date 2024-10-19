import os 
import subprocess
import argparse

import exp_files

def is_case_of(dirpath: str, case: str):
    return f"\\{case}" in dirpath

def do_tests(dirname: str):
    global passed
    global failed

    for root, dirs, files in os.walk(dirname):
        if is_case_of(root, "valid"):
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)

                print(f"Running test {source_path}:  ", end = "")
                compile_result = subprocess.run(
                        ["../occm.exe", source_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                if compile_result.returncode != 0:
                    print("FAILED! Compilation failed")
                    failed += 1
                    continue

                exec_path = file[:-2] + ".exe"
                exp_file_path = exp_files.exp_file_path_from_source_path(source_path)
                exp_file = exp_files.ExpFile(exp_file_path)
                run_result = subprocess.run(
                        [exec_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                if exp_file.exit_code == run_result.returncode:
                    print("PASSED!")
                    passed += 1
                else:
                    print(f"FAILED! Return codes do not match. Expected {exp_file.exit_code}, got {run_result.returncode}")
                    failed += 1
                os.remove(exec_path)

        elif is_case_of(root, "invalid_lex"):
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)
                print(f"Running test {source_path}:  ", end = "")
                compile_result = subprocess.run(
                        ["../occm.exe", source_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                if compile_result.returncode == 2:
                    print("PASSED!")
                    passed += 1
                else:
                    print("FAILED! Lex should not have succeeded")
                    failed += 1

        elif is_case_of(root, "invalid_parse"):
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)
                print(f"Running test {source_path}:  ", end = "")
                compile_result = subprocess.run(
                        ["../occm.exe", source_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )               
                if compile_result.returncode == 3:
                    print("PASSED!")
                    passed += 1
                else:
                    print("FAILED! Parse should not have succeeded")
                    failed += 1

        elif is_case_of(root, "invalid_semantics"):
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)
                print(f"Running test {source_path}:  ", end = "")
                compile_result = subprocess.run(
                        ["../occm.exe", source_path],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )               
                if compile_result.returncode == 4:
                    print("PASSED!")
                    passed += 1
                else:
                    print("FAILED! Semantics are incorrect")
                    failed += 1



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-norebuild")
    args = parser.parse_args()

    if not args.norebuild:
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

    if args.path:
        do_tests(args.path)
    else:
        do_tests(".")

    print(f"Passed: {passed}, Failed: {failed}")

if __name__ == "__main__":
    passed = 0
    failed = 0
    main()
