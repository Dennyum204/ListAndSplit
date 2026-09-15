package com.ferbatech.listandsplit

import org.junit.Assert.*
import org.junit.Test

class PushEnvelopeTest {
    private val account="10000000-0000-4000-8000-000000000001"
    private val binding="20000000-0000-4000-8000-000000000001"
    private val data=mapOf("v" to "1","delivery_id" to "30000000-0000-4000-8000-000000000001",
        "binding_id" to binding,"recipient_id" to account,"kind" to "chat","list_id" to "40000000-0000-4000-8000-000000000001")
    @Test fun currentAccountAndBindingAreBothRequired() {
        val parsed=PushEnvelope.parse(data)!!
        assertTrue(parsed.matches(account,binding))
        assertFalse(parsed.matches(null,binding))
        assertFalse(parsed.matches(account,"old-binding"))
        assertFalse(parsed.matches("different-account",binding))
    }
    @Test fun expandedOrMalformedEnvelopesNeverShow() {
        assertNull(PushEnvelope.parse(data + ("body" to "sensitive content")))
        assertNull(PushEnvelope.parse(data + ("v" to "2")))
        assertNull(PushEnvelope.parse(data - "list_id"))
        assertNull(PushEnvelope.parse(data + ("delivery_id" to "bad")))
        assertNull(PushEnvelope.parse(data + ("kind" to "unknown")))
    }
    @Test fun genericNotificationNeedsNoResourceDetails() {
        assertNotNull(PushEnvelope.parse((data - "list_id") + ("kind" to "notification")))
    }
}
