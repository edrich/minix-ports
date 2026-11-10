/*
 * libudev-minix: the libudev API over a static view of MINIX devices.
 * See libudev.h for the scope.
 *
 * The device database is rebuilt from /dev on every lookup (it is tiny):
 *
 *   /sys/devices/platform/i8042                              platform
 *     serio0, serio1                                         serio
 *       input/inputN                                         input
 *         eventN       /dev/input/eventN (minor 128 / 129)   input
 *   /sys/devices/virtual/input/inputN/eventN  (other evdev)  input
 *   /sys/devices/pci0000:00/0000:00:02.0                     pci (bochs)
 *     drm/card0        /dev/drm0                             drm
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/sysmacros.h>	/* major(), minor() (host test builds) */
#endif

#include "libudev.h"

#define EXPORT __attribute__((visibility("default")))

#define INPUT_MAJOR	64	/* <minix/dmap.h> */
#define DRM_MAJOR	18
#define EVDEV_KBD_MINOR	128	/* <minix/evdev.h> */
#define EVDEV_MOUSE_MINOR 129

/* ------------------------------------------------------------------ */
/* Lists. */

struct udev_list_entry {
	struct udev_list_entry *next;
	char *name;
	char *value;
};

struct ulist {
	struct udev_list_entry *first, *last;
};

static int
ulist_add(struct ulist *l, const char *name, const char *value)
{
	struct udev_list_entry *e;

	if ((e = calloc(1, sizeof(*e))) == NULL)
		return -1;
	e->name = strdup(name);
	e->value = value != NULL ? strdup(value) : NULL;
	if (e->name == NULL || (value != NULL && e->value == NULL)) {
		free(e->name);
		free(e->value);
		free(e);
		return -1;
	}
	if (l->last != NULL)
		l->last->next = e;
	else
		l->first = e;
	l->last = e;
	return 0;
}

static void
ulist_free(struct ulist *l)
{
	struct udev_list_entry *e, *next;

	for (e = l->first; e != NULL; e = next) {
		next = e->next;
		free(e->name);
		free(e->value);
		free(e);
	}
	l->first = l->last = NULL;
}

static const char *
ulist_get(const struct ulist *l, const char *name)
{
	struct udev_list_entry *e;

	for (e = l->first; e != NULL; e = e->next)
		if (strcmp(e->name, name) == 0)
			return e->value;
	return NULL;
}

/* Parse "KEY=VALUE\n..." into a list. */
static void
ulist_parse(struct ulist *l, const char *text)
{
	char line[256], *eq;
	const char *p, *nl;
	size_t len;

	for (p = text; *p != '\0'; p = nl + (*nl != '\0')) {
		nl = strchr(p, '\n');
		if (nl == NULL)
			nl = p + strlen(p);
		len = (size_t)(nl - p);
		if (len == 0 || len >= sizeof(line))
			continue;
		memcpy(line, p, len);
		line[len] = '\0';
		if ((eq = strchr(line, '=')) == NULL)
			continue;
		*eq = '\0';
		ulist_add(l, line, eq + 1);
	}
}

EXPORT struct udev_list_entry *
udev_list_entry_get_next(struct udev_list_entry *list_entry)
{

	return list_entry != NULL ? list_entry->next : NULL;
}

EXPORT struct udev_list_entry *
udev_list_entry_get_by_name(struct udev_list_entry *list_entry,
	const char *name)
{

	for (; list_entry != NULL; list_entry = list_entry->next)
		if (strcmp(list_entry->name, name) == 0)
			return list_entry;
	return NULL;
}

EXPORT const char *
udev_list_entry_get_name(struct udev_list_entry *list_entry)
{

	return list_entry != NULL ? list_entry->name : NULL;
}

EXPORT const char *
udev_list_entry_get_value(struct udev_list_entry *list_entry)
{

	return list_entry != NULL ? list_entry->value : NULL;
}

/* ------------------------------------------------------------------ */
/* Device database. */

struct devdesc {
	char syspath[160];
	char parent[160];		/* parent's syspath, or "" */
	char subsystem[16];
	char devtype[16];
	char driver[16];
	char devnode[48];		/* "" if none */
	dev_t devnum;
	char props[384];		/* extra properties, KEY=VALUE lines */
	char sysattrs[160];		/* sysfs attributes, NAME=VALUE lines */
	char tags[32];			/* ":tag:tag:" or "" */
};

struct devdb {
	struct devdesc *d;
	size_t n, max;
};

