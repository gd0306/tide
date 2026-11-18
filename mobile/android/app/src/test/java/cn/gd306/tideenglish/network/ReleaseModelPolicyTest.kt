package cn.gd306.tideenglish.network

import cn.gd306.tideenglish.core.*
import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class ReleaseModelPolicyTest {
    private val fixture = Json.parseToJsonElement(File("../../../packages/fixtures/cross-platform/release-model-policy.json").readText()).jsonObject
    private val metadata = fixture.getValue("metadata").jsonObject
    private val services = metadata.getValue("aiServices").jsonArray
    private fun policy(entries: List<JsonElement>) = ReleaseModelPolicy.fromSource(
        JsonObject(metadata + ("aiServices" to JsonArray(entries))).toString(), false)

    @Test fun publicUrlsAndMalformedMetadata() {
        fixture.getValue("validURLs").jsonArray.forEach { assertTrue(it.toString(), isPublicHttpsURL(it.jsonPrimitive.content)) }
        fixture.getValue("invalidURLs").jsonArray.forEach { assertFalse(it.toString(), isPublicHttpsURL(it.jsonPrimitive.content)) }
        for (source in listOf(null, "{}", "[]", JsonObject(metadata + ("publisherName" to buildJsonObject { put("privateNote", "synthetic") })).toString())) {
            assertNull(PublicMetadata.decode(source))
            assertTrue(ReleaseModelPolicy.fromSource(source, false).chatChoices.isEmpty())
            assertTrue(ReleaseModelPolicy.fromSource(source, false).restricted)
        }
        assertFalse(ReleaseModelPolicy.fromSource(null, true).restricted)
        assertFalse(ReleaseModelPolicy.fromSource(JsonObject(metadata + ("modelPolicy" to JsonPrimitive("unrestricted"))).toString(), false).restricted)
    }

    @Test fun actualNativeAndCustomRecipients() = runBlocking {
        val declared = policy(services)
        val chat = ProviderConfiguration(ModelProvider.OPENAI, "synthetic-chat")
        assertEquals(4, declared.chatChoices.size)
        val gemini = declared.chatChoices.single { it.provider == ModelProvider.GEMINI }
        val glm = declared.chatChoices.single { it.provider == ModelProvider.GLM }
        assertTrue(declared.permitsNative(gemini))
        assertFalse(declared.permitsNative(glm))
        val chatOnly = policy(services.filter { it.jsonObject["model"]?.jsonPrimitive?.content !in listOf(GEMINI_LIVE_MODEL, OPENAI_LIVE_MODEL) })
        assertFalse(chatOnly.permitsNative(gemini))
        var requests = 0
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            requests++
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"transport":{"type":"webrtc","sdp":"synthetic-answer"}}""".toResponseBody()).build()
        }.build()
        val base = "https://api.openai.com/v1/".toHttpUrl()
        val live = LiveSessionRequest(instructions = "synthetic", sdp = "synthetic-sdp", history = JsonArray(emptyList()))
        fun client(p: ReleaseModelPolicy, url: HttpUrl = base) = APIClient("synthetic-key", http, url, p) { chat }
        assertTrue(runCatching { client(chatOnly).createLiveSession(live) }.isFailure)
        assertTrue(runCatching { client(declared, "https://synthetic-model.org/v1/".toHttpUrl()).createLiveSession(live) }.isFailure)
        assertTrue(runCatching { client(declared).post("live/sessions", buildJsonObject { put("session", buildJsonObject { put("model", chat.model) }) }) }.isFailure)
        assertEquals(0, requests)
        client(declared).createLiveSession(live)
        assertEquals(1, requests)
        val custom = declared.chatChoices.single { it.provider == ModelProvider.CUSTOM }
        assertEquals(custom, declared.requireChat(custom))
        assertTrue(runCatching { declared.requireChat(custom.copy(baseURL = custom.baseURL + "/other")) }.isFailure)
        fixture.getValue("invalidDeclarations").jsonArray.forEach { bad ->
            assertTrue(policy(services.toList() + listOf(bad)).chatChoices.isEmpty())
        }
    }
}
