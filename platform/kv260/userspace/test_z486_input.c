// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include "z486-input.h"

#include <assert.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct fake_ps2 {
	uint32_t status;
	uint8_t keyboard[32], mouse[32];
	unsigned keyboard_count, mouse_count;
};

static uint32_t fake_status(void *context)
{
	return ((struct fake_ps2 *)context)->status;
}

static void fake_keyboard(void *context, uint8_t value)
{
	struct fake_ps2 *fake = context;

	assert(fake->keyboard_count < sizeof(fake->keyboard));
	fake->keyboard[fake->keyboard_count++] = value;
}

static void fake_mouse(void *context, uint8_t value)
{
	struct fake_ps2 *fake = context;

	assert(fake->mouse_count < sizeof(fake->mouse));
	fake->mouse[fake->mouse_count++] = value;
}

static void fake_clear(void *context, unsigned mask)
{
	struct fake_ps2 *fake = context;

	if (mask & 1)
		fake->status &= ~(1U << 8);
	if (mask & 2)
		fake->status &= ~(1U << 9);
}

int main(void)
{
	char keyboard_path[] = "/tmp/z486-keyboard-test-XXXXXX";
	char mouse_path[] = "/tmp/z486-mouse-test-XXXXXX";
	char combined_path[] = "/tmp/z486-combined-test-XXXXXX";
	char quit_path[] = "/tmp/z486-quit-test-XXXXXX";
	struct input_event events[] = {
		{.type = EV_KEY, .code = KEY_A, .value = 1},
		{.type = EV_KEY, .code = KEY_A, .value = 0},
	};
	struct input_event mouse_events[] = {
		{.type = EV_REL, .code = REL_X, .value = 5},
		{.type = EV_REL, .code = REL_Y, .value = -3},
		{.type = EV_KEY, .code = BTN_LEFT, .value = 1},
		{.type = EV_SYN, .code = SYN_REPORT, .value = 0},
	};
	struct input_event quit_events[] = {
		{.type = EV_KEY, .code = KEY_RIGHTCTRL, .value = 1},
		{.type = EV_KEY, .code = KEY_LEFTALT, .value = 1},
		{.type = EV_KEY, .code = KEY_ESC, .value = 1},
	};
	struct fake_ps2 fake = {.status = 3};
	struct z486_ps2_bus bus = {
		.context = &fake,
		.status = fake_status,
		.write_keyboard = fake_keyboard,
		.write_mouse = fake_mouse,
		.clear_host = fake_clear,
	};
	struct z486_input *input;
	int keyboard_fd = mkstemp(keyboard_path);
	int mouse_fd = mkstemp(mouse_path);
	int combined_fd;
	int quit_fd;
	unsigned i;

	assert(keyboard_fd >= 0 && mouse_fd >= 0);
	assert(write(keyboard_fd, events, sizeof(events)) == sizeof(events));
	close(keyboard_fd);
	input = z486_input_open(keyboard_path, mouse_path, 0);
	assert(input);
	for (i = 0; i < 3; i++)
		assert(!z486_input_service(input, &bus));
	assert(fake.keyboard_count == 3);
	assert(fake.keyboard[0] == 0x1c && fake.keyboard[1] == 0xf0 &&
	       fake.keyboard[2] == 0x1c);

	fake.status |= (1U << 8) | (0xffU << 16);
	assert(!z486_input_service(input, &bus));
	assert(!(fake.status & (1U << 8)));
	for (i = 0; i < 2; i++)
		assert(!z486_input_service(input, &bus));
	assert(fake.keyboard_count == 5);
	assert(fake.keyboard[3] == 0xfa && fake.keyboard[4] == 0xaa);

	fake.status |= (1U << 9) | (0xebU << 24);
	assert(!z486_input_service(input, &bus));
	for (i = 0; i < 4; i++)
		assert(!z486_input_service(input, &bus));
	assert(fake.mouse_count == 4);
	assert(fake.mouse[0] == 0xfa && fake.mouse[1] == 0x08 &&
	       fake.mouse[2] == 0 && fake.mouse[3] == 0);

	fake.status = (fake.status & UINT32_C(0x00ffffff)) |
		      (1U << 9) | (0xf4U << 24);
	assert(!z486_input_service(input, &bus));
	assert(write(mouse_fd, mouse_events, sizeof(mouse_events)) ==
	       sizeof(mouse_events));
	for (i = 0; i < 4; i++)
		assert(!z486_input_service(input, &bus));
	assert(fake.mouse_count == 8);
	assert(fake.mouse[4] == 0xfa && fake.mouse[5] == 0x09 &&
	       fake.mouse[6] == 5 && fake.mouse[7] == 3);

	z486_input_close(input);
	close(mouse_fd);

	/* A keyboard with an integrated touchpad must use one grabbed evdev FD. */
	combined_fd = mkstemp(combined_path);
	assert(combined_fd >= 0);
	assert(write(combined_fd, events, sizeof(events)) == sizeof(events));
	assert(write(combined_fd, mouse_events, sizeof(mouse_events)) ==
	       sizeof(mouse_events));
	close(combined_fd);
	memset(&fake, 0, sizeof(fake));
	fake.status = 3 | (1U << 9) | (0xf4U << 24);
	input = z486_input_open(combined_path, combined_path, 0);
	assert(input);
	assert(!z486_input_service(input, &bus));
	for (i = 0; i < 5; i++)
		assert(!z486_input_service(input, &bus));
	assert(fake.keyboard_count == 3);
	assert(fake.keyboard[0] == 0x1c && fake.keyboard[1] == 0xf0 &&
	       fake.keyboard[2] == 0x1c);
	assert(fake.mouse_count == 4);
	assert(fake.mouse[0] == 0xfa && fake.mouse[1] == 0x09 &&
	       fake.mouse[2] == 5 && fake.mouse[3] == 3);
	z486_input_close(input);

	/* The host quit chord is recognized before Escape reaches the guest. */
	quit_fd = mkstemp(quit_path);
	assert(quit_fd >= 0);
	assert(write(quit_fd, quit_events, sizeof(quit_events)) ==
	       sizeof(quit_events));
	close(quit_fd);
	memset(&fake, 0, sizeof(fake));
	fake.status = 3;
	input = z486_input_open(quit_path, NULL, 0);
	assert(input);
	assert(!z486_input_stop_requested(input));
	assert(!z486_input_service(input, &bus));
	assert(z486_input_stop_requested(input));
	assert(fake.keyboard_count == 1);
	assert(fake.keyboard[0] == 0xe0);
	z486_input_close(input);

	unlink(keyboard_path);
	unlink(mouse_path);
	unlink(combined_path);
	unlink(quit_path);
	puts("PASS: evdev to PS/2 input service");
	return 0;
}
