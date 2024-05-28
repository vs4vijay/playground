package io.examples.helidon.virtualthread;

import java.util.Random;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;




import io.helidon.config.Config;


import io.helidon.http.InternalServerException;
import io.helidon.webclient.api.WebClient;
import io.helidon.webserver.WebServer;
import io.helidon.webserver.http.HttpRouting;
import io.helidon.webserver.http.ServerRequest;
import io.helidon.webserver.http.ServerResponse;

public class BlockingMain {
    
    private static final AtomicInteger COUNTER = new AtomicInteger();

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
        // Create and start webserver

        Config config = Config.create();

        WebServer ws = WebServer.builder()
                .routing(BlockingMain::routing)
                .config(config.get("server"))
                .build()
                .start();

        // Create client for BlockingService to use
        BlockingService.client(WebClient.builder()
                .baseUri("http://localhost:" + ws.port())
                .build());
    }

    /**
     * Routing adds:
     * (1) filter to add {@link #SERVER} to all responses
     * (2) a "/remote" service to be accessed by {@link BlockingService}
     * (3) the {@link BlockingService} itself.
     *
     * @param rules routing rules to update
     */
    static void routing(HttpRouting.Builder rules) {
        rules.addFilter((chain, req, res) -> {
                    chain.proceed();
                })
                .get("/remote", BlockingMain::remote)
                .register("/", new BlockingService());
    }

    /**
     * Simulates a "remote" service accessed using {@link BlockingService}.
     * The implementation randomly sleeps for up to half a second to
     * simulate some business logic.
     *
     * @param req the request
     * @param res the response
     */
    private static void remote(ServerRequest req, ServerResponse res) {
        int sleepMillis = RANDOM.nextInt(500);
        int counter = COUNTER.incrementAndGet();

        try {
            TimeUnit.MILLISECONDS.sleep(sleepMillis);
        } catch (InterruptedException e) {
            throw new InternalServerException("Failed to sleep", e);
        }
        res.send("remote_" + counter);
    }
}