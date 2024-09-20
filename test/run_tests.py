import os 
import subprocess
import argparse

import exp_files

def do_chapter_tests(dirname: str):
    for root, dirs, files in os.walk(dirname):
        if os.path.basename(root) == "valid":
            for file in filter(lambda f: f.endswith(".c"), files):
                source_path = os.path.join(root, file)
                print(f"Running test {os.path.join(root, file)}:  ", end = "")
                compile_result = subprocess.run(["../occm.exe", source_path])
                if compile_result.returncode != 0:
                    print("FAILED! Compilation failed")
                    continue
                exec_path = file[:-2] + ".exe"
                exp_file_path = exp_files.exp_file_path_from_source_path(source_path)
                exp_file = exp_files.ExpFile(exp_file_path)
                run_result = subprocess.run([exec_path])
                if exp_file.exit_code == run_result.returncode:
                    print("PASSED!")
                else:
                    print(f"FAILED! Return codes do not match. Expected {exp_file.exit_code}, got {run_result.returncode}")
                os.remove(exec_path)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-high")
    parser.add_argument("-low")
    parser.add_argument("-only")
    args = parser.parse_args()

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

if __name__ == "__main__":
    main()
