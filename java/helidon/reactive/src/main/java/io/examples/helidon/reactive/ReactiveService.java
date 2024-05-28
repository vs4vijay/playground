package io.examples.helidon.reactive;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.helidon.common.reactive.Multi;
import io.helidon.common.reactive.Single;
import io.helidon.faulttolerance.Async;

import io.helidon.webclient.WebClient;

import io.helidon.webserver.Routing;
import io.helidon.webserver.ServerRequest;
import io.helidon.webserver.ServerResponse;
import io.helidon.webserver.Service;

class ReactiveService implements Service {
    private static final ExecutorService EXECUTOR = Executors.newVirtualThreadPerTaskExecutor();
    private static final Async ASYNC = Async.builder().executor(EXECUTOR).build();

    private static WebClient client;

    /**
     * Defines routing rules for this service.
     *
     * @param rules the rules to update
     */
    @Override
    public void update(Routing.Rules rules) {
        rules.get("/one", this::one)
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
        Single<String> response = client.get()
                .request(String.class);

        response.forSingle(res::send)
                .exceptionally(res::send);
    }

    /**
     * Calls remote service {@code count} times in sequence.
     *
     * @param req the request
     * @param res the response
     */
    private void sequence(ServerRequest req, ServerResponse res) {
        int count = count(req);

        Multi.range(0, count)
                .flatMap(i -> client.get().request(String.class), 1, false, 1)
                .collectList()
                .map(it -> "Combined results: " + it)
                .onError(res::send)
                .forSingle(res::send);
    }

    /**
     * Calls remote service {@code count} times concurrently.
     *
     * @param req the request
     * @param res the response
     */
    private void parallel(ServerRequest req, ServerResponse res) {
        int count = count(req);

        Multi.range(0, count)
                .flatMap(i -> client.get().request(String.class), 32, false, 32)
                .collectList()
                .map(it -> "Combined results: " + it)
                .onError(res::send)
                .forSingle(res::send);
    }

    private void sleep(ServerRequest req, ServerResponse res) {
        ASYNC.invoke(() -> {
                    try {
                        Thread.sleep(1000);
                    } catch (Exception e) {
                        return "failed: " + e;
                    }
                    return "finished";
                })
                .forSingle(res::send)
                .exceptionally(res::send);
    }

    private int count(ServerRequest req) {
        return req.queryParams().first("count").map(Integer::parseInt).orElse(10);
    }

    static void port(int port) {
        client = WebClient.builder()
                .baseUri("http://localhost:" + port + "/remote")
                .build();
    }

    private static WebClient client() {
        if (client == null) {
            throw new RuntimeException("Port must be configured on NonBlockingService");
        }
        return client;
    }
}
