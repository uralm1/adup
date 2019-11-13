#!/usr/bin/perl

use strict;
use warnings;
use v5.12;
use utf8;
use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use Net::LDAP qw(LDAP_SUCCESS LDAP_INSUFFICIENT_ACCESS);
use Net::LDAP::Util qw(canonical_dn escape_filter_value escape_dn_value);
use Encode qw(decode);
use Data::Dumper;
use Mojo::File 'path';

use lib "../lib";
use Adup::Ural::Dblog;

use Adup::Ural::SyncCreateOUs;
use Adup::Ural::SyncCreateFlatGroups;
use Adup::Ural::SyncAttributesCreateMoveUsers;
use Adup::Ural::SyncDeleteUsers;
use Adup::Ural::SyncDeleteFlatGroups;
use Adup::Ural::SyncDeleteOUs;

binmode(STDOUT, ':utf8');

my $cfg = eval path('../test.conf')->slurp;
my $remote_user = 'test';

# app object surrogate we need
package Test::App;
sub config { return {
  ldap_base=>$cfg->{ldap_base},
  personnel_ldap_base=>"OU=1,$cfg->{ldap_base}",
  flatgroups_ldap_base=>"OU=2,$cfg->{ldap_base}",
  user_cleanup_skip_dn => [
    "OU=11CONTACTS,OU=1,$cfg->{ldap_base}",
    "OU=4SYSTEM,$cfg->{ldap_base}",
    "OU=5DISMISSED,$cfg->{ldap_base}",
    "OU=6TEMPORARY,$cfg->{ldap_base}",
    "OU=Admins,$cfg->{ldap_base}",
    "CN=Users,$cfg->{ldap_base}",
    "OU=SYSTEM,OU=UWC Users,$cfg->{ldap_base}",
  ],
  ou_cleanup_skip_dn => [
    "OU=11CONTACTS,OU=1,$cfg->{ldap_base}",
  ],
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

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>10);

  my $ldap = Net::LDAP->new($cfg->{ldap_servers}, port => 389, timeout => 10, version => 3);
  unless ($ldap) {
    $log->l(state=>11, info=>"Произошла ошибка подключения к глобальному каталогу");
    die "LDAP creation error $@";
  }

  my $mesg = $ldap->bind($cfg->{ldap_user}, password => $cfg->{ldap_pass});
  if ($mesg->code) {
    $log->l(state=>11, info=>"Произошла ошибка авторизации при подключении глобальному каталогу");
    die "LDAP bind error ".$mesg->error;
  }

  _setstate($db_adup, 1); #$job->id

  my $e = eval {
    $db_adup->query("DELETE FROM changes");
  };
  unless (defined $e) {
    _setstate($db_adup, 0);
    die 'Changes table cleanup error';
  }

  #
  # SyncCreateOUs subtask
  #
  my $c1 = 0;
  my $c2 = 0;
=for comment
  unless (defined ($c1 = Adup::Ural::SyncCreateOUs::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  ))) {
    _setstate($db_adup, 0);
    die 'SyncCreateOUs fatal error';
  }
=cut

  #
  # SyncCreateFlatGroups subtask
  #
=for comment
  unless (defined ($c2 = Adup::Ural::SyncCreateFlatGroups::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  ))) {
    _setstate($db_adup, 0);
    die 'SyncCreateFlatGroups fatal error';
  }
=cut

  if ($c1 > 0 || $c2 > 0) {
    $log->l(info=>"Проведена неполная предварительная синхронизация. Примените изменения создания подразделений и групп, затем перезапустите задание расчета изменений для полной синхронизации.");
    _setstate($db_adup, 0);
    $ldap->unbind;
  
    exit 0;
  }

  #
  # SyncAttributesCreateMoveUsers subtask
  #
#=for comment
  unless (defined Adup::Ural::SyncAttributesCreateMoveUsers::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  )) {
    _setstate($db_adup, 0);
    die 'SyncAttributesCreateMoveUsers fatal error';
  }
#=cut

  #
  # SyncDeleteFlatGroups subtask
  #
=for comment
  unless (defined Adup::Ural::SyncDeleteFlatGroups::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  )) {
    _setstate($db_adup, 0);
    die 'SyncDeleteFlatGroups fatal error';
  }
=cut

  #
  # SyncDeleteUsers subtask
  #
=for comment
  unless (defined Adup::Ural::SyncDeleteUsers::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  )) {
    _setstate($db_adup, 0);
    die 'SyncDeleteUsers fatal error';
  }
=cut

  #
  # SyncDeleteOUs subtask
  #
=for comment
  unless (defined Adup::Ural::SyncDeleteOUs::do_sync(
    db => $db_adup, 
    ldap => $ldap, 
    log => $log, 
    job => $job,
    user => $remote_user
  )) {
    _setstate($db_adup, 0);
    die 'SyncDeleteOUs fatal error';
  }
=cut

_setstate($db_adup, 0);
$ldap->unbind;
  
exit 0;


# internal
sub _setstate {
  my ($db, $s) = @_;
  my $e = eval {
    $db->query("UPDATE state SET value = ? WHERE `key`='sync_id'", $s);
  };
  unless (defined $e) {
    carp "Set task state failed\n";
  }
}

