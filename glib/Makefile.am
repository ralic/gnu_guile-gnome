include $(top_srcdir)/common.mk

SUBDIRS = . gnome test-suite doc examples bin

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = $(pcifiles)

# tried to get autoconf to do this, but failed.
guilesite:=$(prefix)/share/guile/site

gnome-@API_VERSION@.scm: gnome.scm.in Makefile
	if test -f $@; then chmod +w $@; fi
	sed -e "s|@API_VERSION\@|@API_VERSION@|g" \
	    -e "s|@running-uninstalled\@|#t|g" \
	    -e "s|@guilegnomedir\@|$(guilegnomedir)|g" \
	    -e "s|@guilegnomelibdir\@|$(guilegnomelibdir)|g" \
	    -e "s|@libdir\@|$(libdir)|g" \
	    $< > $@
	chmod -w $@

all-local: $(pcifiles) $(pcufiles) gnome-@API_VERSION@.scm

install-data-local: Makefile
	$(mkinstalldirs) $(DESTDIR)$(guilesite)
	sed -e "s|@API_VERSION\@|@API_VERSION@|g" \
	    -e "s|@running-uninstalled\@|#f|g" \
	    -e "s|@guilegnomedir\@|$(guilegnomedir)|g" \
	    -e "s|@guilegnomelibdir\@|$(guilegnomelibdir)|g" \
	    -e "s|@libdir\@|$(libdir)|g" \
	    $(srcdir)/gnome.scm.in > $(DESTDIR)$(guilesite)/gnome-@API_VERSION@.scm
	chmod 644 $(DESTDIR)$(guilesite)/gnome-@API_VERSION@.scm

uninstall-local:
	rm -f $(DESTDIR)$(moduledir)/config.scm
	rm -f $(DESTDIR)$(guilesite)/gnome-@API_VERSION@.scm

EXTRA_DIST = guile-gnome-glib.pc.in guile-gnome-glib-uninstalled.pc.in \
	AUTHORS TODO WARTS REFCOUNTING THREADING NEWS.guile-gobject \
	README gnome.scm.in ChangeLog.pre-2.16

CLEANFILES = $(pcifiles) $(pcufiles) $(bin_SCRIPTS) gnome-@API_VERSION@.scm
