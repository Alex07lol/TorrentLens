package dev.torrentlens.core.domain.security

import kotlinx.serialization.Serializable

/**
 * A detached signature as published alongside a release manifest.
 *
 * Everything in here is downloaded from a third party and therefore untrusted;
 * verification must be able to *fail closed* and must never depend on the
 * content being verified to decide which key to trust.
 */
@Serializable
data class DetachedSignature(
    val algorithm: String,
    /** Base64 or `ed25519:`-prefixed base64 of the raw 32-byte public key. */
    val publicKey: String,
    /** Base64 of the raw 64-byte signature. */
    val signature: String,
    /** Optional key identifier, used only for logging/rollback UX. */
    val keyId: String? = null,
)

sealed interface SignatureVerdict {
    data object Valid : SignatureVerdict
    data class Invalid(val reason: SignatureReason) : SignatureVerdict
}

enum class SignatureReason {
    UNSUPPORTED_ALGORITHM,
    MALFORMED_PUBLIC_KEY,
    MALFORMED_SIGNATURE,
    NO_TRUSTED_KEY,
    SIGNATURE_MISMATCH,
}

object PublisherSignatureVerifier {

    private const val ED25519 = "ed25519"

    /**
     * @param message the exact bytes that were signed (the manifest body).
     * @param trustedPublicKeys raw 32-byte keys pinned in the app. If non-empty,
     *   [DetachedSignature.publicKey] must match one of them — a manifest can
     *   never introduce its own trust root.
     */
    fun verify(
        message: ByteArray,
        signature: DetachedSignature,
        trustedPublicKeys: Set<String> = emptySet(),
    ): SignatureVerdict {
        if (!signature.algorithm.equals(ED25519, ignoreCase = true)) {
            return SignatureVerdict.Invalid(SignatureReason.UNSUPPORTED_ALGORITHM)
        }
        val keyBytes = Ed25519.decodeBase64(signature.publicKey.substringAfter(':'))
            ?: return SignatureVerdict.Invalid(SignatureReason.MALFORMED_PUBLIC_KEY)
        if (keyBytes.size != Ed25519.PUBLIC_KEY_BYTES) {
            return SignatureVerdict.Invalid(SignatureReason.MALFORMED_PUBLIC_KEY)
        }
        if (trustedPublicKeys.isNotEmpty()) {
            val asHex = hex(keyBytes)
            if (trustedPublicKeys.none { it.equals(asHex, ignoreCase = true) }) {
                return SignatureVerdict.Invalid(SignatureReason.NO_TRUSTED_KEY)
            }
        }
        val sigBytes = Ed25519.decodeBase64(signature.signature)
            ?: return SignatureVerdict.Invalid(SignatureReason.MALFORMED_SIGNATURE)
        if (sigBytes.size != Ed25519.SIGNATURE_BYTES) {
            return SignatureVerdict.Invalid(SignatureReason.MALFORMED_SIGNATURE)
        }
        return if (Ed25519.verify(keyBytes, sigBytes, message)) {
            SignatureVerdict.Valid
        } else {
            SignatureVerdict.Invalid(SignatureReason.SIGNATURE_MISMATCH)
        }
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
