package it.a11y.blindensport.webui.mcp;

import io.quarkiverse.mcp.server.ToolArg;

/** One person's attendance in set_attendance ({@link EventTools}). */
public record AttendanceChange(
        @ToolArg(description = "membership_id from get_event's roster") String membershipId,
        @ToolArg(description = "Whether the person attended") boolean attended,
        @ToolArg(description = "PRAE in euros, coaches and assistants only; omit to keep the current amount", required = false)
        Double praeAmount) {
}
