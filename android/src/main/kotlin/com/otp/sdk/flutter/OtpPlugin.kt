package com.otp.sdk.flutter

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.otp.sdk.CodeSubmission
import com.otp.sdk.OtpChannel
import com.otp.sdk.OtpClient
import com.otp.sdk.OtpException
import com.otp.sdk.OtpSession
import com.otp.sdk.OtpStatus
import com.otp.sdk.PendingOtp
import com.otp.sdk.RejectionReason
import com.otp.sdk.Verification
import com.otp.sdk.resumeInterrupted
import com.otp.sdk.ui.RecipientKind
import com.otp.sdk.verify
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * The Android half of the bridge.
 *
 * Nothing here decides anything about a verification: it converts arguments, calls the SDK, and
 * converts the answer. The counterpart on iOS is `OtpPlugin.swift`, and the two are deliberately the
 * same shape, because the contract they serve is one file of Dart.
 *
 * Stateless as far as Dart is concerned. The SDK holds a session, this maps it to the verification's
 * id, and an id with no session is one whose process outlived its Dart half: it is rebuilt from the
 * API rather than refused. A Dart hot restart is what causes that split, the same way a JavaScript
 * reload does on the React Native bridge.
 *
 * No `ActivityAware`: the SDK tracks the foreground activity itself, through its `OtpInitializer`
 * content provider, so this plugin only ever needs the application context.
 */
class OtpPlugin : FlutterPlugin, OtpHostApi {

    private lateinit var context: Context

