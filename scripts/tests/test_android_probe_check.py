"""관측 실행기의 오판정 회귀 검사. ADB와 시간 대기는 모두 대역으로 실행한다."""
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, call, patch


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

    def reservation_case(self, name, first_ok=True, second_ok=True, receipts=0,
                         cancelled=True, stale_second=False, early=False):
        log = ["cursor"]
        first_event = "100 ALARM_SCHEDULED at=6000"
        launch = Mock()
        waits = []

        def launch_action(action, seconds=None):
            launch(action, seconds)
            if action == "cancel":
                if cancelled:
                    log.append("300 ALARM_CANCELLED")
            elif seconds in (6, 8) and first_ok:
                log.append(first_event)
            elif seconds == 14:
                if second_ok:
                    log.append("200 ALARM_SCHEDULED at=14000")
                elif stale_second:
                    log.append("200 EXACT_ALARM_PERMISSION_DENIED")

        def delta(cursor):
            return log[log.index(cursor) + 1:] if cursor is not None else list(log)

        def wait(marker, cursor, *args):
            waits.append((marker, cursor))
            if marker == "ALARM_RECEIVED":
                if receipts:
                    log.extend(["400 ALARM_RECEIVED"] * receipts)
                return bool(receipts)
            return any(marker in event for event in delta(cursor))

        def sleep(seconds):
            if name == "cancel" and seconds == 10 and receipts:
                log.extend(["400 ALARM_RECEIVED"] * receipts)
            if name == "replace" and seconds == 8 and early:
                log.append("350 ALARM_RECEIVED")

        self.reservation_launch = launch
        function = self.probe[name]
        bindings = {"allowed": Mock(), "launch": launch_action,
                    "delta": delta, "events": lambda: list(log),
                    "wait_for": wait, "time": SimpleNamespace(sleep=sleep)}
        with patch.dict(function.__globals__, bindings):
            result = function("cursor")
        return result, launch, waits

    def test_cancel_requires_successful_initial_schedule(self):
        with self.assertRaisesRegex(RuntimeError, "예약 성공"):
            self.reservation_case("cancel", first_ok=False)
        self.assertEqual(self.reservation_launch.call_args_list, [call("schedule", 8)])

    def test_cancel_passes_after_successful_schedule_and_no_receipt(self):
        result, _, _ = self.reservation_case("cancel")
        self.assertTrue(result[0])

    def test_cancel_fails_if_alarm_still_fires(self):
        result, _, _ = self.reservation_case("cancel", receipts=1)
        self.assertFalse(result[0])

    def test_cancel_fails_without_cancel_log(self):
        result, _, _ = self.reservation_case("cancel", cancelled=False)
        self.assertFalse(result[0])

    def test_replace_requires_successful_first_schedule(self):
        with self.assertRaisesRegex(RuntimeError, "예약 성공"):
            self.reservation_case("replace", first_ok=False, second_ok=True, receipts=1)
        self.assertEqual(self.reservation_launch.call_args_list, [call("schedule", 6)])

    def test_replace_requires_successful_second_schedule(self):
        with self.assertRaisesRegex(RuntimeError, "예약 성공"):
            self.reservation_case("replace", second_ok=False, receipts=1)

    def test_replace_does_not_reuse_first_success_when_second_is_denied(self):
        with self.assertRaisesRegex(RuntimeError, "예약 성공"):
            self.reservation_case("replace", second_ok=False, stale_second=True, receipts=1)

    def test_replace_passes_with_two_schedules_and_one_late_receipt(self):
        result, _, waits = self.reservation_case("replace", receipts=1)
        self.assertTrue(result[0])
        scheduled = [cursor for marker, cursor in waits if marker == "ALARM_SCHEDULED at="]
        self.assertEqual(scheduled, ["cursor", "100 ALARM_SCHEDULED at=6000"])

    def test_replace_fails_if_old_alarm_fires_early(self):
        result, _, _ = self.reservation_case("replace", early=True, receipts=1)
        self.assertFalse(result[0])

    def test_replace_fails_if_new_alarm_never_fires(self):
        result, _, _ = self.reservation_case("replace")
        self.assertFalse(result[0])

    def test_replace_fails_on_duplicate_receipts(self):
        result, _, _ = self.reservation_case("replace", receipts=2)
        self.assertFalse(result[0])

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
