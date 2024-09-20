package occm

// It's annoying that this is platform specific, but we need functions for executing gcc from within this process and Odin does not provide a cross-platform way of doing it.
import "core:fmt"
import "core:sys/windows"

run_command_as_process :: proc(format: string, args: ..any) -> (exit_code: i32) {
    command := fmt.aprintf(format, ..args)
    defer delete(command)
    command_wstring := windows.utf8_to_wstring(command)

    s_info: windows.STARTUPINFOW
    s_info.cb = size_of(s_info)
    p_info: windows.PROCESS_INFORMATION = ---

    windows.CreateProcessW(nil, command_wstring, nil, nil, true, 0, nil, nil, &s_info, &p_info)
    windows.WaitForSingleObject(p_info.hProcess, windows.INFINITE)

    e_code: u32 = ---
    windows.GetExitCodeProcess(p_info.hProcess, &e_code)
    windows.CloseHandle(p_info.hProcess)
    windows.CloseHandle(p_info.hThread)

    return transmute(i32)e_code
}

