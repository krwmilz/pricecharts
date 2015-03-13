USR_LOCAL_BIN=/usr/local/bin
LIBDATA=/usr/local/libdata/perl5/site_perl

DEV_ETC=/home/kyle/src/pricechart
BINS=price_scraper product_scraper gen_index pc_fcgi

install:
	cp $(BINS) $(USR_LOCAL_BIN)/
	sed -e "s@$(DEV_ETC)@$(USR_LOCAL_BIN)@" < openbsd_rc.d_pc_fcgi \
		> /etc/rc.d/pc_fcgi
	chmod 555 /etc/rc.d/pc_fcgi
	cp PriceChart.pm $(LIBDATA)/

uninstall:
	rm /etc/rc.d/pc_fcgi
