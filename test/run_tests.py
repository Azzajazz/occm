import os 
import subprocess
import argparse

import exp_files

def is_case_of(dirpath: str, test_case: str) -> bool:
    (head, current) = os.path.split(dirpath)
    parent = os.path.basename(head)
    return current == test_case or (parent == test_case and current == "extra_credit")

def do_chapter_tests(dirname: str):
    global passed
    global failed

    for root, dirs, files in os.walk(dirname):
        if is_case_of(root, "valid"):
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)
                print(f"Running test {os.path.join(root, file)}:  ", end = "")
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
    parser.add_argument("-high")
    parser.add_argument("-low")
    parser.add_argument("-only")
    parser.add_argument("-norebuild")
    args = parser.parse_args()

    if not args.norebuild:
        os.chdir("..")
        subprocess.run(
                ["odin", "build", "."],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )               
        os.chdir("test")

    if args.only:
        do_chapter_tests(f"chapter_{args.only}")
    else:
        if args.low:
            low = int(args.low)
        else:
            low = 1

        if args.high:
            high = int(args.high)
        else:
            high = 20
            

        for i in range(low, high + 1):
            do_chapter_tests(f"chapter_{i}")

    print(f"Passed: {passed}, Failed: {failed}")

if __name__ == "__main__":
    passed = 0
    failed = 0
    main()
