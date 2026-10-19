package com.sirfhum.app

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Platform key store for the crypto core's per-account store key (D-066,
 * docs/security/KEY-MANAGEMENT.md §3, DEVICE-IDENTITY.md).
 *
 * - A non-exportable AES-256-GCM key lives in the Android Keystore
 *   (StrongBox when available, else TEE). It never leaves the Keystore.
 * - Each account slot's 32-byte store key is random, wrapped (encrypted) by
 *   that Keystore key, and kept in `noBackupFilesDir`, which Auto Backup and
 *   device transfer never copy. A restored or copied wrapped blob is useless
 *   without this device's Keystore key, so cloned state fails closed.
 * - Uninstalling deletes the Keystore key, so a reinstall is a new device.
 *
 * Platform primitives only (Keystore + javax.crypto AES-GCM); nothing here is
 * custom cryptography. Errors carry a category, never key bytes or messages.
 */
class SecureKeyStore(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.sirfhum.app/secure_key_store"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val WRAP_ALIAS = "sirf_hum_store_key_wrap_v1"
        private const val STORE_KEY_BYTES = 32
        private const val GCM_TAG_BITS = 128
        private const val FORMAT_VERSION: Byte = 1
        private val SLOT = Regex("^[A-Za-z0-9_-]{1,128}$")
    }

    private class KeyMissing : Exception()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "slotDirectory" -> result.success(slotDirectory(slot(call)).absolutePath)
                "storeKey" -> {
                    val key = storeKey(slot(call), call.argument<Boolean>("create") == true)
                    result.success(key)
                    // The codec copied it; wipe our copy.
                    key.fill(0)
                }
                "removeSlot" -> {
                    removeSlot(slot(call))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: KeyMissing) {
            result.error("key_missing", null, null)
        } catch (_: IllegalArgumentException) {
            result.error("invalid_slot", null, null)
        } catch (_: GeneralSecurityException) {
            result.error("keystore_failure", null, null)
        } catch (_: IOException) {
            result.error("keystore_failure", null, null)
        }
    }

    private fun slot(call: MethodCall): String {
        val slot = call.argument<String>("slot") ?: throw IllegalArgumentException()
        require(SLOT.matches(slot))
        return slot
    }

    /** One directory per account slot, never backed up or transferred. */
    private fun slotDirectory(slot: String): File =
        File(File(context.noBackupFilesDir, "sirf_hum_crypto/accounts"), slot).apply {
            if (!isDirectory && !mkdirs()) throw IOException()
        }

    private fun wrappedFile(slot: String): File =
        File(File(context.noBackupFilesDir, "sirf_hum_keys").apply { mkdirs() }, "$slot.wrapped")

    /** Binds a wrapped blob to its slot: it cannot be moved to another account. */
    private fun aad(slot: String): ByteArray = "SirfHum-StoreKey-v1:$slot".toByteArray(Charsets.UTF_8)

    private fun wrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(WRAP_ALIAS, null) as? SecretKey)?.let { return it }
        return try {
            generateWrappingKey(strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        } catch (_: ProviderException) {
            // StrongBoxUnavailableException (API 28+) is a ProviderException;
            // fall back to the TEE-backed Keystore.
            generateWrappingKey(strongBox = false)
        }
    }

    private fun generateWrappingKey(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            WRAP_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .apply { if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setIsStrongBoxBacked(true) }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            .apply { init(spec) }
            .generateKey()
    }

    /**
     * create = true: a fresh random store key replaces any previous one (the
     * caller found no local state, e.g. first run). create = false: the
     * existing key, or KeyMissing.
     */
    private fun storeKey(slot: String, create: Boolean): ByteArray {
        val file = wrappedFile(slot)
        if (create) {
            val key = ByteArray(STORE_KEY_BYTES).also { SecureRandom().nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
            cipher.updateAAD(aad(slot))
            val iv = cipher.iv
            val sealed = cipher.doFinal(key)
            writeAtomically(file, byteArrayOf(FORMAT_VERSION, iv.size.toByte()) + iv + sealed)
            return key
        }
        if (!file.exists()) throw KeyMissing()
        val blob = file.readBytes()
        if (blob.size < 2 || blob[0] != FORMAT_VERSION) throw GeneralSecurityException()
        val ivLength = blob[1].toInt()
        if (ivLength <= 0 || blob.size <= 2 + ivLength) throw GeneralSecurityException()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            wrappingKey(),
            GCMParameterSpec(GCM_TAG_BITS, blob, 2, ivLength),
        )
        cipher.updateAAD(aad(slot))
        val key = cipher.doFinal(blob, 2 + ivLength, blob.size - 2 - ivLength)
        if (key.size != STORE_KEY_BYTES) throw GeneralSecurityException()
        return key
    }

    /**
     * Deletes the wrapped key first (the only copy: the slot's sealed state
     * becomes unrecoverable at once), then the state itself.
     */
    private fun removeSlot(slot: String) {
        val file = wrappedFile(slot)
        if (file.exists() && !file.delete()) throw IOException()
        val dir = File(File(context.noBackupFilesDir, "sirf_hum_crypto/accounts"), slot)
        if (dir.exists() && !dir.deleteRecursively()) throw IOException()
    }

    private fun writeAtomically(target: File, bytes: ByteArray) {
        val temp = File(target.parentFile, ".${target.name}.tmp")
        FileOutputStream(temp).use { out ->
            out.write(bytes)
            out.fd.sync()
        }
        if (!temp.renameTo(target)) {
            temp.delete()
            throw IOException()
        }
    }
}
