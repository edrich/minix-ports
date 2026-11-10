#!/usr/bin/env python3
"""Apply the binutils 2.43.1 minix-target edits to the extracted tree in CWD.
Anchor strings were validated against the release tarball; each edit is
idempotence-checked by requiring exactly one replacement."""
import sys

edits = []


def sub(path, old, new, count=1):
    edits.append((path, old, new, count))


# --- bfd/config.bfd: add minix target before the generic elf entry
sub("bfd/config.bfd",
    """  i[3-7]86-*-elf* | i[3-7]86-*-rtems* | i[3-7]86-*-genode*)
    targ_defvec=i386_elf32_vec
    targ_selvecs="iamcu_elf32_vec i386_coff_vec"
    ;;
""",
    """  i[3-7]86-*-minix*)
    targ_defvec=i386_elf32_minix_vec
    targ_selvecs="iamcu_elf32_vec i386_coff_vec"
    ;;
  i[3-7]86-*-elf* | i[3-7]86-*-rtems* | i[3-7]86-*-genode*)
    targ_defvec=i386_elf32_vec
    targ_selvecs="iamcu_elf32_vec i386_coff_vec"
    ;;
""")

# --- bfd/configure.ac and bfd/configure: tb case for the new vector
for f in ("bfd/configure.ac", "bfd/configure"):
    sub(f,
        "    i386_elf32_vec)\t\t tb=\"$tb elf32-i386.lo $elfxx_x86 elf32.lo $elf\" ;;",
        "    i386_elf32_minix_vec)\t\t tb=\"$tb elf32-i386.lo $elfxx_x86 elf32.lo $elf\" ;;\n"
        "    i386_elf32_vec)\t\t tb=\"$tb elf32-i386.lo $elfxx_x86 elf32.lo $elf\" ;;")

# --- bfd/elf32-i386.c: append MINIX target section
sub("bfd/elf32-i386.c",
    """#undef	elf32_bed
#define elf32_bed				elf32_i386_vxworks_bed

#include "elf32-target.h"
""",
    """#undef	elf32_bed
#define elf32_bed				elf32_i386_vxworks_bed

#include "elf32-target.h"

/* MINIX support.  */

#undef	TARGET_LITTLE_SYM
#define TARGET_LITTLE_SYM		i386_elf32_minix_vec
#undef	TARGET_LITTLE_NAME
#define TARGET_LITTLE_NAME		"elf32-i386-minix"

#undef	elf32_bed
#define elf32_bed			elf32_i386_minix_bed

#include "elf32-target.h"
""")

# --- bfd/targets.c: extern + vector list entry
sub("bfd/targets.c",
    "extern const bfd_target i386_elf32_vec;\n",
    "extern const bfd_target i386_elf32_minix_vec;\n"
    "extern const bfd_target i386_elf32_vec;\n")
sub("bfd/targets.c",
    "\t&i386_elf32_vec,\n",
    "\t&i386_elf32_minix_vec,\n\t&i386_elf32_vec,\n")

# --- gas/config/tc-i386.h: MINIX output format
sub("gas/config/tc-i386.h",
    """#ifdef TE_SOLARIS
#define ELF_TARGET_FORMAT	"elf32-i386-sol2"
#define ELF_TARGET_FORMAT64	"elf64-x86-64-sol2"
#endif
""",
    """#ifdef TE_SOLARIS
#define ELF_TARGET_FORMAT	"elf32-i386-sol2"
#define ELF_TARGET_FORMAT64	"elf64-x86-64-sol2"
#endif

#ifdef TE_MINIX
#define ELF_TARGET_FORMAT	"elf32-i386-minix"
#endif
""")

# --- gas/configure.tgt: minix entry before generic elf (their -elf glob
# also matches i386-elf32-minix's "-elf", so order matters)
sub("gas/configure.tgt",
    "  i386-*-elf*)				fmt=elf ;;\n",
    "  i386-*-minix*)			fmt=elf em=minix ;;\n"
    "  i386-*-elf*)				fmt=elf ;;\n")

# --- ld/configure.tgt: minix entry before generic elf
sub("ld/configure.tgt",
    """i[3-7]86-*-elf* | i[3-7]86-*-rtems* | i[3-7]86-*-genode*)
			targ_emul=elf_i386
			targ_extra_emuls=elf_iamcu
			;;
""",
    """i[3-7]86-*-minix*)	targ_emul=elf_i386_minix
			targ_extra_emuls="elf_i386 elf_iamcu"
			;;
i[3-7]86-*-elf* | i[3-7]86-*-rtems* | i[3-7]86-*-genode*)
			targ_emul=elf_i386
			targ_extra_emuls=elf_iamcu
			;;
""")

# --- ld/Makefile.am and ld/Makefile.in: add emulation source
sub("ld/Makefile.am",
    "\teelf_i386_ldso.c \\\n",
    "\teelf_i386_ldso.c \\\n\teelf_i386_minix.c \\\n")
sub("ld/Makefile.in",
    "\teelf_i386_ldso.c \\\n",
    "\teelf_i386_ldso.c \\\n\teelf_i386_minix.c \\\n")
sub("ld/Makefile.in",
    "@AMDEP_TRUE@@am__include@ @am__quote@./$(DEPDIR)/eelf_i386_ldso.Po@am__quote@\n",
    "@AMDEP_TRUE@@am__include@ @am__quote@./$(DEPDIR)/eelf_i386_ldso.Po@am__quote@\n"
    "@AMDEP_TRUE@@am__include@ @am__quote@./$(DEPDIR)/eelf_i386_minix.Po@am__quote@\n")

# --- new files
newfiles = {
    "gas/config/te-minix.h": """\
#define TE_MINIX 1

/* We do not know what target is under us exactly; the assembler part of
   libgcc uses local labels in both styles.  */
#define LOCAL_LABELS_DOLLAR 1
#define LOCAL_LABELS_FB 1

#include "obj-format.h"
""",
    "ld/emulparams/elf_minix.sh": """\
ELF_INTERPRETER_NAME=\\"/usr/libexec/ld.elf_so\\"
""",
    "ld/emulparams/elf_i386_minix.sh": """\
. ${srcdir}/emulparams/elf_i386.sh
. ${srcdir}/emulparams/elf_minix.sh
OUTPUT_FORMAT="elf32-i386-minix"
""",
}


def main():
    nrep = 0
    for path, old, new, count in edits:
        with open(path) as f:
            data = f.read()
        if data.count(old) != count:
            print(f"FAIL: {path}: anchor found "
                  f"{data.count(old)}x (expected {count}x)")
            sys.exit(1)
        with open(path, "w") as f:
            f.write(data.replace(old, new))
        nrep += 1
    for path, content in newfiles.items():
        with open(path, "w") as f:
            f.write(content)
        nrep += 1
    print(f"applied {nrep} edits/new files")


if __name__ == "__main__":
    main()
