// SPDX-License-Identifier: MIT
#ifndef Z486_IDE_H
#define Z486_IDE_H

#include <stdbool.h>
#include <stdint.h>

struct z486_mgmt_bus {
	void *context;
	int (*read)(void *context, uint16_t address, uint16_t *value);
	int (*write)(void *context, uint16_t address, uint16_t value);
};

struct z486_ide;

struct z486_ide *z486_ide_open(const char *path, bool debug);
void z486_ide_close(struct z486_ide *ide);
int z486_ide_start(struct z486_ide *ide, const struct z486_mgmt_bus *bus);
int z486_ide_service(struct z486_ide *ide, const struct z486_mgmt_bus *bus,
		     uint8_t ide0_request, uint8_t ide1_request);
uint64_t z486_ide_read_sectors(const struct z486_ide *ide);
uint64_t z486_ide_written_sectors(const struct z486_ide *ide);
bool z486_ide_readonly(const struct z486_ide *ide);

#endif
