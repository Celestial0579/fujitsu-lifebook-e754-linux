// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * fujitsu_fext_extra - Zusatzfunktionen der Fujitsu-FEXT-Schnittstelle (FUJ02E3),
 * die der Mainline-Treiber fujitsu_laptop nicht anbietet.
 *
 * Entwickelt fuer LIFEBOOK E754 (BIOS 1.32), Funktionsnummern aus der DSDT:
 *   0x1005 S005  Geraete-Stromsteuerung (Modulschacht BYCI, Bluetooth BTCI)
 *   0x1006 S006  EC-Mailbox: Luefter-Tacho, EC-Temperaturen, Luefterkurve
 *
 * Bewusst nicht genutzt: S009 HWMR (zwingt den Luefter fuer die Messung auf
 * Vollgas), S007 _PPC (wirkungslos unter intel_pstate), S00A USB-Charge
 * (Bitbelegung unbekannt, Schreiben ginge per SMI an die Firmware).
 *
 * Der Treiber bindet NICHT an FUJ02E3 (das macht fujitsu_laptop), sondern ruft
 * \_SB.FEXT.FUNC direkt auf. FUNC ist "Serialized", parallele Aufrufe sind sicher.
 */
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/hwmon.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/sysfs.h>

#define FUNC_POWER	0x1005
#define FUNC_EC		0x1006

#define FEXT_ERR	0x80000000ULL

static bool allow_raw;
module_param(allow_raw, bool, 0444);
MODULE_PARM_DESC(allow_raw, "raw_call-Attribut fuer beliebige FUNC-Aufrufe freischalten (nur zur Entwicklung)");

static bool force;
module_param(force, bool, 0444);
MODULE_PARM_DESC(force, "Auch auf nicht getesteten Modellen laden");

struct fext_extra {
	acpi_handle func;
	struct mutex lock;		/* raw_call */
	u32 power_caps;
	u32 raw_last;
};

static struct platform_device *fext_pdev;

static int fext_call(struct fext_extra *fx, u32 fn, u32 a1, u32 a2, u32 a3, u32 *out)
{
	union acpi_object p[4] = {
		{ .integer = { .type = ACPI_TYPE_INTEGER, .value = fn } },
		{ .integer = { .type = ACPI_TYPE_INTEGER, .value = a1 } },
		{ .integer = { .type = ACPI_TYPE_INTEGER, .value = a2 } },
		{ .integer = { .type = ACPI_TYPE_INTEGER, .value = a3 } },
	};
	struct acpi_object_list args = { .count = 4, .pointer = p };
	unsigned long long v;
	acpi_status st;

	st = acpi_evaluate_integer(fx->func, NULL, &args, &v);
	if (ACPI_FAILURE(st)) {
		pr_debug("FUNC(%#x,%#x,%#x,%#x) failed: %s\n", fn, a1, a2, a3,
			 acpi_format_exception(st));
		return -EIO;
	}
	pr_debug("FUNC(%#x,%#x,%#x,%#x) = %#llx\n", fn, a1, a2, a3, v);
	if (out)
		*out = (u32)v;
	/* 0x80000000 = nicht unterstuetzt, 0x80000001 = Timeout/Fehler */
	if ((v & 0xffffff00ULL) == FEXT_ERR)
		return v == FEXT_ERR ? -EOPNOTSUPP : -ETIMEDOUT;
	return 0;
}

/* ---------------- EC-Register (S006) ---------------- */

/*
 * S006(0x10, 0x01rr): liest EC-Bank 1, Register rr (16 bit, ECGM-Mailbox 0x43).
 * Gemessen am E754:
 *   0x00 lo  CPU-Temperatur in Grad C (= PDAT)
 *   0x10..0x1b  Luefterkurve: hi = Stellwert, lo = Temperaturschwelle
 *   0x50     Tacho-Periode, RPM = 30000000 / Wert (0xffff = steht/kein Luefter)
 *   0x51     zweiter Tacho (E754: nicht bestueckt, 0xffff)
 *   0x52 hi  geglaettete Regeltemperatur des EC in Grad C
 */
#define EC_TEMP		0x00
#define EC_CURVE	0x10
#define EC_CURVE_N	12
#define EC_TACHO	0x50
#define EC_TCTRL	0x52
#define TACHO_CLK	30000000

static int fext_ec_read(struct fext_extra *fx, u8 reg, u32 *val)
{
	int ret = fext_call(fx, FUNC_EC, 0x10, 0x0100 | reg, 0, val);

	if (!ret)
		*val &= 0xffff;
	return ret;
}

/* ---------------- hwmon ---------------- */

