/* evprobe: is an evdev device held by someone (EBUSY) or free? */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	int i, fd;

	for (i = 1; i < argc; i++) {
		fd = open(argv[i], O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			printf("EVPROBE %s: %s\n", argv[i], strerror(errno));
		else {
			printf("EVPROBE %s: free\n", argv[i]);
			close(fd);
		}
	}
	return 0;
}
