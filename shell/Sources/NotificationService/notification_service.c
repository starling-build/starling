// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The freedesktop notification daemon, Starling side. One vtable, four
// methods, one queue. The shape (thread, euid drop, pinned bus address,
// NameLost complaint, ALLOW_REPLACEMENT name claim, pipe-woken loop) is
// portal_service.c's — divergences there have already cost debugging time,
// so anything structural fixed in one file probably wants fixing in both.

#define _GNU_SOURCE

#include "notification_service.h"

#include <errno.h>
#include <poll.h>
#include <time.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <systemd/sd-bus.h>

#define NOTIF_BUS_NAME "org.freedesktop.Notifications"
#define NOTIF_OBJ_PATH "/org/freedesktop/Notifications"
#define NOTIF_IFACE    "org.freedesktop.Notifications"

#define CMD_SHUTDOWN 1
#define CMD_EMIT     2

typedef struct {
    uint32_t id;
    uint32_t reason;
} PendingClose;

struct NotificationService {
    sd_bus *bus;
    char *bus_address;
    unsigned int target_uid;

    pthread_t thread;
    int thread_started;
    volatile int running;
    int pipe_fd[2];

    pthread_mutex_t init_mutex;
    pthread_cond_t init_cond;
    int init_done;
    int init_result;

    pthread_mutex_t mutex;
    uint32_t next_id;
    PendingClose *pending;
    int pending_count;
    int pending_cap;

    notification_posted_fn posted;
    notification_close_requested_fn close_requested;
    void *userdata;
};

// ============================================================================
// Methods
// ============================================================================

/* Notify(app_name s, replaces_id u, app_icon s, summary s, body s,
 *        actions as, hints a{sv}, expire_timeout i) → id u */
static int _notify(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    NotificationService *ns = userdata;
    const char *app_name = NULL, *app_icon = NULL;
    const char *summary = NULL, *body = NULL;
    uint32_t replaces_id = 0;
    int urgency = 1;
    int32_t expire_timeout = -1;
    int r;

    r = sd_bus_message_read(m, "sus", &app_name, &replaces_id, &app_icon);
    if (r < 0) return r;
    r = sd_bus_message_read(m, "ss", &summary, &body);
    if (r < 0) return r;
    r = sd_bus_message_skip(m, "as");   /* actions — v1 serves none */
    if (r < 0) return r;

    /* hints a{sv}: only urgency matters yet; everything else is skipped
     * whole. The spec allows urgency as byte; some clients send it as
     * anything integral, so accept the common spellings. */
    r = sd_bus_message_enter_container(m, 'a', "{sv}");
    if (r < 0) return r;
    for (;;) {
        r = sd_bus_message_enter_container(m, 'e', "sv");
        if (r <= 0) break;
        const char *key = NULL;
        r = sd_bus_message_read(m, "s", &key);
        if (r < 0) return r;
        if (key && strcmp(key, "urgency") == 0) {
            const char *contents = NULL;
            r = sd_bus_message_peek_type(m, NULL, &contents);
            if (r < 0) return r;
            if (contents && strcmp(contents, "y") == 0) {
                uint8_t u = 1;
                r = sd_bus_message_enter_container(m, 'v', "y");
                if (r < 0) return r;
                r = sd_bus_message_read(m, "y", &u);
                if (r < 0) return r;
                r = sd_bus_message_exit_container(m);
                if (r < 0) return r;
                urgency = u;
            } else {
                r = sd_bus_message_skip(m, "v");
                if (r < 0) return r;
            }
        } else {
            r = sd_bus_message_skip(m, "v");
            if (r < 0) return r;
        }
        r = sd_bus_message_exit_container(m);
        if (r < 0) return r;
    }
    r = sd_bus_message_exit_container(m);
    if (r < 0) return r;

    r = sd_bus_message_read(m, "i", &expire_timeout);
    if (r < 0) return r;

    uint32_t id;
    pthread_mutex_lock(&ns->mutex);
    if (replaces_id != 0) {
        id = replaces_id;
    } else {
        id = ns->next_id++;
        if (ns->next_id == 0) ns->next_id = 1;   /* u32 wrap: 0 is "none" */
    }
    pthread_mutex_unlock(&ns->mutex);

    if (ns->posted)
        ns->posted(ns->userdata, id,
                   app_name ? app_name : "",
                   summary ? summary : "",
                   body ? body : "",
                   urgency, expire_timeout, replaces_id != 0);

    return sd_bus_reply_method_return(m, "u", id);
}

