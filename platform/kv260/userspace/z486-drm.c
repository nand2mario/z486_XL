// SPDX-License-Identifier: MIT
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define CONNECTOR_CONNECTED 1

static volatile sig_atomic_t running = 1;

static void stop(int signal_number)
{
	(void)signal_number;
	running = 0;
}

static void *allocate(size_t count, size_t size)
{
	void *memory = calloc(count ? count : 1, size);

	if (!memory) {
		fprintf(stderr, "out of memory\n");
		exit(EXIT_FAILURE);
	}
	return memory;
}

static int get_resources(int fd, struct drm_mode_card_res *resources,
			 uint32_t **connector_ids, uint32_t **crtc_ids)
{
	uint32_t *fb_ids, *encoder_ids;

	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, resources))
		return -1;
	fb_ids = allocate(resources->count_fbs, sizeof(*fb_ids));
	*connector_ids = allocate(resources->count_connectors,
				  sizeof(**connector_ids));
	*crtc_ids = allocate(resources->count_crtcs, sizeof(**crtc_ids));
	encoder_ids = allocate(resources->count_encoders, sizeof(*encoder_ids));
	resources->fb_id_ptr = (uintptr_t)fb_ids;
	resources->connector_id_ptr = (uintptr_t)*connector_ids;
	resources->crtc_id_ptr = (uintptr_t)*crtc_ids;
	resources->encoder_id_ptr = (uintptr_t)encoder_ids;
	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, resources))
		return -1;
	free(fb_ids);
	free(encoder_ids);
	return 0;
}

static int find_display(int fd, const char *mode_name, uint32_t *connector_id,
			uint32_t *crtc_id, unsigned int *crtc_index,
			struct drm_mode_modeinfo *selected_mode)
{
	struct drm_mode_card_res resources = {0};
	uint32_t *connector_ids = NULL, *crtc_ids = NULL;
	unsigned int requested_width = 0, requested_height = 0;
	unsigned int i;

	if (sscanf(mode_name, "%ux%u", &requested_width, &requested_height) != 2)
		return -1;
	if (get_resources(fd, &resources, &connector_ids, &crtc_ids))
		return -1;

	for (i = 0; i < resources.count_connectors; ++i) {
		struct drm_mode_get_connector connector = {0};
		struct drm_mode_modeinfo temporary_mode;
		struct drm_mode_modeinfo *modes;
		uint32_t *encoders, *properties;
		uint64_t *property_values;
		struct drm_mode_get_encoder encoder = {0};
		unsigned int j, k;

		connector.connector_id = connector_ids[i];
		connector.count_modes = 1;
		connector.modes_ptr = (uintptr_t)&temporary_mode;
		if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &connector))
			continue;
		modes = allocate(connector.count_modes, sizeof(*modes));
		encoders = allocate(connector.count_encoders, sizeof(*encoders));
		properties = allocate(connector.count_props, sizeof(*properties));
		property_values = allocate(connector.count_props,
					   sizeof(*property_values));
		connector.modes_ptr = (uintptr_t)modes;
		connector.encoders_ptr = (uintptr_t)encoders;
		connector.props_ptr = (uintptr_t)properties;
		connector.prop_values_ptr = (uintptr_t)property_values;
		if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &connector) ||
		    connector.connection != CONNECTOR_CONNECTED)
			goto next_connector;

		for (j = 0; j < connector.count_modes; ++j) {
			if (modes[j].hdisplay != requested_width ||
			    modes[j].vdisplay != requested_height)
				continue;
			*connector_id = connector.connector_id;
			*selected_mode = modes[j];
			encoder.encoder_id = connector.encoder_id ?
				connector.encoder_id :
				(connector.count_encoders ? encoders[0] : 0);
			if (encoder.encoder_id &&
			    !ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &encoder))
				*crtc_id = encoder.crtc_id;
			if (!*crtc_id && resources.count_crtcs)
				*crtc_id = crtc_ids[0];
			for (k = 0; k < resources.count_crtcs; ++k)
				if (crtc_ids[k] == *crtc_id)
					*crtc_index = k;
			free(modes); free(encoders); free(properties);
			free(property_values); free(connector_ids); free(crtc_ids);
			return *crtc_id ? 0 : -1;
		}

