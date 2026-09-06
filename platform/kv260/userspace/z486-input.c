// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include "z486-input.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define QUEUE_SIZE 256

struct byte_queue {
	uint8_t data[QUEUE_SIZE];
	unsigned read, write;
};

struct z486_input {
	int keyboard_fd, mouse_fd;
	bool shared_fd;
	struct byte_queue keyboard_queue, mouse_queue;
	struct byte_queue keyboard_reply, mouse_reply;
	uint8_t keyboard_pending;
	uint8_t keyboard_scan_set;
	uint8_t mouse_pending;
	uint8_t mouse_buttons;
	uint8_t mouse_resolution;
	uint8_t mouse_sample_rate;
	bool mouse_reporting;
	bool debug;
	bool left_ctrl_down, right_ctrl_down;
	bool left_alt_down, right_alt_down;
	bool stop_requested;
	int mouse_dx, mouse_dy;
};

static int queue_byte(struct byte_queue *queue, uint8_t value)
{
	unsigned next = (queue->write + 1) % QUEUE_SIZE;

	if (next == queue->read) {
		errno = ENOBUFS;
		return -1;
	}
	queue->data[queue->write] = value;
	queue->write = next;
	return 0;
}

static bool queue_empty(const struct byte_queue *queue)
{
	return queue->read == queue->write;
}

static uint8_t queue_pop(struct byte_queue *queue)
{
	uint8_t value = queue->data[queue->read];

	queue->read = (queue->read + 1) % QUEUE_SIZE;
	return value;
}

static int queue_bytes(struct byte_queue *queue, const uint8_t *bytes,
		       unsigned count)
{
	unsigned i;

	for (i = 0; i < count; i++)
		if (queue_byte(queue, bytes[i]))
			return -1;
	return 0;
}

struct key_code {
	uint8_t code;
	bool extended;
};

static struct key_code linux_to_set2(unsigned key)
{
	static const uint8_t normal[KEY_MAX + 1] = {
		[KEY_ESC] = 0x76, [KEY_1] = 0x16, [KEY_2] = 0x1e,
		[KEY_3] = 0x26, [KEY_4] = 0x25, [KEY_5] = 0x2e,
		[KEY_6] = 0x36, [KEY_7] = 0x3d, [KEY_8] = 0x3e,
		[KEY_9] = 0x46, [KEY_0] = 0x45, [KEY_MINUS] = 0x4e,
		[KEY_EQUAL] = 0x55, [KEY_BACKSPACE] = 0x66, [KEY_TAB] = 0x0d,
		[KEY_Q] = 0x15, [KEY_W] = 0x1d, [KEY_E] = 0x24,
		[KEY_R] = 0x2d, [KEY_T] = 0x2c, [KEY_Y] = 0x35,
		[KEY_U] = 0x3c, [KEY_I] = 0x43, [KEY_O] = 0x44,
		[KEY_P] = 0x4d, [KEY_LEFTBRACE] = 0x54, [KEY_RIGHTBRACE] = 0x5b,
		[KEY_ENTER] = 0x5a, [KEY_LEFTCTRL] = 0x14, [KEY_A] = 0x1c,
		[KEY_S] = 0x1b, [KEY_D] = 0x23, [KEY_F] = 0x2b,
		[KEY_G] = 0x34, [KEY_H] = 0x33, [KEY_J] = 0x3b,
		[KEY_K] = 0x42, [KEY_L] = 0x4b, [KEY_SEMICOLON] = 0x4c,
		[KEY_APOSTROPHE] = 0x52, [KEY_GRAVE] = 0x0e,
		[KEY_LEFTSHIFT] = 0x12, [KEY_BACKSLASH] = 0x5d,
		[KEY_Z] = 0x1a, [KEY_X] = 0x22, [KEY_C] = 0x21,
		[KEY_V] = 0x2a, [KEY_B] = 0x32, [KEY_N] = 0x31,
		[KEY_M] = 0x3a, [KEY_COMMA] = 0x41, [KEY_DOT] = 0x49,
		[KEY_SLASH] = 0x4a, [KEY_RIGHTSHIFT] = 0x59,
		[KEY_LEFTALT] = 0x11, [KEY_SPACE] = 0x29, [KEY_CAPSLOCK] = 0x58,
		[KEY_F1] = 0x05, [KEY_F2] = 0x06, [KEY_F3] = 0x04,
		[KEY_F4] = 0x0c, [KEY_F5] = 0x03, [KEY_F6] = 0x0b,
		[KEY_F7] = 0x83, [KEY_F8] = 0x0a, [KEY_F9] = 0x01,
		[KEY_F10] = 0x09, [KEY_NUMLOCK] = 0x77, [KEY_SCROLLLOCK] = 0x7e,
		[KEY_KP7] = 0x6c, [KEY_KP8] = 0x75, [KEY_KP9] = 0x7d,
		[KEY_KPMINUS] = 0x7b, [KEY_KP4] = 0x6b, [KEY_KP5] = 0x73,
		[KEY_KP6] = 0x74, [KEY_KPPLUS] = 0x79, [KEY_KP1] = 0x69,
		[KEY_KP2] = 0x72, [KEY_KP3] = 0x7a, [KEY_KP0] = 0x70,
		[KEY_KPDOT] = 0x71, [KEY_F11] = 0x78, [KEY_F12] = 0x07,
		[KEY_KPASTERISK] = 0x7c,
	};
	struct key_code result = {0};

