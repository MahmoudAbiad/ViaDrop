// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop;
import java.util.HashSet;
import java.util.Set;

/** UI-thread worker accounting. Register BEFORE enqueueing a job and complete
 * only AFTER its hardware/native handles have been released. A stopped session
 * cannot be reused until every registered (including queued) job completes.
 */
public final class SessionWorkDrain {
    public static final class Job { private Job() {} }
    private final Thread owner = Thread.currentThread();
    private final Set<Job> jobs = new HashSet<>();
    private boolean sealed;
    private Runnable released;
    public Job begin() {
        requireOwner();
        if (sealed) throw new IllegalStateException("Session workers are closing");
        Job job = new Job(); jobs.add(job); return job;
    }
    public boolean complete(Job job) {
        requireOwner();
        if (!jobs.remove(job)) return false;
        deliverIfEmpty(); return true;
    }
    public void seal(Runnable onReleased) {
        requireOwner();
        if (sealed || onReleased == null) throw new IllegalStateException("Invalid worker cleanup");
        sealed = true; released = onReleased; deliverIfEmpty();
    }
    private void deliverIfEmpty() {
        if (sealed && jobs.isEmpty() && released != null) {
            Runnable done = released; released = null; done.run();
        }
    }
    private void requireOwner() {
        if (Thread.currentThread() != owner) throw new IllegalStateException("Session worker accounting requires its owner thread");
    }
}