next_connector:
		free(modes); free(encoders); free(properties); free(property_values);
	}
	free(connector_ids);
	free(crtc_ids);
	errno = ENOENT;
	return -1;
}

static int set_pattern(int fd, unsigned int crtc_index, uint64_t value,
			uint32_t *plane_id)
{
	struct drm_mode_get_plane_res plane_resources = {0};
	uint32_t *plane_ids;
	unsigned int i;

	if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &plane_resources))
		return -1;
	plane_ids = allocate(plane_resources.count_planes, sizeof(*plane_ids));
	plane_resources.plane_id_ptr = (uintptr_t)plane_ids;
	if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &plane_resources))
		return -1;

	for (i = 0; i < plane_resources.count_planes; ++i) {
		struct drm_mode_get_plane plane = {.plane_id = plane_ids[i]};
		struct drm_mode_obj_get_properties properties = {0};
		uint32_t *property_ids;
		uint64_t *property_values;
		unsigned int j;

		if (ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &plane) ||
		    !(plane.possible_crtcs & (1U << crtc_index)))
			continue;
		properties.obj_id = plane.plane_id;
		properties.obj_type = DRM_MODE_OBJECT_PLANE;
		if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &properties))
			continue;
		property_ids = allocate(properties.count_props,
					sizeof(*property_ids));
		property_values = allocate(properties.count_props,
					   sizeof(*property_values));
		properties.props_ptr = (uintptr_t)property_ids;
		properties.prop_values_ptr = (uintptr_t)property_values;
		if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &properties))
			return -1;
		for (j = 0; j < properties.count_props; ++j) {
			struct drm_mode_get_property property = {
				.prop_id = property_ids[j],
			};
			struct drm_mode_obj_set_property set = {
				.value = value,
				.prop_id = property_ids[j],
				.obj_id = plane.plane_id,
				.obj_type = DRM_MODE_OBJECT_PLANE,
			};

			if (!ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &property) &&
			    !strcmp(property.name, "pattern")) {
				int result = ioctl(fd, DRM_IOCTL_MODE_OBJ_SETPROPERTY, &set);
				*plane_id = plane.plane_id;
				free(property_ids); free(property_values); free(plane_ids);
				return result;
			}
		}
		free(property_ids);
		free(property_values);
	}
	free(plane_ids);
	errno = ENOENT;
	return -1;
}

static int pattern_value(const char *name)
{
	static const char *const names[] = {
		NULL, "color-ramp", "lines", "color-square",
		"red", "green", "blue", "yellow",
	};
	unsigned int i;

	for (i = 1; i < sizeof(names) / sizeof(names[0]); ++i)
		if (!strcmp(name, names[i]))
			return i;
	return -1;
}

static void standard_1080p60(struct drm_mode_modeinfo *mode)
{
	memset(mode, 0, sizeof(*mode));
	mode->clock = 148500;
	mode->hdisplay = 1920;
	mode->hsync_start = 2008;
	mode->hsync_end = 2052;
	mode->htotal = 2200;
	mode->hskew = 0;
	mode->vdisplay = 1080;
	mode->vsync_start = 1084;
	mode->vsync_end = 1089;
	mode->vtotal = 1125;
	mode->vscan = 0;
	mode->vrefresh = 60;
	mode->flags = DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC;
	mode->type = DRM_MODE_TYPE_USERDEF;
	strncpy(mode->name, "1920x1080", sizeof(mode->name) - 1);
}

static int create_dummy_framebuffer(int fd, const struct drm_mode_modeinfo *mode,
				    struct drm_mode_create_dumb *dumb,
				    uint32_t *fb_id)
{
	struct drm_mode_fb_cmd2 add = {0};

	dumb->width = mode->hdisplay;
	dumb->height = mode->vdisplay;
	dumb->bpp = 32;
	if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, dumb))
		return -1;
	add.width = dumb->width;
	add.height = dumb->height;
	add.pixel_format = DRM_FORMAT_XRGB8888;
	add.handles[0] = dumb->handle;
	add.pitches[0] = dumb->pitch;
	if (ioctl(fd, DRM_IOCTL_MODE_ADDFB2, &add))
		return -1;
	*fb_id = add.fb_id;
	return 0;
}

