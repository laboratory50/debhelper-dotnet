# ============================================================================
# Makefile для debhelper-dotnet
# ============================================================================

INSTALL = install
DHLIBPATH = /usr/share/perl5/Debian/Debhelper

# ============================================================================
# Генерация man-страницы
# ============================================================================
debhelper/dh_installnuget.1: debhelper/dh_installnuget
	pod2man --utf8 --section=1 --center="Debhelper Tools" --release="debhelper-dotnet" $< $@

# ============================================================================
# Цель по умолчанию
# ============================================================================
all: debhelper/dh_installnuget.1

# ============================================================================
# Установка файлов
# ============================================================================
install:
	# ========================================================================
	# Создание директорий для debhelper файлов
	# ========================================================================
	$(INSTALL) -d $(DESTDIR)/usr/bin
	$(INSTALL) -d $(DESTDIR)/$(DHLIBPATH)/Buildsystem
	$(INSTALL) -d $(DESTDIR)/$(DHLIBPATH)/Sequence
	$(INSTALL) -d $(DESTDIR)/usr/share/man/man1
	
	# ========================================================================
	# Установка Perl-модулей debhelper
	# ========================================================================
	$(INSTALL) -D debhelper/sequence.pm $(DESTDIR)/$(DHLIBPATH)/Sequence/dotnet.pm
	$(INSTALL) -D debhelper/arcade.pm $(DESTDIR)/$(DHLIBPATH)/Buildsystem/
	$(INSTALL) -D debhelper/dotnet.pm $(DESTDIR)/$(DHLIBPATH)/Buildsystem/
	
	# ========================================================================
	# Установка утилит командной строки
	# ========================================================================
	$(INSTALL) -D debhelper/dh_installnuget $(DESTDIR)/usr/bin/
	$(INSTALL) -D dh_make_dotnet $(DESTDIR)/usr/bin/
	
	# ========================================================================
	# Установка man-страниц
	# ========================================================================
	$(INSTALL) -D debhelper/dh_installnuget.1 $(DESTDIR)/usr/share/man/man1/
	
	# ========================================================================
	# Установка nh_patchproj (КОПИРУЕМ ВСЁ из publish/)
	# ========================================================================
	@if [ -d "tools/nh_patchproj" ]; then \
		echo "📦 Installing nh_patchproj..."; \
		PUBLISH_DIR="tools/nh_patchproj/bin/Release/net8.0/publish"; \
		if [ -d "$$PUBLISH_DIR" ] && [ -f "$$PUBLISH_DIR/nh_patchproj.runtimeconfig.json" ]; then \
			# Копируем ВСЕ файлы из publish/ в /usr/share/dotnet/nh_patchproj/ \
			$(INSTALL) -d $(DESTDIR)/usr/share/dotnet/nh_patchproj; \
			cp -a $$PUBLISH_DIR/* $(DESTDIR)/usr/share/dotnet/nh_patchproj/; \
			# Создаём обёртку-скрипт \
			$(INSTALL) -d $(DESTDIR)/usr/bin; \
			echo '#!/bin/bash' > $(DESTDIR)/usr/bin/nh_patchproj; \
			echo 'exec dotnet /usr/share/dotnet/nh_patchproj/nh_patchproj.dll "$$@"' >> $(DESTDIR)/usr/bin/nh_patchproj; \
			chmod 755 $(DESTDIR)/usr/bin/nh_patchproj; \
			# Документация \
			$(INSTALL) -d $(DESTDIR)/usr/share/nh_patchproj/Resources; \
			if [ -f "$$PUBLISH_DIR/../Resources/readme.md" ]; then \
				$(INSTALL) -m 644 $$PUBLISH_DIR/../Resources/readme.md $(DESTDIR)/usr/share/nh_patchproj/Resources/; \
			fi; \
			echo "   ✓ nh_patchproj installed"; \
		else \
			echo "⚠️  nh_patchproj not published correctly, skipping"; \
			echo "   Expected: $$PUBLISH_DIR/nh_patchproj.runtimeconfig.json"; \
		fi; \
	else \
		echo "⚠️  tools/nh_patchproj not found, skipping installation"; \
	fi

# ============================================================================
# Очистка
# ============================================================================
clean:
	rm -f debhelper/dh_installnuget.1
	rm -rf tools/nh_patchproj/bin tools/nh_patchproj/obj 2>/dev/null || true

.PHONY: install clean all
