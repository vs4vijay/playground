package io.examples.helidon.reactive;

import java.time.Duration;
import java.util.Random;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import io.helidon.config.Config;
import io.helidon.common.LogConfig;
import io.helidon.webserver.Routing;
import io.helidon.webserver.ServerRequest;
import io.helidon.webserver.ServerResponse;
import io.helidon.webserver.WebServer;

public class ReactiveMain {
    private static final AtomicInteger COUNTER = new AtomicInteger();
    private static final ScheduledExecutorService SCHEDULED_EXECUTOR = Executors.newSingleThreadScheduledExecutor();

    /**
     * Random generator to simulate remote service. No need to use secure random to
     * compute sleep times
     */
    private static final Random RANDOM = new Random();
    /**
     * Main method for this service.
     *
     * @param args CLI args
     */
    public static void main(String[] args) {
        LogConfig.configureRuntime();

        // Create and start webserver
        WebServer ws = WebServer.builder()
                .routing(ReactiveMain::routing)
                .config(Config.create().get("server"))
                .build()
                .start()
                .await(Duration.ofSeconds(10));

        // Set port in reactive server
        ReactiveService.port(ws.port());
    }

    /**
     * Routing adds:
     * (1) a "/remote" service to be accessed by {@link ReactiveService}
     * (2) the {@link ReactiveService} itself.
     *
     * @param rules routing rules to update
     */
    static void routing(Routing.Rules rules) {
        rules.get("/remote", ReactiveMain::remote)
                .register("/", new ReactiveService());
    }

    /**
     * Simulates a "remote" service accessed using {@link ReactiveService}.
     * The implementation randomly sleeps for up to half a second to
     * simulate some business logic.
     *
     * @param req the request
     * @param res the response
     */
    private static void remote(ServerRequest req, ServerResponse res) {
        // the remote service will randomly sleep up to half a second
        int sleepMillis = RANDOM.nextInt(500);
        int counter = COUNTER.incrementAndGet();

        SCHEDULED_EXECUTOR.schedule(() -> res.send("remote_" + counter), 1000, TimeUnit.MILLISECONDS);
    }
}
