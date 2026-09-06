ifeq ($(origin CC),default)
CC := aarch64-linux-gnu-gcc
endif
CFLAGS ?= -O2 -Wall -Wextra -Werror
CPPFLAGS += -I../include
HOSTCC ?= cc

.PHONY: all test clean

all: z486-main z486-drm

z486-main: z486-main.c z486-ide.c z486-ide.h z486-input.c z486-input.h \
	../include/z486_kv260_memory_map.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ z486-main.c z486-ide.c z486-input.c

z486-drm: z486-drm.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $<

test: test_z486_ide test_z486_input
	./test_z486_ide
	./test_z486_input

test_z486_ide: test_z486_ide.c z486-ide.c z486-ide.h
	$(HOSTCC) $(CPPFLAGS) $(CFLAGS) -o $@ test_z486_ide.c z486-ide.c

test_z486_input: test_z486_input.c z486-input.c z486-input.h
	$(HOSTCC) $(CPPFLAGS) $(CFLAGS) -o $@ test_z486_input.c z486-input.c

clean:
	rm -f z486-main z486-drm test_z486_ide test_z486_input
