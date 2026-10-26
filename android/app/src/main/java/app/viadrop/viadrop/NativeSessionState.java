// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop;

import java.util.ArrayList;
import java.util.List;

/** Application lifecycle ownership, independent of Android and codec licensing.
 * Confined to its creating thread (the Android UI thread in production).
 * One cleanup ticket owns resource release; concurrent stop callers join it.
 */
public final class NativeSessionState {
    public interface FailureHandler { void onFailure(RuntimeException error); }
    private enum Phase { IDLE, ACTIVE, STOPPING }
    private final Thread owner = Thread.currentThread();
    private final FailureHandler failures;
    private final List<Runnable> waiters = new ArrayList<>();
    private Phase phase = Phase.IDLE;
    private long generation;
    private long client;
    private boolean disposed;

    public NativeSessionState(FailureHandler failures) {
        if (failures == null) throw new IllegalArgumentException("Missing failure handler");
        this.failures = failures;
    }

    public long begin(long clientId) {
        requireOwner();
        if (clientId <= 0) throw new IllegalArgumentException("Invalid native client");
        if (disposed || phase != Phase.IDLE) throw new IllegalStateException("Native session busy or disposed");
        phase = Phase.ACTIVE;
        client = clientId;
        return ++generation;
    }

    public long owner() {
        requireOwner();
        return client;
    }

    public boolean owns(long clientId) {
        requireOwner();
        return phase != Phase.IDLE && client == clientId;
    }

    /** A stale screen acknowledges its own stop without touching a new owner. */
    public long stopOwned(long clientId, Runnable completed) {
        requireOwner();
        if (!owns(clientId)) {
            if (completed != null) deliver(completed);
            return 0;
        }
        return stop(completed);
    }

    /** For a late startup reply: even the same screen may now own a NEW
     * native generation, which an old reply has no authority to stop. */
    public long stopOwned(long clientId, long expectedGeneration, Runnable completed) {
        requireOwner();
        if (!owns(clientId) || !isCurrent(expectedGeneration)) {
            if (completed != null) deliver(completed);
            return 0;
        }
        return stop(completed);
    }

    public boolean isCurrent(long token) {
        requireOwner();
        return !disposed && phase == Phase.ACTIVE && generation == token;
    }

    /** Returns a nonzero cleanup ticket only to the first stop caller.
     * Zero means cleanup is unnecessary or another caller already owns it.
     * Completion callbacks still run once, after resource cleanup finishes.
     */
    public long stop(Runnable completed) {
        requireOwner();
        if (phase == Phase.IDLE) {
            if (completed != null) deliver(completed);
            return 0;
        }
        if (completed != null) waiters.add(completed);
        if (phase == Phase.STOPPING) return 0;
        phase = Phase.STOPPING;
        return ++generation; // Immediately invalidates all active callbacks.
    }

    public boolean isStopping(long ticket) {
        requireOwner();
        return phase == Phase.STOPPING && generation == ticket;
    }

    public boolean finishStop(long ticket) {
        requireOwner();
        if (!isStopping(ticket)) return false;
        // Snapshot first: a completion may reentrantly start/stop a NEW session.
        List<Runnable> ready = new ArrayList<>(waiters);
        waiters.clear();
        phase = Phase.IDLE;
        client = 0;
        for (Runnable callback : ready) deliver(callback);
        return true;
    }

    public void disallowStarts() {
        requireOwner();
        disposed = true;
    }

    private void deliver(Runnable callback) {
        try { callback.run(); }
        catch (RuntimeException error) {
            // One failed platform reply must not strand the remaining replies.
            failures.onFailure(error);
        }
    }
    private void requireOwner() {
        if (Thread.currentThread() != owner) throw new IllegalStateException("Native session state requires its owner thread");
    }
}
