package io.examples.helidon.virtualthread;

import java.util.ArrayList;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import io.helidon.webclient.api.WebClient;
import io.helidon.webserver.http.HttpRules;
import io.helidon.webserver.http.HttpService;
import io.helidon.webserver.http.ServerRequest;
import io.helidon.webserver.http.ServerResponse;

class BlockingService implements HttpService {

    private static WebClient client;

    static void client(WebClient client) {
        BlockingService.client = client;
    }

    /**
     * Defines routing rules for this service.
     *
     * @param httpRules the rules to update
     */
    @Override
    public void routing(HttpRules httpRules) {
        httpRules.get("/one", this::one)
                .get("/sequence", this::sequence)
                .get("/parallel", this::parallel)
                .get("/sleep", this::sleep);
    }

    /**
     * Calls remote service a single time.
     *
     * @param req the request
     * @param res the response
     */
    private void one(ServerRequest req, ServerResponse res) {
        String response = callRemote(client());

        res.send(response);
    }

    /**
     * Calls remote service {@code count} times in sequence.
     *
     * @param req the request
     * @param res the response
     */
    private void sequence(ServerRequest req, ServerResponse res) {
        int count = count(req);

        var responses = new ArrayList<String>();

        for (int i = 0; i < count; i++) {
            responses.add(callRemote(client));
        }

        res.send("Combined results: " + responses);
    }

    /**
     * Calls remote service {@code count} concurrently using an executor
     * of virtual threads.
     *
     * @param req the request
     * @param res the response
     * @throws Exception if an error occurs
     */
    private void parallel(ServerRequest req, ServerResponse res) throws Exception {
        try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
            int count = count(req);

            var futures = new ArrayList<Future<String>>();
            for (int i = 0; i < count; i++) {
                futures.add(exec.submit(() -> callRemote(client)));
            }

            var responses = new ArrayList<String>();
            for (var future : futures) {
                responses.add(future.get());
            }

            res.send("Combined results: " + responses);
        }
    }

    private void sleep(ServerRequest req, ServerResponse res) throws Exception {
        Thread.sleep(1000);
        res.send("finished");
    }

    private int count(ServerRequest req) {
        return req.query().first("count").map(Integer::parseInt).orElse(10);
    }

    private static WebClient client() {
        if (client == null) {
            throw new RuntimeException("Client must be configured on BlockingService");
        }
        return client;
    }

    private static String callRemote(WebClient client) {
        return client.get()
                .path("/remote")
                .requestEntity(String.class);
    }
}