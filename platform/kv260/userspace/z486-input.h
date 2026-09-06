// SPDX-License-Identifier: MIT
#ifndef Z486_INPUT_H
#define Z486_INPUT_H

#include <stdbool.h>
#include <stdint.h>

struct z486_ps2_bus {
	void *context;
	uint32_t (*status)(void *context);
	void (*write_keyboard)(void *context, uint8_t value);
	void (*write_mouse)(void *context, uint8_t value);
	void (*clear_host)(void *context, unsigned mask);
};

struct z486_input;

struct z486_input *z486_input_open(const char *keyboard, const char *mouse,
				   int debug);
void z486_input_close(struct z486_input *input);
int z486_input_service(struct z486_input *input,
		       const struct z486_ps2_bus *bus);
bool z486_input_stop_requested(const struct z486_input *input);

#endif
