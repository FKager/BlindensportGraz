package it.a11y.blindensport.webadmin.club;

import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webadmin.club.ClubModels.Attendance;
import it.a11y.blindensport.webadmin.club.ClubModels.BudgetEntry;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubModels.TrainingFavorite;
import it.a11y.blindensport.webadmin.members.MemberStore;
import it.a11y.blindensport.webadmin.supabase.GoTrue;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.SupabaseHttp;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Round trip of every club table against a LOCAL Supabase (never staging or
 * prod): LIVE_SUPABASE_URL, LIVE_SUPABASE_ANON_KEY, LIVE_EMAIL, LIVE_PASSWORD.
 * Creates rows prefixed "IT-" and deletes them again.
 */
@EnabledIfEnvironmentVariable(named = "LIVE_SUPABASE_URL", matches = "http://(host\\.docker\\.internal|127\\.0\\.0\\.1|localhost):54321")
class LiveSupabaseIT {
    @Test
    void clubTablesRoundTripAsRoot() {
        SupabaseHttp http = new SupabaseHttp(System.getenv("LIVE_SUPABASE_URL"), new ObjectMapper());
        String anon = System.getenv("LIVE_SUPABASE_ANON_KEY");
        GoTrue.Tokens tokens = new GoTrue(http, anon).signIn(System.getenv("LIVE_EMAIL"), System.getenv("LIVE_PASSWORD")).orElseThrow();
        Postgrest db = new Postgrest(http, anon, tokens::accessToken);
        ClubStore store = new ClubStore(db, tokens.userId());

        Team team = new Team(ClubStore.newId(), "IT-Team " + System.nanoTime(), "Torball", "Integrationstest");
        store.saveTeam(team);
        assertTrue(store.teams().stream().anyMatch(t -> t.id().equals(team.id())));
        String memberId = new MemberStore(db).all(false).get(0).id().toLowerCase(Locale.ROOT);
        Membership membership = new Membership(ClubStore.newId(), team.id(), memberId, null, "coach", Instant.now());
        store.saveMembership(membership);

        ClubEvent event = new ClubEvent(ClubStore.newId(), "training", "IT-Training", "Torball", "Halle", "", "", "Graz",
                "Österreich", Instant.parse("2030-01-07T17:00:00Z"), Instant.parse("2030-01-07T18:30:00Z"), "", "open",
                90, "Abwehr", null, List.of(team.id()), store.createdBy());
        store.saveEvent(event);
        ClubEvent read = store.event(event.id()).orElseThrow();
        assertEquals(List.of(team.id()), read.teamIds());
        assertEquals(90, read.durationMinutes());

        store.saveAttendance(new Attendance(ClubStore.newId(), event.id(), membership.id(), true, new BigDecimal("45")));
        Attendance attendance = store.attendances(event.id()).get(0);
        assertTrue(attendance.attended());
        assertEquals(0, attendance.praeAmount().compareTo(new BigDecimal("45")));

        TrainingFavorite favorite = new TrainingFavorite(ClubStore.newId(), "IT-Favorit", "Torball", 2, 18, 0, 19, 30,
                "Halle", "", "", "Graz", "Österreich", List.of(team.id()));
        store.saveFavorite(favorite);
        assertTrue(store.favorites().stream().anyMatch(f -> f.id().equals(favorite.id()) && f.teamIds().equals(List.of(team.id()))));

        BudgetEntry budget = new BudgetEntry(ClubStore.newId(), "eventCost", new BigDecimal("12.50"), Instant.now(),
                "IT-Budget", event.id(), store.createdBy());
        store.saveBudget(budget);
        assertTrue(store.budget().stream().anyMatch(b -> b.id().equals(budget.id()) && b.eventId().equals(event.id())));

        assertTrue(store.accountNames().containsKey(tokens.userId().toString()));

        store.deleteBudget(budget.id());
        store.deleteFavorite(favorite.id());
        store.deleteEvent(event.id());
        store.deleteTeam(team.id());
        assertTrue(store.teams().stream().noneMatch(t -> t.id().equals(team.id())));
        assertTrue(store.events().stream().noneMatch(e -> e.id().equals(event.id())));
    }
}
