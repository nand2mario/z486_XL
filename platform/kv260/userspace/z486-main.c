// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include "z486-ide.h"
#include "z486-input.h"
#include "z486_kv260_memory_map.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define Z486_MAGIC       UINT32_C(0x5a343836)
#define ABI_VERSION      UINT32_C(0x00010009)
#define REG_BUS_STATUS   0xb0
#define REG_MAGIC        0x00
#define REG_ABI          0x04
#define REG_CONTROL      0x08
#define REG_BASE_LO      0x0c
#define REG_BASE_HI      0x10
#define REG_REQUESTS     0x14
#define REG_READ_BEATS   0x18
#define REG_STALLS       0x1c
#define REG_ERRORS       0x20
#define REG_SIZE         0x24
#define REG_BOOT_STATUS  0x28
#define REG_CPU_CS       0x2c
#define REG_CPU_EIP      0x30
#define REG_MGMT_STATUS  0x34
#define REG_MGMT_ADDRESS 0x38
#define REG_MGMT_WDATA   0x3c
#define REG_MGMT_RDATA   0x40
#define REG_MGMT_COMMAND 0x44
#define REG_PS2_STATUS   0x48
#define REG_KBD_DATA     0x4c
#define REG_MOUSE_DATA   0x50
#define REG_PS2_COMMAND  0x54
#define REG_VIDEO_CONTROL 0x58
#define REG_VIDEO_SIZE    0x5c
#define REG_VIDEO_FRAMES  0x60
#define REG_VIDEO_WR_BURSTS 0x64
#define REG_VIDEO_RD_BURSTS 0x68
#define REG_VIDEO_WR_BEATS  0x6c
#define REG_VIDEO_RD_BEATS  0x70
#define REG_VIDEO_STALLS    0x74
#define REG_VIDEO_ERRORS    0x78
#define REG_VIDEO_SOURCE    0x80
#define REG_VIDEO_LINE_REQUESTS 0x84
#define REG_VIDEO_LINE_COMPLETIONS 0x88
#define REG_VIDEO_NATIVE_FRAMES 0x8c
#define REG_VIDEO_OUTSTANDING_HWM 0x90
#define REG_GUEST_RAM       0x7c
#define REG_AUDIO_CONTROL   0xc4

#define ROM_WINDOW_START 0x000a0000U
#define ROM_WINDOW_SIZE  0x00060000U
#define BOOT1_OFFSET     0x000c0000U
#define BOOT0_128_OFFSET 0x000e0000U
#define BOOT0_64_OFFSET  0x000f0000U

static volatile sig_atomic_t stopping;

static void signal_stop(int signo)
{
	(void)signo;
	stopping = 1;
}