static struct devdesc *
db_add(struct devdb *db)
{
	struct devdesc *nd;

	if (db->n == db->max) {
		db->max = db->max ? db->max * 2 : 16;
		if ((nd = realloc(db->d, db->max * sizeof(*nd))) == NULL)
			return NULL;
		db->d = nd;
	}
	nd = &db->d[db->n++];
	memset(nd, 0, sizeof(*nd));
	return nd;
}

static struct devdesc *
db_find_syspath(struct devdb *db, const char *syspath)
{
	size_t i;

	for (i = 0; i < db->n; i++)
		if (strcmp(db->d[i].syspath, syspath) == 0)
			return &db->d[i];
	return NULL;
}

static void
db_add_simple(struct devdb *db, const char *syspath, const char *parent,
	const char *subsystem, const char *driver, const char *props,
	const char *sysattrs)
{
	struct devdesc *d;

	if (db_find_syspath(db, syspath) != NULL)
		return;
	if ((d = db_add(db)) == NULL)
		return;
	snprintf(d->syspath, sizeof(d->syspath), "%s", syspath);
	snprintf(d->parent, sizeof(d->parent), "%s", parent ? parent : "");
	snprintf(d->subsystem, sizeof(d->subsystem), "%s", subsystem);
	snprintf(d->driver, sizeof(d->driver), "%s", driver ? driver : "");
	snprintf(d->props, sizeof(d->props), "%s", props ? props : "");
	snprintf(d->sysattrs, sizeof(d->sysattrs), "%s",
	    sysattrs ? sysattrs : "");
}

static void
db_scan_input(struct devdb *db)
{
	char path[64], parent[160], serio[160], props[256], attrs[128];
	const char *name, *class;
	struct devdesc *d;
	struct dirent *de;
	struct stat st;
	DIR *dir;
	int n, serio_nr;

	if ((dir = opendir("/dev/input")) == NULL)
		return;

	while ((de = readdir(dir)) != NULL) {
		if (sscanf(de->d_name, "event%d", &n) != 1 || n < 0)
			continue;
		snprintf(path, sizeof(path), "/dev/input/event%d", n);
		if (stat(path, &st) != 0 || !S_ISCHR(st.st_mode))
			continue;

		serio_nr = -1;
		name = "MINIX input device";
		class = "";
		if (major(st.st_rdev) == INPUT_MAJOR &&
		    minor(st.st_rdev) == EVDEV_KBD_MINOR) {
			serio_nr = 0;
			name = "MINIX keyboard";
			class = "ID_INPUT_KEY=1\nID_INPUT_KEYBOARD=1\n";
		} else if (major(st.st_rdev) == INPUT_MAJOR &&
		    minor(st.st_rdev) == EVDEV_MOUSE_MINOR) {
			serio_nr = 1;
			name = "MINIX mouse";
			class = "ID_INPUT_MOUSE=1\n";
		}

		if (serio_nr >= 0) {
			db_add_simple(db, "/sys/devices/platform/i8042", NULL,
			    "platform", "i8042", NULL, NULL);
			snprintf(serio, sizeof(serio),
			    "/sys/devices/platform/i8042/serio%d", serio_nr);
			db_add_simple(db, serio, "/sys/devices/platform/i8042",
			    "serio", serio_nr == 0 ? "atkbd" : "psmouse", NULL,
			    NULL);
			snprintf(parent, sizeof(parent), "%s/input/input%d",
			    serio, n);
		} else {
			snprintf(parent, sizeof(parent),
			    "/sys/devices/virtual/input/input%d", n);
			serio[0] = '\0';
		}

		/* The inputN device, as udev's input_id sees it. */
		snprintf(props, sizeof(props),
		    "NAME=\"%s\"\nID_INPUT=1\n%s", name, class);
		snprintf(attrs, sizeof(attrs), "name=%s\n", name);
		db_add_simple(db, parent, serio[0] ? serio : NULL, "input",
		    NULL, props, attrs);

		/* The eventN device node. */
		if ((d = db_add(db)) == NULL)
			break;
		snprintf(d->syspath, sizeof(d->syspath), "%s/event%d",
		    parent, n);
		snprintf(d->parent, sizeof(d->parent), "%s", parent);
		snprintf(d->subsystem, sizeof(d->subsystem), "input");
		snprintf(d->devnode, sizeof(d->devnode), "%s", path);
		d->devnum = st.st_rdev;
		snprintf(d->props, sizeof(d->props), "ID_INPUT=1\n%s", class);
		snprintf(d->tags, sizeof(d->tags), ":seat:uaccess:");
	}

	closedir(dir);
}

