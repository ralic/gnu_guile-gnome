pkgs_ordered=""
checks_catted=""

ensure_dependencies()
{
    local pkg=$1
    for check in $pkg/*-checks.ac; do
        if [ -f $check ]; then
            dep_pkg=`echo $check | sed -e "s,^$pkg/\(.*\)-checks\.ac$,\1,"`
            # echo "$pkg depends on $dep_pkg"
            if [ -d $dep_pkg ]; then
                pkgs_ordered=`echo "$pkgs_ordered" | sed -e "s,$dep_pkg,," -e "s,^,$dep_pkg ," -e 's,  , ,'`
                ensure_dependencies $dep_pkg # recurse
            else
                echo "$checks_catted" | grep -q $dep_pkg;
                if test $? -eq 1; then
                    cat $check >> configure.ac
                    checks_catted="$checks_catted $dep_pkg"
                fi
            fi
        fi
    done
}

autogen_pkg()
{
    # Check and parse release ID
    if [ ! -f ../=RELEASE-ID ]; then
	echo "no ../=RELEASE-ID file - you must run tla build-config -r"
	exit 1
    fi
    pkg_source=`awk 'BEGIN { FS = "[()]"; } /.*@.*\/.*\(.*\)/ { n = split($2, parts, "/"); print parts[n] " " parts[n - 1]; }' < ../=RELEASE-ID`
    pkg=`echo $pkg_source | awk '{ print $1 }'`
    source=`echo $pkg_source | awk '{ print $2 }'`
    case $pkg in
	dev) 
	    package=guile-gnome-dev
	    version="`date +%Y%m%d`+$source"
	    ;;
	*.dev)
	    package=`echo $pkg | sed -e 's/\.dev$//'`
	    version="`date +%Y%m%d`+$source"
	    ;;
	*-*.*.*)
	    package=`echo $pkg | sed -e 's/-[^.-]*\.[^.]*\.[^.]*$//'`
	    version=`echo $pkg | sed -e 's/^.*-//'`
	    ;;
	*)
	    echo "unable to parse config file name"
	    exit 1
	    ;;
    esac
    
    echo "+ configuring tree as $package, version $version"

    # Figure out list of packages
    packages=""
    pkgs_path="."
    for dir in [a-z]*; do
	if [ -f $dir/package.ac ]; then
	    packages="$packages $dir"
	fi
    done

    # prelude of configure.ac
    cat > configure.ac <<EOF
dnl -- WARNING: generated by $0, changes will be lost
AC_PREREQ(2.52)
AC_INIT(autogen-pkg.sh)
AM_CONFIG_HEADER(config.h)
AM_INIT_AUTOMAKE($package, $version)

AC_SUBST(VERSION,$version)

AM_MAINTAINER_MODE
AC_DISABLE_STATIC

AC_ISC_POSIX
AC_PROG_CC
AC_STDC_HEADERS
AC_PROG_LIBTOOL

AC_SUBST(AG_PKG_CONFIG_PATH, [$pkg_config_path])
AG_PACKAGES="$packages"
AC_SUBST(AG_PACKAGES)

MK=""; AC_SUBST(MK)
EOF

    cat >> configure.ac <<'EOF'
WARN_CFLAGS=-Wall
AC_ARG_ENABLE([Werror], AC_HELP_STRING([--disable-Werror],[Don't stop the build on errors]),
        [], WARN_CFLAGS="-Wall -Werror")
AC_SUBST(WARN_CFLAGS)

DEBUG_CFLAGS=
AC_ARG_ENABLE([debug], AC_HELP_STRING([--disable-debug],[Disable debugging information]),
        [], DEBUG_CFLAGS=-g)
AC_SUBST(DEBUG_CFLAGS)

# Optimize the DSO symbol hash table -- see ulrich drepper's paper,
# "how to write shared libraries"
GNULD_LDFLAGS=-Wl,-O1
AC_SUBST(GNULD_LDFLAGS)
AM_LDFLAGS='$(GNULD_LDFLAGS)'
AC_SUBST(AM_LDFLAGS)

#
# Check for Guile
#
AC_MSG_CHECKING(for Guile)
guile-config link > /dev/null || {
   echo "configure: cannot find guile-config; is Guile installed?" 1>&2
   exit 1
}
GUILE_VERSION=`guile-config info guileversion`
if test "$GUILE_VERSION" \< 1.6.4; then
   AC_MSG_ERROR([Guile 1.6.4 or newer is required, but you only have $GUILEVERSION.])
fi
GUILE_CFLAGS="`guile-config compile`"
GUILE_LIBS="`guile-config link`"
AC_SUBST(GUILE_CFLAGS)
AC_SUBST(GUILE_LIBS)
AC_MSG_RESULT(yes)

# Check for g-wrap

PKG_CHECK_MODULES(G_WRAP, g-wrap-2.0-guile >= 1.9.1)
AC_SUBST(G_WRAP_CFLAGS)
AC_SUBST(G_WRAP_LIBS)
AC_SUBST(G_WRAP_MODULE_DIR, `${PKG_CONFIG} --variable=module_directory g-wrap`)
AC_SUBST(G_WRAP_LIB_DIR, `echo $G_WRAP_MODULE_DIR | sed -e 's|share/guile|lib|'`)

# Per-package checks follow
EOF

    # package checks
    pkgs_ordered="$packages"
    echo "+ sorting package dependencies..."
    for pkg in $packages; do
	echo "# $pkg" >> configure.ac
	cat $pkg/package.ac >> configure.ac
        ensure_dependencies $pkg
    done
    echo "  $pkgs_ordered"
    
    # postlude
    (
	echo
	echo "AC_CONFIG_FILES(dev-environ, [chmod +x ./dev-environ])"
	echo "AC_CONFIG_FILES("
	echo "Makefile"
	find $packages -name Makefile.am | egrep -v '{arch}|\+\+|,,' | sed -e 's/\.am$//'
	for pkg in $packages; do
	  if [ -f $pkg/files.ac ]; then
	    while read file; do
	      echo "$pkg/$file"
	    done < $pkg/files.ac
	  fi
	done
	echo ")"
	echo "AC_OUTPUT" 
    ) >> configure.ac

    cat > Makefile.am <<EOF
# this file is generated by autogen-pkg.sh

SUBDIRS = $pkgs_ordered

EXTRA_DIST = dev-environ h2def.py \\
             autogen.sh autogen-pkg.sh autogen-support.sh

EOF
}
