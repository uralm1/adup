package Adup::Ural::Changelog;
use Mojo::Base -base;

use Carp;
use Mojo::mysql;


# Adup::Ural::Changelog->new($db, $APP::VERSION);
# Adup::Ural::Changelog->new($db, $APP::VERSION, 10);
sub new {
  my ($class, $db, $version, $limit) = @_;
  croak "Database and version required" unless defined $db and defined $version;
  my $self = bless {
    version => $version,
    changelog => '',
  }, $class;
  return undef unless( $self->_load($db, $limit || 5) );
  return $self;
}

# internal
sub _load {
  my ($self, $db, $limit) = @_;
  if ($self->{version} =~ m/^\D*(\d+)\.(\d+)\D*$/) {
    my ($major, $minor) = ($1, $2);
   
    my $e = eval {
      my $rec = $db->query("SELECT CONCAT_WS('.', ver_major, ver_minor) AS ver, \
DATE_FORMAT(date, '%e.%m.%Y') AS date, changelog \
FROM changelog \
WHERE (ver_major = ? AND ver_minor <= ?) OR ver_major < ? \
ORDER BY ver_major DESC, ver_minor DESC LIMIT ?",
        $major, $minor, $major, $limit);
      while (my $next = $rec->hash) {
	my $d = $next->{date} ? ", $next->{date}" : '';
        $self->{changelog} .= "<p><b>Версия $next->{ver}$d</b></p><p>$next->{changelog}</p>";
      }
      $rec->finish;
    };
    unless (defined $e) {
      carp $@;
      return undef;
    }
    return 1;
  } else {
    carp "Invalid program version";
    return undef;
  }
}

#
# getters
#
sub get_changelog_html {
  return shift->{changelog};
}

sub get_version {
  return shift->{version};
}


1;
