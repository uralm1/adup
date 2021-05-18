package Adup::Ural::Change;
use Mojo::Base -base;

use Carp;
use Adup::Ural::MySQLDateTimeAnalog;
use Scalar::Util qw(blessed);
use Mojo::JSON qw(to_json);
use Mojo::Util qw(xml_escape);
use Net::LDAP::Util qw(unescape_dn_value);


# Adup::Ural::Change->new($name, $dn, 'author');
sub new {
  my ($class, $name, $dn, $author) = @_;
  croak 'Name required' unless defined $name;
  $author ||= 'н/д';

  my $self = $class->SUPER::new;

  $self->{id} = undef;
  $self->{name} = $name;
  $self->{dn} = $dn;
  $self->{author} = $author;
  $self->{date} = mysql_datetime_now;
  $self->{approved} = undef;
  $self->{approval_author} = 'н/д';
  $self->{approval_date} = undef;
  $self->{merged} = undef;
  $self->{merge_author} = 'н/д';
  $self->{merge_date} = undef;

  $self->{type} = blessed $self;
  return $self;
}

#
# getters
#
sub type {
  return shift->{type};
}

sub type_human {
  return 'Абстрактное';
}

sub type_robotic {
  return 0;
}

sub name {
  return shift->{name};
}

sub dn {
  return shift->{dn};
}

sub author {
  my $self = shift;
  return { author => $self->{author},
    date => $self->{date}
  };
}

sub info_human {
  my $self = shift;
  my $r = '<b>DN:</b> '.xml_escape(unescape_dn_value($self->{dn})).'<br>';
  $r .= '<span class="info-error">Изменение этого типа не предназначено к использованию</span>';
  return $r;
}

# {author,date} or undef = $obj->approved;
sub approved {
  my $self = shift;
  return { author => $self->{approval_author},
    date => $self->{approval_date}
  } if (defined $self->{approved});
  undef;
}

# {author,date} or undef = $obj->merged;
sub merged {
  my $self = shift;
  return { author => $self->{merge_author},
    date => $self->{merge_date}
  } if (defined $self->{merged});
  undef;
}


# $obj->approve(author => 'author');
sub approve {
  my ($self, %args) = @_;
  $args{author} ||= 'н/д';
  $self->{approved} = 1;
  $self->{approval_author} = $args{author};
  $self->{approval_date} = mysql_datetime_now;
}

# $obj->unapprove();
sub unapprove {
  my $self = shift;
  $self->{approved} = undef;
  $self->{approval_author} = 'н/д';
  $self->{approval_date} = undef;
}


sub TO_JSON {
  return { %{shift()} };
}

# $id or undef = $obj->todb(db => $mysql->db);
# $id or undef = $obj->todb(db => $mysql->db, metadata => $integer_or_undef);
sub todb {
  my ($self, %args) = @_;
  croak 'Db required' unless defined $args{db};
  my $id;
  if (defined $self->{id}) {
    $id = $self->{id};
    my $e = eval {
      if (exists $args{metadata}) {
        $args{db}->query("UPDATE changes SET c = ?, metadata = ? WHERE id = ?", {json=>$self}, $args{metadata}, $id);
      } else {
        $args{db}->query("UPDATE changes SET c = ? WHERE id = ?", {json=>$self}, $id);
      }
    };
    unless (defined $e) {
      carp 'Error updating change object to DB';
      return undef;
    }
    $id;
  } else {
    my $e = eval {
      if (exists $args{metadata}) {
        $id = $args{db}->query("INSERT INTO changes (name, type, c, metadata) VALUES (?, ?, ?, ?)",
	  $self->{name}, $self->type_robotic, {json=>$self}, $args{metadata})->last_insert_id;
      } else {
        $id = $args{db}->query("INSERT INTO changes (name, type, c) VALUES (?, ?, ?)",
	  $self->{name}, $self->type_robotic, {json=>$self})->last_insert_id;
      }
    };
    unless (defined $e) {
      carp 'Error inserting change object to DB';
      return undef;
    }
    $self->{id} = $id;
  }
}


# 1 or undef = $obj->deletedb(db => $mysql->db);
sub deletedb {
  my ($self, %args) = @_;
  croak 'Db object required' unless defined $args{db};
  if (defined $self->{id}) {
    my $e = eval {
      $args{db}->query("DELETE FROM changes WHERE id = ?", $self->{id});
    };
    unless (defined $e) {
      carp 'Error deleting change object from database';
      return undef;
    }
  } else {
    carp 'Cant delete change object without id';
    return undef;
  }
  1;
}


# $id or undef = $obj->toarchive(db => $mysql->db);
sub toarchive {
  my ($self, %args) = @_;
  croak 'Db required' unless defined $args{db};
  unless ($self->{merged}) {
    carp 'Only merged changes are permitted to put in archive.';
    return undef;
  }

  my $id;
  my $e = eval {
    $id = $args{db}->query("INSERT INTO changes_archive (name, type, c) VALUES (?, ?, ?)",
      $self->{name}, $self->type_robotic, {json=>$self})->last_insert_id;
  };
  unless (defined $e) {
    carp 'Error putting change object to archive';
    return undef;
  }
  return $id;
}


# 1 or undef = $obj->merge(
#     author => 'author',
#     db => $mysql->db
#   );
sub merge {
  my ($self, %args) = @_;
  croak 'Db object required' unless defined $args{db};
  $args{author} ||= 'н/д';
  $self->_set_merged($args{author});

  # just delete from db
  my $r = $self->deletedb(db => $args{db});
  # save to archive
  $self->toarchive(db => $args{db}) if $r;
  return $r;
}

# internal helper
sub _set_merged {
  my ($self, $author) = @_;
  $self->{merged} = 1;
  $self->{merge_author} = $author;
  $self->{merge_date} = mysql_datetime_now;
}


1;
