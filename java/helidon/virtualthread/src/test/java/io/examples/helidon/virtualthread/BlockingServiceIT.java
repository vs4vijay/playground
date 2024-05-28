package io.examples.helidon.virtualthread;

import io.helidon.webserver.testing.junit5.ServerTest;
import io.helidon.webclient.api.WebClient;

// test proper HTTP communication, opens socket
@ServerTest
class BlockingServiceIT extends AbstractBlockingServiceTest {
    BlockingServiceIT(WebClient client) {
        super(client);
    }
}
