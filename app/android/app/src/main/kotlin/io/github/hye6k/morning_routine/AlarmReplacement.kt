package io.github.hye6k.morning_routine

internal data class AlarmSlot(
    val id: String,
    val atMillis: Long,
    val state: String = "scheduled",
    val tokenVersion: Int = 2,
) {
    fun sameToken(other: AlarmSlot) = id == other.id && atMillis == other.atMillis && tokenVersion == other.tokenVersion
}

internal interface AlarmReplacementBackend {
    fun permitted(): Boolean
    fun read(id: String): AlarmSlot?
    fun arm(slot: AlarmSlot)
    fun cancel(slot: AlarmSlot)
    fun write(slot: AlarmSlot)
    fun remove(id: String)
    fun stopRinging(id: String)
}

internal class AlarmReplacementFailure(cause: Exception, val recoveryErrors: List<Exception>) : Exception("알람 변경 실패", cause)

/** 새 OS 예약과 상태 저장이 끝나기 전에는 이전 예약·울림을 취소하지 않는다. */
internal class AlarmReplacement(private val backend: AlarmReplacementBackend, private val now: () -> Long) {
    fun schedule(id: String, at: Long): List<Exception> {
        require(id.isNotBlank() && id.length <= 128)
        require(at > now()) { "알람은 미래 시각이어야 합니다." }
        if (!backend.permitted()) throw SecurityException("알림·정확한 알람 권한을 확인하세요.")
        val previous = backend.read(id)
        val next = AlarmSlot(id, at)
        try {
            backend.arm(next)
            backend.write(next)
        } catch (error: Exception) {
            val failures = mutableListOf<Exception>()
            // 동일 토큰 재적용 실패에서 기존 예약 자체를 지우지 않는다.
            if (previous == null || !next.sameToken(previous)) {
                try { backend.cancel(next) } catch (failure: Exception) { failures.add(failure) }
            }
            try {
                if (previous != null) backend.write(previous) else backend.remove(id)
            } catch (failure: Exception) { failures.add(failure) }
            throw AlarmReplacementFailure(error, failures)
        }
        // 이 시점부터 새 예약이 유효하다. 이전 토큰 정리 실패가 새 예약을 취소해서는 안 된다.
        val warnings = mutableListOf<Exception>()
        if (previous != null && !next.sameToken(previous)) {
            try { backend.cancel(previous) } catch (error: Exception) { warnings.add(error) }
        }
        try { backend.stopRinging(id) } catch (error: Exception) { warnings.add(error) }
        return warnings
    }
}
