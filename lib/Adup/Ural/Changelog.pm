package Adup::Ural::Changelog;
use Mojo::Base -base;

use Carp;
use Mojo::File qw(path);
use Encode;

# Adup::Ural::Changelog->new($APP::VERSION);
# Adup::Ural::Changelog->new($APP::VERSION, 10);
sub new {
  my ($class, $version, $limit) = @_;
  croak "Version required" unless defined $version;
  my $self = bless {
    version => $version,
    changelog => '',
  }, $class;
  return undef unless( $self->_load($limit || 5) );
  return $self;
}

# internal
sub _load {
  my ($self, $limit) = @_;

  my $fh = eval { path('CHANGELOG.md')->open('<') };
  unless ($fh) {
    carp "Can't open CHANGELOG.md file";
    return undef;
  }
  my $vcnt = 0;
  my $mode = 0;
  while (<$fh>) {
    if ($mode == 0) {
      next if /^# changelog/i;
      next if /^all notable changes to this project/i;
      next if /^$/;
      $mode = 1;
    }
    $vcnt++ if /## \[.*\]/;
    last if $vcnt > $limit;
    $self->{changelog} .= decode_utf8($_) if $mode > 0;
  }
  $fh->close;
  return 1;
}

#
# getters
#
sub get_changelog {
  return shift->{changelog};
}

sub get_version {
  return shift->{version};
}


1;
