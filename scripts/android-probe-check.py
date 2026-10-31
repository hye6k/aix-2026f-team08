import argparse
import json
import re
import tempfile
import subprocess
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser(description='개발 전용 Android 가상 기기의 화면 신호·알람 관측')
parser.add_argument('--serial', required=True, help='adb devices에서 확인한 가상 기기 ID')
parser.add_argument('--output', type=Path, help='관측 결과를 저장할 폴더')
parser.add_argument('--allow-permission-changes', action='store_true', help='검증 앱의 알람·알림 권한 변경과 종료 실험 허용')
parser.add_argument('--include-reboot', action='store_true', help='선택한 가상 기기의 재부팅 관측 포함')
args = parser.parse_args()
if not args.allow_permission_changes:
    parser.error('--allow-permission-changes가 필요합니다. 검증 앱의 권한 변경·종료 실험을 수행합니다.')
ROOT = args.output or Path(tempfile.mkdtemp(prefix='aix-android-probe-'))
ROOT.mkdir(parents=True, exist_ok=True)
PKG = 'io.github.hye6k.morning_routine'
SERIAL = args.serial
ADB = ['adb', '-s', SERIAL]
cases = []
started = datetime.now(ZoneInfo('Asia/Seoul')).isoformat()

def adb(*args, check=True, timeout=25):
    p = subprocess.run(ADB + list(args), text=True, capture_output=True, timeout=timeout)
    if check and p.returncode:
        raise RuntimeError(f'{args}: {p.stderr.strip()} {p.stdout.strip()}')
    return p

virtual = adb('shell', 'getprop', 'ro.kernel.qemu').stdout.strip()
if virtual != '1':
    raise SystemExit('자동 권한 변경·종료 실험은 Android 가상 기기에서만 실행합니다. 실기기는 수동 절차를 사용하세요.')
sdk = int(adb('shell', 'getprop', 'ro.build.version.sdk').stdout.strip())
if sdk < 33:
    raise SystemExit('이 자동 관측 절차는 API 33 이상용입니다. 이전 API는 수동 절차를 사용하세요.')
if adb('shell', 'getprop', 'sys.boot_completed').stdout.strip() != '1':
    raise SystemExit('가상 기기 부팅이 완료되지 않았습니다.')
adb('shell', 'run-as', PKG, 'id')

def events():
    p = adb('shell', 'run-as', PKG, 'cat', 'shared_prefs/android_probe.xml', check=False)
    if p.returncode:
        if 'No such file' in p.stderr or 'No such file' in p.stdout:
            return []
        raise RuntimeError(p.stderr + p.stdout)
    node = ET.fromstring(p.stdout).find("string[@name='events']")
    return json.loads(node.text) if node is not None else []

def launch(action=None, seconds=6):
    args = ['shell', 'am', 'start', '-W', '-n', PKG + '/.ProbeActivity']
    if action:
        args += ['--es', 'action', action, '--ei', 'delay_seconds', str(seconds)]
    p = adb(*args)
    if 'Status: timeout' in p.stdout:
        raise RuntimeError('Activity 시작 시간 초과: ' + p.stdout)

def allowed(exact=True, notification=True):
    adb('shell', 'appops', 'set', PKG, 'SCHEDULE_EXACT_ALARM', 'allow' if exact else 'deny')
    adb('shell', 'pm', 'grant' if notification else 'revoke', PKG, 'android.permission.POST_NOTIFICATIONS')

def delta(before):
    log = events()
    if before is None:
        return log
    for index in range(len(log) - 1, -1, -1):
        if log[index] == before:
            return log[index + 1:]
    raise RuntimeError('관측 기준 로그가 사라져 판정할 수 없습니다.')

