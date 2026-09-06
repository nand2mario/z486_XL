// SPDX-License-Identifier: GPL-2.0
/* CMA-backed UIO glue for the KV260 z486 core. */

#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/sizes.h>
#include <linux/uio_driver.h>

#include "z486_kv260_memory_map.h"

#define DRIVER_NAME         "z486_uio"
#define DEFAULT_BUFFER_SIZE ((size_t)Z486_KV260_CMA_SIZE)
#define MAX_BUFFER_SIZE     DEFAULT_BUFFER_SIZE

#define Z486_MAGIC  0x5a343836
#define REG_MAGIC   0x00
#define REG_CONTROL 0x08
#define REG_BASE_LO 0x0c
#define REG_BASE_HI 0x10
#define REG_SIZE    0x24
#define REG_VIDEO_CONTROL 0x58

struct z486_uio {
	struct uio_info info;
	void *buffer;
	dma_addr_t dma_handle;
	size_t buffer_size;
	void __iomem *regs;
};

static void z486_stop(struct z486_uio *priv)
{
	u32 video_control = ioread32(priv->regs + REG_VIDEO_CONTROL);

	iowrite32(video_control & ~0x3, priv->regs + REG_VIDEO_CONTROL);
	iowrite32(0, priv->regs + REG_CONTROL);
}

static int z486_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct z486_uio *priv;
	struct resource *res;
	u32 requested_size = DEFAULT_BUFFER_SIZE;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -ENODEV;
	priv->regs = devm_ioremap_resource(dev, res);
	if (IS_ERR(priv->regs))
		return PTR_ERR(priv->regs);
	if (ioread32(priv->regs + REG_MAGIC) != Z486_MAGIC) {
		dev_err(dev, "PL register magic does not match z486\n");
		return -ENODEV;
	}

	/* The AXI master stays quiescent until userspace has staged the ROMs. */
	z486_stop(priv);
	of_property_read_u32(dev->of_node, "nand2mario,buffer-size",
			     &requested_size);
	if (!requested_size || requested_size > MAX_BUFFER_SIZE ||
	    !IS_ALIGNED(requested_size, SZ_1M)) {
		dev_err(dev, "buffer size must be 1..%zu MiB and MiB-aligned\n",
			MAX_BUFFER_SIZE / SZ_1M);
		return -EINVAL;
	}
	priv->buffer_size = requested_size;

	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(40));
	if (ret)
		return dev_err_probe(dev, ret, "cannot set 40-bit DMA mask\n");

	priv->buffer = dmam_alloc_coherent(dev, priv->buffer_size,
					   &priv->dma_handle, GFP_KERNEL);
	if (!priv->buffer) {
		dev_err(dev, "cannot allocate %zu MiB contiguous DMA memory\n",
			priv->buffer_size / SZ_1M);
		return -ENOMEM;
	}
	if (!IS_ALIGNED(priv->dma_handle, 256)) {
		dev_err(dev, "DMA allocation is not burst-aligned\n");
		return -EINVAL;
	}

	/* Only the kernel chooses the physical buffer passed to the PL. */
	iowrite32(lower_32_bits(priv->dma_handle), priv->regs + REG_BASE_LO);
	iowrite32(upper_32_bits(priv->dma_handle), priv->regs + REG_BASE_HI);
	iowrite32(priv->buffer_size, priv->regs + REG_SIZE);

	priv->info.name = "z486";
	priv->info.version = "1.0";
	priv->info.irq = UIO_IRQ_NONE;
	priv->info.mem[0].name = "registers";
	priv->info.mem[0].addr = res->start;
	priv->info.mem[0].size = resource_size(res);
	priv->info.mem[0].memtype = UIO_MEM_PHYS;
	priv->info.mem[0].internal_addr = priv->regs;
	priv->info.mem[1].name = "cma-buffer";
	priv->info.mem[1].addr = (uintptr_t)priv->buffer;
	priv->info.mem[1].dma_addr = priv->dma_handle;
	priv->info.mem[1].size = priv->buffer_size;
	priv->info.mem[1].memtype = UIO_MEM_DMA_COHERENT;
	priv->info.mem[1].dma_device = dev;

	ret = devm_uio_register_device(dev, &priv->info);
	if (ret)
		return dev_err_probe(dev, ret, "cannot register UIO device\n");

	platform_set_drvdata(pdev, priv);
	dev_info(dev, "allocated %zu MiB at DMA address %pad; PC held stopped\n",
		 priv->buffer_size / SZ_1M, &priv->dma_handle);
	return 0;
}

static void z486_remove(struct platform_device *pdev)
{
	z486_stop(platform_get_drvdata(pdev));
}

static void z486_shutdown(struct platform_device *pdev)
{
	z486_stop(platform_get_drvdata(pdev));
}

static const struct of_device_id z486_of_match[] = {
	{ .compatible = "nand2mario,z486-kv260-1.1" },
	{ .compatible = "nand2mario,z486-kv260-1.0" },
	{ }
};
MODULE_DEVICE_TABLE(of, z486_of_match);

static struct platform_driver z486_driver = {
	.probe = z486_probe,
	.remove = z486_remove,
	.shutdown = z486_shutdown,
	.driver = {
		.name = DRIVER_NAME,
		.of_match_table = z486_of_match,
	},
};
module_platform_driver(z486_driver);

MODULE_AUTHOR("nand2mario");
MODULE_DESCRIPTION("CMA-backed UIO driver for the KV260 z486 core");
MODULE_LICENSE("GPL");
