USR ?=		/usr/local
VAR ?=		/var

USER =		kyle
GROUP =		wheel

USR_BIN =	$(USR)/bin
PERL_LIBDATA =	$(USR)/libdata/perl5/site_perl
HTDOCS =	$(VAR)/www/htdocs

DEV_BIN =	/home/kyle/src/pricesloth
BINS =		ps_html ps_fcgi price_scraper product_scraper
# WARNING stupid idiom used below if adding > 1 item to LIBS!!
LIBS =		PriceSloth.pm
HTML =		tt logo pricesloth.css pricesloth.jpg

install:
	cp $(BINS) $(USR_BIN)/
	cp $(LIBS) $(PERL_LIBDATA)/
	mkdir -p $(VAR)/db/pricesloth
	chown $(USER):$(GROUP) $(VAR)/db/pricesloth

	sed -e "s@$(DEV_BIN)@$(USR_BIN)@" < openbsd_rc.d_ps_fcgi \
		> /etc/rc.d/ps_fcgi
	chmod 555 /etc/rc.d/ps_fcgi
	cp pricesloth.cfg /etc/

	mkdir -p $(HTDOCS)/pricesloth
	cp -R $(HTML) $(HTDOCS)/pricesloth/
	chown -R $(USER):$(GROUP) $(HTDOCS)/pricesloth

uninstall:
	# rm /etc/rc.d/ps_fcgi
	rm $(PERL_LIBDATA)/$(LIBS)
	# rm $(USR_BIN)/$(BINS)
