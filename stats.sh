#!/bin/ksh

if [ $# -ne 1 ]; then
	echo "usage: ${0} <db>"
	exit 1
fi

sql_cmd="sqlite3 ${1}"

printf "products:     %i\n" $($sql_cmd "select count(*) from products;")
printf "prices:       %i\n" $($sql_cmd "select count(*) from prices;")
printf "descriptions: %i\n" $($sql_cmd "select count(*) from descriptions;")
printf "retailers:    %i\n" $($sql_cmd "select count(*) from retailers;")
