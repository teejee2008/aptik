SHELL=/bin/bash
CFLAGS=--std=c99

prefix=/usr
bindir=$(prefix)/bin
sharedir=$(prefix)/share
localedir=$(sharedir)/locale
launcherdir=$(sharedir)/applications
polkitdir=$(sharedir)/polkit-1/actions
mandir=$(sharedir)/man
man1dir=$(mandir)/man1

app_name=aptik
app_fullname=Aptik

all: aptik-console

aptik-console:

	valac -X -D'GETTEXT_PACKAGE="${app_name}"' --Xcc="-lm" --thread \
		*.vala Console/*.vala Utility/Console/*.vala \
		-o ${app_name} \
		--pkg glib-2.0 \
		--pkg gio-unix-2.0 \
		--pkg posix \
		--pkg gee-0.8 #--pkg json-glib-1.0

clean:
	rm -rfv ../release/{source,i386,amd64,armel,armhf}
	rm -rfv ../release/*.{run,deb}
	rm -rfv *.c *.o *.mo
	rm -fv ${app_name} ${app_name}-gtk

install:

	#dirs
	mkdir -p "$(DESTDIR)$(bindir)"
	mkdir -p "$(DESTDIR)$(sharedir)"
	mkdir -p "$(DESTDIR)$(mandir)"
	mkdir -p "$(DESTDIR)$(man1dir)"
	mkdir -p "$(DESTDIR)$(launcherdir)"
	mkdir -p "$(DESTDIR)$(polkitdir)"

	#binary
	install -m 0755 aptik "$(DESTDIR)$(bindir)"

	#polkit policy file
	install -m 0644 ./share/polkit-1/actions/in.teejeetech.pkexec.aptik.policy "$(DESTDIR)$(polkitdir)"

uninstall:

	#binary
	rm -f "$(DESTDIR)$(bindir)/aptik"

	#polkit policy file
	rm -f ./share/polkit-1/actions/in.teejeetech.pkexec.aptik.policy "$(DESTDIR)$(polkitdir)"
