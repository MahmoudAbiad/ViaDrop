// Copyright 2026 Mahmoud Abiad. All rights reserved.
package app.viadrop.viadrop;
import java.util.ArrayList;
import java.util.List;

/** Host simulation of the actual worker barrier used by AudioBridge. */
public final class AudioSessionDrainTest {
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    static void busy(Runnable run){try{run.run();}catch(IllegalStateException expected){return;}throw new AssertionError("Expected busy rejection");}
    public static void main(String[] args){
        NativeSessionState state = new NativeSessionState(e -> {throw e;});
        SessionWorkDrain drain = new SessionWorkDrain();
        List<String> events = new ArrayList<>();
        long generation = state.begin(10);
        SessionWorkDrain.Job reader = drain.begin(), decoder = drain.begin();
        long stop = state.stopOwned(10,() -> events.add("stop replied"));
        state.stopOwned(10,() -> events.add("second stop replied"));
        drain.seal(() -> {events.add("all resources released");state.finishStop(stop);});
        check(!state.isCurrent(generation),"Old microphone packet remained valid after stop");
        busy(() -> state.begin(20));
        events.add("reader released hardware");
        drain.complete(reader);
        check(!events.contains("stop replied"),"Stop replied before OFDM handle was released");
        check(!drain.complete(reader),"Duplicate reader completion counted twice");
        SessionWorkDrain foreign = new SessionWorkDrain();
        check(!drain.complete(foreign.begin()),"Foreign session completed this session's job");
        events.add("decoder released handle");
        drain.complete(decoder);
        check(events.indexOf("stop replied") > events.indexOf("all resources released"),"Reply preceded resource cleanup");
        check(events.contains("second stop replied"),"Joined stop reply was lost");
        long next = state.begin(20);
        state.stopOwned(10,null);
        check(state.isCurrent(next),"Old audio cleanup cancelled a new microphone");
        System.out.println("PASS microphone/decoder barrier, duplicate/foreign worker completion, joined stops and restart");

        SessionWorkDrain playback = new SessionWorkDrain();
        SessionWorkDrain.Job queuedEncoding = playback.begin();
        long ticket = state.stopOwned(20,null);
        playback.seal(() -> state.finishStop(ticket));
        busy(playback::begin);
        busy(() -> state.begin(30));
        // A queued job is registered even before its executor starts. Cancelled
        // work must reach finally and account for its skipped encode/play job.
        playback.complete(queuedEncoding);
        state.begin(30);
        check(!playback.complete(queuedEncoding),"Queued encode cleanup completed twice");
        System.out.println("PASS stop before queued encode starts waits for its finally");

        int[] replies={0};
        NativeSessionState repeated=new NativeSessionState(e -> {throw e;});
        for(int i=0;i<10000;i++){
            repeated.begin(i+1);
            SessionWorkDrain loop=new SessionWorkDrain();
            SessionWorkDrain.Job a=loop.begin(),b=loop.begin();
            long t=repeated.stopOwned(i+1,()->replies[0]++);
            loop.seal(()->repeated.finishStop(t));
            if((i&1)==0){loop.complete(a);loop.complete(b);}else{loop.complete(b);loop.complete(a);}
        }
        check(replies[0]==10000,"Repeated audio drain lost a reply");
        System.out.println("PASS 10000 two-worker audio teardown cycles / exactly-once completion");
    }
}