static void
db_scan_drm(struct devdb *db)
{
	static const char pci[] = "/sys/devices/pci0000:00/0000:00:02.0";
	struct devdesc *d;
	struct stat st;

	if (stat("/dev/drm0", &st) != 0 || !S_ISCHR(st.st_mode) ||
	    major(st.st_rdev) != DRM_MAJOR)
		return;

	/* The only DRM-lite device is QEMU's Bochs/stdvga adapter. */
	db_add_simple(db, pci, NULL, "pci", "bochs",
	    "PCI_ID=1234:1111\nPCI_SLOT_NAME=0000:00:02.0\n"
	    "PCI_CLASS=30000\n",
	    "vendor=0x1234\ndevice=0x1111\nclass=0x030000\nboot_vga=1\n");

	if ((d = db_add(db)) == NULL)
		return;
	snprintf(d->syspath, sizeof(d->syspath), "%s/drm/card0", pci);
	snprintf(d->parent, sizeof(d->parent), "%s", pci);
	snprintf(d->subsystem, sizeof(d->subsystem), "drm");
	snprintf(d->devtype, sizeof(d->devtype), "drm_minor");
	snprintf(d->devnode, sizeof(d->devnode), "/dev/drm0");
	d->devnum = st.st_rdev;
	snprintf(d->tags, sizeof(d->tags), ":seat:master-of-seat:uaccess:");
}

static int
desc_cmp(const void *a, const void *b)
{

	return strcmp(((const struct devdesc *)a)->syspath,
	    ((const struct devdesc *)b)->syspath);
}

static void
db_scan(struct devdb *db)
{

	memset(db, 0, sizeof(*db));
	db_scan_input(db);
	db_scan_drm(db);
	if (db->n > 0)
		qsort(db->d, db->n, sizeof(db->d[0]), desc_cmp);
}

static void
db_free(struct devdb *db)
{

	free(db->d);
	memset(db, 0, sizeof(*db));
}

/* ------------------------------------------------------------------ */
/* Library context. */

struct udev {
	int refcount;
	void *userdata;
};

EXPORT struct udev *
udev_new(void)
{
	struct udev *udev;

	if ((udev = calloc(1, sizeof(*udev))) == NULL)
		return NULL;
	udev->refcount = 1;
	return udev;
}

EXPORT struct udev *
udev_ref(struct udev *udev)
{

	if (udev != NULL)
		udev->refcount++;
	return udev;
}

EXPORT struct udev *
udev_unref(struct udev *udev)
{

	if (udev != NULL && --udev->refcount == 0)
		free(udev);
	return NULL;
}

EXPORT void
udev_set_log_fn(struct udev *udev, void (*log_fn)(struct udev *, int,
	const char *, int, const char *, const char *, va_list))
{

	(void)udev;
	(void)log_fn;
}

EXPORT int
udev_get_log_priority(struct udev *udev)
{

	(void)udev;
	return 3;	/* LOG_ERR */
}

EXPORT void
udev_set_log_priority(struct udev *udev, int priority)
{

	(void)udev;
	(void)priority;
}

EXPORT void *
udev_get_userdata(struct udev *udev)
{

	return udev != NULL ? udev->userdata : NULL;
}

EXPORT void
udev_set_userdata(struct udev *udev, void *userdata)
{

	if (udev != NULL)
		udev->userdata = userdata;
}

/* ------------------------------------------------------------------ */
/* Devices. */

struct udev_device {
	int refcount;
	struct udev *udev;
	struct udev_device *parent;	/* lazily created, owned */
	int parent_done;
	char *syspath, *devpath, *sysname, *sysnum, *subsystem, *devtype;
	char *driver, *devnode, *parent_syspath;
	dev_t devnum;
	struct ulist props, sysattrs, tags, devlinks;
};

