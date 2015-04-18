USR ?=		/usr/local
VAR ?=		/var

USR_BIN =	$(USR)/bin
PERL_LIBDATA =	$(USR)/libdata/perl5/site_perl
HTDOCS =	$(VAR)/www/htdocs

DEV_BIN =	/home/kyle/src/pricechart
BINS =		pc_gen_html pc_fcgi price_scraper product_scraper
# WARNING stupid idiom used below if adding > 1 item to LIBS!!
LIBS =		PriceChart.pm
HTML =		tt logo pricechart.css

install:
	cp $(BINS) $(USR_BIN)/
	cp $(LIBS) $(PERL_LIBDATA)/

	sed -e "s@$(DEV_BIN)@$(USR_BIN)@" < openbsd_rc.d_pc_fcgi \
		> /etc/rc.d/pc_fcgi
	chmod 555 /etc/rc.d/pc_fcgi
	cp pricechart.cfg /etc/

	mkdir -p $(HTDOCS)/pricechart
	mkdir -p $(HTDOCS)/pricechart/svg
	cp -R $(HTML) $(HTDOCS)/pricechart/
	chown -R www:daemon $(HTDOCS)/pricechart

uninstall:
	# rm /etc/rc.d/pc_fcgi
	rm $(PERL_LIBDATA)/$(LIBS)
	# rm $(USR_BIN)/$(BINS)
