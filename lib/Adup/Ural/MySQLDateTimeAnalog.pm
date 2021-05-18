package Adup::Ural::MySQLDateTimeAnalog;
use Mojo::Base -base;

use POSIX qw(strftime);
use Exporter qw(import);
our @EXPORT = qw(mysql_datetime_now);

# '2021-05-01 12:30:01' = Adup::Ural::MySQLDateTimeAnalog::mysql_datetime_now();
sub mysql_datetime_now {
  return strftime '%Y-%m-%d %H:%M:%S', localtime;
}


1;
