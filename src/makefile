SHELL=/bin/bash
CFLAGS=--std=c99

prefix=/usr
bindir=$(prefix)/bin
sharedir=$(prefix)/share
localedir=$(sharedir)/locale
launcherdir=$(sharedir)/applications
mandir=$(sharedir)/man
man1dir=$(mandir)/man1

app_name=aptik
app_fullname=Aptik

all: aptik-console

aptik-console:

	valac -X -D'GETTEXT_PACKAGE="${app_name}"' --Xcc="-lm" --thread \
		Console/*.vala Utility/Console/*.vala \
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

	#binary
	install -m 0755 aptik "$(DESTDIR)$(bindir)"

uninstall:

	#binary
	rm -f "$(DESTDIR)$(bindir)/aptik"