    private val sessions = ConcurrentHashMap<UUID, OtpSession>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        OtpHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OtpHostApi.setUp(binding.binaryMessenger, null)
    }

    override suspend fun configure(publishableKey: String, baseUrl: String?) {
        answer { OtpClient.configure(context, publishableKey, baseUrl) }
    }

    // The presented screens. They are the reason this package exists: an app that builds its own on
    // the calls below has to rewrite six languages, right-to-left layout, the one-time-code autofill
    // and the WhatsApp handoff, all of which are already here.

    override suspend fun verify(recipient: String, locale: String?): VerificationMessage =
        answer { map(OtpClient.verify(recipient, locale)) }

    override suspend fun verifyCollecting(kind: String, locale: String?): VerificationMessage =
        answer {
            val collecting = recipientKind(kind)
                ?: throw Refusal("collecting must be \"phone\" or \"email\", not \"$kind\"")
            map(OtpClient.verify(collecting = collecting, locale = locale))
        }

    override suspend fun resumeInterrupted(): VerificationMessage? =
        answer { OtpClient.resumeInterrupted()?.let(::map) }

    // The core, for an app drawing its own screens.

    override suspend fun start(recipient: String, locale: String?): PendingOtpMessage =
        answer {
            val session = OtpSession()
            val pending = session.start(recipient, locale)
            sessions[pending.id] = session
            map(pending)
        }

    override suspend fun submit(otpId: String, code: String): CodeSubmissionMessage =
        answer {
            val id = uuid(otpId)
            val outcome = session(id).submit(code)
            if (outcome is CodeSubmission.Verified) sessions.remove(id)
            map(outcome)
        }

    override suspend fun resend(otpId: String, channel: String?): PendingOtpMessage =
        answer {
            val id = uuid(otpId)
            val requested = channel?.let {
                channel(it) ?: throw Refusal("$it is not a channel this build can name")
            }
            map(session(id).resend(requested))
        }

    override suspend fun resume(otpId: String): PendingOtpMessage =
        answer {
            val id = uuid(otpId)
            val session = OtpSession()
            val pending = session.resume(id, OtpClient.interrupted?.locale)
            sessions[id] = session
            map(pending)
        }

    override suspend fun interrupted(): InterruptedMessage? =
        answer {
            OtpClient.interrupted?.let {
                InterruptedMessage(otpId = it.otpId.toString(), expiresAt = iso(it.expiresAt), locale = it.locale)
            }
        }

    /**
     * Turns a failure into the one `FlutterError` shape Dart reads back.
     *
     * Every method above goes through here, so a failure cannot reach Dart as anything but the
     * documented exception. No scope of its own: the generated dispatcher already launches each call
     * in a coroutine on the main dispatcher, and the SDK's own calls dispatch their work from there.
     */
    private suspend fun <T> answer(body: suspend () -> T): T =
        try {
            body()
        } catch (refusal: Refusal) {
            throw FlutterError("validationFailed", refusal.message, null)
        } catch (error: OtpException) {
            throw FlutterError(code(error.kind), error.message ?: code(error.kind), details(error))
        }

    /**
     * The session for a verification, rebuilt when there is none.
     *
     * Dart survives its own hot restarts and the native side survives longer still, so an id can
     * arrive here for a verification this process has no session for. Reading it back from the API is
     * what the id is for.
     */
    private suspend fun session(id: UUID): OtpSession =
        sessions[id] ?: OtpSession().also {
            it.resume(id, OtpClient.interrupted?.locale)
            sessions[id] = it
        }

    /** An argument this bridge refused before the SDK ever saw it. */
    private class Refusal(override val message: String) : Exception(message)

    private companion object {
        /**
         * The kinds, spelled exactly as `OtpErrorKind` in `otp_flutter.dart`. The two lists are one
         * contract, and a value that does not appear on both sides reaches application code as
         * `unknown`.
         */
        fun code(kind: OtpException.Kind): String = when (kind) {
            OtpException.Kind.NOT_CONFIGURED -> "notConfigured"
            OtpException.Kind.UNAUTHORIZED -> "unauthorized"
            OtpException.Kind.DEVICE_PROOF_REJECTED -> "deviceProofRejected"
            OtpException.Kind.DEVICE_PROOF_UNSUPPORTED -> "deviceProofUnsupported"
            OtpException.Kind.NOT_FOUND -> "notFound"
            OtpException.Kind.CONFLICT -> "conflict"
            OtpException.Kind.VALIDATION_FAILED -> "validationFailed"
            OtpException.Kind.RATE_LIMITED -> "rateLimited"
            OtpException.Kind.UNAVAILABLE -> "unavailable"
            OtpException.Kind.TRANSPORT -> "transport"
            OtpException.Kind.CANCELLED -> "cancelled"
            OtpException.Kind.NO_PRESENTER -> "noPresenter"
            OtpException.Kind.UNEXPECTED -> "unexpected"
        }

        /**
         * Carries the fields a rejection has nowhere else to put. `otp_flutter.dart` reads this map
         * back from `PlatformException.details`.
         */
        fun details(error: OtpException): Map<String, Any> = buildMap {
            error.type?.let { put("type", it) }
            error.statusCode?.let { put("statusCode", it) }
            error.retryAfterSeconds?.let { put("retryAfterSeconds", it) }
        }

        fun map(pending: PendingOtp): PendingOtpMessage = PendingOtpMessage(
            id = pending.id.toString(),
            status = string(pending.status),
            channel = pending.channel?.let(::string),
            maskedRecipient = pending.maskedRecipient,
            codeLength = pending.codeLength.toLong(),
            expiresAt = iso(pending.expiresAt),
            resendAvailableAt = pending.resendAvailableAt?.let(::iso),
            handoffUrl = pending.handoffUrl,
        )

        fun map(verification: Verification): VerificationMessage = VerificationMessage(
            otpId = verification.otpId.toString(),
            token = verification.token,
            tokenExpiresAt = iso(verification.tokenExpiresAt),
        )

        fun map(outcome: CodeSubmission): CodeSubmissionMessage = when (outcome) {
            is CodeSubmission.Verified -> CodeSubmissionMessage(verification = map(outcome.verification))
            is CodeSubmission.Rejected -> CodeSubmissionMessage(
                attemptsRemaining = outcome.attemptsRemaining?.toLong(),
                reason = string(outcome.reason),
            )
        }

        fun string(reason: RejectionReason): String = when (reason) {
            RejectionReason.INCORRECT_CODE -> "incorrectCode"
            RejectionReason.EXPIRED -> "expired"
            RejectionReason.NO_ATTEMPTS_LEFT -> "noAttemptsLeft"
            RejectionReason.UNKNOWN -> "unknown"
        }

        fun string(status: OtpStatus): String = when (status) {
            OtpStatus.PENDING -> "pending"
            OtpStatus.APPROVED -> "approved"
            OtpStatus.FAILED -> "failed"
            OtpStatus.EXPIRED -> "expired"
            OtpStatus.UNKNOWN -> "unknown"
        }

        fun string(channel: OtpChannel): String = when (channel) {
            OtpChannel.SMS -> "sms"
            OtpChannel.WHATSAPP -> "whatsapp"
            OtpChannel.EMAIL -> "email"
            OtpChannel.TELEGRAM -> "telegram"
            OtpChannel.UNKNOWN -> "unknown"
        }

        // Deliberately no `unknown`: a resend has to name a channel the API can act on, and this
        // build cannot name one it does not know.
        fun channel(name: String): OtpChannel? = when (name) {
            "sms" -> OtpChannel.SMS
            "whatsapp" -> OtpChannel.WHATSAPP
            "email" -> OtpChannel.EMAIL
            "telegram" -> OtpChannel.TELEGRAM
            else -> null
        }

        fun recipientKind(name: String): RecipientKind? = when (name) {
            "phone" -> RecipientKind.PHONE
            "email" -> RecipientKind.EMAIL
            else -> null
        }

        /** ISO 8601 with the offset, which is what `DateTime.parse` in Dart parses. */
        fun iso(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant)

        fun uuid(value: String): UUID = runCatching { UUID.fromString(value) }.getOrNull()
            ?: throw Refusal("$value is not a verification id")
    }
}
