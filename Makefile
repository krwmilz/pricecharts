USR_LOCAL_BIN=/usr/local/bin
PERL_LIBDATA=/usr/local/libdata/perl5/site_perl
HTDOCS=/var/www/htdocs

DEV_BIN=/home/kyle/src/pricechart
BINS=price_scraper product_scraper gen_index pc_fcgi gen_svg
# WARNING stupid idiom used below if adding > 1 item to LIBS!!
LIBS=PriceChart.pm
HTML=tt logo pricechart.css

install:
	cp $(BINS) $(USR_LOCAL_BIN)/
	cp $(LIBS) $(PERL_LIBDATA)/

	sed -e "s@$(DEV_BIN)@$(USR_LOCAL_BIN)@" < openbsd_rc.d_pc_fcgi \
		> /etc/rc.d/pc_fcgi
	chmod 555 /etc/rc.d/pc_fcgi

	mkdir -p $(HTDOCS)/pricechart
	mkdir -p $(HTDOCS)/pricechart/svg
	cp -R $(HTML) $(HTDOCS)/pricechart/
	chown -R www:daemon $(HTDOCS)/pricechart

uninstall:
	# rm /etc/rc.d/pc_fcgi
	rm $(PERL_LIBDATA)/$(LIBS)
	# rm $(USR_LOCAL_BIN)/$(BINS)
