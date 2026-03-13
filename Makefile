INSTALL = install
DHLIBPATH = /usr/share/perl5/Debian/Debhelper

debhelper/dh_installnuget.1: debhelper/dh_installnuget
	pod2man --utf8 $< $@

all: debhelper/dh_installnuget.1

clean:
	rm -f debhelper/dh_installnuget.1

install:
	$(INSTALL) -d $(DESTDIR)/usr/bin
	$(INSTALL) -d $(DESTDIR)/$(DHLIBPATH)/Buildsystem
	$(INSTALL) -D debhelper/sequence.pm $(DESTDIR)/$(DHLIBPATH)/Sequence/dotnet.pm
	$(INSTALL) -D debhelper/arcade.pm debhelper/dotnet.pm $(DESTDIR)/$(DHLIBPATH)/Buildsystem
	$(INSTALL) debhelper/dh_installnuget dh_make_dotnet $(DESTDIR)/usr/bin
	$(INSTALL) -D debhelper/dh_installnuget.1 $(DESTDIR)/usr/share/man/man1/dh_installnuget.1


.PHONY: install clean all
