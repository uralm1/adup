package Adup::Controller::Syncmergearchive;
use Mojo::Base 'Mojolicious::Controller';

use Carp;
use POSIX qw(ceil);
use Mojo::Util qw(xml_escape);
use Mojo::mysql;
use Adup::Ural::ChangeFactory;
use Adup::Ural::Change;
use Adup::Ural::ChangeOUCreate;
use Adup::Ural::ChangeOUModify;
use Adup::Ural::ChangeOUDelete;
use Adup::Ural::ChangeFlatGroupCreate;
use Adup::Ural::ChangeFlatGroupModify;
use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeUserCreate;
use Adup::Ural::ChangeAttr;
use Adup::Ural::ChangeError;
use Data::Dumper;

sub index {
  my $self = shift;
  return undef unless $self->authorize({admin=>1});

  my $search = $self->param('s');
  my @search_chtypes = grep {/^\d{1,2}$/} @{$self->every_param('t')};
  my $active_page = $self->param('p') || 1;
  return unless $self->exists_and_number($active_page);

  my $db = $self->mysql_adup->db;
  my $changes_alltotal;
  my $e = eval {
    my $r = $db->query("SELECT COUNT(*) FROM changes_archive");
    $changes_alltotal = $r->array->[0];
    $r->finish;
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  my @apnd;
  push @apnd, 'name LIKE '.$db->quote("%$search%") if (defined($search) && $search ne '');
  my $apnd2 = join ' OR ', map {'type='.$db->quote($_)} @search_chtypes;
  push @apnd, "($apnd2)" if $apnd2 ne '';
  my $apnd = join ' AND ', @apnd;
  $apnd = (defined($apnd) && $apnd ne '') ? 'WHERE '.$apnd : '';
  #say $apnd;

  my $changes_found;
  $e = eval {
    my $r = $db->query("SELECT COUNT(*) FROM changes_archive $apnd");
    $changes_found = $r->array->[0];
    $r->finish;
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  my $changes_on_page = $self->config('changes_on_page');
  my $num_pages = ceil($changes_found / $changes_on_page);
  return $self->render(text => 'ошибка формирования списка') if ($active_page < 1 || ($num_pages > 0 && $active_page > $num_pages));

  my @changes_rec;
  my $r;
  $e = eval {
    $r = $db->query("SELECT id, name, c \
      FROM changes_archive $apnd \
      ORDER BY id DESC LIMIT ? OFFSET ?",
      $changes_on_page, ($active_page - 1)*$changes_on_page
    );
  };
  return $self->render(text => 'Ошибка операции с БД') unless defined $e;

  while (my $n = $r->hash) {
    my $c = Adup::Ural::ChangeFactory->fromdb(id=>$n->{id}, json=>$n->{c});
    push @changes_rec, $c;
  }
  $r->finish;

  $self->render(template => 'sync/mergearchive',
    search => $search,
    search_chtypes => \@search_chtypes,
    changes_alltotal => $changes_alltotal,
    changes_found => $changes_found,
    changes_num_pages => $num_pages,
    changes_active_page => $active_page,
    changes_on_page => $changes_on_page,
    changes_rec => \@changes_rec,
  );
}


1;
