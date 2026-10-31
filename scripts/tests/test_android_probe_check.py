"""관측 실행기의 오판정 회귀 검사. ADB와 시간 대기는 모두 대역으로 실행한다."""
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


class ProbeVerdictTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = tempfile.TemporaryDirectory(prefix="probe-verdict-test-")
        script = Path(__file__).resolve().parents[1] / "android-probe-check.py"

        def startup(command, **kwargs):
            values = {"ro.kernel.qemu": "1", "ro.build.version.sdk": "36", "sys.boot_completed": "1"}
            return subprocess.CompletedProcess(command, 0, values.get(command[-1], ""), "")

        argv = [str(script), "--serial", "mock-emulator", "--output", cls.output.name, "--allow-permission-changes"]
        with patch.object(sys, "argv", argv), patch("subprocess.run", side_effect=startup):
            cls.probe = runpy.run_path(str(script), run_name="probe_verdict_test")

    @classmethod
    def tearDownClass(cls):
        cls.output.cleanup()

    def revoked(self, receipts=0, denied=True, scheduled=True):
        wait = Mock(side_effect=lambda marker, *_: scheduled if marker == "ALARM_SCHEDULED at=" else denied)
        launch = Mock()
        adb = Mock()
        bindings = {"allowed": Mock(), "launch": launch, "adb": adb, "wait_for": wait,
                    "delta": lambda _: ["ALARM_RECEIVED"] * receipts,
                    "time": SimpleNamespace(sleep=Mock())}
        with patch.dict(self.probe["revoked"].__globals__, bindings):
            result = self.probe["revoked"]("cursor")
        return result, launch, adb

    def task_removed(self, screen=False, received=True, removed=True):
        task = "* Task{abc #42 A=123:io.github.hye6k.morning_routine U=0}"
        dumps = iter([task, "" if removed else task])

        def adb(*args, **kwargs):
            value = next(dumps) if args[:4] == ("shell", "dumpsys", "activity", "activities") else ""
            return SimpleNamespace(stdout=value)

        bindings = {"allowed": Mock(), "launch": Mock(), "adb": Mock(side_effect=adb),
                    "wait_for": Mock(side_effect=[True, received]),
                    "delta": lambda _: ["ACTIVITY_SIGNAL android.intent.action.SCREEN_ON"] if screen else [],
                    "time": SimpleNamespace(sleep=Mock())}
        with patch.dict(self.probe["task_removed"].__globals__, bindings):
            return self.probe["task_removed"]("cursor")

    def test_revoked_passes_with_no_receipt_and_new_schedule_denied(self):
        result, _, _ = self.revoked()
        self.assertTrue(result[0])
        self.assertEqual(result[1]["receipts_after_revocation"], 0)

    def test_revoked_fails_if_existing_alarm_fires(self):
        result, _, _ = self.revoked(receipts=1)
        self.assertFalse(result[0])
        self.assertEqual(result[1]["receipts_after_revocation"], 1)

    def test_revoked_fails_if_new_schedule_is_not_denied(self):
        result, _, _ = self.revoked(denied=False)
        self.assertFalse(result[0])

    def test_revoked_requires_successful_initial_schedule(self):
        with self.assertRaisesRegex(RuntimeError, "예약 성공"):
            self.revoked(scheduled=False)

    def test_task_passes_when_removed_alarm_received_and_no_screen_signal(self):
        self.assertTrue(self.task_removed()[0])

    def test_task_fails_if_screen_signal_is_received(self):
        result = self.task_removed(screen=True)
        self.assertFalse(result[0])
        self.assertTrue(result[1]["screen_signal_after_task_removal"])

    def test_task_fails_if_alarm_is_not_received(self):
        self.assertFalse(self.task_removed(received=False)[0])

    def test_task_fails_if_task_is_still_present(self):
        self.assertFalse(self.task_removed(removed=False)[0])

    def test_task_requires_successful_initial_schedule(self):
        function = self.probe["task_removed"]
        adb = Mock()
        with patch.dict(function.__globals__, {"allowed": Mock(), "launch": Mock(), "wait_for": Mock(return_value=False), "adb": adb}):
            with self.assertRaisesRegex(RuntimeError, "예약 성공"):
                function("cursor")
        adb.assert_not_called()


if __name__ == "__main__":
    unittest.main()