	if (key <= KEY_MAX && normal[key]) {
		result.code = normal[key];
		return result;
	}
	switch (key) {
	case KEY_RIGHTCTRL: result.code = 0x14; break;
	case KEY_RIGHTALT: result.code = 0x11; break;
	case KEY_HOME: result.code = 0x6c; break;
	case KEY_UP: result.code = 0x75; break;
	case KEY_PAGEUP: result.code = 0x7d; break;
	case KEY_LEFT: result.code = 0x6b; break;
	case KEY_RIGHT: result.code = 0x74; break;
	case KEY_END: result.code = 0x69; break;
	case KEY_DOWN: result.code = 0x72; break;
	case KEY_PAGEDOWN: result.code = 0x7a; break;
	case KEY_INSERT: result.code = 0x70; break;
	case KEY_DELETE: result.code = 0x71; break;
	case KEY_KPENTER: result.code = 0x5a; break;
	case KEY_KPSLASH: result.code = 0x4a; break;
	case KEY_LEFTMETA: result.code = 0x1f; break;
	case KEY_RIGHTMETA: result.code = 0x27; break;
	case KEY_COMPOSE: result.code = 0x2f; break;
	default: return result;
	}
	result.extended = true;
	return result;
}

static int queue_key(struct z486_input *input, unsigned key, bool pressed)
{
	struct key_code code;
	uint8_t sequence[8];
	unsigned count = 0;

	if (key == KEY_PAUSE) {
		static const uint8_t pause[] = {0xe1, 0x14, 0x77, 0xe1,
						0xf0, 0x14, 0xf0, 0x77};
		return pressed ? queue_bytes(&input->keyboard_queue, pause,
					     sizeof(pause)) : 0;
	}
	if (key == KEY_SYSRQ) {
		static const uint8_t make[] = {0xe0, 0x12, 0xe0, 0x7c};
		static const uint8_t release[] = {0xe0, 0xf0, 0x7c, 0xe0,
						  0xf0, 0x12};
		return pressed ? queue_bytes(&input->keyboard_queue, make,
					     sizeof(make)) :
			queue_bytes(&input->keyboard_queue, release,
				    sizeof(release));
	}
	code = linux_to_set2(key);
	if (!code.code)
		return 0;
	if (code.extended)
		sequence[count++] = 0xe0;
	if (!pressed)
		sequence[count++] = 0xf0;
	sequence[count++] = code.code;
	return queue_bytes(&input->keyboard_queue, sequence, count);
}

static int queue_mouse_packet(struct z486_input *input, struct byte_queue *queue,
			      int dx, int dy)
{
	do {
		int step_x = dx < -127 ? -127 : dx > 127 ? 127 : dx;
		int step_y = dy < -127 ? -127 : dy > 127 ? 127 : dy;
		uint8_t bytes[3] = {0x08 | input->mouse_buttons, step_x, step_y};

		if (step_x < 0)
			bytes[0] |= 0x10;
		if (step_y < 0)
			bytes[0] |= 0x20;
		if (queue_bytes(queue, bytes, 3))
			return -1;
		dx -= step_x;
		dy -= step_y;
	} while (dx || dy);
	return 0;
}

static int handle_keyboard_event(struct z486_input *input,
				 const struct input_event *event)
{
	bool pressed;

	if (event->type != EV_KEY || event->value == 2 ||
	    event->code >= BTN_MISC)
		return 0;
	pressed = event->value != 0;
	switch (event->code) {
	case KEY_LEFTCTRL: input->left_ctrl_down = pressed; break;
	case KEY_RIGHTCTRL: input->right_ctrl_down = pressed; break;
	case KEY_LEFTALT: input->left_alt_down = pressed; break;
	case KEY_RIGHTALT: input->right_alt_down = pressed; break;
	case KEY_ESC:
		if (pressed &&
		    (input->left_ctrl_down || input->right_ctrl_down) &&
		    (input->left_alt_down || input->right_alt_down)) {
			input->stop_requested = true;
			return 0;
		}
		break;
	default: break;
	}
	return queue_key(input, event->code, pressed);
}

