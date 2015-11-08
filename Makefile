USR ?=		/usr/local
VAR ?=		/var

USER =		www
GROUP =		daemon

USR_BIN =	$(USR)/bin
PERL_LIBDATA =	$(USR)/libdata/perl5/site_perl
HTDOCS =	$(VAR)/www/htdocs

DEV_BIN =	/home/kyle/src/pricesloth
BINS =		ps_{html,fcgi,scrape}
# WARNING stupid idiom used below if adding > 1 item to LIBS!!
LIBS =		PriceSloth.pm
HTML =		tt logo etc/pricesloth.css etc/charts.css

install:
	cp $(BINS) $(USR_BIN)/
	cp $(LIBS) $(PERL_LIBDATA)/
	mkdir -p $(VAR)/db/pricesloth
	chown $(USER):$(GROUP) $(VAR)/db/pricesloth

	sed -e "s@$(DEV_BIN)@$(USR_BIN)@" < etc/openbsd_rc.d_ps_fcgi \
		> /etc/rc.d/ps_fcgi
	chmod 555 /etc/rc.d/ps_fcgi
	cp etc/pricesloth.cfg /etc/

	mkdir -p $(HTDOCS)/pricesloth
	cp -R $(HTML) $(HTDOCS)/pricesloth/
	chown -R $(USER):$(GROUP) $(HTDOCS)/pricesloth

uninstall:
	# rm /etc/rc.d/ps_fcgi
	rm $(PERL_LIBDATA)/$(LIBS)
	# rm $(USR_BIN)/$(BINS)