def wait_for(marker, before, timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(marker in s for s in delta(before)):
            return True
        time.sleep(1)
    return False

def record(key, title, passed, before, details=None):
    case = {'key': key, 'title': title, 'passed': passed, 'details': details or {}, 'events': delta(before)}
    cases.append(case)
    payload = {'started_at_kst': started, 'device': SERIAL, 'virtual_device': True, 'physical_sound_vibration_verified': False, 'cases': cases}
    (ROOT / 'probe-results.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    print(f'{key}: {"PASS" if passed else "FAIL"} {title}', flush=True)

def check_case(key, title, fn):
    log = events()
    before = log[-1] if log else None
    try:
        passed, details = fn(before)
        record(key, title, passed, before, details)
    except Exception as error:
        try:
            record(key, title, False, before, {'error': str(error)})
        except Exception:
            cases.append({'key': key, 'title': title, 'passed': False, 'details': {'error': str(error)}})
            (ROOT / 'probe-results.json').write_text(json.dumps({'started_at_kst': started, 'cases': cases}, ensure_ascii=False, indent=2) + '\n')
            print(f'{key}: ERROR {error}', flush=True)

def background_app():
    adb('shell', 'input', 'keyevent', '3')
    time.sleep(2)
    data = adb('shell', 'dumpsys', 'activity', 'activities').stdout
    rows = [line.strip() for line in data.splitlines() if 'topResumedActivity=' in line]
    if not rows or any(PKG in line for line in rows):
        raise RuntimeError('백그라운드 전환을 확인하지 못함: ' + str(rows))
    return rows

def screen(before, background=False):
    launch()
    if background:
        foreground = background_app()
    adb('shell', 'input', 'keyevent', '223')
    time.sleep(1)
    adb('shell', 'input', 'keyevent', '224')
    return wait_for('ACTIVITY_SIGNAL android.intent.action.SCREEN_ON', before, 12), {'background': background, 'foreground_activity': foreground if background else None}

def denied(before):
    allowed(exact=False, notification=False)
    launch('schedule')
    observed = wait_for('EXACT_ALARM_PERMISSION_DENIED', before, 5)
    time.sleep(7)
    return observed and not any('ALARM_RECEIVED' in s for s in delta(before)), {}

def alarm(before, background=False):
    allowed()
    launch('schedule')
    if background:
        foreground = background_app()
    return wait_for('ALARM_RECEIVED', before), {'background': background, 'foreground_activity': foreground if background else None}

def cancel(before):
    allowed()
    launch('schedule', 8)
    launch('cancel')
    time.sleep(10)
    log = delta(before)
    return any('ALARM_CANCELLED' in s for s in log) and not any('ALARM_RECEIVED' in s for s in log), {'window_seconds': 10, 'scheduled_delay_seconds': 8}

def replace(before):
    allowed()
    launch('schedule', 6)
    launch('schedule', 14)
    time.sleep(8)
    early = sum('ALARM_RECEIVED' in s for s in delta(before))
    received = wait_for('ALARM_RECEIVED', before, 15)
    time.sleep(2)
    count = sum('ALARM_RECEIVED' in s for s in delta(before))
    return early == 0 and received and count == 1, {'old_delay': 6, 'new_delay': 14, 'early_receipts': early, 'total_receipts': count}

def process_kill(before):
    allowed()
    launch('schedule', 15)
    foreground = background_app()
    old = adb('shell', 'pidof', PKG, check=False).stdout.strip()
    adb('shell', 'am', 'kill', PKG)
    time.sleep(1)
    killed = not adb('shell', 'pidof', PKG, check=False).stdout.strip()
    received = wait_for('ALARM_RECEIVED', before, 25)
    new = adb('shell', 'pidof', PKG, check=False).stdout.strip()
    return killed and received, {'old_pid': old, 'absent_after_kill': killed, 'new_pid': new, 'foreground_activity': foreground}

def force_stop(before):
    allowed()
    launch('schedule', 8)
    adb('shell', 'input', 'keyevent', '3')
    adb('shell', 'am', 'force-stop', PKG)
    time.sleep(11)
    received = sum('ALARM_RECEIVED' in s for s in delta(before))
    scheduled = sum('ALARM_SCHEDULED' in event for event in delta(before))
    return received == 0 and scheduled == 1, {'scheduled_command_count': scheduled, 'expected_observation': '강제 종료 뒤 예약 알람 미수신', 'receipts': received, 'window_seconds': 11}

def no_notification(before):
    allowed(notification=False)
    launch('schedule')
    received = wait_for('ALARM_RECEIVED', before)
    denied = wait_for('NOTIFICATION_PERMISSION_DENIED', before, 5)
    return received and denied, {}

def revoked(before):
    allowed()
    launch('schedule', 8)
    if not wait_for('ALARM_SCHEDULED at=', before, 5):
        raise RuntimeError('예약 성공을 확인하지 못해 권한 철회 실험을 중단합니다.')
    adb('shell', 'appops', 'set', PKG, 'SCHEDULE_EXACT_ALARM', 'deny')
    time.sleep(11)
    count = sum('ALARM_RECEIVED' in s for s in delta(before))
    launch('schedule')
    denied = wait_for('EXACT_ALARM_PERMISSION_DENIED', before, 5)
    return denied and count == 0, {'receipts_after_revocation': count, 'control': 'ADB appops 변경, 수동 설정 화면 조작과 구분'}

def task_removed(before):
    allowed()
    launch('schedule', 18)
    if not wait_for('ALARM_SCHEDULED at=', before, 5):
        raise RuntimeError('예약 성공을 확인하지 못해 Task 제거 실험을 중단합니다.')
    data = adb('shell', 'dumpsys', 'activity', 'activities').stdout
    ids = set(re.findall(r'\* Task\{[^\n]*?#(\d+)[^\n]*?A=\d+:io\.github\.hye6k\.morning_routine\b', data))
    if len(ids) != 1:
        raise RuntimeError('검증 앱의 단일 Task를 식별하지 못했습니다.')
    task = next(iter(ids))
    adb('shell', 'am', 'stack', 'remove', task)
    time.sleep(2)
    after = adb('shell', 'dumpsys', 'activity', 'activities').stdout
    gone = not re.search(r'\* Task\{[^\n]*?#' + task + r'\b', after)
    adb('shell', 'input', 'keyevent', '223'); time.sleep(1)
    adb('shell', 'input', 'keyevent', '224'); time.sleep(2)
    screen = any('ACTIVITY_SIGNAL android.intent.action.SCREEN_ON' in event for event in delta(before))
    received = wait_for('ALARM_RECEIVED', before, 28)
    return gone and received and not screen, {'control': 'ADB am stack remove, 화면 스와이프와 구분', 'task_id': task, 'task_removed': gone, 'screen_signal_after_task_removal': screen}

def rebooted(before):
    allowed()
    launch('schedule', 15)
    if not wait_for('ALARM_SCHEDULED at=', before, 5):
        raise RuntimeError('예약 성공을 확인하지 못해 재부팅 실험을 중단합니다.')
    scheduled = [event for event in delta(before) if 'ALARM_SCHEDULED at=' in event]
    target = int(scheduled[-1].split('at=')[1])
    adb('reboot')
    adb('wait-for-disconnect', timeout=30)
    adb('wait-for-device', timeout=90)
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline:
        if adb('shell', 'getprop', 'sys.boot_completed', check=False, timeout=5).stdout.strip() == '1':
            break
        time.sleep(2)
    else:
        raise RuntimeError('재부팅 완료를 확인하지 못했습니다.')
    now = int(adb('shell', 'date', '+%s').stdout.strip())
    remaining = max(0, target / 1000 - now + 5)
    time.sleep(min(remaining, 30))
    receipts = sum('ALARM_RECEIVED' in event for event in delta(before))
    return receipts == 0, {'boot_completed': True, 'expected_observation': '재부팅 후 자동 재예약 미구현', 'receipts_after_reboot': receipts}

if __name__ == '__main__':
    launch()
    check_case('screen_foreground', '전면 화면 켜짐 신호 수신', screen)
    check_case('exact_permission_denied', '정확한 알람 권한 거부 시 예약 차단', denied)
    check_case('alarm_foreground', '전면 예약 알람 수신', alarm)
    check_case('screen_background', 'Activity가 유지된 백그라운드 화면 신호', lambda before: screen(before, True))
    check_case('alarm_background', '백그라운드 예약 알람 수신', lambda before: alarm(before, True))
    check_case('alarm_cancel', '예약 취소 뒤 관측 구간 내 미수신', cancel)
    check_case('alarm_replace', '동일 PendingIntent 예약 변경 후 1회 수신', replace)
    check_case('alarm_process_killed', '백그라운드 프로세스 제거 뒤 알람 수신', process_kill)
    check_case('alarm_force_stopped', '강제 종료 뒤 예약 알람 미수신 관측', force_stop)
    check_case('notification_denied', '알림 거부 상태의 알람 수신과 거부 로그', no_notification)
    check_case('exact_permission_revoked', '정확한 알람 권한 철회 뒤 예약 차단', revoked)
    check_case('alarm_task_removed', 'Task 제거 뒤 알람과 화면 신호 관측', task_removed)
    if args.include_reboot:
        check_case('alarm_reboot', '재부팅 뒤 알람 자동 복원 여부 관측', rebooted)
    allowed()
    launch('cancel')
    print('결과 폴더: ' + str(ROOT), flush=True)
    print('완료: ' + str(sum(bool(c['passed']) for c in cases)) + '/' + str(len(cases)), flush=True)

    if any(not case.get('passed') for case in cases):
        raise SystemExit(1)
