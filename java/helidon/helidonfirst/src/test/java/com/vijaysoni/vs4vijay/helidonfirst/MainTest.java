package com.vijaysoni.vs4vijay.helidonfirst;

import io.helidon.webserver.testing.junit5.DirectClient;
import io.helidon.webserver.testing.junit5.RoutingTest;

@RoutingTest
class MainTest extends AbstractMainTest {
    MainTest(DirectClient client) {
        super(client);
    }
}