static int _close_notification(sd_bus_message *m, void *userdata,
                               sd_bus_error *ret_error) {
    NotificationService *ns = userdata;
    uint32_t id = 0;
    int r = sd_bus_message_read(m, "u", &id);
    if (r < 0) return r;
    if (ns->close_requested)
        ns->close_requested(ns->userdata, id);
    return sd_bus_reply_method_return(m, "");
}

static int _get_capabilities(sd_bus_message *m, void *userdata,
                             sd_bus_error *ret_error) {
    /* Only what the banners actually render. Advertising "actions" without
     * buttons would make every client send buttons nobody can press. */
    return sd_bus_reply_method_return(m, "as", 1, "body");
}

static int _get_server_information(sd_bus_message *m, void *userdata,
                                   sd_bus_error *ret_error) {
    return sd_bus_reply_method_return(m, "ssss",
                                      "Starling", "Starling", "0.1", "1.2");
}

static const sd_bus_vtable notif_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Notify", "susssasa{sv}i", "u", _notify,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("CloseNotification", "u", "", _close_notification,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("GetCapabilities", "", "as", _get_capabilities,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("GetServerInformation", "", "ssss", _get_server_information,
                  SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("NotificationClosed", "uu", 0),
    SD_BUS_SIGNAL("ActionInvoked", "us", 0),
    SD_BUS_VTABLE_END
};

// ============================================================================
// Thread
// ============================================================================

static int _thread_set_euid(uid_t euid) {
    return syscall(SYS_setresuid, (uid_t)-1, euid, (uid_t)-1);
}

static int _on_name_lost(sd_bus_message *m, void *userdata,
                         sd_bus_error *ret_error) {
    const char *name = NULL;
    if (sd_bus_message_read(m, "s", &name) < 0 || !name)
        return 0;
    if (strcmp(name, NOTIF_BUS_NAME) == 0)
        fprintf(stderr, "[NotificationService] LOST %s — another daemon took "
                        "it; notifications now go to that process, not the "
                        "shell's banners\n", NOTIF_BUS_NAME);
    return 0;
}

static int _setup_bus(NotificationService *ns) {
    int r;

    if (ns->target_uid != 0 && geteuid() != ns->target_uid) {
        if (_thread_set_euid(ns->target_uid) < 0) {
            fprintf(stderr, "[NotificationService] seteuid(%u): %s\n",
                    (unsigned)ns->target_uid, strerror(errno));
            return -errno;
        }
    }

    if (ns->bus_address) {
        r = sd_bus_new(&ns->bus);
        if (r < 0) return r;
        r = sd_bus_set_address(ns->bus, ns->bus_address);
        if (r < 0) return r;
        r = sd_bus_set_bus_client(ns->bus, 1);
        if (r < 0) return r;
        r = sd_bus_start(ns->bus);
        if (r < 0) return r;
    } else {
        r = sd_bus_open_user(&ns->bus);
        if (r < 0) return r;
    }

    r = sd_bus_add_object_vtable(ns->bus, NULL, NOTIF_OBJ_PATH,
                                 NOTIF_IFACE, notif_vtable, ns);
    if (r < 0) {
        fprintf(stderr, "[NotificationService] Failed to register %s: %s\n",
                NOTIF_IFACE, strerror(-r));
        return r;
    }

    r = sd_bus_match_signal(ns->bus, NULL, "org.freedesktop.DBus",
                            "/org/freedesktop/DBus", "org.freedesktop.DBus",
                            "NameLost", _on_name_lost, ns);
    if (r < 0)
        fprintf(stderr, "[NotificationService] NameLost match failed: %s\n",
                strerror(-r));

    r = sd_bus_request_name(ns->bus, NOTIF_BUS_NAME,
                            SD_BUS_NAME_ALLOW_REPLACEMENT
                            | SD_BUS_NAME_REPLACE_EXISTING);
    if (r < 0) {
        fprintf(stderr, "[NotificationService] Failed to claim %s: %s\n",
                NOTIF_BUS_NAME, strerror(-r));
        return r;
    }
    fprintf(stderr, "[NotificationService] Claimed %s\n", NOTIF_BUS_NAME);
    return 0;
}

