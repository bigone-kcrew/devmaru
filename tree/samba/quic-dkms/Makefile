KERNELRELEASE ?= $(shell uname -r)
KERNEL_BUILD := /lib/modules/$(KERNELRELEASE)/build

.PHONY: all clean

all:
	$(MAKE) -C $(KERNEL_BUILD) \
		W=1 \
		M=$(CURDIR)/modules/net/quic \
		modules \
		ROOTDIR=$(CURDIR)/modules \
		CONFIG_IP_QUIC=m

clean:
	$(MAKE) -C $(KERNEL_BUILD) \
		M=$(CURDIR)/modules/net/quic \
		clean
