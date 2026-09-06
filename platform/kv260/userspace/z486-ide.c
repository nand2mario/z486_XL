// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include "z486-ide.h"

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define IDE_BASE UINT16_C(0xf000)

#define ATA_RDY UINT8_C(0x40)
#define ATA_DSC UINT8_C(0x10)
#define ATA_DRQ UINT8_C(0x08)
#define ATA_IRQ UINT8_C(0x04)
#define ATA_END UINT8_C(0x02)
#define ATA_ERR UINT8_C(0x01)

enum transfer_phase {
	PHASE_IDLE,
	PHASE_READ_WAIT,
	PHASE_WRITE_WAIT,
};

struct ide_regs {
	uint8_t io_size;
	uint8_t error;
	uint16_t sector_count;
	uint16_t sector;
	uint32_t cylinder;
	uint8_t head;
	uint8_t drive;
	bool lba;
	uint8_t status;
};

struct z486_ide {
	int fd;
	bool readonly;
	bool debug;
	bool dirty;
	uint32_t total_sectors;
	uint16_t cylinders;
	uint16_t heads;
	uint16_t sectors_per_track;
	uint16_t identify[256];
	struct ide_regs regs;
	enum transfer_phase phase;
	uint64_t read_sectors;
	uint64_t written_sectors;
};

static void set_ident_string(uint16_t *identify, unsigned base,
			     unsigned words, const char *text)
{
	unsigned i;

	for (i = 0; i < words; i++) {
		unsigned offset = i * 2;
		uint8_t first = text[offset] ? (uint8_t)text[offset] : ' ';
		uint8_t second = text[offset] && text[offset + 1] ?
			(uint8_t)text[offset + 1] : ' ';

		identify[base + i] = ((uint16_t)first << 8) | second;
		if (!text[offset]) {
			for (i++; i < words; i++)
				identify[base + i] = UINT16_C(0x2020);
			break;
		}
	}
}

static void update_identify(struct z486_ide *ide, const char *path)
{
	const char *name = strrchr(path, '/');
	char model[41];

	name = name ? name + 1 : path;
	memset(ide->identify, 0, sizeof(ide->identify));
	ide->identify[0] = 0x0040;
	ide->identify[1] = ide->cylinders;
	ide->identify[3] = ide->heads;
	ide->identify[4] = 512 * ide->sectors_per_track;
	ide->identify[5] = 512;
	ide->identify[6] = ide->sectors_per_track;
	set_ident_string(ide->identify, 10, 10, "AOHD0000");
	ide->identify[20] = 3;
	ide->identify[21] = 512;
	ide->identify[22] = 4;
	set_ident_string(ide->identify, 23, 4, "");
	ide->identify[47] = 0x8020;
	ide->identify[48] = 0x0001;
	ide->identify[49] = 1 << 9;
	ide->identify[50] = 0x4001;
	ide->identify[51] = 0x0200;
	ide->identify[52] = 0x0200;
	ide->identify[53] = 0x0007;
	ide->identify[54] = ide->cylinders;
	ide->identify[55] = ide->heads;
	ide->identify[56] = ide->sectors_per_track;
	ide->identify[57] = ide->total_sectors & 0xffff;
	ide->identify[58] = ide->total_sectors >> 16;
	ide->identify[59] = 0x0110;
	ide->identify[60] = ide->total_sectors & 0xffff;
	ide->identify[61] = ide->total_sectors >> 16;
	ide->identify[65] = 120;
	ide->identify[66] = 120;
	ide->identify[67] = 120;
	ide->identify[68] = 120;
	ide->identify[80] = 0x007e;
	ide->identify[82] = (1 << 14) | (1 << 9);
	ide->identify[83] = (1 << 14) | (1 << 13) | (1 << 12);
	ide->identify[84] = 1 << 14;
	ide->identify[85] = (1 << 14) | (1 << 9);
	ide->identify[86] = (1 << 14) | (1 << 13) | (1 << 12);
	ide->identify[87] = 1 << 14;
	ide->identify[93] = (1 << 14) | (1 << 13) | (1 << 9) |
		(1 << 8) | (1 << 3) | (1 << 1) | 1;
	ide->identify[100] = ide->total_sectors & 0xffff;
	ide->identify[101] = ide->total_sectors >> 16;
	strncpy(model, name, sizeof(model) - 1);
	model[sizeof(model) - 1] = '\0';
	set_ident_string(ide->identify, 27, 20, model);
}

