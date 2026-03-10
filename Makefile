PACKAGE  := pve-compose
VERSION  := 1.1.0
PREFIX   := /usr
DESTDIR  :=
LIBDIR   := $(DESTDIR)$(PREFIX)/lib/$(PACKAGE)
BINDIR   := $(DESTDIR)$(PREFIX)/bin

COMPDIR  := $(DESTDIR)/usr/share/bash-completion/completions

SHELL_FILES := bin/pve-compose \
	$(wildcard lib/*.sh) \
	$(wildcard commands/*.sh) \
	$(wildcard commands/template/*.sh) \
	$(wildcard scripts/*.sh)

.PHONY: all install uninstall lint test deb clean

all:
	@echo "Usage: make [install|uninstall|lint|test|deb|clean]"

install:
	install -d $(BINDIR)
	install -d $(LIBDIR)/lib
	install -d $(LIBDIR)/commands/template
	install -d $(LIBDIR)/scripts
	install -m 0755 bin/pve-compose $(BINDIR)/pve-compose
	@for f in lib/*.sh; do \
		install -m 0644 "$$f" $(LIBDIR)/lib/; \
	done
	@for f in commands/*.sh; do \
		install -m 0644 "$$f" $(LIBDIR)/commands/; \
	done
	@if ls commands/template/*.sh >/dev/null 2>&1; then \
		for f in commands/template/*.sh; do \
			install -m 0644 "$$f" $(LIBDIR)/commands/template/; \
		done; \
	fi
	@for f in scripts/*.sh; do \
		install -m 0644 "$$f" $(LIBDIR)/scripts/; \
	done
	install -d $(COMPDIR)
	install -m 0644 completions/pve-compose.bash $(COMPDIR)/pve-compose

uninstall:
	rm -f $(BINDIR)/pve-compose
	rm -rf $(LIBDIR)
	rm -f $(COMPDIR)/pve-compose

lint:
	shellcheck -s sh -e SC1091 bin/pve-compose lib/*.sh commands/*.sh scripts/*.sh
	@if ls commands/template/*.sh >/dev/null 2>&1; then \
		shellcheck -s sh -e SC1091 commands/template/*.sh; \
	fi
	@echo "shellcheck: all clear"

test:
	bats tests/

deb:
	dpkg-buildpackage -us -uc -b

clean:
	rm -rf debian/.debhelper debian/$(PACKAGE) debian/files debian/debhelper-build-stamp
	rm -f ../$(PACKAGE)_*.deb ../$(PACKAGE)_*.changes ../$(PACKAGE)_*.buildinfo
