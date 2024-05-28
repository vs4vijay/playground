package io.examples.helidon.reactive;

import io.helidon.webclient.WebClient;

public class ReactiveClient {

    /**
     * Entry point for simple reactive client.
     *
     * @param args CLI args
     */
    public static void main(String[] args) {
        WebClient client = WebClient.create();

        client.get()
                .uri("http://localhost:8080/one")
                .request()
                .forSingle(response -> {
                    System.out.println(response.status());
                    response.content().as(String.class)
                                    .forSingle(System.out::println);
                });
    }
}
