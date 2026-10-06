// Native bspwm preselection feedback: libwayland-client only.
// One opaque #100000 pixel, scaled by viewporter: no GTK/Cairo/Python or HiDPI
// buffer rounding. Margins and dimensions are output-local logical coordinates.
#define _GNU_SOURCE
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-layer-shell-client-protocol.h"
#include "viewporter-client-protocol.h"

#define MAX_RECTS 256
#define MAX_OUTPUTS 32
#define NAME_SIZE 128
#define STATE_LIMIT 65536
#define PIXEL_COLOR UINT32_C(0x00100000) // XRGB8888: fully opaque #100000
#define NAMESPACE "bspwm-presel-feedback"
#define HEADER "BSPWM_PRESEL_V2\n"

struct rect { char output[NAME_SIZE]; int x, y, w, h; };
struct app;
struct output {
    struct app *app;
    struct wl_output *object;
    uint32_t id;
    char name[NAME_SIZE];
};
struct view {
    struct app *app;
    struct output *output;
    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer;
    struct wp_viewport *viewport;
    struct rect rect;
};
struct app {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct zwlr_layer_shell_v1 *shell;
    struct wp_viewporter *viewporter;
    struct wl_buffer *buffer;
    struct output outputs[MAX_OUTPUTS];
    struct view views[MAX_RECTS];
    struct rect rects[MAX_RECTS];
    size_t count;
    bool dirty, had_state;
    struct stat last_stat;
};
static volatile sig_atomic_t running = 1;
static void stop(int signo) { (void)signo; running = 0; }

// Parse bounded plain text, not executable content. Output names cannot contain
// whitespace; those emitted by Hyprland are connector names (DP-4, HEADLESS-1).
static bool parse_state(char *text, struct rect *rects, size_t *count) {
    *count = 0;
    if (strncmp(text, HEADER, strlen(HEADER))) return false;
    char *line = text + strlen(HEADER);
    while (*line) {
        char *end = strchr(line, '\n');
        if (!end || *count == MAX_RECTS) return false;
        *end = '\0';
        struct rect r = {0};
        int used = 0;
        if (sscanf(line, "%127s%n", r.output, &used) != 1) return false;
        char *cursor = line + used;
        int *values[] = { &r.x, &r.y, &r.w, &r.h };
        for (size_t i = 0; i < 4; ++i) {
            if (!isspace((unsigned char)*cursor)) return false;
            char *next;
            errno = 0;
            long value = strtol(cursor, &next, 10);
            if (next == cursor || errno || value < INT_MIN || value > INT_MAX) return false;
            *values[i] = (int)value;
            cursor = next;
        }
        for (const char *p = cursor; *p; ++p) if (!isspace((unsigned char)*p)) return false;
        for (const char *p = r.output; *p; ++p)
            if (!isalnum((unsigned char)*p) && !strchr("_.:-", *p)) return false;
        if (r.x < 0 || r.y < 0 || r.w <= 0 || r.h <= 0 || r.x > 1000000 || r.y > 1000000 || r.w > 1000000 || r.h > 1000000)
            return false;
        rects[(*count)++] = r;
        line = end + 1;
    }
    return true;
}

static void destroy_view(struct view *v) {
    if (v->viewport) wp_viewport_destroy(v->viewport);
    if (v->layer) zwlr_layer_surface_v1_destroy(v->layer);
    if (v->surface) wl_surface_destroy(v->surface);
    memset(v, 0, sizeof(*v));
}
static void configure_view(void *data, struct zwlr_layer_surface_v1 *layer,
                           uint32_t serial, uint32_t width, uint32_t height) {
    struct view *v = data;
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    int w = width ? (int)width : v->rect.w;
    int h = height ? (int)height : v->rect.h;
    if (w <= 0 || h <= 0) { destroy_view(v); return; }
    wp_viewport_set_destination(v->viewport, w, h);
    struct wl_region *opaque = wl_compositor_create_region(v->app->compositor);
    wl_region_add(opaque, 0, 0, w, h);
    wl_surface_set_opaque_region(v->surface, opaque);
    wl_region_destroy(opaque);
    wl_surface_attach(v->surface, v->app->buffer, 0, 0);
    wl_surface_damage(v->surface, 0, 0, INT32_MAX, INT32_MAX);
    wl_surface_commit(v->surface);
}
static void close_view(void *data, struct zwlr_layer_surface_v1 *layer) {
    (void)layer; destroy_view(data);
}
static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = configure_view, .closed = close_view,
};