static struct udev_device *
device_new(struct udev *udev, const struct devdesc *d)
{
	struct udev_device *dev;
	char buf[64];
	const char *p, *t;

	if ((dev = calloc(1, sizeof(*dev))) == NULL)
		return NULL;
	dev->refcount = 1;
	dev->udev = udev_ref(udev);
	dev->syspath = strdup(d->syspath);
	dev->devpath = strdup(d->syspath + 4);		/* minus "/sys" */
	p = strrchr(d->syspath, '/');
	dev->sysname = strdup(p != NULL ? p + 1 : d->syspath);
	dev->subsystem = strdup(d->subsystem);
	dev->devtype = d->devtype[0] ? strdup(d->devtype) : NULL;
	dev->driver = d->driver[0] ? strdup(d->driver) : NULL;
	dev->devnode = d->devnode[0] ? strdup(d->devnode) : NULL;
	dev->parent_syspath = d->parent[0] ? strdup(d->parent) : NULL;
	dev->devnum = d->devnum;
	if (dev->sysname != NULL) {
		for (t = dev->sysname + strlen(dev->sysname);
		    t > dev->sysname && t[-1] >= '0' && t[-1] <= '9'; t--)
			;
		dev->sysnum = *t ? strdup(t) : NULL;
	}

	/* Properties: the standard ones first, then the class ones. */
	ulist_add(&dev->props, "DEVPATH", dev->devpath);
	ulist_add(&dev->props, "SUBSYSTEM", dev->subsystem);
	if (dev->devnode != NULL) {
		ulist_add(&dev->props, "DEVNAME", dev->devnode);
		snprintf(buf, sizeof(buf), "%u", (unsigned)major(dev->devnum));
		ulist_add(&dev->props, "MAJOR", buf);
		snprintf(buf, sizeof(buf), "%u", (unsigned)minor(dev->devnum));
		ulist_add(&dev->props, "MINOR", buf);
	}
	if (dev->devtype != NULL)
		ulist_add(&dev->props, "DEVTYPE", dev->devtype);
	if (dev->driver != NULL)
		ulist_add(&dev->props, "DRIVER", dev->driver);
	if (d->tags[0] != '\0') {
		ulist_add(&dev->props, "TAGS", d->tags);
		ulist_add(&dev->props, "CURRENT_TAGS", d->tags);
		for (p = d->tags + 1; *p != '\0'; p = t + 1) {
			if ((t = strchr(p, ':')) == NULL)
				break;
			if (t > p && (size_t)(t - p) < sizeof(buf)) {
				memcpy(buf, p, t - p);
				buf[t - p] = '\0';
				ulist_add(&dev->tags, buf, NULL);
			}
		}
	}
	ulist_parse(&dev->props, d->props);
	ulist_parse(&dev->sysattrs, d->sysattrs);

	if (dev->syspath == NULL || dev->devpath == NULL ||
	    dev->sysname == NULL || dev->subsystem == NULL) {
		udev_device_unref(dev);
		return NULL;
	}
	return dev;
}

EXPORT struct udev_device *
udev_device_ref(struct udev_device *dev)
{

	if (dev != NULL)
		dev->refcount++;
	return dev;
}

EXPORT struct udev_device *
udev_device_unref(struct udev_device *dev)
{

	if (dev == NULL || --dev->refcount > 0)
		return NULL;
	if (dev->parent != NULL)
		udev_device_unref(dev->parent);
	free(dev->syspath);
	free(dev->devpath);
	free(dev->sysname);
	free(dev->sysnum);
	free(dev->subsystem);
	free(dev->devtype);
	free(dev->driver);
	free(dev->devnode);
	free(dev->parent_syspath);
	ulist_free(&dev->props);
	ulist_free(&dev->sysattrs);
	ulist_free(&dev->tags);
	ulist_free(&dev->devlinks);
	udev_unref(dev->udev);
	free(dev);
	return NULL;
}

EXPORT struct udev *
udev_device_get_udev(struct udev_device *dev)
{

	return dev != NULL ? dev->udev : NULL;
}

EXPORT struct udev_device *
udev_device_new_from_syspath(struct udev *udev, const char *syspath)
{
	struct udev_device *dev;
	struct devdesc *d;
	struct devdb db;

	if (udev == NULL || syspath == NULL) {
		errno = EINVAL;
		return NULL;
	}
	db_scan(&db);
	d = db_find_syspath(&db, syspath);
	dev = d != NULL ? device_new(udev, d) : NULL;
	db_free(&db);
	if (dev == NULL)
		errno = ENODEV;
	return dev;
}

EXPORT struct udev_device *
udev_device_new_from_devnum(struct udev *udev, char type, dev_t devnum)
{
	struct udev_device *dev;
	struct devdb db;
	size_t i;

	if (udev == NULL || type != 'c') {
		errno = type != 'c' ? ENODEV : EINVAL;
		return NULL;
	}
	db_scan(&db);
	dev = NULL;
	for (i = 0; i < db.n; i++) {
		if (db.d[i].devnode[0] != '\0' && db.d[i].devnum == devnum) {
			dev = device_new(udev, &db.d[i]);
			break;
		}
	}
	db_free(&db);
	if (dev == NULL)
		errno = ENODEV;
	return dev;
}

EXPORT struct udev_device *
udev_device_new_from_subsystem_sysname(struct udev *udev,
	const char *subsystem, const char *sysname)
{
	struct udev_device *dev;
	struct devdb db;
	const char *p;
	size_t i;

	if (udev == NULL || subsystem == NULL || sysname == NULL) {
		errno = EINVAL;
		return NULL;
	}
	db_scan(&db);
	dev = NULL;
	for (i = 0; i < db.n; i++) {
		p = strrchr(db.d[i].syspath, '/');
		if (strcmp(db.d[i].subsystem, subsystem) == 0 && p != NULL &&
		    strcmp(p + 1, sysname) == 0) {
			dev = device_new(udev, &db.d[i]);
			break;
		}
	}
	db_free(&db);
	if (dev == NULL)
		errno = ENODEV;
	return dev;
}

