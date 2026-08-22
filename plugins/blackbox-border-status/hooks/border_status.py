#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import time


APP_ID = "com.raggesilver.BlackBox"
STATES = {
    "UserPromptSubmit": ("#00FFFF", True, "persistent"),
    "PermissionRequest": ("#FFFF00", False, "resettable_on_focus"),
    "Stop": ("#00FF00", False, "resettable_on_focus"),
}
ATTENTION_STATE = ("#FFFF00", False, "resettable_on_focus")
ABORTED_STATE = ("#FF0000", False, "resettable_on_focus")


def parent_pid(pid: int) -> int:
    try:
        with open(f"/proc/{pid}/status", encoding="utf-8") as status:
            for line in status:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def blackbox_terminal_pid() -> int:
    child = os.getpid()
    pid = os.getppid()

    while pid > 1:
        try:
            with open(f"/proc/{pid}/comm", encoding="utf-8") as comm:
                if comm.read().strip() == "blackbox":
                    return child
        except OSError:
            return 0

        child, pid = pid, parent_pid(pid)

    return 0


def run_action(action: str, parameter: str) -> None:
    try:
        subprocess.run(
            [
                "/usr/bin/gapplication",
                "action",
                APP_ID,
                action,
                parameter,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def set_border(terminal_pid: int, state: tuple[str, bool, str]) -> None:
    color, animate, border_type = state
    parameter = "(%d, '%s', %s, '%s')" % (
        terminal_pid,
        color,
        str(animate).lower(),
        border_type,
    )
    run_action("set-terminal-border", parameter)


def notify_attention(terminal_pid: int, body: str) -> None:
    run_action(
        "notify-codex-attention",
        "(%d, '%s')" % (terminal_pid, body),
    )


def watch_abort(data: dict) -> None:
    transcript_path = data.get("transcript_path")
    turn_id = data.get("turn_id")
    terminal_pid = blackbox_terminal_pid()
    if not transcript_path or not turn_id or not terminal_pid:
        return

    try:
        with open(transcript_path, encoding="utf-8") as transcript:
            while True:
                position = transcript.tell()
                line = transcript.readline()
                if not line or not line.endswith("\n"):
                    transcript.seek(position)
                    time.sleep(0.1)
                    continue

                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                payload = entry.get("payload", {})
                entry_turn_id = payload.get("turn_id") or payload.get(
                    "internal_chat_message_metadata_passthrough", {}
                ).get("turn_id")
                if entry_turn_id != turn_id:
                    continue
                if (
                    entry.get("type") == "response_item"
                    and payload.get("type") == "function_call"
                    and payload.get("name") == "request_user_input"
                ):
                    set_border(terminal_pid, ATTENTION_STATE)
                    notify_attention(terminal_pid, "Codex is waiting for input.")
                elif entry.get("type") != "event_msg":
                    continue
                elif payload.get("type") == "turn_aborted":
                    set_border(terminal_pid, ABORTED_STATE)
                    return
                elif payload.get("type") == "task_complete":
                    return
    except OSError:
        return


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, AttributeError):
        data = {}

    if sys.argv[1:] == ["--watch-abort"]:
        watch_abort(data)
    else:
        event = data.get("hook_event_name")
        state = STATES.get(event)
        terminal_pid = blackbox_terminal_pid()
        if state is not None and terminal_pid:
            set_border(terminal_pid, state)
            if event == "PermissionRequest":
                notify_attention(terminal_pid, "Codex needs permission.")
            elif event == "Stop":
                run_action("notify-turn-finished", str(terminal_pid))

    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