static void _drain_pending(NotificationService *ns) {
    for (;;) {
        PendingClose pc;
        pthread_mutex_lock(&ns->mutex);
        if (ns->pending_count == 0) {
            pthread_mutex_unlock(&ns->mutex);
            return;
        }
        pc = ns->pending[0];
        memmove(ns->pending, ns->pending + 1,
                (size_t)(ns->pending_count - 1) * sizeof(PendingClose));
        ns->pending_count--;
        pthread_mutex_unlock(&ns->mutex);

        int r = sd_bus_emit_signal(ns->bus, NOTIF_OBJ_PATH, NOTIF_IFACE,
                                   "NotificationClosed", "uu",
                                   pc.id, pc.reason);
        if (r < 0)
            fprintf(stderr, "[NotificationService] NotificationClosed(%u): %s\n",
                    pc.id, strerror(-r));
    }
}

/* Block until the bus or `extra_fd` has something, or sd-bus's own deadline.
 *
 * The sd-bus event-loop integration, as documented: ask the connection for its
 * fd, the events it wants, and its next timeout, and poll them yourself. The
 * alternative (`sd_bus_wait`) can only watch the bus, which is why every
 * caller of it ends up passing a timeout to cover whatever else it needs to
 * notice. Returns 0 only on a real error.
 *
 * The portal service has the same loop with one more fd — see
 * shell/Sources/PortalService/portal_service.c. */
static int _bus_poll(sd_bus *bus, int extra_fd) {
    int fd = sd_bus_get_fd(bus);
    int events = sd_bus_get_events(bus);
    if (fd < 0 || events < 0) return 0;

    uint64_t deadline_usec = 0;
    int r = sd_bus_get_timeout(bus, &deadline_usec);
    if (r < 0) return 0;

    int timeout_ms = -1;                    /* nothing due: wait indefinitely */
    if (deadline_usec != UINT64_MAX) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        uint64_t now_usec = (uint64_t)ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000;
        timeout_ms = deadline_usec > now_usec
            ? (int)((deadline_usec - now_usec + 999) / 1000)
            : 0;
    }

    struct pollfd fds[2] = {
        { fd, (short)events, 0 },
        { extra_fd, POLLIN, 0 },
    };
    int n = poll(fds, extra_fd >= 0 ? 2 : 1, timeout_ms);
    if (n < 0 && errno != EINTR) return 0;
    return 1;
}

static void *_service_thread(void *arg) {
    NotificationService *ns = arg;
    int r = _setup_bus(ns);

    pthread_mutex_lock(&ns->init_mutex);
    ns->init_result = r;
    ns->init_done = 1;
    pthread_cond_signal(&ns->init_cond);
    pthread_mutex_unlock(&ns->init_mutex);

    if (r < 0) return NULL;

    while (ns->running) {
        for (;;) {
            r = sd_bus_process(ns->bus, NULL);
            if (r <= 0) break;
        }

        uint8_t cmd;
        while (read(ns->pipe_fd[0], &cmd, 1) == 1) {
            if (cmd == CMD_EMIT)
                _drain_pending(ns);
            else if (cmd == CMD_SHUTDOWN)
                goto done;
        }

        // Wait on the bus AND the command pipe together, for as long as
        // sd-bus says it has nothing due.
        //
        // This used to be `sd_bus_wait(bus, 200ms)`, which watches only the
        // bus fd — so the pipe the shell writes to was noticed on the next
        // timeout rather than when it was written, and the 200 ms cap was
        // there to bound that. Five wakeups a second, forever, on a desktop
        // where nothing is calling us. Polling the pipe alongside the bus
        // makes the cap unnecessary: `sd_bus_get_timeout` gives the only
        // deadline sd-bus actually has (a method call's timeout), and
        // UINT64_MAX means "nothing due", which is the idle case.
        if (!_bus_poll(ns->bus, ns->pipe_fd[0])) break;
    }

done:
    return NULL;
}