EXPORT struct udev_device *
udev_device_new_from_device_id(struct udev *udev, const char *id)
{
	unsigned int ma, mi;

	if (id != NULL && sscanf(id, "c%u:%u", &ma, &mi) == 2)
		return udev_device_new_from_devnum(udev, 'c',
		    makedev(ma, mi));
	errno = ENODEV;
	return NULL;
}

EXPORT struct udev_device *
udev_device_new_from_environment(struct udev *udev)
{

	(void)udev;
	errno = ENODEV;
	return NULL;
}

EXPORT struct udev_device *
udev_device_get_parent(struct udev_device *dev)
{

	if (dev == NULL)
		return NULL;
	if (!dev->parent_done) {
		dev->parent_done = 1;
		if (dev->parent_syspath != NULL)
			dev->parent = udev_device_new_from_syspath(dev->udev,
			    dev->parent_syspath);
	}
	return dev->parent;
}

EXPORT struct udev_device *
udev_device_get_parent_with_subsystem_devtype(struct udev_device *dev,
	const char *subsystem, const char *devtype)
{
	struct udev_device *p;

	for (p = udev_device_get_parent(dev); p != NULL;
	    p = udev_device_get_parent(p)) {
		if (subsystem != NULL && strcmp(p->subsystem, subsystem) != 0)
			continue;
		if (devtype != NULL && (p->devtype == NULL ||
		    strcmp(p->devtype, devtype) != 0))
			continue;
		return p;
	}
	errno = ENOENT;
	return NULL;
}

#define GETTER(field)							\
EXPORT const char *							\
udev_device_get_##field(struct udev_device *dev)			\
{									\
	return dev != NULL ? dev->field : NULL;				\
}

GETTER(devpath)
GETTER(subsystem)
GETTER(devtype)
GETTER(syspath)
GETTER(sysname)
GETTER(sysnum)
GETTER(devnode)
GETTER(driver)

EXPORT int
udev_device_get_is_initialized(struct udev_device *dev)
{

	return dev != NULL;
}

EXPORT struct udev_list_entry *
udev_device_get_devlinks_list_entry(struct udev_device *dev)
{

	return dev != NULL ? dev->devlinks.first : NULL;
}

EXPORT struct udev_list_entry *
udev_device_get_properties_list_entry(struct udev_device *dev)
{

	return dev != NULL ? dev->props.first : NULL;
}

EXPORT struct udev_list_entry *
udev_device_get_tags_list_entry(struct udev_device *dev)
{

	return dev != NULL ? dev->tags.first : NULL;
}

EXPORT struct udev_list_entry *
udev_device_get_current_tags_list_entry(struct udev_device *dev)
{

	return udev_device_get_tags_list_entry(dev);
}

EXPORT struct udev_list_entry *
udev_device_get_sysattr_list_entry(struct udev_device *dev)
{

	return dev != NULL ? dev->sysattrs.first : NULL;
}

EXPORT const char *
udev_device_get_property_value(struct udev_device *dev, const char *key)
{

	if (dev == NULL || key == NULL)
		return NULL;
	return ulist_get(&dev->props, key);
}

EXPORT dev_t
udev_device_get_devnum(struct udev_device *dev)
{

	return dev != NULL ? dev->devnum : makedev(0, 0);
}

EXPORT const char *
udev_device_get_action(struct udev_device *dev)
{

	(void)dev;
	return NULL;	/* not from a monitor */
}

EXPORT unsigned long long int
udev_device_get_seqnum(struct udev_device *dev)
{

	(void)dev;
	return 0;
}

EXPORT unsigned long long int
udev_device_get_usec_since_initialized(struct udev_device *dev)
{

	(void)dev;
	return 1;
}

EXPORT const char *
udev_device_get_sysattr_value(struct udev_device *dev, const char *sysattr)
{

	if (dev == NULL || sysattr == NULL)
		return NULL;
	return ulist_get(&dev->sysattrs, sysattr);
}

EXPORT int
udev_device_set_sysattr_value(struct udev_device *dev, const char *sysattr,
	const char *value)
{

	(void)dev;
	(void)sysattr;
	(void)value;
	return -EACCES;
}

EXPORT int
udev_device_has_tag(struct udev_device *dev, const char *tag)
{

	return dev != NULL && tag != NULL &&
	    udev_list_entry_get_by_name(dev->tags.first, tag) != NULL;
}

