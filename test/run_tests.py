import os 
import subprocess
import argparse

import exp_files

def is_case_of(dirpath: str, case: str):
    return f"\\{case}" in dirpath

def do_valid_test(source_path: str):
    global passed
    global failed

    print(f"Running test {source_path}:  ", end = "")
    compile_result = subprocess.run(
            ["../occm.exe", source_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    if compile_result.returncode != 0:
        print("FAILED! Compilation failed")
        failed += 1
        return

    exec_path = os.path.basename(source_path)[:-2] + ".exe"
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

def do_invalid_lex_test(source_path: str):
    global passed
    global failed

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

def do_invalid_parse_test(source_path: str):
    global passed
    global failed

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

def do_invalid_semantics_test(source_path: str):
    global passed
    global failed

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

def do_test(dirname: str, source_path: str):
    if is_case_of(dirname, "valid"):
        do_valid_test(source_path)

    elif is_case_of(dirname, "invalid_lex"):
        do_invalid_parse_test(source_path)

    elif is_case_of(dirname, "invalid_parse"):
        do_invalid_parse_test(source_path)

    elif is_case_of(dirname, "invalid_semantics"):
        do_invalid_semantics_test(source_path)

def do_tests(dirname: str):
    if os.path.isfile(dirname):
        do_test(dirname, dirname)

    for root, dirs, files in os.walk(dirname):
        for file in filter(lambda f: f.endswith(".c"), files):
            source_path = os.path.join(root, file)
            do_test(root, source_path)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-high")
    parser.add_argument("-low")
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
        low = 1
        if args.low: low = int(args.low)
        high = 18 
        if args.high: high = int(args.high)
        for i in range(low, high + 1):
            do_tests(f"chapter_{i}")

    print(f"Passed: {passed}, Failed: {failed}")

if __name__ == "__main__":
    passed = 0
    failed = 0
    main()
