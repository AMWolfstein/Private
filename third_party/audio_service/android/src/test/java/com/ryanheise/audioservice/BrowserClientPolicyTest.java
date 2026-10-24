package com.ryanheise.audioservice;

import org.junit.Test;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public class BrowserClientPolicyTest {
    private static final int OWN_UID = 10001;
    private static final int OTHER_UID = 10002;

    @Test
    public void ownProcessIsAllowedWithoutPlatformTrust() {
        assertTrue(BrowserClientPolicy.isAllowed(OWN_UID, "local.app", OWN_UID,
                "local.app", OWN_UID, true, () -> false));
    }

    @Test
    public void androidTrustedSystemAndCarControllersAreAllowed() {
        for (String controller : new String[] {"com.android.bluetooth", "trusted.car"}) {
            assertTrue(BrowserClientPolicy.isAllowed(OWN_UID, controller, OTHER_UID,
                    controller, OTHER_UID, true, () -> true));
        }
    }

    @Test
    public void untrustedControllerCannotBrowse() {
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "untrusted.app", OTHER_UID,
                "untrusted.app", OTHER_UID, true, () -> false));
    }

    @Test
    public void spoofedIdentityIsDeniedBeforeTrustIsConsulted() {
        BrowserClientPolicy.ControllerTrust unexpectedTrust = () -> {
            fail("Unverified caller must not be trusted");
            return true;
        };
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "local.app", OWN_UID,
                "attacker.app", OTHER_UID, true, unexpectedTrust));
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "local.app", OWN_UID,
                "local.app", OTHER_UID, true, unexpectedTrust));
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "trusted.car", OTHER_UID,
                "trusted.car", OTHER_UID, false, unexpectedTrust));
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, null, OTHER_UID,
                "trusted.car", OTHER_UID, true, unexpectedTrust));
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "", OTHER_UID,
                "", OTHER_UID, true, unexpectedTrust));
        assertFalse(BrowserClientPolicy.isAllowed(OWN_UID, "trusted.car", -1,
                "trusted.car", -1, true, unexpectedTrust));
    }
}