EXPORT int
udev_device_has_current_tag(struct udev_device *dev, const char *tag)
{

	return udev_device_has_tag(dev, tag);
}

/* ------------------------------------------------------------------ */
/* Monitors: an fd that never becomes readable (no hotplug). */

struct udev_monitor {
	int refcount;
	struct udev *udev;
	int fds[2];
};

EXPORT struct udev_monitor *
udev_monitor_new_from_netlink(struct udev *udev, const char *name)
{
	struct udev_monitor *m;

	(void)name;
	if (udev == NULL) {
		errno = EINVAL;
		return NULL;
	}
	if ((m = calloc(1, sizeof(*m))) == NULL)
		return NULL;
	if (pipe(m->fds) != 0) {
		free(m);
		return NULL;
	}
	fcntl(m->fds[0], F_SETFD, FD_CLOEXEC);
	fcntl(m->fds[1], F_SETFD, FD_CLOEXEC);
	fcntl(m->fds[0], F_SETFL, O_NONBLOCK);
	m->refcount = 1;
	m->udev = udev_ref(udev);
	return m;
}

EXPORT struct udev_monitor *
udev_monitor_ref(struct udev_monitor *m)
{

	if (m != NULL)
		m->refcount++;
	return m;
}

EXPORT struct udev_monitor *
udev_monitor_unref(struct udev_monitor *m)
{

	if (m == NULL || --m->refcount > 0)
		return NULL;
	close(m->fds[0]);
	close(m->fds[1]);
	udev_unref(m->udev);
	free(m);
	return NULL;
}

EXPORT struct udev *
udev_monitor_get_udev(struct udev_monitor *m)
{

	return m != NULL ? m->udev : NULL;
}

EXPORT int
udev_monitor_enable_receiving(struct udev_monitor *m)
{

	return m != NULL ? 0 : -EINVAL;
}

EXPORT int
udev_monitor_set_receive_buffer_size(struct udev_monitor *m, int size)
{

	(void)size;
	return m != NULL ? 0 : -EINVAL;
}

EXPORT int
udev_monitor_get_fd(struct udev_monitor *m)
{

	return m != NULL ? m->fds[0] : -EINVAL;
}

EXPORT struct udev_device *
udev_monitor_receive_device(struct udev_monitor *m)
{

	(void)m;
	errno = EAGAIN;
	return NULL;
}

EXPORT int
udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *m,
	const char *subsystem, const char *devtype)
{

	(void)subsystem;
	(void)devtype;
	return m != NULL ? 0 : -EINVAL;
}

EXPORT int
udev_monitor_filter_add_match_tag(struct udev_monitor *m, const char *tag)
{

	(void)tag;
	return m != NULL ? 0 : -EINVAL;
}

EXPORT int
udev_monitor_filter_update(struct udev_monitor *m)
{

	return m != NULL ? 0 : -EINVAL;
}

EXPORT int
udev_monitor_filter_remove(struct udev_monitor *m)
{

	return m != NULL ? 0 : -EINVAL;
}

/* ------------------------------------------------------------------ */
/* Enumeration. */

struct udev_enumerate {
	int refcount;
	struct udev *udev;
	struct ulist match_subsystem, nomatch_subsystem, match_sysname;
	struct ulist match_property, match_sysattr, nomatch_sysattr;
	struct ulist match_tag, match_parent, syspaths;
	struct ulist result;
};

EXPORT struct udev_enumerate *
udev_enumerate_new(struct udev *udev)
{
	struct udev_enumerate *e;

	if (udev == NULL) {
		errno = EINVAL;
		return NULL;
	}
	if ((e = calloc(1, sizeof(*e))) == NULL)
		return NULL;
	e->refcount = 1;
	e->udev = udev_ref(udev);
	return e;
}

EXPORT struct udev_enumerate *
udev_enumerate_ref(struct udev_enumerate *e)
{

	if (e != NULL)
		e->refcount++;
	return e;
}

EXPORT struct udev_enumerate *
udev_enumerate_unref(struct udev_enumerate *e)
{

	if (e == NULL || --e->refcount > 0)
		return NULL;
	ulist_free(&e->match_subsystem);
	ulist_free(&e->nomatch_subsystem);
	ulist_free(&e->match_sysname);
	ulist_free(&e->match_property);
	ulist_free(&e->match_sysattr);
	ulist_free(&e->nomatch_sysattr);
	ulist_free(&e->match_tag);
	ulist_free(&e->match_parent);
	ulist_free(&e->syspaths);
	ulist_free(&e->result);
	udev_unref(e->udev);
	free(e);
	return NULL;
}