static umode_t fext_hwmon_visible(const void *data, enum hwmon_sensor_types type,
				  u32 attr, int channel)
{
	return 0444;
}

static int fext_hwmon_read(struct device *dev, enum hwmon_sensor_types type,
			   u32 attr, int channel, long *val)
{
	struct fext_extra *fx = dev_get_drvdata(dev);
	u32 v;
	int ret;

	switch (type) {
	case hwmon_fan:
		ret = fext_ec_read(fx, EC_TACHO, &v);
		if (ret)
			return ret;
		*val = (v == 0 || v == 0xffff) ? 0 : TACHO_CLK / v;
		return 0;
	case hwmon_temp:
		ret = fext_ec_read(fx, channel ? EC_TCTRL : EC_TEMP, &v);
		if (ret)
			return ret;
		*val = (channel ? (v >> 8) : (v & 0xff)) * 1000L;
		return 0;
	default:
		return -EOPNOTSUPP;
	}
}

static int fext_hwmon_read_string(struct device *dev, enum hwmon_sensor_types type,
				  u32 attr, int channel, const char **str)
{
	if (type == hwmon_fan)
		*str = "CPU-Luefter";
	else
		*str = channel ? "EC Regeltemperatur" : "EC CPU";
	return 0;
}

static const struct hwmon_channel_info * const fext_hwmon_info[] = {
	HWMON_CHANNEL_INFO(fan, HWMON_F_INPUT | HWMON_F_LABEL),
	HWMON_CHANNEL_INFO(temp, HWMON_T_INPUT | HWMON_T_LABEL, HWMON_T_INPUT | HWMON_T_LABEL),
	NULL
};

static const struct hwmon_ops fext_hwmon_ops = {
	.is_visible = fext_hwmon_visible,
	.read = fext_hwmon_read,
	.read_string = fext_hwmon_read_string,
};

static const struct hwmon_chip_info fext_hwmon_chip = {
	.ops = &fext_hwmon_ops,
	.info = fext_hwmon_info,
};

/* Luefterkurve der Firmware, eine Zeile pro Stufe: "<Grad C> <Stellwert 0-255>" */
static ssize_t fan_curve_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct fext_extra *fx = dev_get_drvdata(dev);
	ssize_t len = 0;
	u32 v;
	int i, ret;

	for (i = 0; i < EC_CURVE_N; i++) {
		ret = fext_ec_read(fx, EC_CURVE + i, &v);
		if (ret)
			return ret;
		len += sysfs_emit_at(buf, len, "%u %u\n", v & 0xff, v >> 8);
	}
	return len;
}
static DEVICE_ATTR_RO(fan_curve);

/* ---------------- Geraete-Strom (S005) ---------------- */

#define PWR_BAY		BIT(0)		/* BYCI: Modulschacht (SATA-Bay) */
#define PWR_BT		BIT(10)		/* BTCI: Bluetooth */

/* S005(1, mask, value): Bit gesetzt = Geraet AUS. Mit mask=0 reine Abfrage. */
static ssize_t power_show(struct device *dev, char *buf, u32 bit)
{
	struct fext_extra *fx = dev_get_drvdata(dev);
	u32 v;
	int ret = fext_call(fx, FUNC_POWER, 1, 0, 0, &v);

	if (ret)
		return ret;
	return sysfs_emit(buf, "%d\n", !(v & bit));
}

static ssize_t power_store(struct device *dev, const char *buf, size_t count, u32 bit)
{
	struct fext_extra *fx = dev_get_drvdata(dev);
	bool on;
	int ret = kstrtobool(buf, &on);

	if (ret)
		return ret;
	ret = fext_call(fx, FUNC_POWER, 1, bit, on ? 0 : bit, NULL);
	return ret ? ret : count;
}

static ssize_t bay_power_show(struct device *d, struct device_attribute *a, char *b)
{ return power_show(d, b, PWR_BAY); }
static ssize_t bay_power_store(struct device *d, struct device_attribute *a, const char *b, size_t c)
{ return power_store(d, b, c, PWR_BAY); }
static DEVICE_ATTR_RW(bay_power);

static ssize_t bluetooth_power_show(struct device *d, struct device_attribute *a, char *b)
{ return power_show(d, b, PWR_BT); }
static ssize_t bluetooth_power_store(struct device *d, struct device_attribute *a, const char *b, size_t c)
{ return power_store(d, b, c, PWR_BT); }
static DEVICE_ATTR_RW(bluetooth_power);

/* ---------------- Entwicklung: raw_call ---------------- */

static ssize_t raw_call_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct fext_extra *fx = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%#x\n", fx->raw_last);
}

