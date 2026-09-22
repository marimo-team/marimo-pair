from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import BytesIO, StringIO
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

ROOT = Path(__file__).parents[1]
SCRIPTS = ROOT / "skills" / "marimo-pair" / "scripts"


def load_script(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


discover = load_script("discover_servers")
execute = load_script("execute_code")


class FakeResponse:
    def __init__(self, lines: list[bytes]) -> None:
        self.lines = lines

    def __enter__(self):
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def __iter__(self):
        return iter(self.lines)


class DiscoverServersTests(unittest.TestCase):
    def test_tasklist_parser_tolerates_non_utf8_localized_columns(self) -> None:
        output = (
            b'"Secure System","212","Services","0","76\xff232 K"\r\n'
            b'"python.exe","28488","Console","1","10 K"\r\n'
        )
        self.assertEqual(discover.parse_tasklist_process_ids(output), {212, 28488})

    def test_local_wildcard_uses_loopback(self) -> None:
        hosts = list(discover.candidate_hosts("0.0.0.0", 2718, "local", set()))
        self.assertEqual(hosts, ["127.0.0.1"])

    def test_windows_host_prefers_specific_address_then_gateway(self) -> None:
        with patch.object(discover, "wsl_gateway", return_value="172.20.0.1"):
            hosts = list(
                discover.candidate_hosts(
                    "192.168.1.10",
                    2718,
                    "windows-host",
                    set(),
                )
            )
        self.assertEqual(hosts, ["192.168.1.10", "172.20.0.1"])

    def test_windows_loopback_skipped_when_local_server_owns_port(self) -> None:
        with patch.object(discover, "wsl_gateway", return_value=None):
            hosts = list(
                discover.candidate_hosts(
                    "127.0.0.1",
                    2718,
                    "windows-host",
                    {2718},
                )
            )
        self.assertEqual(hosts, [])

    def test_private_ipv4_matches_shell_ranges(self) -> None:
        self.assertTrue(discover.is_private_ipv4("172.31.255.255"))
        self.assertTrue(discover.is_private_ipv4("169.254.1.1"))
        self.assertFalse(discover.is_private_ipv4("172.32.0.1"))
        self.assertFalse(discover.is_private_ipv4("192.0.0.1"))

    def test_main_deletes_entry_only_when_process_is_definitely_dead(self) -> None:
        for alive, should_exist in ((False, False), (None, True)):
            with self.subTest(alive=alive), tempfile.TemporaryDirectory() as temp_dir:
                registry_file = Path(temp_dir) / "server.json"
                registry_file.write_text("{}", encoding="utf-8")
                entry = (registry_file, "local", {"pid": 123, "port": 2718})
                with (
                    patch.object(discover, "load_entries", return_value=[entry]),
                    patch.object(discover, "process_alive", return_value=alive),
                    patch.object(discover, "resolve_url", return_value=None),
                    redirect_stdout(StringIO()),
                ):
                    self.assertEqual(discover.main(), 0)
                self.assertEqual(registry_file.exists(), should_exist)

    def test_main_keeps_reachable_server_when_pid_is_dead(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            registry_file = Path(temp_dir) / "server.json"
            registry_file.write_text("{}", encoding="utf-8")
            metadata = {
                "server_id": "127.0.0.1:2718",
                "pid": 123,
                "port": 2718,
                "started_at": "now",
                "version": "1.0",
            }
            output = StringIO()
            with (
                patch.object(
                    discover,
                    "load_entries",
                    return_value=[(registry_file, "local", metadata)],
                ),
                patch.object(discover, "process_alive", return_value=False),
                patch.object(
                    discover,
                    "resolve_url",
                    return_value="http://127.0.0.1:2718",
                ),
                redirect_stdout(output),
            ):
                discover.main()
            self.assertTrue(registry_file.exists())
            self.assertEqual(
                json.loads(output.getvalue())[0]["url"],
                "http://127.0.0.1:2718",
            )


class ExecuteCodeTests(unittest.TestCase):
    def test_wsl_detection_does_not_treat_normal_linux_as_wsl(self) -> None:
        with (
            patch.dict(execute.os.environ, {}, clear=True),
            patch.object(
                execute.Path,
                "read_text",
                return_value="Linux version 6.12.0-generic",
            ),
        ):
            self.assertFalse(execute.is_wsl())

    def test_wsl_detection_accepts_microsoft_kernel_marker(self) -> None:
        with (
            patch.dict(execute.os.environ, {}, clear=True),
            patch.object(
                execute.Path,
                "read_text",
                return_value="Linux version 6.6.87.2-microsoft-standard-WSL2",
            ),
        ):
            self.assertTrue(execute.is_wsl())

    def test_authorization_header_is_optional(self) -> None:
        self.assertEqual(execute.authorization_headers(""), {})
        self.assertEqual(
            execute.authorization_headers("secret"),
            {"Authorization": "Bearer secret"},
        )

    def test_file_selector_matches_path_or_filename(self) -> None:
        sessions = {
            "first": {"path": "/work/one.py", "filename": "one.py"},
            "second": {"path": "/work/two.py", "filename": "two.py"},
        }
        with patch.object(execute, "request_json", return_value=sessions):
            self.assertEqual(
                execute.resolve_session("http://localhost", {}, "two.py", None),
                "second",
            )

    def test_multiple_sessions_require_a_selector(self) -> None:
        sessions = {"first": {"path": "one.py"}, "second": {"path": "two.py"}}
        with (
            patch.object(execute, "request_json", return_value=sessions),
            self.assertRaisesRegex(SystemExit, "Multiple sessions on server"),
        ):
            execute.resolve_session("http://localhost", {}, None, None)

    def test_execute_routes_sse_and_sends_session_header(self) -> None:
        lines = [
            b"event: stdout\r\n",
            b'data: {"data": "hello\\n"}\r\n',
            b"\r\n",
            b"event: stderr\n",
            b'data: {"data": "warning\\n"}\n',
            b"\n",
            b"event: done\n",
            b'data: {"success": true, "output": {"data": "42"}}\n',
        ]
        stdout = StringIO()
        stderr = StringIO()
        with (
            patch.object(execute.urllib.request, "urlopen", return_value=FakeResponse(lines))
            as urlopen,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            success = execute.execute(
                "http://localhost:2718",
                {"Authorization": "Bearer secret"},
                "session-id",
                "6 * 7",
            )

        self.assertTrue(success)
        self.assertEqual(stdout.getvalue(), "hello\n42\n")
        self.assertEqual(stderr.getvalue(), "warning\n")
        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("Marimo-session-id"), "session-id")
        self.assertEqual(request.get_header("Authorization"), "Bearer secret")
        self.assertEqual(json.loads(request.data), {"code": "6 * 7"})

    def test_execute_fails_when_stream_has_no_done_event(self) -> None:
        response = FakeResponse([b"event: stdout\n", b'data: {"data": "partial"}\n'])
        stderr = StringIO()
        with (
            patch.object(execute.urllib.request, "urlopen", return_value=response),
            redirect_stdout(StringIO()),
            redirect_stderr(stderr),
        ):
            success = execute.execute(
                "http://localhost",
                {},
                "session-id",
                "1",
                "retry with the stable selector",
            )
        self.assertFalse(success)
        self.assertIn("ended the stream without a result", stderr.getvalue())
        self.assertIn("retry with the stable selector", stderr.getvalue())

    def test_execute_http_error_includes_stale_session_hint(self) -> None:
        error = execute.urllib.error.HTTPError(
            "http://localhost/api/kernel/execute",
            400,
            "Bad Request",
            hdrs=None,
            fp=BytesIO(b'{"detail":"Invalid session id"}'),
        )
        stderr = StringIO()
        with (
            patch.object(execute.urllib.request, "urlopen", side_effect=error),
            redirect_stderr(stderr),
        ):
            success = execute.execute(
                "http://localhost",
                {},
                "stale-session",
                "1",
                "Retry without --session.",
            )
        self.assertFalse(success)
        self.assertIn("Invalid session id", stderr.getvalue())
        self.assertIn("Retry without --session.", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()