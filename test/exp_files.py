import os

class ExpFile:
    def __init__(self, path):
        with open(path, "r") as f:
            lines = f.readlines()
        for line in lines:
            if line.startswith("exit_code: "):
                self.exit_code = int(line.strip("exit_code: "))
            elif line.startswith("stdout: "):
                self.stdout = line.strip("stdout: ")
            elif line.startswith("stderr: "):
                self.stderr = line.strip("stderr: ")

def exp_file_path_from_source_path(path: str) -> str:
    noext = os.path.splitext(path)[0]
    return f"{noext}.txt"