// ============================================================================
// Public API
// ============================================================================

NotificationService *notification_service_create(void) {
    NotificationService *ns = calloc(1, sizeof(NotificationService));
    if (!ns) return NULL;
    ns->pipe_fd[0] = ns->pipe_fd[1] = -1;
    ns->next_id = 1;
    pthread_mutex_init(&ns->mutex, NULL);
    pthread_mutex_init(&ns->init_mutex, NULL);
    pthread_cond_init(&ns->init_cond, NULL);
    return ns;
}

void notification_service_destroy(NotificationService *ns) {
    if (!ns) return;
    notification_service_stop(ns);
    if (ns->pipe_fd[0] >= 0) close(ns->pipe_fd[0]);
    if (ns->pipe_fd[1] >= 0) close(ns->pipe_fd[1]);
    free(ns->pending);
    free(ns->bus_address);
    free(ns);
}

void notification_service_set_callbacks(NotificationService *ns,
                                        notification_posted_fn posted,
                                        notification_close_requested_fn close_requested,
                                        void *userdata) {
    if (!ns) return;
    ns->posted = posted;
    ns->close_requested = close_requested;
    ns->userdata = userdata;
}

int notification_service_start(NotificationService *ns,
                               const char *bus_address,
                               unsigned int target_uid) {
    if (!ns || ns->thread_started) return -EINVAL;

    if (pipe2(ns->pipe_fd, O_NONBLOCK | O_CLOEXEC) < 0)
        return -errno;

    ns->bus_address = bus_address ? strdup(bus_address) : NULL;
    ns->target_uid = target_uid;
    ns->running = 1;
    ns->init_done = 0;

    int r = pthread_create(&ns->thread, NULL, _service_thread, ns);
    if (r != 0) {
        ns->running = 0;
        return -r;
    }
    ns->thread_started = 1;

    pthread_mutex_lock(&ns->init_mutex);
    while (!ns->init_done)
        pthread_cond_wait(&ns->init_cond, &ns->init_mutex);
    r = ns->init_result;
    pthread_mutex_unlock(&ns->init_mutex);
    return r;
}

void notification_service_stop(NotificationService *ns) {
    if (!ns || !ns->thread_started) return;
    ns->running = 0;
    uint8_t cmd = CMD_SHUTDOWN;
    (void)!write(ns->pipe_fd[1], &cmd, 1);
    pthread_join(ns->thread, NULL);
    ns->thread_started = 0;
    if (ns->bus) {
        sd_bus_flush_close_unref(ns->bus);
        ns->bus = NULL;
    }
}

void notification_service_emit_closed(NotificationService *ns,
                                      uint32_t id, uint32_t reason) {
    if (!ns || !ns->thread_started) return;
    pthread_mutex_lock(&ns->mutex);
    if (ns->pending_count == ns->pending_cap) {
        int cap = ns->pending_cap ? ns->pending_cap * 2 : 8;
        PendingClose *grown = realloc(ns->pending,
                                      (size_t)cap * sizeof(PendingClose));
        if (!grown) {
            pthread_mutex_unlock(&ns->mutex);
            return;
        }
        ns->pending = grown;
        ns->pending_cap = cap;
    }
    ns->pending[ns->pending_count++] =
        (PendingClose){ .id = id, .reason = reason };
    pthread_mutex_unlock(&ns->mutex);
    uint8_t cmd = CMD_EMIT;
    (void)!write(ns->pipe_fd[1], &cmd, 1);
}
