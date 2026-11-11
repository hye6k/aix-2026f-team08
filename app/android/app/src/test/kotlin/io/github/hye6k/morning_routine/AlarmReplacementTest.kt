package io.github.hye6k.morning_routine

import org.junit.Assert.*
import org.junit.Test

class AlarmReplacementTest {
    private class Backend(previous: AlarmSlot? = null) : AlarmReplacementBackend {
        var slot = previous
        val arms = mutableSetOf<AlarmSlot>()
        val calls = mutableListOf<String>()
        var allowed = true
        var failArmAt: Long? = null
        var failWriteAt: Long? = null
        var failCancelAt: Long? = null
        var failRestore = false
        var stopped = false
        init { if (previous?.state == "scheduled") arms.add(previous) }
        override fun permitted() = allowed
        override fun read(id: String) = slot
        override fun arm(slot: AlarmSlot) {
            calls.add("arm:${slot.atMillis}")
            if (slot.atMillis == failArmAt) throw IllegalStateException("OS failure")
            arms.add(slot)
        }
        override fun cancel(slot: AlarmSlot) {
            calls.add("cancel:${slot.atMillis}")
            if (slot.atMillis == failCancelAt) throw IllegalStateException("cancel failure")
            arms.remove(slot)
        }
        override fun write(slot: AlarmSlot) {
            calls.add("write:${slot.atMillis}")
            this.slot = slot // SharedPreferences의 메모리 갱신 후 저장 실패도 재현한다.
            if (slot.atMillis == failWriteAt || (failRestore && slot.atMillis == 100L)) throw IllegalStateException("disk failure")
        }
        override fun remove(id: String) { slot = null }
        override fun stopRinging(id: String) { stopped = true }
    }
    private val old = AlarmSlot("wake", 100)
    private fun replacement(b: Backend) = AlarmReplacement(b) { 0 }
    private fun fails(action: () -> Unit): AlarmReplacementFailure {
        try { action(); fail("실패해야 합니다.") } catch (error: AlarmReplacementFailure) { return error }
        throw AssertionError()
    }
    @Test fun newReservationCommitsBeforeOldCancellation() {
        val b=Backend(old); replacement(b).schedule("wake",200)
        assertEquals(setOf(AlarmSlot("wake",200)),b.arms)
        assertTrue(b.calls.indexOf("write:200") < b.calls.indexOf("cancel:100"))
        assertTrue(b.stopped)
    }
    @Test fun failedNewArmPreservesPreviousAlarm() {
        val b=Backend(old); b.failArmAt=200
        fails { replacement(b).schedule("wake",200) }
        assertEquals(setOf(old),b.arms); assertEquals(old,b.slot); assertFalse(b.stopped)
    }
    @Test fun failedSnoozeKeepsRinging() {
        val ringing=old.copy(state="ringing"); val b=Backend(ringing); b.failArmAt=200
        fails { replacement(b).schedule("wake",200) }
        assertEquals(ringing,b.slot); assertFalse(b.stopped)
    }
    @Test fun failedStateCommitCancelsOnlyNewReservation() {
        val b=Backend(old); b.failWriteAt=200
        fails { replacement(b).schedule("wake",200) }
        assertEquals(setOf(old),b.arms); assertEquals(old,b.slot); assertFalse(b.stopped)
    }
    @Test fun sameTimeFailureDoesNotCancelTheOriginalToken() {
        val b=Backend(old); b.failWriteAt=100
        fails { replacement(b).schedule("wake",100) }
        assertEquals(setOf(old),b.arms); assertFalse(b.calls.contains("cancel:100"))
    }
    @Test fun deniedPermissionDoesNotTouchOldRinging() {
        val b=Backend(old.copy(state="ringing")); b.allowed=false
        try { replacement(b).schedule("wake",200); fail() } catch (_: SecurityException) { }
        assertFalse(b.stopped); assertTrue(b.calls.isEmpty())
    }
    @Test fun legacyTokenIsRetiredOnlyAfterVersionTwoIsCommitted() {
        val previous=old.copy(tokenVersion=1); val b=Backend(previous)
        replacement(b).schedule("wake",200)
        assertEquals(2,b.slot!!.tokenVersion); assertEquals(setOf(AlarmSlot("wake",200)),b.arms)
    }
    @Test fun failureToCleanOldTokenDoesNotRemoveCommittedNewAlarm() {
        val b=Backend(old); b.failCancelAt=100
        assertEquals(1,replacement(b).schedule("wake",200).size)
        assertEquals(200,b.slot!!.atMillis); assertTrue(b.arms.contains(AlarmSlot("wake",200))); assertTrue(b.stopped)
    }
    @Test fun recoveryFailureIsExposed() {
        val b=Backend(old); b.failWriteAt=200; b.failRestore=true
        val error=fails { replacement(b).schedule("wake",200) }
        assertEquals(1,error.recoveryErrors.size); assertFalse(b.stopped)
    }
    @Test fun expiredRequestDoesNotTouchPreviousReservation() {
        val b=Backend(old)
        try { replacement(b).schedule("wake",0); fail() } catch (_: IllegalArgumentException) { }
        assertEquals(setOf(old),b.arms); assertTrue(b.calls.isEmpty())
    }
}
