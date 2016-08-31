PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
MANDIR ?= $(PREFIX)/share/man

BASHCOMP_PATH ?= $(DESTDIR)$(PREFIX)/share/bash-completion/completions

all:
	@echo "Password store is a shell script, so there is nothing to do. Try \"make install\" instead."

install-common:
	@install -v -d "$(DESTDIR)$(MANDIR)/man1" && install -m 0644 -v man/pass.1 "$(DESTDIR)$(MANDIR)/man1/pass.1"
	@[ "$(FORCE_BASHCOMP)" = "1" ] && install -v -d "$(BASHCOMP_PATH)" && install -m 0644 -v src/completion/pass.bash-completion "$(BASHCOMP_PATH)/pass" || true


install: install-common
	@install -v -d "$(DESTDIR)$(BINDIR)/"
	@install --v -d -m 0755 src/password-store.sh "$(DESTDIR)$(BINDIR)/pass"

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(BINDIR)/pass" \
		"$(DESTDIR)$(LIBDIR)/password-store/" \
		"$(DESTDIR)$(MANDIR)/man1/pass.1" \
		"$(BASHCOMP_PATH)/pass" \
	@rmdir "$(DESTDIR)$(LIBDIR)/password-store/" 2>/dev/null || true

TESTS = $(sort $(wildcard tests/t[0-9][0-9][0-9][0-9]-*.sh))

test: $(TESTS)

$(TESTS):
	@$@ $(PASS_TEST_OPTS)

clean:
	$(RM) -rf tests/test-results/ tests/trash\ directory.*/ tests/gnupg/random_seed

.PHONY: install uninstall install-common test clean $(TESTS)
