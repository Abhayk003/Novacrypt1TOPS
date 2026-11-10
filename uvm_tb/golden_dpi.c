#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include "svdpi.h"

static int g_fd = -1;
static char g_response[8192];

static int connect_server(void) {
    const char *host = getenv("GOLDEN_HOST");
    const char *port_s = getenv("GOLDEN_PORT");
    int port = port_s ? atoi(port_s) : 45721;
    if (!host || !*host) host = "127.0.0.1";

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) return -1;

    g_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (g_fd < 0) return -1;
    if (connect(g_fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
        close(g_fd);
        g_fd = -1;
        return -1;
    }
    return 0;
}

static int send_request(const char *request) {
    size_t n = strlen(request);
    size_t sent = 0;
    while (sent < n) {
        ssize_t rc = send(g_fd, request + sent, n - sent, 0);
        if (rc <= 0) return -1;
        sent += (size_t)rc;
    }

    size_t used = 0;
    while (used + 1 < sizeof(g_response)) {
        ssize_t rc = recv(g_fd, g_response + used, 1, 0);
        if (rc <= 0) return -1;
        if (g_response[used++] == '\n') break;
    }
    g_response[used] = '\0';
    return 0;
}

static int response_ok(void) {
    return strstr(g_response, "\"ok\":true") != NULL ||
           strstr(g_response, "\"ok\": true") != NULL;
}

int golden_init(const char *instr_file, const char *dmem_file) {
    if (g_fd < 0 && connect_server() != 0) return 0;

    char req[4096];
    snprintf(req, sizeof(req),
             "{\"cmd\":\"init\",\"instr\":\"%s\",\"dmem\":\"%s\"}\n",
             instr_file ? instr_file : "", dmem_file ? dmem_file : "");
    if (send_request(req) != 0 || !response_ok()) return 0;
    return 1;
}

int golden_irq(int line, int value) {
    if (g_fd < 0) return 0;
    const char *name = (line == 0) ? "timer" :
                       (line == 1) ? "software" : "external";
    char req[256];
    snprintf(req, sizeof(req),
             "{\"cmd\":\"irq\",\"line\":\"%s\",\"value\":%d}\n",
             name, value ? 1 : 0);
    if (send_request(req) != 0 || !response_ok()) return 0;
    return 1;
}

const char *golden_step(void) {
    if (g_fd < 0) return "ERR,golden_server_not_connected";
    if (send_request("{\"cmd\":\"step\"}\n") != 0)
        return "ERR,golden_server_io";

    if (!response_ok()) {
        static char err[8192];
        snprintf(err, sizeof(err), "ERR,%s", g_response);
        return err;
    }

    /* Convert the JSON event into a compact SV-friendly line. The server's
       response is intentionally simple and contains either a W or R event. */
    static char out[512];
unsigned pc, opcode, funct3, funct7, addr, data, strb, rdata;

if (sscanf(g_response,
           "{\"ok\":true,\"event\":{\"kind\":\"W\",\"pc\":%u,\"opcode\":%u,\"funct3\":%u,\"funct7\":%u,\"addr\":%u,\"data\":%u,\"strb\":%u}}",
           &pc, &opcode, &funct3, &funct7, &addr, &data, &strb) == 7) {
    snprintf(out, sizeof(out),
             "W %08x %02x %x %02x %08x %08x %x",
             pc, opcode, funct3, funct7, addr, data, strb);
    return out;
}

if (sscanf(g_response,
           "{\"ok\":true,\"event\":{\"kind\":\"R\",\"pc\":%u,\"opcode\":%u,\"funct3\":%u,\"funct7\":%u,\"addr\":%u,\"rdata\":%u}}",
           &pc, &opcode, &funct3, &funct7, &addr, &rdata) == 6) {
    snprintf(out, sizeof(out),
             "R %08x %02x %x %02x %08x %08x",
             pc, opcode, funct3, funct7, addr, rdata);
    return out;
}
}

int golden_dump_dmem(const char *path) {
    if (g_fd < 0) return 0;
    char req[4096];
    snprintf(req, sizeof(req),
             "{\"cmd\":\"dump_dmem\",\"path\":\"%s\"}\n",
             path ? path : "");
    if (send_request(req) != 0 || !response_ok()) return 0;
    return 1;
}

void golden_stop(void) {
    if (g_fd < 0) return;
    (void)send_request("{\"cmd\":\"stop\"}\n");
    close(g_fd);
    g_fd = -1;
}
