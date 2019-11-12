#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn);
use Encode qw(decode);
use Data::Dumper;
use Mojo::File 'path';

use lib "../lib";
use Adup::Ural::ChangeFactory;
use Adup::Ural::Change;
use Adup::Ural::ChangeUserCreate;
use Adup::Ural::ChangeUserDelete;
use Adup::Ural::ChangeUserFlatGroup;
use Adup::Ural::ChangeAttr;
use Adup::Ural::ChangeOUCreate;
use Adup::Ural::ChangeOUDelete;
use Adup::Ural::ChangeOUModify;
use Adup::Ural::ChangeFlatGroupCreate;
use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeFlatGroupModify;
use Adup::Ural::ChangeError;
use Adup::Ural::Dblog;

binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;
my $remote_user = 'test';

# app object surrogate we need
package Test::App;
sub config { return {
  ldap_base=>$cfg->{ldap_base},
  personnel_ldap_base=>"OU=1,$cfg->{ldap_base}",
  flatgroups_ldap_base=>"OU=2,$cfg->{ldap_base}",
  dismissed_ou_dn=>"OU=5DISMISSED,$cfg->{ldap_base}",
} }
# job object surrogate we need
package Test::Job;
sub app { return bless {},'Test::App'; }
sub note { my ($s,%d)=@_; say $d{progress}.'% done'; }
# return back
package main;
my $job = bless {},'Test::Job';


  my $mysql_adup = Mojo::mysql->new($cfg->{adup_db_conn});
  my $db_adup = $mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($mysql_adup->db, login=>$remote_user, state=>90);

  my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    $log->l(state=>91, info=>"Произошла ошибка подключения к глобальному каталогу");
    die "LDAP creation error $@";
  }

  my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});
  if ($mesg->code) {
    $log->l(state=>91, info=>"Произошла ошибка авторизации при подключении глобальному каталогу");
    die "LDAP bind error ".$mesg->error;
  }

  _setstate($db_adup, 1); #$job->id

  # merging changes for types ... in sequence
  # see type_robotic field in change objects
  my @merge_sequence = (
    { type => 0, desc => 'абстракт', rep_no => 0},
    { type => 99, desc => 'ошибки', rep_no => 0},
    { type => 20, desc => 'создание подразделений', rep_no => 1},
    { type => 22, desc => 'изменение подразделений', rep_no => 1},
    { type => 10, desc => 'создание групп почтового справочника', rep_no => 1},
    { type => 12, desc => 'изменение групп почтового справочника', rep_no => 1},
    { type => 2, desc => 'создание пользователей', rep_no => 1},
    { type => 1, desc => 'аттрибутов', rep_no => 1},
    { type => 13, desc => 'удаление пользователей из групп почтового справочника', rep_no => 1},
    { type => 5, desc => 'перемещение пользователей', rep_no => 1},
    { type => 8, desc => 'блокирование пользователей', rep_no => 1},
    { type => 11, desc => 'удаление групп почтового справочника', rep_no => 1},
    { type => 21, desc => 'удаление подразделений', rep_no => 1},
  );

  my $log_buf;

  #
  # begin of merge sequence main loop
  #
  for my $seq_el (@merge_sequence) {
    my $mt = $seq_el->{type};
    say "Merging changes type $mt";
    my $res;
    my $m_order_tmpl = '';
    # use metadata ordering when changing departments
    if ($mt == 20 || $mt == 22) {
      $m_order_tmpl = 'metadata ASC,'; #create/modify depts
    } elsif ($mt == 21) {
      $m_order_tmpl = 'metadata DESC,'; #delete depts
    }

    my $e = eval {
      $res = $db_adup->query("SELECT id, name, c \
        FROM changes WHERE type = ? \
        ORDER BY $m_order_tmpl id ASC", $mt);
    };
    unless (defined $e) {
      _setstate($db_adup, 0);
      die 'Merge - database fatal error';
    }
    my $changes_count = 0;
    my $changes_approved_count = 0;
    my $changes_processed_count = 0;
    my $changes_total = $res->rows;
    my $mod = int($changes_total / 20) || 1;
    while (my $next = $res->hash) {
      my $c = Adup::Ural::ChangeFactory->fromdb(id=>$next->{id}, json=>$next->{c});
      if ($c->approved) {
	if ($c->merge(author=>$remote_user, db=>$db_adup, ldap=>$ldap, config=>$job->app->config, log=>$log)) {
	  $changes_processed_count++;
	} else {
	  $log->l(state=>91, info=>"Изменение-$seq_el->{desc} не применено. Возникла ошибка при применении изменения-$seq_el->{desc}: $next->{name}.");
	}
	$changes_approved_count++;
      }

      # update progress
      $changes_count++;
      if ($changes_count % $mod == 0) {
	my $percent = ceil($changes_count / $changes_total * 100);
	say "$percent% done";
      }
    }
    $res->finish;

    #say "Approved: $changes_approved_count, Processed: $changes_processed_count, Total: $changes_total";
    if ($changes_approved_count > 0) {
      $log_buf .= ' ' if $log_buf;
      $log_buf .= "Изменение-$seq_el->{desc}, применено: $changes_processed_count, утверждено: $changes_approved_count, всего: $changes_total.";
    } elsif ($seq_el->{rep_no}) {
      $log_buf .= ' ' if $log_buf;
      $log_buf .= "Изменение-$seq_el->{desc}, отсутствуют утверждённые.";
    }
  }
  #
  # end of merge sequence main loop
  #

  $log->l(info => 'Отчёт о применении изменений. '.$log_buf) if $log_buf;

_setstate($db_adup, 0);
$ldap->unbind;
  
exit 0;


# internal
sub _setstate {
  my ($db, $s) = @_;
  my $e = eval {
    $db->query("UPDATE state SET value = ? WHERE `key`='merge_id'", $s);
  };
  unless (defined $e) {
    carp "Set task state failed\n";
  }
}