bool z486_input_stop_requested(const struct z486_input *input)
{
	return input && input->stop_requested;
}

static int handle_mouse_event(struct z486_input *input,
			      const struct input_event *event)
{
	if (event->type == EV_REL && event->code == REL_X)
		input->mouse_dx += event->value;
	else if (event->type == EV_REL && event->code == REL_Y)
		input->mouse_dy -= event->value;
	else if (event->type == EV_KEY) {
		unsigned bit;

		if (event->code == BTN_LEFT)
			bit = 0;
		else if (event->code == BTN_RIGHT)
			bit = 1;
		else if (event->code == BTN_MIDDLE)
			bit = 2;
		else
			return 0;
		if (event->value)
			input->mouse_buttons |= 1U << bit;
		else
			input->mouse_buttons &= ~(1U << bit);
	} else if (event->type == EV_SYN && event->code == SYN_REPORT) {
		if (input->mouse_reporting &&
		    queue_mouse_packet(input, &input->mouse_queue,
				       input->mouse_dx, input->mouse_dy))
			return -1;
		input->mouse_dx = 0;
		input->mouse_dy = 0;
	}
	return 0;
}

static int read_events(struct z486_input *input, int fd, bool keyboard,
		       bool mouse)
{
	struct input_event events[32];
	ssize_t count;
	unsigned i;

	while ((count = read(fd, events, sizeof(events))) > 0)
		for (i = 0; i < (unsigned)count / sizeof(events[0]); i++) {
			if (keyboard && handle_keyboard_event(input, &events[i]))
				return -1;
			if (mouse && handle_mouse_event(input, &events[i]))
				return -1;
		}
	if (count < 0 && errno != EAGAIN && errno != EINTR)
		return -1;
	return 0;
}

static int handle_keyboard_command(struct z486_input *input, uint8_t command)
{
	struct byte_queue *queue = &input->keyboard_reply;

	if (input->keyboard_pending) {
		if (input->keyboard_pending == 0xf0 && command && command <= 3)
			input->keyboard_scan_set = command;
		if (queue_byte(queue, 0xfa))
			return -1;
		if (input->keyboard_pending == 0xf0 && !command &&
		    queue_byte(queue, input->keyboard_scan_set))
			return -1;
		input->keyboard_pending = 0;
		return 0;
	}
	switch (command) {
	case 0xff:
		input->keyboard_scan_set = 2;
		if (queue_byte(queue, 0xfa) || queue_byte(queue, 0xaa))
			return -1;
		break;
	case 0xf2:
		if (queue_byte(queue, 0xfa) || queue_byte(queue, 0xab) ||
		    queue_byte(queue, 0x83))
			return -1;
		break;
	case 0xf0:
	case 0xf3:
	case 0xed:
		input->keyboard_pending = command;
		return queue_byte(queue, 0xfa);
	case 0xf6:
		input->keyboard_scan_set = 2;
		return queue_byte(queue, 0xfa);
	case 0xee:
		return queue_byte(queue, 0xee);
	case 0xf4:
	case 0xf5:
	case 0xfa:
		return queue_byte(queue, 0xfa);
	default:
		return queue_byte(queue, 0xfe);
	}
	return 0;
}

static int handle_mouse_command(struct z486_input *input, uint8_t command)
{
	struct byte_queue *queue = &input->mouse_reply;

	if (input->mouse_pending) {
		if (input->mouse_pending == 0xe8)
			input->mouse_resolution = command;
		else if (input->mouse_pending == 0xf3)
			input->mouse_sample_rate = command;
		input->mouse_pending = 0;
		return queue_byte(queue, 0xfa);
	}
	switch (command) {
	case 0xff: {
		static const uint8_t reply[] = {0xfa, 0xaa, 0x00};

		input->mouse_reporting = false;
		input->mouse_resolution = 2;
		input->mouse_sample_rate = 100;
		return queue_bytes(queue, reply, sizeof(reply));
	}
	case 0xf2:
		if (queue_byte(queue, 0xfa) || queue_byte(queue, 0x00))
			return -1;
		return 0;
	case 0xe9:
		if (queue_byte(queue, 0xfa) ||
		    queue_byte(queue, input->mouse_reporting ? 0x20 : 0) ||
		    queue_byte(queue, input->mouse_resolution) ||
		    queue_byte(queue, input->mouse_sample_rate))
			return -1;
		return 0;
	case 0xeb:
		if (queue_byte(queue, 0xfa))
			return -1;
		return queue_mouse_packet(input, queue, 0, 0);
	case 0xe8:
	case 0xf3:
		input->mouse_pending = command;
		return queue_byte(queue, 0xfa);
	case 0xf4:
		input->mouse_reporting = true;
		return queue_byte(queue, 0xfa);
	case 0xf5:
		input->mouse_reporting = false;
		return queue_byte(queue, 0xfa);
	case 0xf6:
		input->mouse_reporting = false;
		input->mouse_resolution = 2;
		input->mouse_sample_rate = 100;
		return queue_byte(queue, 0xfa);
	default:
		return queue_byte(queue, 0xfa);
	}
}

