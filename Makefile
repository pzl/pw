PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
MANDIR ?= $(PREFIX)/share/man

BASHCOMP_PATH ?= $(DESTDIR)$(PREFIX)/share/bash-completion/completions

all:
	@echo "pw is a shell script, so there is nothing to do. Try \"make install\" instead."

install-common:
	@install -v -d "$(DESTDIR)$(MANDIR)/man1" && install -m 0644 -v man/pw.1 "$(DESTDIR)$(MANDIR)/man1/pw.1"
	@[ "$(FORCE_BASHCOMP)" = "1" ] && install -v -d "$(BASHCOMP_PATH)" && install -m 0644 -v src/completion/pw.bash-completion "$(BASHCOMP_PATH)/pw" || true


install: install-common
	@install -v -d "$(DESTDIR)$(BINDIR)/"
	@install --v -d -m 0755 src/pw.sh "$(DESTDIR)$(BINDIR)/pw"

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(BINDIR)/pw" \
		"$(DESTDIR)$(LIBDIR)/pw/" \
		"$(DESTDIR)$(MANDIR)/man1/pw.1" \
		"$(BASHCOMP_PATH)/pw" \
	@rmdir "$(DESTDIR)$(LIBDIR)/pw/" 2>/dev/null || true

TESTS = $(sort $(wildcard tests/t[0-9][0-9][0-9][0-9]-*.sh))

test: $(TESTS)

$(TESTS):
	@$@ $(PASS_TEST_OPTS)

clean:
	$(RM) -rf tests/test-results/ tests/trash\ directory.*/ tests/gnupg/random_seed

.PHONY: install uninstall install-common test clean $(TESTS)
