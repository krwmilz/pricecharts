#!/bin/ksh

sql_cmd="sqlite3 /var/db/pricesloth/db"

printf "prices:       %i\n" $($sql_cmd "select count(*) from prices;")
printf "products:     %i\n" $($sql_cmd "select count(*) from products;")
printf "descriptions: %i\n" $($sql_cmd "select count(*) from descriptions;")
printf "retailers:    %i\n" $($sql_cmd "select count(*) from retailers;")