EXPORT struct udev *
udev_enumerate_get_udev(struct udev_enumerate *e)
{

	return e != NULL ? e->udev : NULL;
}

#define ADDER(fn, list)							\
EXPORT int								\
udev_enumerate_add_##fn(struct udev_enumerate *e, const char *s)	\
{									\
	if (e == NULL || s == NULL)					\
		return -EINVAL;						\
	return ulist_add(&e->list, s, NULL) == 0 ? 0 : -ENOMEM;		\
}

ADDER(match_subsystem, match_subsystem)
ADDER(nomatch_subsystem, nomatch_subsystem)
ADDER(match_sysname, match_sysname)
ADDER(match_tag, match_tag)
ADDER(syspath, syspaths)

EXPORT int
udev_enumerate_add_match_sysattr(struct udev_enumerate *e,
	const char *sysattr, const char *value)
{

	if (e == NULL || sysattr == NULL)
		return -EINVAL;
	return ulist_add(&e->match_sysattr, sysattr, value) == 0 ? 0 : -ENOMEM;
}

EXPORT int
udev_enumerate_add_nomatch_sysattr(struct udev_enumerate *e,
	const char *sysattr, const char *value)
{

	if (e == NULL || sysattr == NULL)
		return -EINVAL;
	return ulist_add(&e->nomatch_sysattr, sysattr, value) == 0 ?
	    0 : -ENOMEM;
}

EXPORT int
udev_enumerate_add_match_property(struct udev_enumerate *e,
	const char *property, const char *value)
{

	if (e == NULL || property == NULL)
		return -EINVAL;
	return ulist_add(&e->match_property, property, value) == 0 ?
	    0 : -ENOMEM;
}

EXPORT int
udev_enumerate_add_match_parent(struct udev_enumerate *e,
	struct udev_device *parent)
{

	if (e == NULL || parent == NULL)
		return -EINVAL;
	return ulist_add(&e->match_parent, parent->syspath, NULL) == 0 ?
	    0 : -ENOMEM;
}

EXPORT int
udev_enumerate_add_match_is_initialized(struct udev_enumerate *e)
{

	return e != NULL ? 0 : -EINVAL;	/* every device is initialized */
}

/* Does an attribute or property list match (fnmatch on values)? */
static int
match_values(const struct ulist *have, const struct ulist *want)
{
	struct udev_list_entry *w;
	const char *v;

	for (w = want->first; w != NULL; w = w->next) {
		v = ulist_get(have, w->name);
		if (v == NULL)
			continue;
		if (w->value == NULL || fnmatch(w->value, v, 0) == 0)
			return 1;
	}
	return 0;
}

static int
enum_matches(struct udev_enumerate *e, struct udev_device *dev)
{
	struct udev_list_entry *l;
	size_t len;
	int ok;

	if (e->match_subsystem.first != NULL) {
		ok = 0;
		for (l = e->match_subsystem.first; l != NULL; l = l->next)
			if (fnmatch(l->name, dev->subsystem, 0) == 0)
				ok = 1;
		if (!ok)
			return 0;
	}
	for (l = e->nomatch_subsystem.first; l != NULL; l = l->next)
		if (fnmatch(l->name, dev->subsystem, 0) == 0)
			return 0;
	if (e->match_sysname.first != NULL) {
		ok = 0;
		for (l = e->match_sysname.first; l != NULL; l = l->next)
			if (fnmatch(l->name, dev->sysname, 0) == 0)
				ok = 1;
		if (!ok)
			return 0;
	}
	if (e->match_property.first != NULL &&
	    !match_values(&dev->props, &e->match_property))
		return 0;
	for (l = e->match_sysattr.first; l != NULL; l = l->next) {
		const char *v = ulist_get(&dev->sysattrs, l->name);
		if (v == NULL || (l->value != NULL &&
		    fnmatch(l->value, v, 0) != 0))
			return 0;
	}
	for (l = e->nomatch_sysattr.first; l != NULL; l = l->next) {
		const char *v = ulist_get(&dev->sysattrs, l->name);
		if (v != NULL && (l->value == NULL ||
		    fnmatch(l->value, v, 0) == 0))
			return 0;
	}
	for (l = e->match_tag.first; l != NULL; l = l->next)
		if (!udev_device_has_tag(dev, l->name))
			return 0;
	if (e->match_parent.first != NULL) {
		ok = 0;
		for (l = e->match_parent.first; l != NULL; l = l->next) {
			len = strlen(l->name);
			if (strncmp(dev->syspath, l->name, len) == 0 &&
			    (dev->syspath[len] == '\0' ||
			    dev->syspath[len] == '/'))
				ok = 1;
		}
		if (!ok)
			return 0;
	}
	return 1;
}

