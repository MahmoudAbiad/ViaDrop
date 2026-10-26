package app.viadrop.viadrop;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class RadioDecisionGateTest {
    private static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) throws Exception {
        RadioDecisionGate gate = new RadioDecisionGate();
        gate.begin(1);
        check(!gate.answer(2, true));
        check(gate.answer(1, false));
        check(!gate.answer(1, true));
        check(!gate.await(1, 100));
        gate.begin(2);
        check(!gate.answer(1, true));
        check(gate.answer(2, true));
        check(gate.await(2, 100));
        gate.begin(3);
        check(!gate.await(3, 1));
        check(!gate.answer(3, true));
        RadioDecisionGate cancelled = new RadioDecisionGate();
        cancelled.begin(4);
        CountDownLatch started = new CountDownLatch(1), ended = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Thread worker = new Thread(() -> {
            try { started.countDown(); check(!cancelled.await(4, 60000)); }
            catch (Throwable error) { failure.set(error); }
            finally { ended.countDown(); }
        });
        worker.start();
        check(started.await(1, TimeUnit.SECONDS));
        cancelled.cancel();
        check(ended.await(1, TimeUnit.SECONDS));
        check(failure.get() == null);
        check(!cancelled.answer(4, true));
        try { cancelled.begin(5); throw new AssertionError(); }
        catch (IllegalStateException expected) { }
        for (int n=0;n<10000;n++) {
            long offer=10+n*2, verification=offer+1;
            gate.begin(offer); check(gate.answer(offer,true)); check(gate.await(offer,100));
            gate.begin(verification); check(!gate.answer(offer,true));
            check(gate.answer(verification,false)); check(!gate.await(verification,100));
        }
        System.out.println("PASS radio consent/verification IDs, cancellation, expiry and 10000 stale-reply cycles");
    }
}
