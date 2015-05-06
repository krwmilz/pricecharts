#!/bin/sh

sql_cmd="sqlite3 /var/db/pricesloth/db"

echo -n "prices: " 
$sql_cmd "select count(*) from prices;"
echo -n "products: " 
$sql_cmd "select count(*) from products;"
echo -n "descriptions: " 
$sql_cmd "select count(*) from descriptions;"
echo -n "retailers: " 
$sql_cmd "select count(*) from retailers;"
