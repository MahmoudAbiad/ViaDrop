// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop;

import java.util.concurrent.TimeUnit;

/** Cross-thread consent mailbox. Matching and delivery are one atomic operation;
 * a duplicate old reply can never cross into the verification request. */
public final class RadioDecisionGate {
    private long request;
    private Boolean answer;
    private boolean closed;

    public synchronized void begin(long id) {
        if (closed || id <= 0) throw new IllegalStateException("Decision gate closed or invalid");
        request = id;
        answer = null;
    }
    public synchronized boolean answer(long id, boolean accepted) {
        if (closed || request != id || answer != null) return false;
        answer = accepted;
        notifyAll();
        return true;
    }
    public synchronized boolean await(long id, long timeoutMillis) throws InterruptedException {
        long end = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        while (!closed && request == id && answer == null) {
            long remaining = end - System.nanoTime();
            if (remaining <= 0) break;
            TimeUnit.NANOSECONDS.timedWait(this, remaining);
        }
        if (closed || request != id) return false;
        boolean accepted = Boolean.TRUE.equals(answer);
        request = 0;
        answer = null;
        return accepted;
    }
    public synchronized void cancel() {
        closed = true;
        request = 0;
        answer = null;
        notifyAll();
    }
}
