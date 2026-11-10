/*
 * atexitlog.so - LD_PRELOAD debugging aid: log atexit(), __cxa_atexit(),
 * and __cxa_finalize() calls (with the object each
 * function pointer / DSO handle lives in) to stderr, then forward them via
 * RTLD_NEXT (-DNO_ATEXIT / -DNO_FINALIZE leave those wrappers out).  Used to chase exit handlers left behind by dlclose()d objects.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void
logf_(const char *what, const void *p, const void *extra)
{
	Dl_info dli;
	char buf[320];
	int n;
	const char *obj = "?";

	if (p != NULL && dladdr(p, &dli) != 0 && dli.dli_fname != NULL)
		obj = dli.dli_fname;
	n = snprintf(buf, sizeof(buf), "ATEXITLOG %s %p (%s) %p\n", what, p,
	    obj, extra);
	if (n > 0)
		write(STDERR_FILENO, buf, (size_t)n < sizeof(buf) ? n : sizeof(buf));
}

#ifndef NO_ATEXIT
int
atexit(void (*fn)(void))
{
	static int (*real)(void (*)(void));

	if (real == NULL)
		real = (int (*)(void (*)(void)))dlsym(RTLD_NEXT, "atexit");
	logf_("atexit", (void *)fn, __builtin_return_address(0));
	return real(fn);
}

int
__cxa_atexit(void (*fn)(void *), void *arg, void *dso)
{
	static int (*real)(void (*)(void *), void *, void *);

	if (real == NULL)
		real = (int (*)(void (*)(void *), void *, void *))
		    dlsym(RTLD_NEXT, "__cxa_atexit");
	logf_("cxa_atexit", (void *)fn, dso);
	return real(fn, arg, dso);
}

#endif /* NO_ATEXIT */

#ifndef NO_FINALIZE
void
__cxa_finalize(void *dso)
{
	static void (*real)(void *);

	if (real == NULL)
		real = (void (*)(void *))dlsym(RTLD_NEXT, "__cxa_finalize");
	logf_("cxa_finalize", dso, __builtin_return_address(0));
	real(dso);
	logf_("cxa_finalize-done", dso, NULL);
}

#endif /* NO_FINALIZE */

/*
 * No dlopen()/dlclose() wrappers: dlsym(RTLD_NEXT, "dlopen") finds libc's
 * weak stub (returns NULL), not ld.elf_so's implementation.
 */