EXPORT int
udev_enumerate_scan_devices(struct udev_enumerate *e)
{
	struct udev_device *dev;
	struct udev_list_entry *l;
	struct devdb db;
	size_t i;

	if (e == NULL)
		return -EINVAL;
	ulist_free(&e->result);
	db_scan(&db);
	for (i = 0; i < db.n; i++) {
		if ((dev = device_new(e->udev, &db.d[i])) == NULL)
			continue;
		if (enum_matches(e, dev))
			ulist_add(&e->result, dev->syspath, NULL);
		udev_device_unref(dev);
	}
	db_free(&db);
	for (l = e->syspaths.first; l != NULL; l = l->next)
		if (udev_list_entry_get_by_name(e->result.first,
		    l->name) == NULL)
			ulist_add(&e->result, l->name, NULL);
	return 0;
}

EXPORT int
udev_enumerate_scan_subsystems(struct udev_enumerate *e)
{
	static const char *subsystems[] = { "drm", "input", "pci",
	    "platform", "serio" };
	size_t i;

	if (e == NULL)
		return -EINVAL;
	ulist_free(&e->result);
	for (i = 0; i < sizeof(subsystems) / sizeof(subsystems[0]); i++) {
		char path[64];
		snprintf(path, sizeof(path), "/sys/subsystem/%s",
		    subsystems[i]);
		ulist_add(&e->result, path, NULL);
	}
	return 0;
}

EXPORT struct udev_list_entry *
udev_enumerate_get_list_entry(struct udev_enumerate *e)
{

	return e != NULL ? e->result.first : NULL;
}

/* ------------------------------------------------------------------ */
/* Queue: always settled.  Hardware database: empty. */

struct udev_queue {
	int refcount;
	struct udev *udev;
};

EXPORT struct udev_queue *
udev_queue_new(struct udev *udev)
{
	struct udev_queue *q;

	if (udev == NULL || (q = calloc(1, sizeof(*q))) == NULL)
		return NULL;
	q->refcount = 1;
	q->udev = udev_ref(udev);
	return q;
}

EXPORT struct udev_queue *
udev_queue_ref(struct udev_queue *q)
{

	if (q != NULL)
		q->refcount++;
	return q;
}

EXPORT struct udev_queue *
udev_queue_unref(struct udev_queue *q)
{

	if (q != NULL && --q->refcount == 0) {
		udev_unref(q->udev);
		free(q);
	}
	return NULL;
}

EXPORT struct udev *
udev_queue_get_udev(struct udev_queue *q)
{

	return q != NULL ? q->udev : NULL;
}

EXPORT int
udev_queue_get_udev_is_active(struct udev_queue *q)
{

	(void)q;
	return 1;
}

EXPORT int
udev_queue_get_queue_is_empty(struct udev_queue *q)
{

	(void)q;
	return 1;
}

EXPORT int
udev_queue_get_fd(struct udev_queue *q)
{

	(void)q;
	return -ENOSYS;
}

EXPORT int
udev_queue_flush(struct udev_queue *q)
{

	(void)q;
	return 0;
}

EXPORT struct udev_hwdb *
udev_hwdb_new(struct udev *udev)
{

	(void)udev;
	errno = ENOENT;
	return NULL;
}

EXPORT struct udev_hwdb *
udev_hwdb_ref(struct udev_hwdb *hwdb)
{

	return hwdb;
}

EXPORT struct udev_hwdb *
udev_hwdb_unref(struct udev_hwdb *hwdb)
{

	(void)hwdb;
	return NULL;
}

EXPORT struct udev_list_entry *
udev_hwdb_get_properties_list_entry(struct udev_hwdb *hwdb,
	const char *modalias, unsigned flags)
{

	(void)hwdb;
	(void)modalias;
	(void)flags;
	return NULL;
}

/* ------------------------------------------------------------------ */

EXPORT int
udev_util_encode_string(const char *str, char *str_enc, size_t len)
{
	size_t i, j;

	if (str == NULL || str_enc == NULL)
		return -EINVAL;
	for (i = 0, j = 0; str[i] != '\0'; i++) {
		if (str[i] == ' ' || str[i] == '\\' || str[i] == '/' ||
		    (unsigned char)str[i] < 0x20) {
			if (j + 4 >= len)
				return -EINVAL;
			snprintf(&str_enc[j], 5, "\\x%02x",
			    (unsigned char)str[i]);
			j += 4;
		} else {
			if (j + 1 >= len)
				return -EINVAL;
			str_enc[j++] = str[i];
		}
	}
	if (j >= len)
		return -EINVAL;
	str_enc[j] = '\0';
	return 0;
}