static int open_event(const char *path)
{
	int fd;

	if (!path)
		return -1;
	fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0)
		return -1;
	/* Match Main_MiSTer: while the core owns input, keep it out of the VT. */
	if (ioctl(fd, EVIOCGRAB, 1) && errno != ENOTTY) {
		int saved_errno = errno;

		close(fd);
		errno = saved_errno;
		return -1;
	}
	return fd;
}

struct z486_input *z486_input_open(const char *keyboard, const char *mouse,
				   int debug)
{
	struct z486_input *input = calloc(1, sizeof(*input));

	if (!input)
		return NULL;
	input->keyboard_fd = -1;
	input->mouse_fd = -1;
	input->debug = debug;
	input->keyboard_fd = open_event(keyboard);
	if (keyboard && input->keyboard_fd < 0)
		goto error;
	if (keyboard && mouse && !strcmp(keyboard, mouse)) {
		input->mouse_fd = input->keyboard_fd;
		input->shared_fd = true;
	} else {
		input->mouse_fd = open_event(mouse);
		if (mouse && input->mouse_fd < 0)
			goto error;
	}
	input->keyboard_scan_set = 2;
	input->mouse_resolution = 2;
	input->mouse_sample_rate = 100;
	return input;

error:
	{
		int saved_errno = errno;

		z486_input_close(input);
		errno = saved_errno;
	}
	return NULL;
}

void z486_input_close(struct z486_input *input)
{
	if (!input)
		return;
	if (input->keyboard_fd >= 0) {
		ioctl(input->keyboard_fd, EVIOCGRAB, 0);
		close(input->keyboard_fd);
	}
	if (input->mouse_fd >= 0 && !input->shared_fd) {
		ioctl(input->mouse_fd, EVIOCGRAB, 0);
		close(input->mouse_fd);
	}
	free(input);
}

int z486_input_service(struct z486_input *input,
		       const struct z486_ps2_bus *bus)
{
	uint32_t status;

	if (!input || !bus || !bus->status || !bus->write_keyboard ||
	    !bus->write_mouse || !bus->clear_host) {
		errno = EINVAL;
		return -1;
	}
	status = bus->status(bus->context);
	if (status & (1U << 8)) {
		uint8_t command = status >> 16;

		if (input->debug)
			fprintf(stderr, "PS/2 keyboard command=%02x\n", command);
		bus->clear_host(bus->context, 1);
		return handle_keyboard_command(input, command);
	}
	if (status & (1U << 9)) {
		uint8_t command = status >> 24;

		if (input->debug)
			fprintf(stderr, "PS/2 mouse command=%02x\n", command);
		bus->clear_host(bus->context, 2);
		return handle_mouse_command(input, command);
	}
	if (input->shared_fd) {
		if (read_events(input, input->keyboard_fd, true, true))
			return -1;
	} else {
		if (input->keyboard_fd >= 0 &&
		    read_events(input, input->keyboard_fd, true, false))
			return -1;
		if (input->mouse_fd >= 0 &&
		    read_events(input, input->mouse_fd, false, true))
			return -1;
	}
	if (status & 1) {
		if (!queue_empty(&input->keyboard_reply)) {
			uint8_t value = queue_pop(&input->keyboard_reply);

			if (input->debug)
				fprintf(stderr, "PS/2 keyboard reply=%02x\n", value);
			bus->write_keyboard(bus->context, value);
		} else if (!queue_empty(&input->keyboard_queue)) {
			uint8_t value = queue_pop(&input->keyboard_queue);

			if (input->debug)
				fprintf(stderr, "PS/2 keyboard event=%02x\n", value);
			bus->write_keyboard(bus->context, value);
		}
	}
	if (status & 2) {
		if (!queue_empty(&input->mouse_reply)) {
			uint8_t value = queue_pop(&input->mouse_reply);

			if (input->debug)
				fprintf(stderr, "PS/2 mouse reply=%02x\n", value);
			bus->write_mouse(bus->context, value);
		} else if (!queue_empty(&input->mouse_queue)) {
			uint8_t value = queue_pop(&input->mouse_queue);

			if (input->debug)
				fprintf(stderr, "PS/2 mouse event=%02x\n", value);
			bus->write_mouse(bus->context, value);
		}
	}
	return 0;
}
