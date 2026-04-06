INSTALL = install
DHLIBPATH = /usr/share/perl5/Debian/Debhelper
PUBLISH_DIR = tools/nh_patchproj/bin/Release/net8.0/publish

debhelper/dh_installnuget.1: debhelper/dh_installnuget
	pod2man --utf8 --section=1 --center="Debhelper Tools" --release="debhelper-dotnet" $< $@

all: debhelper/dh_installnuget.1

# ============================================================================
# Установка файлов
# ============================================================================
install:
	$(INSTALL) -d $(DESTDIR)/$(DHLIBPATH)/Sequence
	$(INSTALL) debhelper/sequence.pm $(DESTDIR)/$(DHLIBPATH)/Sequence/dotnet.pm
	$(INSTALL) -D -t $(DESTDIR)/$(DHLIBPATH)/Buildsystem/ debhelper/arcade.pm debhelper/dotnet.pm

	$(INSTALL) -D -t $(DESTDIR)/usr/bin dh_make_dotnet debhelper/dh_installnuget
	$(INSTALL) -D -t $(DESTDIR)/usr/share/man/man1 debhelper/dh_installnuget.1
	
	echo "📦 Installing nh_patchproj..."
	# Копируем ВСЕ файлы из publish/ в /usr/share/dotnet/nh_patchproj/
	$(INSTALL) -d $(DESTDIR)/usr/share/dotnet/nh_patchproj
	cp -a $(PUBLISH_DIR)/* $(DESTDIR)/usr/share/dotnet/nh_patchproj/
	# Создаём обёртку-скрипт
	$(INSTALL) -d $(DESTDIR)/usr/bin
	echo '#!/bin/bash' > $(DESTDIR)/usr/bin/nh_patchproj
	echo 'exec dotnet /usr/share/dotnet/nh_patchproj/nh_patchproj.dll "$$@"' >> $(DESTDIR)/usr/bin/nh_patchproj
	chmod 755 $(DESTDIR)/usr/bin/nh_patchproj
	# Документация
	$(INSTALL) -d $(DESTDIR)/usr/share/nh_patchproj/Resources
	$(INSTALL) -m 644 $(PUBLISH_DIR)/../Resources/readme.md $(DESTDIR)/usr/share/nh_patchproj/Resources

clean:
	rm -f debhelper/dh_installnuget.1
	rm -rf tools/nh_patchproj/bin tools/nh_patchproj/obj

.PHONY: install clean all
