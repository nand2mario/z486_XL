// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include "z486-ide.h"

#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct fake_bus {
	uint16_t taskfile[6];
	uint16_t buffer[256];
	unsigned buffer_index;
	uint8_t request;
	unsigned writes;
};

static int fake_read(void *context, uint16_t address, uint16_t *value)
{
	struct fake_bus *bus = context;
	unsigned offset = address - 0xf000;

	if (offset < 6) {
		*value = bus->taskfile[offset];
		bus->buffer_index = 0;
	} else if (offset == 0xff) {
		assert(bus->buffer_index < 256);
		*value = bus->buffer[bus->buffer_index++];
	} else {
		*value = 0;
		bus->buffer_index = 0;
	}
	return 0;
}

static int fake_write(void *context, uint16_t address, uint16_t value)
{
	struct fake_bus *bus = context;
	unsigned offset = address - 0xf000;

	bus->writes++;
	if (offset < 6) {
		bus->taskfile[offset] = value;
		bus->buffer_index = 0;
		if (offset == 5)
			bus->request = 0;
	} else if (offset == 0xff) {
		assert(bus->buffer_index < 256);
		bus->buffer[bus->buffer_index++] = value;
	} else {
		bus->buffer_index = 0;
	}
	return 0;
}

static void set_command(struct fake_bus *bus, uint8_t command,
			uint8_t count, uint32_t lba)
{
	bus->taskfile[0] = 0;
	bus->taskfile[1] = ((lba & 0xff) << 8) | count;
	bus->taskfile[2] = (lba >> 8) & 0xffff;
	bus->taskfile[3] = 0;
	bus->taskfile[4] = 0;
	bus->taskfile[5] = ((uint16_t)command << 8) |
		0xe0 | ((lba >> 24) & 0x0f);
	bus->buffer_index = 0;
	bus->request = 4;
}

int main(void)
{
	char path[] = "/tmp/z486-ide-test-XXXXXX";
	uint8_t image[1024], verify[512];
	struct fake_bus fake = {0};
	struct z486_mgmt_bus bus = {
		.context = &fake,
		.read = fake_read,
		.write = fake_write,
	};
	struct z486_ide *ide;
	int fd;
	unsigned i;

	for (i = 0; i < sizeof(image); i++)
		image[i] = i ^ (i >> 8);
	fd = mkstemp(path);
	assert(fd >= 0);
	assert(write(fd, image, sizeof(image)) == sizeof(image));
	close(fd);

	ide = z486_ide_open(path, false);
	assert(ide);
	assert(!z486_ide_start(ide, &bus));
	set_command(&fake, 0xec, 7, 0x01234567);
	assert(!z486_ide_service(ide, &bus, fake.request, 0));
	assert(fake.taskfile[0] == 0x0001);
	assert(fake.taskfile[1] == 0x0000);
	assert(fake.taskfile[2] == 0x0000);
	assert(fake.taskfile[3] == 0x0000);
	assert(fake.taskfile[4] == 0x0000);
	assert(fake.taskfile[5] == 0x4ea0);
	assert(fake.buffer[0] == 0x0040);
	assert(fake.buffer[60] == 2);
	fake.taskfile[5] = 0x00b0;
	fake.request = 6;
	assert(!z486_ide_service(ide, &bus, fake.request, 0));
	assert(fake.taskfile[1] == 0x0101);
	assert(fake.taskfile[2] == 0xffff);
	assert(fake.taskfile[5] == 0x50b0);
	set_command(&fake, 0x20, 1, 0);
	assert(!z486_ide_service(ide, &bus, fake.request, 0));
	for (i = 0; i < 256; i++)
		assert(fake.buffer[i] ==
		       (uint16_t)(image[i * 2] | image[i * 2 + 1] << 8));
	assert(z486_ide_read_sectors(ide) == 1);

	set_command(&fake, 0x30, 1, 1);
	assert(!z486_ide_service(ide, &bus, fake.request, 0));
	for (i = 0; i < 256; i++)
		fake.buffer[i] = 0xa500 | i;
	fake.buffer_index = 0;
	fake.request = 5;
	assert(!z486_ide_service(ide, &bus, fake.request, 0));
	assert(z486_ide_written_sectors(ide) == 1);
	z486_ide_close(ide);

	fd = open(path, O_RDONLY);
	assert(fd >= 0);
	assert(pread(fd, verify, sizeof(verify), 512) == sizeof(verify));
	close(fd);
	for (i = 0; i < 256; i++)
		assert((uint16_t)(verify[i * 2] | verify[i * 2 + 1] << 8) ==
		       (uint16_t)(0xa500 | i));
	unlink(path);
	puts("PASS: z486 persistent IDE0 service");
	return 0;
}
