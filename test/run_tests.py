from pathlib import Path
import os 
import subprocess
import argparse

import exp_files
from common import *

class Stats:
    passed_count = 0
    failed_count = 0

    def failed(self, message: str):
        print(f"FAIL! {message}")
        self.failed_count += 1

    def passed(self):
        print(f"PASS!")
        self.passed_count += 1

def compare_to_exp_file(process_result: subprocess.CompletedProcess, exp_file: exp_files.ExpFile, stats: Stats) -> bool:
    if exp_file.exit_code != process_result.returncode:
        stats.failed(f"Return codes do not match. Expected {exp_file.exit_code}, got {process_result.returncode}")
        return False
    elif eval(exp_file.stdout) != process_result.stdout:
        stats.failed("stdout does not match")
        return False
    elif eval(exp_file.stderr) != process_result.stderr:
        stats.failed("stderr does not match")
        return False
    return True

def do_valid_test(source_path: Path, stats: Stats):
    print(f"Running test {source_path}:  ", end = "")
    compile_result = subprocess.run(
            ["../occm.exe", source_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    if compile_result.returncode != 0:
        stats.failed("Compilation unsuccessful")
        return

    exec_path = Path(source_path.with_suffix(".exe").name)
    exp_file_path = exp_files.exp_file_path_from_source_path(source_path)
    exp_file = exp_files.ExpFile(exp_file_path)
    run_result = subprocess.run([exec_path], capture_output=True)
    if compare_to_exp_file(run_result, exp_file, stats):
        stats.passed()
    os.remove(exec_path)

def do_invalid_test(source_path: Path, stats: Stats):
    print(f"Running test {source_path}:  ", end = "")
    compile_result = subprocess.run(["../occm.exe", source_path], capture_output=True)
    exp_file_path = exp_files.exp_file_path_from_source_path(source_path)
    exp_file = exp_files.ExpFile(exp_file_path)
    if not compare_to_exp_file(compile_result, exp_file, stats):
        return
    stderr = eval(exp_file.stderr)
    if is_test_case_of_type(source_path, "invalid_lex") and b"Lex error" not in stderr:
        print(exp_file.stderr)
        stats.failed("Lexing succeeded, but should have failed")
    elif is_test_case_of_type(source_path, "invalid_parse") and b"Parse error" not in stderr:
        stats.failed("Parsing succeeded, but should have failed")
    elif is_test_case_of_type(source_path, "invalid_semantics") and b"Semantic error" not in stderr:
        stats.failed("Semantic checking succeeded, but should have failed")
    else:
        stats.passed()
                        
def do_tests(base_path: Path, stats: Stats):
    if base_path.is_file():
        if is_test_case_of_type(base_path, "valid"):
            do_valid_test(base_path, stats)
        elif is_test_case_of_type(base_path, "invalid"):
            do_invalid_test(base_path, stats)
    
    for file in base_path.glob("**\\*.c"):
        if is_test_case_of_type(file, "valid"):
            do_valid_test(file, stats)
        elif is_test_case_of_type(file, "invalid"):
            do_invalid_test(file, stats)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-high")
    parser.add_argument("-low")
    parser.add_argument("-norebuild")
    args = parser.parse_args()

    stats = Stats()

    if not args.norebuild:
        rebuild_compiler()

    if args.path:
        do_tests(Path(args.path), stats)
    else:
        low = 1
        if args.low: low = int(args.low)
        high = 20
        if args.high: high = int(args.high)
        for i in range(low, high + 1):
            do_tests(Path(f"chapter_{i}"), stats)

    print(f"Passed: {stats.passed_count}, Failed: {stats.failed_count}")

if __name__ == "__main__":
    main()
