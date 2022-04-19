package Adup::Ural::PersonsDeduplicator;
use Mojo::Base -base;

use Carp;
use Mojo::mysql;
#use Data::Dumper;

use Exporter qw(import);
our @EXPORT_OK = qw(deduplicate_persons);

# deduplication procedure
# Adup::Ural::PersonsDeduplicator::deduplicate_persons($db);
# dies on errors.
sub deduplicate_persons {
  my $db = shift;
  die 'No database!' unless $db;

  my $e = eval {
    $db->query("TRUNCATE _fio_dedup");
    $db->query("TRUNCATE _fio_otd_dedup");
  };
  die "Database temporary tables cleanup error\n" unless defined $e;

  $e = eval {
    $db->query("INSERT INTO _fio_dedup (fio) \
SELECT fio FROM persons GROUP BY fio HAVING COUNT(*) > 1");
  };
  die "Database calculation fio duplicates error\n" unless defined $e;

  $e = eval {
    $db->query("INSERT INTO _fio_otd_dedup (fio, otdel) \
SELECT fio, otdel FROM persons GROUP BY fio, otdel HAVING COUNT(*) > 1");
  };
  die "Database calculation fio,otdel duplicates error\n" unless defined $e;

  $e = eval {
    $db->query("UPDATE persons SET dup = 1 \
WHERE fio IN (SELECT fio FROM _fio_dedup)");
  };
  die "Database update duplicates (1) in table persons error\n" unless defined $e;

  # ignore duplicates in the same otdel with sovm
  $e = eval {
    $db->query("UPDATE persons SET dup = 2 \
WHERE (fio, otdel) IN (SELECT fio, otdel FROM _fio_otd_dedup) AND sovm = 1");
  };
  die "Database update duplicates (2, sovm) in table persons error\n" unless defined $e;

  $e = eval {
    $db->query("TRUNCATE _fio_otd_dedup");
  };
  die "Database temporary tables cleanup error (2)\n" unless defined $e;

  # and without sovm
  $e = eval {
    $db->query("INSERT INTO _fio_otd_dedup (fio, otdel) \
SELECT fio, otdel FROM persons WHERE sovm = 0 GROUP BY fio, otdel HAVING COUNT(*) > 1");
  };
  die "Database calculation fio,otdel duplicates error\n" unless defined $e;

  $e = eval {
    $db->query("UPDATE persons SET dup = 2 \
WHERE (fio, otdel) IN (SELECT fio, otdel FROM _fio_otd_dedup)");
  };
  die "Database update duplicates (2) in table persons error\n" unless defined $e;

  1;
}

1;
