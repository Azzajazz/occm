from pathlib import Path
import os 
import subprocess
import argparse

import exp_files
import common

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

def do_valid_test(paths: list[Path], stats: Stats):
    print(f"Running test {paths[0]}:  ", end = "")
    compile_result = subprocess.run(
            ["../occm.exe"] + paths,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    if compile_result.returncode != 0:
        stats.failed("Compilation unsuccessful")
        return

    exec_path = Path(paths[0].with_suffix(".exe").name)
    exp_file_path = exp_files.exp_file_path_from_source_path(paths[0])
    exp_file = exp_files.ExpFile(exp_file_path)
    run_result = subprocess.run([exec_path], capture_output=True)
    if compare_to_exp_file(run_result, exp_file, stats):
        stats.passed()
    os.remove(exec_path)

def do_invalid_test(paths: list[Path], stats: Stats):
    print(f"Running test {paths[0]}:  ", end = "")
    compile_result = subprocess.run(["../occm.exe"] + paths, capture_output=True)
    exp_file_path = exp_files.exp_file_path_from_source_path(paths[0])
    exp_file = exp_files.ExpFile(exp_file_path)
    if not compare_to_exp_file(compile_result, exp_file, stats):
        return
    stderr = eval(exp_file.stderr)
    if common.is_test_case_of_type(paths[0], "invalid_lex") and b"Lex error" not in stderr:
        stats.failed("Lexing succeeded, but should have failed")
    elif common.is_test_case_of_type(paths[0], "invalid_parse") and b"Parse error" not in stderr:
        stats.failed("Parsing succeeded, but should have failed")
    elif common.is_test_case_of_type(paths[0], "invalid_semantics") and b"Semantic error" not in stderr:
        stats.failed("Semantic checking succeeded, but should have failed")
    else:
        stats.passed()
                        
def do_tests(base_path: Path, stats: Stats):
    groups = common.get_test_groups(base_path)
    for group in groups:
        if common.is_test_case_of_type(group[0], "valid"):
            do_valid_test(group, stats)
        elif common.is_test_case_of_type(group[0], "invalid"):
            do_invalid_test(group, stats)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-path")
    parser.add_argument("-high")
    parser.add_argument("-low")
    parser.add_argument("-norebuild")
    args = parser.parse_args()

    stats = Stats()

    if not args.norebuild:
        common.rebuild_compiler()

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