struct z486_ide *z486_ide_open(const char *path, bool debug)
{
	struct z486_ide *ide;
	struct stat st;
	uint64_t sectors;
	uint64_t cylinders;
	int fd;

	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0 && (errno == EACCES || errno == EROFS))
		fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return NULL;
	if (fstat(fd, &st) || st.st_size <= 0 || (st.st_size & 511)) {
		if (!errno)
			errno = EINVAL;
		close(fd);
		return NULL;
	}
	sectors = (uint64_t)st.st_size >> 9;
	if (sectors > UINT32_MAX) {
		errno = EFBIG;
		close(fd);
		return NULL;
	}
	ide = calloc(1, sizeof(*ide));
	if (!ide) {
		close(fd);
		return NULL;
	}
	ide->fd = fd;
	ide->readonly = fcntl(fd, F_GETFL) < 0 ||
		(fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY;
	ide->debug = debug;
	ide->total_sectors = (uint32_t)sectors;
	ide->heads = 16;
	ide->sectors_per_track = 63;
	cylinders = sectors / (ide->heads * ide->sectors_per_track);
	ide->cylinders = cylinders > UINT16_MAX ? UINT16_MAX : cylinders;
	ide->regs.sector_count = 1;
	ide->regs.sector = 1;
	ide->regs.status = ATA_RDY;
	update_identify(ide, path);
	return ide;
}

void z486_ide_close(struct z486_ide *ide)
{
	if (!ide)
		return;
	if (ide->dirty)
		fdatasync(ide->fd);
	close(ide->fd);
	free(ide);
}

static int bus_read(const struct z486_mgmt_bus *bus, uint16_t address,
		    uint16_t *value)
{
	return bus->read(bus->context, address, value);
}

static int bus_write(const struct z486_mgmt_bus *bus, uint16_t address,
		     uint16_t value)
{
	return bus->write(bus->context, address, value);
}

static uint8_t binary_to_bcd(unsigned value)
{
	return ((value / 10) << 4) | value % 10;
}

static int configure_cmos(const struct z486_mgmt_bus *bus)
{
	uint8_t cmos[128] = {0};
	unsigned sum = 0;
	struct tm now;
	time_t timestamp = 1704067200;
	unsigned i;

	gmtime_r(&timestamp, &now);
	cmos[0x00] = binary_to_bcd(now.tm_sec);
	cmos[0x02] = binary_to_bcd(now.tm_min);
	cmos[0x04] = binary_to_bcd(now.tm_hour);
	cmos[0x05] = 0x12;
	cmos[0x06] = now.tm_wday + 1;
	cmos[0x07] = binary_to_bcd(now.tm_mday);
	cmos[0x08] = binary_to_bcd(now.tm_mon + 1);
	cmos[0x09] = binary_to_bcd(now.tm_year < 117 ? 17 : now.tm_year - 100);
	cmos[0x0a] = 0x26;
	cmos[0x0b] = 0x02;
	cmos[0x0d] = 0x80;
	cmos[0x12] = 0xf0;
	cmos[0x14] = 0x4d;
	cmos[0x15] = 0x80;
	cmos[0x16] = 0x02;
	cmos[0x17] = 0x00;
	cmos[0x18] = 0x3c;
	cmos[0x19] = 0x2f;
	cmos[0x30] = 0x00;
	cmos[0x31] = 0x3c;
	cmos[0x32] = 0x20;
	cmos[0x37] = 0x20;
	cmos[0x39] = 0x02;
	for (i = 0x10; i <= 0x2d; i++)
		sum += cmos[i];
	cmos[0x2e] = sum >> 8;
	cmos[0x2f] = sum;
	for (i = 0; i < sizeof(cmos); i++)
		if (bus_write(bus, UINT16_C(0xf400) + i, cmos[i]))
			return -1;
	return 0;
}

static int configure_absent_floppy(const struct z486_mgmt_bus *bus,
				   unsigned drive)
{
	static const uint8_t offsets[] = {0, 1, 2, 3, 4, 5, 0x0c};
	static const uint16_t values[] = {0, 1, 0, 0, 0, 0, 0};
	uint16_t base = UINT16_C(0xf200) + (drive << 7);
	unsigned i;

	for (i = 0; i < sizeof(offsets); i++)
		if (bus_write(bus, base + offsets[i], values[i]))
			return -1;
	return 0;
}

