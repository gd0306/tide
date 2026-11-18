package cn.gd306.tideenglish.core

import android.content.Context
import cn.gd306.tideenglish.R
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private val publicURL = Regex("""https://([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?((?:/[A-Za-z0-9._~!$&'()*+,;=:@/%-]*)?(?:\?[A-Za-z0-9._~!$&'()*+,;=:@/?%-]*)?)""")
private val dnsLabel = Regex("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
private val reservedNames = listOf("example.com", "example.net", "example.org", "example", "test", "invalid", "localhost", "local", "internal", "home.arpa", "onion", "alt", "localdomain", "home", "corp", "lan")

internal fun isPublicHttpsURL(value: String): Boolean {
    if (value.length > 2048) return false
    val (_, hostValue, port, suffix) = publicURL.matchEntire(value)?.groupValues ?: return false
    val host = hostValue.lowercase()
    val labels = host.split('.')
    return host.length <= 253 && labels.size > 1 && labels.all(dnsLabel::matches) &&
        labels.last().first() in 'a'..'z' &&
        reservedNames.none { host == it || host.endsWith(".$it") } &&
        (port.isEmpty() || port.toInt() in 1..65535) && !Regex("%(?![0-9a-fA-F]{2})|%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|5[Cc])").containsMatchIn(suffix)
}

internal fun readPublicInformation(context: Context): String? = runCatching {
    context.resources.openRawResource(R.raw.public_information).bufferedReader().use { it.readText() }
}.getOrNull()

@Serializable
internal data class PublicMetadata(val schemaVersion: Int, val publisherName: String, val supportEmail: String,
    val publicPagesReady: Boolean, val links: Map<String, String>, val appFilingNumber: String,
    val modelPolicy: String, val aiServices: List<DeclaredModel>) {
    companion object {
        fun decode(source: String?): PublicMetadata? = runCatching {
            Json.decodeFromString<PublicMetadata>(requireNotNull(source)).also { require(it.schemaVersion == 1) }
        }.getOrNull()
    }
}

@Serializable
internal data class DeclaredModel(val provider: String, val model: String, val baseURL: String, val filingNumber: String) {
    fun configuration(): ProviderConfiguration {
        val id = when (provider) {
            "openAI" -> ModelProvider.OPENAI
            "deepSeek" -> ModelProvider.DEEPSEEK
            "glm" -> ModelProvider.GLM
            "gemini" -> ModelProvider.GEMINI
            "custom" -> ModelProvider.CUSTOM
            else -> error("Unknown model provider.")
        }
        val config = ProviderConfiguration(id, model, baseURL)
        require(filingNumber.isNotEmpty() && filingNumber.codePointCount(0, filingNumber.length) <= 500 &&
                filingNumber == filingNumber.trim() && filingNumber.none { it.isISOControl() || it == '\u2028' || it == '\u2029' })
        require(isPublicHttpsURL(baseURL))
        if (id == ModelProvider.GEMINI && model == GEMINI_LIVE_MODEL) require(config.isGeminiLiveDeclaration())
        else require(config.validated() == config)
        return config
    }
}

internal const val GEMINI_LIVE_BASE = "https://generativelanguage.googleapis.com"
internal const val GEMINI_LIVE_MODEL = "models/gemini-3.8-live"
internal const val OPENAI_LIVE_MODEL = "gpt-live-1"
private fun ProviderConfiguration.isGeminiLiveDeclaration() =
    provider == ModelProvider.GEMINI && baseURL == GEMINI_LIVE_BASE && model == GEMINI_LIVE_MODEL

class ReleaseModelPolicy private constructor(private val declarations: List<ProviderConfiguration>?) {
    val restricted get() = declarations != null
    val chatChoices get() = declarations.orEmpty().filterNot { it.isGeminiLiveDeclaration() || (it.provider == ModelProvider.OPENAI && it.model == OPENAI_LIVE_MODEL) }

    fun requireChat(configuration: ProviderConfiguration): ProviderConfiguration = configuration.validated().also {
        require(!restricted || it in chatChoices) { "Choose a model available in this release in Settings." }
    }

    internal fun permitsWire(provider: ModelProvider, model: String?, baseURL: String): Boolean =
        declarations == null || (model != null && ProviderConfiguration(provider, model, baseURL) in declarations)

    internal fun permitsNative(config: ProviderConfiguration): Boolean = !restricted ||
        (runCatching { requireChat(config) }.isSuccess && when (config.provider) {
            ModelProvider.OPENAI -> permitsWire(ModelProvider.OPENAI, OPENAI_LIVE_MODEL, ModelProvider.OPENAI.defaultBaseURL)
            ModelProvider.GEMINI -> permitsWire(ModelProvider.GEMINI, GEMINI_LIVE_MODEL, GEMINI_LIVE_BASE)
            else -> false // GLM's native endpoint does not identify the model on the wire.
        })

    companion object {
        val unrestricted = ReleaseModelPolicy(null)
        private val closed = ReleaseModelPolicy(emptyList())
        internal fun fromSource(source: String?, debug: Boolean): ReleaseModelPolicy {
            val metadata = PublicMetadata.decode(source) ?: return if (debug && source == null) unrestricted else closed
            return when (metadata.modelPolicy) {
                "unrestricted" -> unrestricted
                "declaredOnly" -> runCatching {
                    require(metadata.aiServices.size <= 20)
                    ReleaseModelPolicy(metadata.aiServices.map { it.configuration() }.distinct())
                }.getOrDefault(closed)
                else -> closed
            }
        }
    }
}