static uint64_t monotonic_milliseconds(void)
{
	struct timespec now;

	if (clock_gettime(CLOCK_MONOTONIC, &now))
		return 0;
	return (uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static inline uint32_t reg_read(volatile uint32_t *regs, unsigned offset)
{
	uint32_t value = regs[offset / 4];
	__sync_synchronize();
	return value;
}

static inline void reg_write(volatile uint32_t *regs, unsigned offset,
			     uint32_t value)
{
	__sync_synchronize();
	regs[offset / 4] = value;
	__sync_synchronize();
}

static int stop_and_drain(volatile uint32_t *regs)
{
	reg_write(regs, REG_VIDEO_CONTROL,
		  reg_read(regs, REG_VIDEO_CONTROL) & ~3U);
	reg_write(regs, REG_CONTROL, 0);
	/* Let the scanout CDC settle, then require consecutive idle samples. */
	unsigned idle_samples = 0;
	for (unsigned attempt = 0; attempt < 3000; ++attempt) {
		usleep(1000);
		if ((reg_read(regs, REG_BUS_STATUS) & 7U) == 7U) {
			if (++idle_samples == 2)
				return 0;
		} else {
			idle_samples = 0;
		}
	}
	fprintf(stderr, "AXI did not drain; do not unload/reconfigure the FPGA\n");
	return -1;
}

static int find_uio(char *device, size_t device_len, int *index)
{
	DIR *dir = opendir("/sys/class/uio");
	struct dirent *entry;
	char path[256], name[64], extra;
	FILE *file;
	int candidate;

	if (!dir)
		return -1;
	while ((entry = readdir(dir))) {
		if (sscanf(entry->d_name, "uio%d%c", &candidate, &extra) != 1)
			continue;
		snprintf(path, sizeof(path), "/sys/class/uio/uio%d/name", candidate);
		file = fopen(path, "r");
		if (!file)
			continue;
		if (fgets(name, sizeof(name), file) && !strncmp(name, "z486", 4)) {
			fclose(file);
			snprintf(device, device_len, "/dev/uio%d", candidate);
			*index = candidate;
			closedir(dir);
			return 0;
		}
		fclose(file);
	}
	closedir(dir);
	errno = ENODEV;
	return -1;
}

static int read_map_size(int index, unsigned map, size_t *size)
{
	char path[256], text[64], *end;
	unsigned long long value;
	FILE *file;

	snprintf(path, sizeof(path), "/sys/class/uio/uio%d/maps/map%u/size",
		 index, map);
	file = fopen(path, "r");
	if (!file)
		return -1;
	if (!fgets(text, sizeof(text), file)) {
		fclose(file);
		errno = EINVAL;
		return -1;
	}
	fclose(file);
	errno = 0;
	value = strtoull(text, &end, 0);
	if (errno || end == text || value > SIZE_MAX) {
		errno = EINVAL;
		return -1;
	}
	while (isspace((unsigned char)*end))
		end++;
	if (*end) {
		errno = EINVAL;
		return -1;
	}
	*size = (size_t)value;
	return 0;
}

static int load_file(const char *path, uint8_t *destination,
		     size_t expected_a, size_t expected_b, size_t *actual)
{
	struct stat st;
	ssize_t count;
	size_t done = 0;
	int fd = open(path, O_RDONLY);

	if (fd < 0)
		return -1;
	if (fstat(fd, &st)) {
		close(fd);
		return -1;
	}
	if (st.st_size < 0 || (size_t)st.st_size != expected_a) {
		if (!expected_b || (size_t)st.st_size != expected_b) {
			fprintf(stderr, "%s must be %zu%s bytes (is %jd)\n", path,
				expected_a, expected_b ? " or 131072" : "",
				(intmax_t)st.st_size);
			close(fd);
			errno = EINVAL;
			return -1;
		}
	}
	while (done < (size_t)st.st_size) {
		count = read(fd, destination + done, (size_t)st.st_size - done);
		if (count <= 0) {
			if (!count)
				errno = EIO;
			close(fd);
			return -1;
		}
		done += (size_t)count;
	}
	close(fd);
	*actual = done;
	return 0;
}

static void show_status(volatile uint32_t *regs, uint32_t status)
{
	static const char *const source_name[] = { "VGA", "packed", "zSST" };
	uint32_t management = reg_read(regs, REG_MGMT_STATUS);
	uint32_t ps2 = reg_read(regs, REG_PS2_STATUS);
	uint32_t video_size = reg_read(regs, REG_VIDEO_SIZE);
	uint32_t video_source = reg_read(regs, REG_VIDEO_SOURCE) & 3;

	printf("boot=%u bios=%u first=%u post=%02x cpu=%04x:%08x "
	       "requests=%" PRIu32 " reads=%" PRIu32 " stalls=%" PRIu32
	       " errors=%" PRIu32 " fdd=%u ide0=%u ide1=%u ps2=%08x\n",
	       status & 7, (status >> 3) & 1, (status >> 4) & 1,
	       (status >> 5) & 0xff, reg_read(regs, REG_CPU_CS) & 0xffff,
	       reg_read(regs, REG_CPU_EIP), reg_read(regs, REG_REQUESTS),
	       reg_read(regs, REG_READ_BEATS), reg_read(regs, REG_STALLS),
	       reg_read(regs, REG_ERRORS), (management >> 6) & 3,
	       management & 7, (management >> 3) & 7, ps2);
	printf("video=%ux%u frames=%" PRIu32 " scanout_bursts=%" PRIu32
	       " scanout_beats=%" PRIu32 " underflows=%" PRIu32
	       " errors=%" PRIu32 "\n",
	       (video_size & 0xfff) + 1, ((video_size >> 16) & 0xfff) + 1,
	       reg_read(regs, REG_VIDEO_FRAMES),
	       reg_read(regs, REG_VIDEO_RD_BURSTS),
	       reg_read(regs, REG_VIDEO_RD_BEATS),
	       reg_read(regs, REG_VIDEO_STALLS),
	       reg_read(regs, REG_VIDEO_ERRORS));
	printf("video_source=%s lines=%" PRIu32 "/%" PRIu32
	       " native_frames=%" PRIu32 " outstanding_hwm=%" PRIu32 "\n",
	       video_source < 3 ? source_name[video_source] : "invalid",
	       reg_read(regs, REG_VIDEO_LINE_COMPLETIONS),
	       reg_read(regs, REG_VIDEO_LINE_REQUESTS),
	       reg_read(regs, REG_VIDEO_NATIVE_FRAMES),
	       reg_read(regs, REG_VIDEO_OUTSTANDING_HWM));
	fflush(stdout);
}

static int filter_mode(const char *name)
{
	static const char *const names[] = {
		"nearest", "bilinear", "sharp", "bicubic",
	};
	unsigned i;

	for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
		if (!strcmp(name, names[i]))
			return (int)i;
	return -1;
}

static int ram_size_code(const char *text)
{
	static const char *const sizes[] = { "16", "32", "64", "128" };
	unsigned i;

	for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
		if (!strcmp(text, sizes[i]))
			return (int)i;
	return -1;
}

static int audio_boost_code(const char *text)
{
	static const char *const gains[] = { "1", "2", "4" };
	unsigned i;

	for (i = 0; i < sizeof(gains) / sizeof(gains[0]); i++)
		if (!strcmp(text, gains[i]))
			return (int)i;
	return -1;
}

struct uio_mgmt {
	volatile uint32_t *regs;
};

static int mgmt_wait_idle(struct uio_mgmt *mgmt)
{
	unsigned count;

	for (count = 0; count < 1000000; count++)
		if (!(reg_read(mgmt->regs, REG_MGMT_COMMAND) & 1))
			return 0;
	errno = ETIMEDOUT;
	return -1;
}

static int mgmt_read_word(void *context, uint16_t address, uint16_t *value)
{
	struct uio_mgmt *mgmt = context;

	if (mgmt_wait_idle(mgmt))
		return -1;
	reg_write(mgmt->regs, REG_MGMT_ADDRESS, address);
	reg_write(mgmt->regs, REG_MGMT_COMMAND, 1);
	if (mgmt_wait_idle(mgmt))
		return -1;
	*value = reg_read(mgmt->regs, REG_MGMT_RDATA);
	return 0;
}

static int mgmt_write_word(void *context, uint16_t address, uint16_t value)
{
	struct uio_mgmt *mgmt = context;

	if (mgmt_wait_idle(mgmt))
		return -1;
	reg_write(mgmt->regs, REG_MGMT_ADDRESS, address);
	reg_write(mgmt->regs, REG_MGMT_WDATA, value);
	reg_write(mgmt->regs, REG_MGMT_COMMAND, 2);
	return mgmt_wait_idle(mgmt);
}

static uint32_t ps2_status(void *context)
{
	struct uio_mgmt *mgmt = context;

	return reg_read(mgmt->regs, REG_PS2_STATUS);
}

static void ps2_write_keyboard(void *context, uint8_t value)
{
	struct uio_mgmt *mgmt = context;

	reg_write(mgmt->regs, REG_KBD_DATA, value);
}

static void ps2_write_mouse(void *context, uint8_t value)
{
	struct uio_mgmt *mgmt = context;

	reg_write(mgmt->regs, REG_MOUSE_DATA, value);
}

static void ps2_clear_host(void *context, unsigned mask)
{
	struct uio_mgmt *mgmt = context;

	reg_write(mgmt->regs, REG_PS2_COMMAND, mask);
}

int main(int argc, char **argv)
{
	const char *boot0 = "/media/fat/games/Z486/boot0.rom";
	const char *boot1 = "/media/fat/games/Z486/boot1.rom";
	const char *disk = NULL;
	const char *keyboard = NULL, *mouse = NULL;
	const char *filter = "nearest";
	const char *ram_mb = "16";
	const char *audio_boost = "1";
	bool no_wait = false, stop_only = false, ide_debug = false;
	bool input_debug = false;
	bool running = false;
	char uio_path[64];
	volatile uint32_t *regs = MAP_FAILED;
	uint8_t *memory = MAP_FAILED;
	uint32_t status = UINT32_MAX, next_status;
	uint64_t dma_base;
	size_t memory_size, boot0_size, boot1_size;
	long page_size;
	int fd = -1, uio_index, positional = 0, i, result = 1;
	uint64_t next_status_ms = 0;
	struct z486_ide *ide = NULL;
	struct z486_input *input = NULL;
	struct uio_mgmt mgmt;
	struct z486_mgmt_bus mgmt_bus;
	struct z486_ps2_bus ps2_bus;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--no-wait"))
			no_wait = true;
		else if (!strcmp(argv[i], "--stop"))
			stop_only = true;
		else if (!strcmp(argv[i], "--ide-debug"))
			ide_debug = true;
		else if (!strcmp(argv[i], "--input-debug"))
			input_debug = true;
		else if (!strcmp(argv[i], "--filter")) {
			if (++i == argc || filter_mode(argv[i]) < 0) {
				fprintf(stderr, "--filter requires nearest, bilinear, sharp, or bicubic\n");
				return 2;
			}
			filter = argv[i];
		}
		else if (!strcmp(argv[i], "--ram-mb")) {
			if (++i == argc || ram_size_code(argv[i]) < 0) {
				fprintf(stderr, "--ram-mb requires 16, 32, 64, or 128\n");
				return 2;
			}
			ram_mb = argv[i];
		}
		else if (!strcmp(argv[i], "--audio-boost")) {
			if (++i == argc || audio_boost_code(argv[i]) < 0) {
				fprintf(stderr, "--audio-boost requires 1, 2, or 4\n");
				return 2;
			}
			audio_boost = argv[i];
		}
		else if (!strcmp(argv[i], "--disk")) {
			if (++i == argc) {
				fprintf(stderr, "--disk requires a .vhd path\n");
				return 2;
			}
			disk = argv[i];
		}
		else if (!strcmp(argv[i], "--keyboard")) {
			if (++i == argc) {
				fprintf(stderr, "--keyboard requires /dev/input/eventX\n");
				return 2;
			}
			keyboard = argv[i];
		}
		else if (!strcmp(argv[i], "--mouse")) {
			if (++i == argc) {
				fprintf(stderr, "--mouse requires /dev/input/eventX\n");
				return 2;
			}
			mouse = argv[i];
		}
		else if (argv[i][0] == '-') {
			fprintf(stderr, "usage: %s [--stop | --no-wait] "
				"[--disk image.vhd] [--ide-debug] [--input-debug] "
				"[--filter nearest|bilinear|sharp|bicubic] "
				"[--ram-mb 16|32|64|128] "
				"[--audio-boost 1|2|4] "
				"[--keyboard /dev/input/eventX] "
				"[--mouse /dev/input/eventX] "
				"[boot0.rom boot1.rom]\n",
				argv[0]);
			return 2;
		} else if (positional++ == 0)
			boot0 = argv[i];
		else if (positional == 2)
			boot1 = argv[i];
		else {
			fprintf(stderr, "too many ROM paths\n");
			return 2;
		}
	}
	if (positional == 1) {
		fprintf(stderr, "specify both boot0.rom and boot1.rom\n");
		return 2;
	}
	if ((disk || keyboard || mouse) && (stop_only || no_wait)) {
		fprintf(stderr, "media/input options require the foreground "
			"service loop\n");
		return 2;
	}
	if (strcmp(filter, "nearest"))
		fprintf(stderr, "warning: KV260 direct scanout ignores --filter %s; "
			"using nearest-neighbor\n", filter);
	if (find_uio(uio_path, sizeof(uio_path), &uio_index)) {
		perror("z486 UIO device not found");
		return 1;
	}
	fd = open(uio_path, O_RDWR | O_SYNC);
	if (fd < 0) {
		perror(uio_path);
		return 1;
	}
	page_size = sysconf(_SC_PAGESIZE);
	regs = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE,
		    MAP_SHARED, fd, 0);
	if (regs == MAP_FAILED) {
		perror("mmap registers");
		goto out;
	}
	if (reg_read(regs, REG_MAGIC) != Z486_MAGIC ||
	    reg_read(regs, REG_ABI) != ABI_VERSION) {
		fprintf(stderr, "unsupported z486 PL ABI\n");
		goto out;
	}
	mgmt.regs = regs;
	mgmt_bus.context = &mgmt;
	mgmt_bus.read = mgmt_read_word;
	mgmt_bus.write = mgmt_write_word;
	ps2_bus.context = &mgmt;
	ps2_bus.status = ps2_status;
	ps2_bus.write_keyboard = ps2_write_keyboard;
	ps2_bus.write_mouse = ps2_write_mouse;
	ps2_bus.clear_host = ps2_clear_host;
	if (stop_and_drain(regs))
		goto out;
	if (stop_only) {
		printf("z486 and video stopped\n");
		result = 0;
		goto out;
	}
	reg_write(regs, REG_GUEST_RAM, (uint32_t)ram_size_code(ram_mb));
	reg_write(regs, REG_AUDIO_CONTROL,
		  (uint32_t)audio_boost_code(audio_boost));
	if ((reg_read(regs, REG_GUEST_RAM) & 3U) !=
	    (uint32_t)ram_size_code(ram_mb)) {
		fprintf(stderr, "failed to configure guest RAM size\n");
		goto out;
	}
	if ((reg_read(regs, REG_AUDIO_CONTROL) & 3U) !=
	    (uint32_t)audio_boost_code(audio_boost)) {
		fprintf(stderr, "failed to configure audio boost\n");
		goto out;
	}
	if (read_map_size(uio_index, 1, &memory_size)) {
		perror("read UIO CMA map size");
		goto out;
	}
	if (memory_size != Z486_KV260_CMA_SIZE ||
	    memory_size < ROM_WINDOW_START + ROM_WINDOW_SIZE ||
	    memory_size != reg_read(regs, REG_SIZE)) {
		fprintf(stderr, "invalid or inconsistent CMA allocation size\n");
		goto out;
	}
	memory = mmap(NULL, memory_size, PROT_READ | PROT_WRITE, MAP_SHARED,
		      fd, page_size);
	if (memory == MAP_FAILED) {
		perror("mmap CMA buffer");
		goto out;
	}
	memset(memory + ROM_WINDOW_START, 0xff, ROM_WINDOW_SIZE);
	memset(memory + 0x000a0000, 0x00, 0x00020000);
	memset(memory + 0x000ce000, 0x00, 0x00002000);
	if (load_file(boot1, memory + BOOT1_OFFSET, 32768, 0, &boot1_size)) {
		perror(boot1);
		goto out;
	}
	if (load_file(boot0, memory + BOOT0_128_OFFSET, 65536, 131072,
		      &boot0_size)) {
		perror(boot0);
		goto out;
	}
	if (boot0_size == 65536) {
		memmove(memory + BOOT0_64_OFFSET, memory + BOOT0_128_OFFSET,
			boot0_size);
		memset(memory + BOOT0_128_OFFSET, 0xff, boot0_size);
	}
	if (disk) {
		ide = z486_ide_open(disk, ide_debug);
		if (!ide) {
			perror(disk);
			goto out;
		}
		printf("IDE0: %s%s\n", disk,
		       z486_ide_readonly(ide) ? " (read-only)" : "");
	}
	input = z486_input_open(keyboard, mouse, input_debug);
	if (!input) {
		perror("open evdev input");
		goto out;
	}
	if (keyboard)
		printf("keyboard: %s\n", keyboard);
	if (mouse)
		printf("mouse: %s\n", mouse);
	__sync_synchronize();
	dma_base = ((uint64_t)(reg_read(regs, REG_BASE_HI) & 0xff) << 32) |
		   reg_read(regs, REG_BASE_LO);
	printf("staged %zu-byte VGA and %zu-byte system ROM in %zu MiB at %#"
	       PRIx64 "\n", boot1_size, boot0_size,
	       memory_size / (1024 * 1024), dma_base);
	printf("CMA: guest %#x+%#x, zSST FBI %#x+%#x, TMU %#x+%#x, "
	       "packed VGA %#x+%#x\n",
	       Z486_KV260_GUEST_OFFSET, Z486_KV260_GUEST_SIZE,
	       Z486_KV260_ZSST_FBI_OFFSET, Z486_KV260_ZSST_FBI_SIZE,
	       Z486_KV260_ZSST_TMU_OFFSET, Z486_KV260_ZSST_TMU_SIZE,
	       Z486_KV260_PACKED_VGA_OFFSET, Z486_KV260_PACKED_VGA_SIZE);
	signal(SIGINT, signal_stop);
	signal(SIGTERM, signal_stop);
	reg_write(regs, REG_CONTROL, 1);
	reg_write(regs, REG_VIDEO_CONTROL, 1U);
	running = true;
	printf("z486 released from reset; %s MiB RAM; audio %sx; "
	       "shared nearest-neighbor 1080p scanout\n", ram_mb, audio_boost);
	if (ide) {
		if (z486_ide_start(ide, &mgmt_bus)) {
			perror("initialize IDE0 management service");
			goto out;
		}
		printf("IDE0 management service ready\n");
	}
	if (no_wait) {
		result = 0;
		goto out;
	}

	while (!stopping) {
		uint32_t media_requests = reg_read(regs, REG_MGMT_STATUS);
		uint8_t ide_request = media_requests & 7;
		uint8_t ide1_request = (media_requests >> 3) & 7;
		uint64_t now_ms;

		if (ide && (ide_request || ide1_request) &&
		    z486_ide_service(ide, &mgmt_bus, ide_request,
				 ide1_request)) {
			perror("IDE0 service");
			goto out;
		}
		if (z486_input_service(input, &ps2_bus)) {
			perror("PS/2 input service");
			goto out;
		}
		if (z486_input_stop_requested(input)) {
			printf("Host quit chord pressed; stopping z486\n");
			break;
		}
		next_status = reg_read(regs, REG_BOOT_STATUS);
		now_ms = monotonic_milliseconds();
		if ((next_status & ~7U) != (status & ~7U) ||
		    now_ms >= next_status_ms) {
			show_status(regs, next_status);
			status = next_status;
			next_status_ms = now_ms + 1000;
		}
		if (!ide || (!ide_request && !ide1_request))
			usleep(50);
	}
	if (stop_and_drain(regs))
		goto out;
	running = false;
	printf("z486 stopped\n");
	if (ide)
		printf("IDE0 sectors: read=%" PRIu64 " written=%" PRIu64 "\n",
		       z486_ide_read_sectors(ide),
		       z486_ide_written_sectors(ide));
	result = 0;

out:
	if (running) {
		if (stop_and_drain(regs))
			result = 1;
	}
	z486_input_close(input);
	z486_ide_close(ide);
	if (memory != MAP_FAILED)
		munmap(memory, memory_size);
	if (regs != MAP_FAILED)
		munmap((void *)regs, (size_t)page_size);
	if (fd >= 0)
		close(fd);
	return result;
}