static void render(struct app *a) {
    for (size_t i = 0; i < MAX_RECTS; ++i) {
        struct view *v = &a->views[i];
        struct output *output = NULL;
        if (i < a->count) {
            for (size_t j = 0; j < MAX_OUTPUTS; ++j) {
                if (a->outputs[j].object && !strcmp(a->outputs[j].name, a->rects[i].output)) {
                    output = &a->outputs[j]; break;
                }
            }
        }
        if (!output) { destroy_view(v); continue; }
        if (v->surface && v->output != output) destroy_view(v);
        if (v->surface && !memcmp(&v->rect, &a->rects[i], sizeof(v->rect))) continue;
        v->app = a; v->output = output; v->rect = a->rects[i];
        if (!v->surface) {
            v->surface = wl_compositor_create_surface(a->compositor);
            v->viewport = wp_viewporter_get_viewport(a->viewporter, v->surface);
            v->layer = zwlr_layer_shell_v1_get_layer_surface(a->shell, v->surface, output->object,
                                                           ZWLR_LAYER_SHELL_V1_LAYER_TOP, NAMESPACE);
            zwlr_layer_surface_v1_add_listener(v->layer, &layer_listener, v);
            zwlr_layer_surface_v1_set_anchor(v->layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
            zwlr_layer_surface_v1_set_keyboard_interactivity(v->layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
            zwlr_layer_surface_v1_set_exclusive_zone(v->layer, -1);
            struct wl_region *empty = wl_compositor_create_region(a->compositor);
            wl_surface_set_input_region(v->surface, empty);
            wl_region_destroy(empty); // remains empty for the lifetime of the surface
        }
        zwlr_layer_surface_v1_set_margin(v->layer, v->rect.y, 0, 0, v->rect.x);
        zwlr_layer_surface_v1_set_size(v->layer, v->rect.w, v->rect.h);
        // Initial commit is bufferless. configure_view attaches only after ack.
        wl_surface_commit(v->surface);
    }
    a->dirty = false;
}

static void output_geometry(void *data, struct wl_output *object, int32_t x, int32_t y,
                            int32_t pw, int32_t ph, int32_t subpixel, const char *make,
                            const char *model, int32_t transform) {
    (void)data; (void)object; (void)x; (void)y; (void)pw; (void)ph;
    (void)subpixel; (void)make; (void)model; (void)transform;
}
static void output_mode(void *data, struct wl_output *object, uint32_t flags, int32_t w, int32_t h, int32_t rate) {
    (void)data; (void)object; (void)flags; (void)w; (void)h; (void)rate;
}
static void output_done(void *data, struct wl_output *object) { (void)data; (void)object; }
static void output_scale(void *data, struct wl_output *object, int32_t scale) { (void)data; (void)object; (void)scale; }
static void output_description(void *data, struct wl_output *object, const char *description) {
    (void)data; (void)object; (void)description;
}
static void output_name(void *data, struct wl_output *object, const char *name) {
    (void)object;
    struct output *o = data;
    snprintf(o->name, sizeof(o->name), "%s", name);
    o->app->dirty = true;
}
static const struct wl_output_listener output_listener = {
    .geometry = output_geometry, .mode = output_mode, .done = output_done,
    .scale = output_scale, .name = output_name, .description = output_description,
};
static void registry_add(void *data, struct wl_registry *registry, uint32_t id, const char *interface, uint32_t version) {
    struct app *a = data;
    if (!strcmp(interface, wl_compositor_interface.name))
        a->compositor = wl_registry_bind(registry, id, &wl_compositor_interface, version < 4 ? version : 4);
    else if (!strcmp(interface, wl_shm_interface.name))
        a->shm = wl_registry_bind(registry, id, &wl_shm_interface, 1);
    else if (!strcmp(interface, zwlr_layer_shell_v1_interface.name) && version >= 3)
        a->shell = wl_registry_bind(registry, id, &zwlr_layer_shell_v1_interface, 3);
    else if (!strcmp(interface, wp_viewporter_interface.name))
        a->viewporter = wl_registry_bind(registry, id, &wp_viewporter_interface, 1);
    else if (!strcmp(interface, wl_output_interface.name) && version >= 4) {
        for (size_t i = 0; i < MAX_OUTPUTS; ++i) if (!a->outputs[i].object) {
            struct output *o = &a->outputs[i];
            o->app = a; o->id = id;
            o->object = wl_registry_bind(registry, id, &wl_output_interface, 4);
            wl_output_add_listener(o->object, &output_listener, o);
            break;
        }
    }
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t id) {
    (void)registry;
    struct app *a = data;
    for (size_t i = 0; i < MAX_OUTPUTS; ++i) if (a->outputs[i].object && a->outputs[i].id == id) {
        for (size_t j = 0; j < MAX_RECTS; ++j)
            if (a->views[j].output == &a->outputs[i]) destroy_view(&a->views[j]);
        wl_output_release(a->outputs[i].object);
        memset(&a->outputs[i], 0, sizeof(a->outputs[i]));
        a->dirty = true;
    }
}
static const struct wl_registry_listener registry_listener = { .global = registry_add, .global_remove = registry_remove };

static void buffer_release(void *data, struct wl_buffer *buffer) { (void)data; (void)buffer; }
static const struct wl_buffer_listener buffer_listener = { .release = buffer_release };

static bool create_buffer(struct app *a) {
    int fd = memfd_create("bspwm-presel", MFD_CLOEXEC);
    if (fd < 0) return false;
    uint32_t color = PIXEL_COLOR;
    if (write(fd, &color, sizeof(color)) != sizeof(color)) { close(fd); return false; }
    struct wl_shm_pool *pool = wl_shm_create_pool(a->shm, fd, sizeof(color));
    a->buffer = wl_shm_pool_create_buffer(pool, 0, 1, 1, sizeof(color), WL_SHM_FORMAT_XRGB8888);
    if (a->buffer) wl_buffer_add_listener(a->buffer, &buffer_listener, a);
    wl_shm_pool_destroy(pool);
    close(fd);
    return a->buffer != NULL;
}

static void reload_state(struct app *a, const char *path) {
    struct stat st;
    if (stat(path, &st) < 0) {
        if (a->had_state) { a->had_state = false; a->count = 0; a->dirty = true; }
        return;
    }
    if (a->had_state && st.st_ino == a->last_stat.st_ino && st.st_size == a->last_stat.st_size &&
        st.st_mtim.tv_sec == a->last_stat.st_mtim.tv_sec && st.st_mtim.tv_nsec == a->last_stat.st_mtim.tv_nsec) return;
    a->had_state = true; a->last_stat = st; a->dirty = true; a->count = 0;
    char text[STATE_LIMIT + 1];
    FILE *file = fopen(path, "r");
    if (!file) return;
    size_t n = fread(text, 1, STATE_LIMIT, file);
    bool complete = !ferror(file) && fgetc(file) == EOF;
    fclose(file); text[n] = '\0';
    if (!complete || memchr(text, '\0', n) || !parse_state(text, a->rects, &a->count)) {
        a->count = 0;
        fprintf(stderr, "invalid feedback state (hidden): %s\n", path);
    }
}

// One-time migration. A pidfd pins the process identity; verify owner, script,
// --state argument AND the held singleton lock before signalling the old helper.
static void retire_helper(const char *state, const char *program, bool only_if_updated) {
    if (!state || !program) return;
    char path[PATH_MAX], args[8192];
    if (snprintf(path, sizeof(path), "%s.lock", state) >= (int)sizeof(path)) return;
    int lock = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (lock < 0) return;
    if (flock(lock, LOCK_EX | LOCK_NB) == 0) { close(lock); return; }
    if (errno != EWOULDBLOCK) { close(lock); return; }
    FILE *file = fdopen(lock, "r");
    long pid = 0;
    if (!file) { close(lock); return; }
    int scanned = fscanf(file, "%ld", &pid);
    fclose(file);
    if (scanned != 1 || pid <= 1 || pid > INT_MAX) return;
    int pidfd = (int)syscall(SYS_pidfd_open, (pid_t)pid, 0);
    if (pidfd < 0) return;
    snprintf(path, sizeof(path), "/proc/%ld/cmdline", pid);
    struct stat st;
    if (stat(path, &st) < 0 || st.st_uid != getuid()) { close(pidfd); return; }
    file = fopen(path, "r");
    if (!file) { close(pidfd); return; }
    size_t n = fread(args, 1, sizeof(args) - 1, file);
    fclose(file); args[n] = '\0';
    if (only_if_updated) {
        struct stat old_exe, new_exe;
        snprintf(path, sizeof(path), "/proc/%ld/exe", pid);
        if (stat(path, &old_exe) < 0 || stat(program, &new_exe) < 0 ||
            (old_exe.st_ino == new_exe.st_ino && old_exe.st_dev == new_exe.st_dev)) { close(pidfd); return; }
    }
    bool has_script = false, has_state = false;
    for (size_t i = 0; i < n;) {
        const char *arg = args + i;
        size_t len = strlen(arg);
        if (!strcmp(arg, program)) has_script = true;
        i += len + 1;
        if (!strcmp(arg, "--state") && i < n && !strcmp(args + i, state)) has_state = true;
    }
    if (has_script && has_state) {
        if (syscall(SYS_pidfd_send_signal, pidfd, SIGTERM, NULL, 0) < 0)
            perror("could not stop previous feedback helper");
        else {
            struct pollfd exited = { .fd = pidfd, .events = POLLIN };
            poll(&exited, 1, 2000);
        }
    }
    close(pidfd);
}

static int self_test(void) {
    struct rect rects[MAX_RECTS]; size_t count;
    char valid[] = HEADER "DP-4 8 40 1900 2000\nHDMI-A-2 0 0 800 600\n";
    assert(parse_state(valid, rects, &count) && count == 2);
    assert(!strcmp(rects[0].output, "DP-4") && rects[0].x == 8 && rects[0].h == 2000);
    char empty[] = HEADER; assert(parse_state(empty, rects, &count) && count == 0);
    const char *invalid[] = { "bad\n", HEADER "DP-4 0 0 0 10\n", HEADER "DP-4 -1 0 10 10\n",
        HEADER "DP-4 0 0 10 10 junk\n", HEADER "DP-4 0 0 10 10", HEADER "DP-4 0 0 1000001 1\n",
        HEADER "DP-4 0 0 999999999999999999999999999999999 1\n", HEADER "DP-4 0 0 10.5 5\n" };
    for (size_t i = 0; i < sizeof(invalid)/sizeof(invalid[0]); ++i) {
        char text[256]; snprintf(text, sizeof(text), "%s", invalid[i]);
        assert(!parse_state(text, rects, &count));
    }
    assert(PIXEL_COLOR == 0x00100000 && WL_SHM_FORMAT_XRGB8888 == 1);
    puts("native feedback self-test passed (parser, bounds, opaque color)");
    return 0;
}

int main(int argc, char **argv) {
    const char *state = NULL, *legacy = NULL;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--self-test")) return self_test();
        if (!strcmp(argv[i], "--state") && i + 1 < argc) state = argv[++i];
        else if (!strcmp(argv[i], "--legacy-state") && i + 1 < argc) legacy = argv[++i];
        else { fprintf(stderr, "usage: %s --state FILE [--legacy-state FILE]\n", argv[0]); return 1; }
    }
    if (!state) return 1;
    char lock_path[PATH_MAX];
    if (snprintf(lock_path, sizeof(lock_path), "%s.lock", state) >= (int)sizeof(lock_path)) return 1;
    int lock = open(lock_path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (lock < 0) { perror("feedback lock"); return 1; }
    if (flock(lock, LOCK_EX | LOCK_NB) < 0) {
        // Reloading updated native code must not leave the old executable
        // running forever just because it already owns the singleton lock.
        retire_helper(state, argv[0], true);
        if (flock(lock, LOCK_EX | LOCK_NB) < 0) { close(lock); return 0; }
    }
    if (ftruncate(lock, 0) == 0) dprintf(lock, "%ld\n", (long)getpid());
    struct app a = {0};
    int result = 1;
    a.display = wl_display_connect(NULL);
    if (!a.display) { fprintf(stderr, "cannot connect to Wayland display\n"); goto cleanup; }
    a.registry = wl_display_get_registry(a.display);
    wl_registry_add_listener(a.registry, &registry_listener, &a);
    if (wl_display_roundtrip(a.display) < 0 || wl_display_roundtrip(a.display) < 0) goto cleanup;
    if (!a.compositor || !a.shm || !a.shell || !a.viewporter) {
        fprintf(stderr, "compositor lacks layer-shell/viewporter/shm\n"); goto cleanup;
    }
    if (!create_buffer(&a)) { perror("feedback buffer"); goto cleanup; }
    const char *home = getenv("HOME");
    char script[PATH_MAX];
    if (home && snprintf(script, sizeof(script), "%s/.config/hypr/scripts/presel_feedback.py", home) < (int)sizeof(script))
        retire_helper(legacy, script, false);
    signal(SIGTERM, stop); signal(SIGINT, stop);
    while (running) {
        reload_state(&a, state);
        if (a.dirty) render(&a);
        while (wl_display_prepare_read(a.display) != 0)
            if (wl_display_dispatch_pending(a.display) < 0) goto cleanup;
        short events = POLLIN;
        if (wl_display_flush(a.display) < 0) {
            if (errno != EAGAIN) { wl_display_cancel_read(a.display); goto cleanup; }
            events |= POLLOUT;
        }
        struct pollfd fd = { .fd = wl_display_get_fd(a.display), .events = events };
        int ready = poll(&fd, 1, 50);
        if (ready > 0 && (fd.revents & POLLIN)) {
            if (wl_display_read_events(a.display) < 0) goto cleanup;
        } else wl_display_cancel_read(a.display);
        if (ready < 0 && errno != EINTR) goto cleanup;
        if (ready > 0 && (fd.revents & (POLLERR | POLLHUP | POLLNVAL))) goto cleanup;
        if (wl_display_dispatch_pending(a.display) < 0) goto cleanup;
    }
    result = 0;
cleanup:
    for (size_t i = 0; i < MAX_RECTS; ++i) destroy_view(&a.views[i]);
    for (size_t i = 0; i < MAX_OUTPUTS; ++i) if (a.outputs[i].object) wl_output_release(a.outputs[i].object);
    if (a.buffer) wl_buffer_destroy(a.buffer);
    if (a.viewporter) wp_viewporter_destroy(a.viewporter);
    if (a.shell) zwlr_layer_shell_v1_destroy(a.shell);
    if (a.shm) wl_shm_destroy(a.shm);
    if (a.compositor) wl_compositor_destroy(a.compositor);
    if (a.registry) wl_registry_destroy(a.registry);
    if (a.display) wl_display_disconnect(a.display);
    close(lock);
    return result;
}