static ssize_t raw_call_store(struct device *dev, struct device_attribute *attr,
			      const char *buf, size_t count)
{
	struct fext_extra *fx = dev_get_drvdata(dev);
	u32 f, a1, a2, a3, v = 0;
	int ret;

	if (sscanf(buf, "%x %x %x %x", &f, &a1, &a2, &a3) != 4)
		return -EINVAL;
	ret = fext_call(fx, f, a1, a2, a3, &v);
	mutex_lock(&fx->lock);
	fx->raw_last = v;
	mutex_unlock(&fx->lock);
	return (ret && ret != -EOPNOTSUPP && ret != -ETIMEDOUT) ? ret : count;
}
static DEVICE_ATTR(raw_call, 0600, raw_call_show, raw_call_store);

static struct attribute *fext_attrs[] = {
	&dev_attr_bay_power.attr,
	&dev_attr_bluetooth_power.attr,
	&dev_attr_fan_curve.attr,
	&dev_attr_raw_call.attr,
	NULL
};

static umode_t fext_attr_visible(struct kobject *kobj, struct attribute *attr, int n)
{
	struct fext_extra *fx = dev_get_drvdata(kobj_to_dev(kobj));

	if (attr == &dev_attr_raw_call.attr)
		return allow_raw ? attr->mode : 0;
	if (attr == &dev_attr_bay_power.attr)
		return (fx->power_caps & PWR_BAY) ? attr->mode : 0;
	if (attr == &dev_attr_bluetooth_power.attr)
		return (fx->power_caps & PWR_BT) ? attr->mode : 0;
	return attr->mode;
}

static const struct attribute_group fext_group = {
	.attrs = fext_attrs,
	.is_visible = fext_attr_visible,
};
__ATTRIBUTE_GROUPS(fext);

static int fext_probe(struct platform_device *pdev)
{
	struct fext_extra *fx;
	struct device *hw;
	acpi_status st;
	u32 v;

	fx = devm_kzalloc(&pdev->dev, sizeof(*fx), GFP_KERNEL);
	if (!fx)
		return -ENOMEM;
	mutex_init(&fx->lock);

	st = acpi_get_handle(NULL, "\\_SB.FEXT.FUNC", &fx->func);
	if (ACPI_FAILURE(st))
		return -ENODEV;

	platform_set_drvdata(pdev, fx);

	if (!fext_call(fx, FUNC_POWER, 0, 0, 0, &v))
		fx->power_caps = v;
	dev_info(&pdev->dev, "Geraete-Strom-Caps %#x\n", fx->power_caps);

	hw = devm_hwmon_device_register_with_info(&pdev->dev, "fujitsu_fext", fx,
						  &fext_hwmon_chip, NULL);
	if (IS_ERR(hw))
		dev_warn(&pdev->dev, "hwmon nicht registriert: %ld\n", PTR_ERR(hw));
	return 0;
}

static struct platform_driver fext_driver = {
	.driver = {
		.name = "fujitsu-fext-extra",
		.dev_groups = fext_groups,
	},
	.probe = fext_probe,
};

static const struct dmi_system_id fext_dmi[] = {
	{ .matches = { DMI_MATCH(DMI_SYS_VENDOR, "FUJITSU"),
		       DMI_MATCH(DMI_PRODUCT_NAME, "LIFEBOOK E754") } },
	{ }
};
MODULE_DEVICE_TABLE(dmi, fext_dmi);

static int __init fext_init(void)
{
	acpi_handle h;
	int ret;

	if (!dmi_check_system(fext_dmi) && !force)
		return -ENODEV;
	if (ACPI_FAILURE(acpi_get_handle(NULL, "\\_SB.FEXT.FUNC", &h)))
		return -ENODEV;

	ret = platform_driver_register(&fext_driver);
	if (ret)
		return ret;
	fext_pdev = platform_device_register_simple("fujitsu-fext-extra", PLATFORM_DEVID_NONE,
						    NULL, 0);
	if (IS_ERR(fext_pdev)) {
		platform_driver_unregister(&fext_driver);
		return PTR_ERR(fext_pdev);
	}
	return 0;
}

static void __exit fext_exit(void)
{
	platform_device_unregister(fext_pdev);
	platform_driver_unregister(&fext_driver);
}

module_init(fext_init);
module_exit(fext_exit);

MODULE_DESCRIPTION("Fujitsu FEXT Zusatzfunktionen (Luefter, EC-Temperaturen, Geraete-Strom)");
MODULE_LICENSE("GPL");
MODULE_SOFTDEP("pre: fujitsu_laptop");