int z486_ide_start(struct z486_ide *ide, const struct z486_mgmt_bus *bus)
{
	if (!ide || !bus || !bus->read || !bus->write) {
		errno = EINVAL;
		return -1;
	}
	/* Gate bit 3 plus {HOB enabled, present}=01 for drive 0. */
	if (bus_write(bus, IDE_BASE + 6, 0x0009))
		return -1;
	/* Secondary controller is installed but has no media. */
	if (bus_write(bus, IDE_BASE + 0x100 + 6, 0x0008))
		return -1;
	if (configure_absent_floppy(bus, 0) ||
	    configure_absent_floppy(bus, 1))
		return -1;
	return configure_cmos(bus);
}

static uint32_t get_lba(const struct z486_ide *ide)
{
	uint32_t lba;

	if (ide->regs.lba)
		return (ide->regs.sector & 0xff) |
			((ide->regs.cylinder & 0xffff) << 8) |
			((uint32_t)(ide->regs.head & 0x0f) << 24);
	lba = ide->regs.cylinder * ide->heads + ide->regs.head;
	return lba * ide->sectors_per_track + ide->regs.sector - 1;
}

static void put_lba(struct z486_ide *ide, uint32_t lba)
{
	if (ide->regs.lba) {
		ide->regs.sector = lba & 0xff;
		ide->regs.cylinder = (lba >> 8) & 0xffff;
		ide->regs.head = (lba >> 24) & 0x0f;
	} else {
		uint32_t track = ide->heads * ide->sectors_per_track;

		ide->regs.cylinder = lba / track;
		lba %= track;
		ide->regs.head = lba / ide->sectors_per_track;
		ide->regs.sector = lba % ide->sectors_per_track + 1;
	}
}

static uint8_t drive_address(const struct z486_ide *ide)
{
	return (ide->regs.lba ? 0xe0 : 0xa0) |
		(ide->regs.drive ? 0x10 : 0) | ide->regs.head;
}

static int send_regs(struct z486_ide *ide,
		     const struct z486_mgmt_bus *bus)
{
	uint16_t values[6];
	unsigned i;

	if (!(ide->regs.status & ATA_DRQ))
		ide->regs.status |= ATA_DSC;
	values[0] = ((uint16_t)ide->regs.error << 8) | ide->regs.io_size;
	values[1] = ((uint16_t)ide->regs.sector << 8) |
		(ide->regs.sector_count & 0xff);
	values[2] = ide->regs.cylinder & 0xffff;
	values[3] = ((ide->regs.sector >> 8) << 8) |
		(ide->regs.sector_count >> 8);
	values[4] = ide->regs.cylinder >> 16;
	values[5] = ((uint16_t)ide->regs.status << 8) | drive_address(ide);
	for (i = 0; i < 6; i++)
		if (bus_write(bus, IDE_BASE + i, values[i]))
			return -1;
	return 0;
}

static int read_taskfile(struct z486_ide *ide,
			 const struct z486_mgmt_bus *bus, uint8_t *command)
{
	uint16_t value[6];
	unsigned i;

	for (i = 0; i < 6; i++)
		if (bus_read(bus, IDE_BASE + i, &value[i]))
			return -1;
	ide->regs.sector_count = (value[1] & 0xff) | ((value[3] & 0xff) << 8);
	ide->regs.sector = (value[1] >> 8) | (value[3] & 0xff00);
	ide->regs.cylinder = value[2] | ((uint32_t)value[4] << 16);
	ide->regs.drive = (value[5] >> 4) & 1;
	ide->regs.lba = (value[5] >> 6) & 1;
	ide->regs.head = value[5] & 0x0f;
	*command = value[5] >> 8;
	return 0;
}

static int send_words(const struct z486_mgmt_bus *bus,
		      const uint16_t words[256])
{
	unsigned i;

	for (i = 0; i < 256; i++)
		if (bus_write(bus, IDE_BASE + 0xff, words[i]))
			return -1;
	return 0;
}

static int verify_words(const struct z486_mgmt_bus *bus,
			const uint16_t expected[256])
{
	uint16_t actual, discard;
	unsigned mismatches = 0;
	unsigned i;

	/* Any non-buffer access resets the IDE management buffer index. */
	if (bus_read(bus, IDE_BASE, &discard))
		return -1;
	for (i = 0; i < 256; i++) {
		if (bus_read(bus, IDE_BASE + 0xff, &actual))
			return -1;
		if (actual != expected[i]) {
			if (mismatches < 8)
				fprintf(stderr,
					"IDE0 buffer[%u]: expected=%04x actual=%04x\n",
					i, expected[i], actual);
			mismatches++;
		}
	}
	if (bus_read(bus, IDE_BASE, &discard))
		return -1;
	if (mismatches) {
		fprintf(stderr, "IDE0 buffer readback: %u mismatches\n",
			mismatches);
		errno = EIO;
		return -1;
	}
	fprintf(stderr, "IDE0 buffer readback: 256 words verified\n");
	return 0;
}

