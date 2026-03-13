INSTALL = install
DHLIBPATH = /usr/share/perl5/Debian/Debhelper

debhelper/dh_installnuget.1: debhelper/dh_installnuget
	pod2man --utf8 $< $@

all: debhelper/dh_installnuget.1

clean:
	rm debhelper/dh_installnuget.1

install:
	$(INSTALL) -d $(DESTDIR)/$(DHLIBPATH)/Buildsystem
	$(INSTALL) -D debhelper/sequence.pm $(DESTDIR)/$(DHLIBPATH)/Sequence/dotnet.pm
	$(INSTALL) -D debhelper/arcade.pm debhelper/dotnet.pm $(DESTDIR)/$(DHLIBPATH)/Buildsystem
	$(INSTALL) -D debhelper/dh_installnuget $(DESTDIR)/usr/bin/dh_installnuget
	$(INSTALL) -D debhelper/dh_installnuget.1 $(DESTDIR)/usr/share/man/man1/dh_installnuget.1


.PHONY: install clean all
