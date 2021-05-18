use Mojo::Base -strict;

use Test::More;

use Adup::Ural::MySQLDateTimeAnalog;

my $s = mysql_datetime_now();
diag "$s\n";
ok($s =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d$/, "Datetime format check");

done_testing();
