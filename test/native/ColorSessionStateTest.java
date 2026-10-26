// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

/** Host lifecycle simulation, no Android hardware involved. */
public final class ColorSessionStateTest {
    static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static void busy(Runnable action) {
        try { action.run(); } catch (IllegalStateException expected) { return; }
        throw new AssertionError("Expected busy/disposed rejection");
    }
    public static void main(String[] args) throws Exception {
        List<RuntimeException> failures = new ArrayList<>();
        ColorSessionState state = new ColorSessionState(failures::add);
        long first = state.begin(1);
        busy(() -> state.begin(1));
        check(state.isCurrent(first), "Duplicate start cancelled the active transfer");
        List<String> replies = new ArrayList<>();
        long cleanup = state.stop(() -> replies.add("first"));
        check(cleanup != 0 && !state.isCurrent(first), "Stop must immediately invalidate old results");
        check(state.stop(() -> replies.add("second")) == 0, "Duplicate stop acquired cleanup twice");
        check(state.stop(null) == 0, "Background stop acquired cleanup twice");
        busy(() -> state.begin(1));
        check(replies.isEmpty(), "Stop replied before native resources were released");
        check(!state.finishStop(cleanup + 123), "Unrelated cleanup changed session state");
        check(state.finishStop(cleanup), "Owning cleanup did not finish");
        check(replies.equals(Arrays.asList("first", "second")), "Joined stop replies lost or reordered");
        check(!state.finishStop(cleanup), "Duplicate native release completed twice");
        long second = state.begin(1);
        check(!state.isCurrent(first) && state.isCurrent(second), "Old results became current after restart");
        check(!state.finishStop(cleanup) && state.isCurrent(second), "Late cleanup cancelled a new transfer");
        long nextCleanup = state.stop(() -> { throw new IllegalStateException("reply channel closed"); });
        state.stop(() -> replies.add("surviving reply"));
        state.finishStop(nextCleanup);
        check(failures.size() == 1 && replies.contains("surviving reply"), "One failed reply stranded another");
        System.out.println("PASS duplicate start, joined stops, ordered release, stale callbacks and failed replies");

        // Restart from a cleanup completion. Draining the old waiter list must
        // not clear or complete the new transfer's own stop callbacks.
        long third = state.begin(1);
        final long[] restarted = new long[2];
        long thirdCleanup = state.stop(() -> {
            restarted[0] = state.begin(1);
            restarted[1] = state.stop(() -> replies.add("new cleanup"));
        });
        state.stop(() -> replies.add("old cleanup"));
        state.finishStop(thirdCleanup);
        check(!state.isCurrent(third) && state.isStopping(restarted[1]), "Reentrant restart lost its cleanup ticket");
        check(!replies.contains("new cleanup"), "Old cleanup prematurely completed new cleanup");
        state.finishStop(restarted[1]);
        check(replies.contains("new cleanup"), "New cleanup callback lost");
        System.out.println("PASS restart during cleanup completion preserves the new transfer");

        long active = state.begin(1);
        state.disallowStarts();
        check(!state.isCurrent(active), "Dispose failed to invalidate pending data");
        busy(() -> state.begin(1));
        long disposing = state.stop(() -> replies.add("disposed"));
        state.stop(() -> replies.add("joined disposal"));
        state.finishStop(disposing);
        busy(() -> state.begin(1));
        check(replies.contains("disposed") && replies.contains("joined disposal"), "Dispose lost stop replies");
        check(state.stop(() -> replies.add("idle stop")) == 0 && replies.contains("idle stop"), "Idle stop did not complete");
        AtomicReference<Throwable> wrongThread = new AtomicReference<>();
        Thread worker = new Thread(() -> {
            try { state.stop(null); } catch (Throwable error) { wrongThread.set(error); }
        });
        worker.start(); worker.join();
        check(wrongThread.get() instanceof IllegalStateException, "Cross-thread state access accepted");
        System.out.println("PASS disposal, idle stop and owner-thread enforcement");

        ColorSessionState ownership = new ColorSessionState(failures::add);
        long oldToken = ownership.begin(10);
        long oldCleanup = ownership.stopOwned(10, null);
        ownership.finishStop(oldCleanup);
        long currentToken = ownership.begin(20);
        check(ownership.stopOwned(10, () -> replies.add("stale owner ack")) == 0,
            "Old screen acquired new session cleanup");
        check(ownership.isCurrent(currentToken) && !ownership.isCurrent(oldToken),
            "Old screen cleanup stopped a newer screen");
        check(replies.contains("stale owner ack"), "Stale stop did not acknowledge its caller");
        check(ownership.owns(20) && !ownership.owns(10), "Wrong client owns active resources");
        long ownedCleanup = ownership.stopOwned(20, null);
        check(ownedCleanup != 0 && ownership.owns(20), "Owner lost while resources still closing");
        ownership.finishStop(ownedCleanup);
        check(!ownership.owns(20), "Owner retained after resource release");
        System.out.println("PASS delayed old-screen stop cannot cancel the new screen's session");

        // Repeated navigation/background cycles must not accumulate waiters or
        // accept an old decoder result after opening the next session.
        ColorSessionState repeated = new ColorSessionState(failures::add);
        int[] completions = {0};
        for (int i = 0; i < 10000; i++) {
            long token = repeated.begin(2);
            long ticket = repeated.stop(() -> completions[0]++);
            repeated.stop(() -> completions[0]++);
            check(!repeated.isCurrent(token), "Stale data in repeated session");
            repeated.finishStop(ticket);
        }
        check(completions[0] == 20000, "Repeated cycles leaked or duplicated stop replies");
        System.out.println("PASS 10000 simulated lifecycle cycles / 20000 exactly-once cleanup replies");
    }
}
