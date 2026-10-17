package it.a11y.blindensport.webadmin.api;

import it.a11y.blindensport.webadmin.auth.AdminSession;
import jakarta.ws.rs.container.ContainerRequestContext;

/** The admin {@link ApiAuthFilter} found for this request. */
final class CurrentAdmin {
    private CurrentAdmin() {
    }

    static AdminSession require(ContainerRequestContext request) {
        Object session = request.getProperty(ApiAuthFilter.SESSION_PROPERTY);
        if (session instanceof AdminSession admin) {
            return admin;
        }
        throw new ApiException(401, "Bitte anmelden.");
    }

    static AdminSession require(ContainerRequestContext request, String permission) {
        AdminSession admin = require(request);
        if (!admin.can(permission)) {
            throw ApiException.forbidden(permission);
        }
        return admin;
    }
}
