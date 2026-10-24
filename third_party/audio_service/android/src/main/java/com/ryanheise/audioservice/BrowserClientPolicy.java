package com.ryanheise.audioservice;

/** Browser identity must be verified before consulting Android's controller trust. */
final class BrowserClientPolicy {
    private BrowserClientPolicy() {}

    interface ControllerTrust {
        boolean isTrusted();
    }

    static boolean isAllowed(int ownUid, String clientPackage, int clientUid,
            String remotePackage, int remoteUid, boolean packageBelongsToUid,
            ControllerTrust trustedController) {
        if (clientPackage == null || clientPackage.isEmpty() || clientUid < 0
                || clientUid != remoteUid || !clientPackage.equals(remotePackage)
                || !packageBelongsToUid) {
            return false;
        }
        return clientUid == ownUid || trustedController.isTrusted();
    }
}