static int receive_words(const struct z486_mgmt_bus *bus,
			 uint16_t words[256])
{
	unsigned i;

	for (i = 0; i < 256; i++)
		if (bus_read(bus, IDE_BASE + 0xff, &words[i]))
			return -1;
	return 0;
}

static int prepare_read(struct z486_ide *ide,
			const struct z486_mgmt_bus *bus)
{
	uint8_t bytes[512] = {0};
	uint16_t words[256];
	uint32_t lba = get_lba(ide);
	ssize_t count;
	unsigned i;

	if (lba < ide->total_sectors) {
		count = pread(ide->fd, bytes, sizeof(bytes), (off_t)lba << 9);
		if (count != sizeof(bytes)) {
			if (count >= 0)
				errno = EIO;
			return -1;
		}
	}
	for (i = 0; i < 256; i++)
		words[i] = bytes[i * 2] | ((uint16_t)bytes[i * 2 + 1] << 8);
	put_lba(ide, lba + 1);
	ide->regs.sector_count--;
	ide->regs.io_size = 1;
	ide->regs.error = 0;
	ide->regs.status = ATA_RDY | ATA_DRQ | ATA_IRQ;
	if (!ide->regs.sector_count)
		ide->regs.status |= ATA_END;
	if (send_words(bus, words) || send_regs(ide, bus))
		return -1;
	ide->read_sectors++;
	ide->phase = ide->regs.sector_count ? PHASE_READ_WAIT : PHASE_IDLE;
	if (ide->debug)
		fprintf(stderr, "IDE0 read LBA=%" PRIu32 " remaining=%u\n",
			lba, ide->regs.sector_count);
	return 0;
}

static int prepare_write(struct z486_ide *ide,
			 const struct z486_mgmt_bus *bus)
{
	ide->regs.io_size = 1;
	ide->regs.error = 0;
	ide->regs.status = ATA_RDY | ATA_DRQ;
	ide->phase = PHASE_WRITE_WAIT;
	return send_regs(ide, bus);
}

static int finish_write(struct z486_ide *ide,
			const struct z486_mgmt_bus *bus)
{
	uint16_t words[256];
	uint8_t bytes[512];
	uint32_t lba = get_lba(ide);
	ssize_t count;
	unsigned i;

	if (receive_words(bus, words))
		return -1;
	for (i = 0; i < 256; i++) {
		bytes[i * 2] = words[i];
		bytes[i * 2 + 1] = words[i] >> 8;
	}
	if (ide->readonly || lba >= ide->total_sectors) {
		ide->regs.error = 0x04;
		ide->regs.status = ATA_RDY | ATA_ERR | ATA_IRQ;
		ide->phase = PHASE_IDLE;
		return send_regs(ide, bus);
	}
	count = pwrite(ide->fd, bytes, sizeof(bytes), (off_t)lba << 9);
	if (count != sizeof(bytes)) {
		if (count >= 0)
			errno = EIO;
		return -1;
	}
	ide->dirty = true;
	ide->written_sectors++;
	put_lba(ide, lba + 1);
	ide->regs.sector_count--;
	if (ide->debug)
		fprintf(stderr, "IDE0 write LBA=%" PRIu32 " remaining=%u\n",
			lba, ide->regs.sector_count);
	if (ide->regs.sector_count)
		return prepare_write(ide, bus);
	if (fdatasync(ide->fd))
		return -1;
	ide->dirty = false;
	ide->regs.error = 0;
	ide->regs.status = ATA_RDY | ATA_IRQ;
	ide->phase = PHASE_IDLE;
	return send_regs(ide, bus);
}

static int reset_drive(struct z486_ide *ide,
		       const struct z486_mgmt_bus *bus)
{
	uint16_t value;

	if (bus_read(bus, IDE_BASE + 5, &value))
		return -1;
	memset(&ide->regs, 0, sizeof(ide->regs));
	ide->regs.drive = ((uint8_t)value >> 4) & 1;
	ide->regs.lba = ((uint8_t)value >> 6) & 1;
	ide->regs.sector_count = 1;
	ide->regs.sector = 1;
	ide->regs.cylinder = ide->regs.drive ? UINT32_C(0xffff) : 0;
	ide->regs.status = ATA_RDY;
	ide->phase = PHASE_IDLE;
	return send_regs(ide, bus);
}