int main(int argc, char **argv)
{
	const char *device = "/dev/dri/card0";
	const char *pattern_name = argc > 1 ? argv[1] : "color-square";
	const char *mode_name = argc > 2 ? argv[2] : "1920x1080";
	struct drm_mode_modeinfo mode = {0};
	struct drm_mode_crtc crtc = {0};
	struct drm_mode_create_dumb dumb = {0};
	struct drm_mode_destroy_dumb destroy = {0};
	struct drm_mode_fb_cmd remove = {0};
	uint32_t connector_id = 0, crtc_id = 0, crtc_index = 0, plane_id = 0;
	uint32_t fb_id = 0;
	int force_1080 = !strncmp(mode_name, "1920x1080", 9);
	int found = -1;
	unsigned int attempt;
	struct drm_set_client_cap universal_planes = {
		.capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES,
		.value = 1,
	};
	int pattern = pattern_value(pattern_name);
	int fd;

	if (argc > 3 || pattern < 0) {
		fprintf(stderr, "usage: %s {color-ramp|lines|color-square|red|green|blue|yellow} [WIDTHxHEIGHT]\n", argv[0]);
		return EXIT_FAILURE;
	}
	fd = open(device, O_RDWR | O_CLOEXEC);
	if (fd < 0 || ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &universal_planes)) {
		fprintf(stderr, "open %s: %s\n", device, strerror(errno));
		return EXIT_FAILURE;
	}
	for (attempt = 0; attempt < 5; ++attempt) {
		connector_id = crtc_id = crtc_index = 0;
		found = find_display(fd, force_1080 ? "640x480" : mode_name,
				     &connector_id, &crtc_id, &crtc_index, &mode);
		if (!found)
			break;
		sleep(1);
	}
	if (found) {
		fprintf(stderr, "find connected %s mode on %s: %s\n",
			mode_name, device, strerror(errno));
		return EXIT_FAILURE;
	}
	if (force_1080)
		standard_1080p60(&mode);
	if (set_pattern(fd, crtc_index, pattern, &plane_id)) {
		if (errno == ENOENT)
			fprintf(stderr,
				"AVPG plane property 'pattern' not found on %s; "
				"load the live-hdmi FPGA application first\n",
				device);
		else
			fprintf(stderr, "set pattern property: %s\n",
				strerror(errno));
		return EXIT_FAILURE;
	}
	if (create_dummy_framebuffer(fd, &mode, &dumb, &fb_id)) {
		fprintf(stderr, "create dummy framebuffer: %s\n", strerror(errno));
		return EXIT_FAILURE;
	}
	crtc.set_connectors_ptr = (uintptr_t)&connector_id;
	crtc.count_connectors = 1;
	crtc.crtc_id = crtc_id;
	crtc.fb_id = fb_id;
	crtc.mode_valid = 1;
	crtc.mode = mode;
	if (ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc)) {
		fprintf(stderr, "enable CRTC: %s\n", strerror(errno));
		goto cleanup;
	}

	printf("%s: %s %ux%u@%u (connector %u, CRTC %u, plane %u)\n",
		pattern_name, device, mode.hdisplay, mode.vdisplay, mode.vrefresh,
		connector_id, crtc_id, plane_id);
	printf("Press Ctrl-C to disable the live pipeline.\n");
	fflush(stdout);
	signal(SIGINT, stop);
	signal(SIGTERM, stop);
	signal(SIGHUP, stop);
	while (running)
		pause();

	memset(&crtc, 0, sizeof(crtc));
	crtc.crtc_id = crtc_id;
	ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc);

cleanup:
	remove.fb_id = fb_id;
	ioctl(fd, DRM_IOCTL_MODE_RMFB, &remove.fb_id);
	destroy.handle = dumb.handle;
	ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
	close(fd);
	return running ? EXIT_FAILURE : EXIT_SUCCESS;
}
