// Headless protocol test: a tiny Wayland server validates the real helper's
// surfaces, buffer color/opacity, input region, placement, resize and dismissal.
#define _GNU_SOURCE
#include <assert.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wayland-server.h>
#include "layer-server.h"
#include "viewport-server.h"

static struct wl_display *display;
static char state_path[4096];
static unsigned serial = 0;
static int phase = 0;
struct surface {
    struct wl_resource *resource, *layer, *buffer;
    int width, height, configured_w, configured_h, viewport_w, viewport_h, x, y;
    int exclusive, keyboard, anchors;
    bool input_empty, acknowledged;
};
static void update_state(const char *text) {
    char tmp[4200]; snprintf(tmp, sizeof(tmp), "%s.tmp", state_path);
    FILE *f = fopen(tmp, "w"); assert(f);
    assert(fputs(text, f) >= 0); assert(fclose(f) == 0); assert(rename(tmp, state_path) == 0);
}
static void destroy_resource(struct wl_client *c, struct wl_resource *r) { wl_resource_destroy(r); }
static void region_add(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) {
    wl_resource_set_user_data(r, (void *)1);
}
static const struct wl_region_interface region_impl = { .destroy=destroy_resource, .add=region_add, .subtract=region_add };
static void surface_destroyed(struct wl_resource *r) {
    free(wl_resource_get_user_data(r));
    if (phase == 2) { phase = 3; wl_display_terminate(display); }
}
static void attach(struct wl_client *c, struct wl_resource *r, struct wl_resource *buffer, int32_t x, int32_t y) {
    ((struct surface *)wl_resource_get_user_data(r))->buffer = buffer;
}
static void damage(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) {}
static void opaque(struct wl_client *c, struct wl_resource *r, struct wl_resource *region) {}
static void input(struct wl_client *c, struct wl_resource *r, struct wl_resource *region) {
    ((struct surface *)wl_resource_get_user_data(r))->input_empty = region && !wl_resource_get_user_data(region);
}
static void commit(struct wl_client *c, struct wl_resource *r) {
    struct surface *s = wl_resource_get_user_data(r);
    assert(s->layer);
    if (s->configured_w != s->width || s->configured_h != s->height) {
        s->configured_w = s->width; s->configured_h = s->height; s->acknowledged = false;
        zwlr_layer_surface_v1_send_configure(s->layer, ++serial, s->width, s->height);
        return;
    }
    if (!s->buffer) return;
    assert(s->acknowledged && s->input_empty && s->keyboard == 0 && s->exclusive == -1);
    assert(s->anchors == (ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT));
    assert(s->viewport_w == s->width && s->viewport_h == s->height);
    struct wl_shm_buffer *b = wl_shm_buffer_get(s->buffer); assert(b);
    assert(wl_shm_buffer_get_width(b) == 1 && wl_shm_buffer_get_height(b) == 1);
    assert(wl_shm_buffer_get_format(b) == WL_SHM_FORMAT_XRGB8888);
    wl_shm_buffer_begin_access(b);
    assert(*(uint32_t *)wl_shm_buffer_get_data(b) == 0x00100000);
    wl_shm_buffer_end_access(b);
    wl_buffer_send_release(s->buffer);
    if (phase == 0) {
        assert(s->x == 12 && s->y == 34 && s->width == 300 && s->height == 400);
        phase = 1;
        update_state("BSPWM_PRESEL_V2\nDP-4 100 200 100 200\n");
    } else if (phase == 1) {
        assert(s->x == 100 && s->y == 200 && s->width == 100 && s->height == 200);
        phase = 2;
        update_state("BSPWM_PRESEL_V2\n");
    }
}
static const struct wl_surface_interface surface_impl = {
    .destroy=destroy_resource, .attach=attach, .damage=damage, .set_opaque_region=opaque,
    .set_input_region=input, .commit=commit, .damage_buffer=damage,
};
static void create_surface(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct surface *s = calloc(1, sizeof(*s)); assert(s);
    s->resource = wl_resource_create(c, &wl_surface_interface, 4, id);
    wl_resource_set_implementation(s->resource, &surface_impl, s, surface_destroyed);
}
static void create_region(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *region = wl_resource_create(c, &wl_region_interface, 1, id);
    wl_resource_set_implementation(region, &region_impl, NULL, NULL);
}
static const struct wl_compositor_interface compositor_impl = { .create_surface=create_surface, .create_region=create_region };
static void bind_compositor(struct wl_client *c, void *data, uint32_t v, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_compositor_interface, v, id);
    wl_resource_set_implementation(r, &compositor_impl, NULL, NULL);
}
static const struct wl_output_interface output_impl = { .release=destroy_resource };
static void bind_output(struct wl_client *c, void *data, uint32_t v, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_output_interface, v, id);
    wl_resource_set_implementation(r, &output_impl, NULL, NULL);
    wl_output_send_geometry(r, 3840, 0, 600, 340, 0, "test", "test", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT, 3840, 2160, 60000);
    wl_output_send_scale(r, 2); // viewporter geometry must still remain logical
    wl_output_send_name(r, "DP-4"); wl_output_send_done(r);
}
static void layer_size(struct wl_client *c, struct wl_resource *r, uint32_t w, uint32_t h) {
    struct surface *s = wl_resource_get_user_data(r); s->width=w; s->height=h;
}
static void anchor(struct wl_client *c, struct wl_resource *r, uint32_t a) { ((struct surface *)wl_resource_get_user_data(r))->anchors=a; }
static void zone(struct wl_client *c, struct wl_resource *r, int32_t a) { ((struct surface *)wl_resource_get_user_data(r))->exclusive=a; }
static void keyboard(struct wl_client *c, struct wl_resource *r, uint32_t a) { ((struct surface *)wl_resource_get_user_data(r))->keyboard=a; }
static void margin(struct wl_client *c, struct wl_resource *r, int32_t t, int32_t right, int32_t b, int32_t l) {
    struct surface *s=wl_resource_get_user_data(r); s->x=l; s->y=t;
}
static void ack(struct wl_client *c, struct wl_resource *r, uint32_t value) {
    assert(value == serial); ((struct surface *)wl_resource_get_user_data(r))->acknowledged=true;
}
static const struct zwlr_layer_surface_v1_interface layer_impl = {
    .set_size=layer_size, .set_anchor=anchor, .set_exclusive_zone=zone, .set_margin=margin,
    .set_keyboard_interactivity=keyboard, .ack_configure=ack, .destroy=destroy_resource,
};
static void get_layer(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *surf,
                      struct wl_resource *output, uint32_t layer, const char *name) {
    assert(output && layer == ZWLR_LAYER_SHELL_V1_LAYER_TOP && !strcmp(name, "bspwm-presel-feedback"));
    struct surface *s=wl_resource_get_user_data(surf);
    s->layer=wl_resource_create(c, &zwlr_layer_surface_v1_interface, 3, id);
    wl_resource_set_implementation(s->layer, &layer_impl, s, NULL);
}
static const struct zwlr_layer_shell_v1_interface shell_impl = { .get_layer_surface=get_layer, .destroy=destroy_resource };
static void bind_shell(struct wl_client *c, void *data, uint32_t v, uint32_t id) {
    struct wl_resource *r=wl_resource_create(c, &zwlr_layer_shell_v1_interface, v, id);
    wl_resource_set_implementation(r, &shell_impl, NULL, NULL);
}
static void destination(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) {
    struct surface *s=wl_resource_get_user_data(r); s->viewport_w=w; s->viewport_h=h;
}
static const struct wp_viewport_interface viewport_impl = { .destroy=destroy_resource, .set_destination=destination };
static void get_viewport(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *surf) {
    struct wl_resource *view=wl_resource_create(c, &wp_viewport_interface, 1, id);
    wl_resource_set_implementation(view, &viewport_impl, wl_resource_get_user_data(surf), NULL);
}
static const struct wp_viewporter_interface viewporter_impl = { .destroy=destroy_resource, .get_viewport=get_viewport };
static void bind_viewporter(struct wl_client *c, void *data, uint32_t v, uint32_t id) {
    struct wl_resource *r=wl_resource_create(c, &wp_viewporter_interface, v, id);
    wl_resource_set_implementation(r, &viewporter_impl, NULL, NULL);
}
static int timeout(void *data) { fprintf(stderr, "native protocol test timed out at phase %d\n", phase); wl_display_terminate(display); return 0; }
int main(int argc, char **argv) {
    assert(argc == 2 && getenv("XDG_RUNTIME_DIR"));
    snprintf(state_path, sizeof(state_path), "%s/feedback.state", getenv("XDG_RUNTIME_DIR"));
    update_state("BSPWM_PRESEL_V2\nDP-4 12 34 300 400\n");
    display=wl_display_create(); assert(display);
    assert(wl_display_init_shm(display) == 0);
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_global_create(display, &wl_output_interface, 4, NULL, bind_output);
    wl_global_create(display, &zwlr_layer_shell_v1_interface, 3, NULL, bind_shell);
    wl_global_create(display, &wp_viewporter_interface, 1, NULL, bind_viewporter);
    const char *socket=wl_display_add_socket_auto(display); assert(socket);
    setenv("WAYLAND_DISPLAY", socket, 1);
    struct wl_event_source *timer=wl_event_loop_add_timer(wl_display_get_event_loop(display), timeout, NULL);
    wl_event_source_timer_update(timer, 5000);
    pid_t child=fork(); assert(child >= 0);
    if (!child) { execl(argv[1], argv[1], "--state", state_path, NULL); _exit(127); }
    wl_display_run(display);
    kill(child, SIGTERM);
    int status; waitpid(child, &status, 0);
    wl_event_source_remove(timer);
    wl_display_destroy_clients(display); wl_display_destroy(display);
    assert(phase == 3 && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    puts("native Wayland protocol test passed: solid color, no input/focus, exact geometry, resize, hide");
    return 0;
}