static int handle_command(struct z486_ide *ide,
			  const struct z486_mgmt_bus *bus)
{
	uint8_t command;
	uint32_t cylinders;

	if (read_taskfile(ide, bus, &command))
		return -1;
	ide->regs.sector_count &= 0xff;
	ide->regs.sector &= 0xff;
	ide->regs.cylinder &= 0xffff;
	if ((command == 0x20 || command == 0x21 || command == 0x30 ||
	     command == 0x31) && !ide->regs.sector_count)
		ide->regs.sector_count = 256;
	if (ide->debug)
		fprintf(stderr,
			"IDE0 command=%02x drive=%u LBA=%" PRIu32
			" count=%u C/H/S=%" PRIu32 "/%u/%u%s\n",
			command, ide->regs.drive, get_lba(ide),
			ide->regs.sector_count, ide->regs.cylinder,
			ide->regs.head, ide->regs.sector,
			ide->regs.lba ? " (LBA)" : " (CHS)");
	if (ide->regs.drive) {
		ide->regs.error = 0x04;
		ide->regs.status = ATA_RDY | ATA_ERR | ATA_IRQ;
		return send_regs(ide, bus);
	}
	switch (command) {
	case 0xec:
		{
			uint8_t drive = ide->regs.drive;

			memset(&ide->regs, 0, sizeof(ide->regs));
			ide->regs.drive = drive;
		}
		ide->regs.io_size = 1;
		ide->regs.status = ATA_RDY | ATA_DRQ | ATA_IRQ | ATA_END;
		ide->phase = PHASE_IDLE;
		if (send_words(bus, ide->identify))
			return -1;
		if (ide->debug && verify_words(bus, ide->identify))
			return -1;
		return send_regs(ide, bus);
	case 0x20:
	case 0x21:
		return prepare_read(ide, bus);
	case 0x30:
	case 0x31:
		return prepare_write(ide, bus);
	case 0x91:
		ide->sectors_per_track = ide->regs.sector_count ?
			ide->regs.sector_count : 63;
		ide->heads = ide->regs.head + 1;
		if (!ide->heads)
			ide->heads = 16;
		cylinders = ide->total_sectors /
			(ide->heads * ide->sectors_per_track);
		ide->cylinders = cylinders > UINT16_MAX ? UINT16_MAX : cylinders;
		ide->regs.status = ATA_RDY | ATA_IRQ;
		return send_regs(ide, bus);
	case 0x10 ... 0x1f:
		ide->regs.cylinder = 0;
		/* fall through */
	case 0x40:
		ide->regs.status = ATA_RDY | ATA_IRQ;
		return send_regs(ide, bus);
	default:
		ide->regs.error = 0x04;
		ide->regs.status = ATA_RDY | ATA_ERR | ATA_IRQ;
		return send_regs(ide, bus);
	}
}

static int service_absent_ide(const struct z486_mgmt_bus *bus, uint16_t base,
			      uint8_t request)
{
	uint16_t drive_command = 0;
	uint16_t values[6] = {0x0000, 0x0101, 0xffff, 0, 0, 0x50a0};
	unsigned i;

	if (!request)
		return 0;
	if (request == 4 || request == 6) {
		if (bus_read(bus, base + 5, &drive_command))
			return -1;
		values[5] = (request == 4 ? 0x5500 : 0x5000) |
			(drive_command & 0xff);
		if (request == 4)
			values[0] = 0x0400;
		for (i = 0; i < 6; i++)
			if (bus_write(bus, base + i, values[i]))
				return -1;
	}
	return 0;
}

int z486_ide_service(struct z486_ide *ide, const struct z486_mgmt_bus *bus,
		     uint8_t ide0_request, uint8_t ide1_request)
{
	if (!ide || !bus) {
		errno = EINVAL;
		return -1;
	}
	if (service_absent_ide(bus, IDE_BASE + 0x100, ide1_request))
		return -1;
	switch (ide0_request) {
	case 0:
		return 0;
	case 4:
		return handle_command(ide, bus);
	case 5:
		if (ide->phase == PHASE_READ_WAIT)
			return prepare_read(ide, bus);
		if (ide->phase == PHASE_WRITE_WAIT)
			return finish_write(ide, bus);
		return 0;
	case 6:
		return reset_drive(ide, bus);
	default:
		return 0;
	}
}

uint64_t z486_ide_read_sectors(const struct z486_ide *ide)
{
	return ide ? ide->read_sectors : 0;
}

uint64_t z486_ide_written_sectors(const struct z486_ide *ide)
{
	return ide ? ide->written_sectors : 0;
}

bool z486_ide_readonly(const struct z486_ide *ide)
{
	return !ide || ide->readonly;
}
