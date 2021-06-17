package Adup::Ural::ZupLoader;
use Mojo::Base -base;

use Carp;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::mysql;
use POSIX qw(ceil);
use Encode qw(encode_utf8);
use Digest::SHA qw(sha1_hex);
#use Data::Dumper;

use Adup::Ural::FlatGroupNamingAI qw(flatgroup_ai);

# my $obj = Adup::Ural::ZupLoader->new($job->app);
# dies on error - bad server url
sub new {
  my ($class, $app, $db, $progress_cb) = @_;
  croak 'App and db parameters required' unless defined $app and defined $db;
  croak 'Invalid progress callback' if defined $progress_cb and ref $progress_cb ne 'CODE';

  my $self = $class->SUPER::new;

  $self->{app} = $app;
  $self->{db} = $db;
  $self->{progress_cb} = $progress_cb;
  #$self->{url_base}
  #$self->{org_key}
  #$self->{si}
  #$self->{kis_array}

  #timeouts
  $app->ua->connect_timeout(10);
  $app->ua->request_timeout(600);

  # set up certs
  $app->ua->ca($app->config('zup_ca')) if $app->config('zup_ca');
  $app->ua->cert($app->config('zup_cert')) if $app->config('zup_cert');
  $app->ua->key($app->config('zup_key')) if $app->config('zup_key');

  # set up url
  my $url_base = Mojo::URL->new($app->config('zup_url'));
  die "Bad server url\n" unless $url_base->is_abs;
  my $p = $url_base->path->trailing_slash(1)->merge('odata/standard.odata/');
  $url_base->path($p);
  # authentication
  $url_base->userinfo(encode_utf8($app->config('zup_auth'))) if $app->config('zup_auth');
  $self->{url_base} = $url_base;
  $app->log->info("Server url: $url_base");

  $self->init_si();

  return $self;
}


sub get_ua {
  return shift->{app}->ua;
}

# _console_ logger
sub get_log {
  return shift->{app}->log;
}

sub get_db {
  return shift->{db};
}


# $self->progress(10, "10% done")
sub progress {
  my $self = shift;
  $self->{progress_cb}(@_) if $self->{progress_cb};
}


# retrive organization key and store it to org_key
# return org_key on success,
# dies on errors.
sub read_org_key {
  my $self = shift;
  my $orgs = $self->read_orgs();
  my $name = $self->{app}->config('zup_org_name');
  my @ooo;
  for (@$orgs) {
    push @ooo, $_->{Description};
    if ($_->{Description} eq $name) {
      my $k = $_->{Ref_Key};
      $self->get_log->info("Found organization key: $k");
      $self->{org_key} = $k;
      return $k;
    }
  }
  $self->get_log->error('Org not found, existed: ['.join(', ', @ooo).']');
  die "Org not found\n";
}


# load catalogues into si hash attribute
# returns a number of loaded records on success,
# dies on errors.
sub read_si {
  my ($self, $si_name) = @_;
  die 'Parameter missing' unless $si_name;
  die 'Si is not initialized!' unless $self->{si};

  my $si_d = $self->{si}{$si_name};
  my $url = Mojo::URL->new($si_d->{obj})->to_abs($self->{url_base})->query({'$select'=>$si_d->{select}, '$filter'=>$si_d->{filter}, '$top'=>$si_d->{top}});
  #say $url_org->to_unsafe_string;
  my %h;
  my $d = $self->read_url($url, $si_d->{print_body});
  my $cnt = 0;
  for (@$d) {
    my $rk = $_->{Ref_Key};
    $self->get_log->error("Duplicate Key $si_d->{obj}!") if exists $h{$rk};
    delete $_->{Ref_Key};
    $h{$rk} = $_;
    $cnt++;
  }
  $si_d->{hash} = \%h;
  $self->get_log->info("Loaded [$si_d->{obj}], $cnt records.");
  return $cnt;
}


# load main information register into kis_array attribute
# returns a number of loaded records on success,
# dies on errors.
sub read_kis {
  my $self = shift;
  croak 'Org key is not loaded!' unless $self->{org_key};

  # Перечисление.ВидыКадровыхСобытий
  my $dismiss_ev = 'Увольнение';

  my $obj = 'InformationRegister_КадроваяИсторияСотрудников_RecordType/SliceLast()';
  my $select = 'Period,Сотрудник_Key,ФизическоеЛицо_Key,Подразделение_Key,Должность_Key,ДолжностьПоШтатномуРасписанию_Key,ВидСобытия,ВидДоговора';
  my $filter = "ГоловнаяОрганизация_Key eq guid'$self->{org_key}' and Организация_Key eq guid'$self->{org_key}' and Active eq true and ВидСобытия ne '$dismiss_ev'";
  my $top = undef;

  my $url_kis = Mojo::URL->new($obj)->to_abs($self->{url_base})->query({'$select'=>$select, '$filter'=>$filter, '$top'=>$top});
  #say $url_kis->to_unsafe_string;

  $self->{kis_array} = $self->read_url($url_kis);
  my $cnt = scalar @{$self->{kis_array}};
  $self->get_log->info("Loaded [$obj], $cnt records.");
  return $cnt;
}


# main uploading procedure
# returns 1,
# dies on errors.
sub upload_data {
  my $self = shift;
  die 'Si is not initialized!' unless $self->{si};
  $self->progress(0, '0% Поиск организации');
  $self->read_org_key;
  $self->progress(5, '5% Загрузка справочников');
  $self->read_si($_) for keys %{$self->{si}};
  $self->progress(10, '10% Загрузка данных сотрудников');
  $self->read_kis;
  return 1;
}

# main processing procedure
# returns list ($loaded_cnt, $dept_loaded_cnt, $flatdept_loaded_cnt) with numbers of loaded records on success,
# dies on errors.
sub process_data {
  my $self = shift;
  die 'Si is not initialized!' unless $self->{si};
  die 'Kis is not loaded!' unless $self->{kis_array};

  $self->progress(10, '10% Очистка таблиц');
  my $e = eval {
    $self->get_db->query("DELETE FROM persons");
    $self->get_db->query("DELETE FROM depts");
    $self->get_db->query("DELETE FROM flatdepts");
  };
  die "Database tables cleanup error\n" unless defined $e;

  # optimizations
  my $_sot = $self->{si}{'Сотрудники'}{hash};
  my $_fl = $self->{si}{'ФизическиеЛица'}{hash};
  my $_dl = $self->{si}{'Должности'}{hash};
  my $_pod = $self->{si}{'ПодразделенияОрганизаций'}{hash};

  my $dept_id_gen_val = 1;

  #
  ### 1.generate db ids for departments
  #
  $_->{_id} = $dept_id_gen_val++ for values %$_pod;
  #
  ### done
  #

  my $loaded_cnt = 0;
  my %fio_dedup_h;
  my %fio_otd_dedup_h;
  my %flatdept_dedup_h;
  my $flatdept_id_gen_val = 1;

  my $total_rec = scalar @{$self->{kis_array}};
  my $mod = int($total_rec / 20) || 1;
  #
  ### 2.begin of persons loop ###
  #
  for my $rec (@{$self->{kis_array}}) {
    # collect data
    my $sot_key = $rec->{'Сотрудник_Key'};
    my $fl_key = $rec->{'ФизическоеЛицо_Key'};
    my $dl_key = $rec->{'Должность_Key'};
    my $pod_key = $rec->{'Подразделение_Key'};

    my $sot_v = $_sot->{$sot_key};
    my $id = $sot_key // 0;
    my $tabn = $sot_v->{Code} // 0;

    my $fl_v = $_fl->{$fl_key};
    my $fio = $fl_v->{'ФИО'}; # first try ФизическиеЛица
    $fio = $sot_v->{Description} unless $fio; # then Сотрудники
    unless ($fio) {
      $self->get_log->error("Employee $id has empty FIO - we will skip him.");
      next;
    }

    my $dolj = $_dl->{$dl_key}{Description} // '';
    my $otdel_hierarhy = _unwind_hierarhy($pod_key, $_pod); # this also mark depts as used
    my $otdel = join('\\', @$otdel_hierarhy) // '';

    # split fio
    my ($fio_f, $fio_i, $fio_o);
    if ($fio =~ m/^\s*(\S+)\s*(\S*)\s*\b(.*)\b\s*$/) { # we have to do it to reset $N vars
      $fio_f = "\u\L$1";
      $fio_i = "\u\L$2"; # will expand to empty strings, not undefs
      $fio_o = "\u$3";
    } else {
      $fio_f = 'Не указано';
      $fio_i = '';
      $fio_o = '';
    }
    $fio = join(' ', grep $_, $fio_f, $fio_i, $fio_o);

    # fio dedup (and then dedup by fio+otdel)
    if (exists $fio_dedup_h{$fio}) {
      # fio+otdel
      my $fio_otd = join('', $fio, $otdel);
      if (exists $fio_otd_dedup_h{$fio_otd}) {
        #$fio_otd_dedup_h{$fio_otd} = 1; # not needed
        $fio_dedup_h{$fio} = 2;
      } else {
        $fio_otd_dedup_h{$fio_otd} = 0;
        $fio_dedup_h{$fio} = 1;
      }
    } else {
      $fio_dedup_h{$fio} = 0;
    }

    # flatdept dedup
    $flatdept_dedup_h{$otdel} = $flatdept_id_gen_val++ unless exists $flatdept_dedup_h{$otdel};

    $e = eval {
      $self->get_db->query("INSERT INTO persons (gal_id, fio, dup, f, i, o, dept_id, flatdept_id, otdel, dolj, tabn) \
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        $id,
        $fio,
        0, # will update later
        $fio_f, $fio_i, $fio_o,
        $_pod->{$pod_key}{_id},
        $flatdept_dedup_h{$otdel},
        $otdel,
        $dolj,
        $tabn
      );
    };
    die "Database insert to table persons error" unless defined $e;

    if ($loaded_cnt % $mod == 0) {
      my $percent = ceil($loaded_cnt / $total_rec * 80) + 10;
      $self->progress($percent, "$percent% Обработка перечня сотрудников");
    }
    $loaded_cnt++;
  }
  $self->get_log->info("Persons processed, $loaded_cnt.");
  #
  ### end of persons loop ###
  #

  #
  ### 3.update duplicates ###
  #
  $self->progress(90, '90% Запись информации о дубликатах');
  while (my ($fio, $v) = each %fio_dedup_h) {
    if ($v > 0) {
      $e = eval {
        $self->get_db->query("UPDATE persons SET dup = ? WHERE fio = ?", $v, $fio);
      };
      die "Database update duplicates in table persons error" unless defined $e;
    }
  }
  $self->get_log->info("Persons duplicates processed.");
  #
  ### done ###
  #

  #
  ### 4.begin of processing depts hash ###
  #
  $self->progress(90, '90% Разбор информации об оргструктуре подразделений');
  my $dept_loaded_cnt = 0;
  for (values %$_pod) {
    next unless $_->{_used};

    my ($level, $parent) = (0, 0); # root element has parent 0, level 0
    # when element is a child...
    my $pk = $_->{Parent_Key};
    unless (_zero_key($pk)) {
      # get parent id
      $parent = $_pod->{$pk}{_id};
      # and calculate level
      do {
        $pk = $_pod->{$pk}{Parent_Key};
        $level++;
      } until _zero_key($pk);
    }
    $e = eval {
      $self->get_db->query("INSERT INTO depts (id, name, level, parent) \
        VALUES(?, ?, ?, ?)",
        $_->{_id},
        $_->{Description},
        $level,
        $parent
      );
    };
    die "Database insert to table depts error" unless defined $e;
    $dept_loaded_cnt++;
  }
  $self->get_log->info("Departments processed, $dept_loaded_cnt.");
  #
  ### end of saving processed depts hash ###
  #

  #
  ### 5.begin of saving flat depts hash ###
  #
  $self->progress(95, '95% Сохранение оргструктуры подразделений для почтового справочника');
  my $flatdept_loaded_cnt = 0;
  #say Dumper \%flatdept_dedup_h;
  for my $otd (keys %flatdept_dedup_h) {
    my $mod_otd = $otd;
    $mod_otd =~ s/\\/-/g;
    $e = eval {
      $self->get_db->query("INSERT INTO flatdepts (id, cn, name) \
        VALUES(?, ?, ?)",
        $flatdept_dedup_h{$otd},
        sha1_hex(encode_utf8($otd)),
        flatgroup_ai($mod_otd)
      );
    };
    die "Database insert to table flatdepts error" unless defined $e;
    $flatdept_loaded_cnt++;
  }
  $self->get_log->info("Flatdepts processed, $flatdept_loaded_cnt.");
  #
  ### end of saving flat depts hash ###
  #
  $self->progress(100, '100% Завершено');

  return ($loaded_cnt, $dept_loaded_cnt, $flatdept_loaded_cnt);
}


# internal
sub read_orgs {
  my $self = shift;
  my $obj = 'Catalog_Организации';
  my $select = 'Ref_Key,Description';
  my $filter = 'DeletionMark eq false';
  my $top = 1000;
  $self->get_log->info("Loading [$obj]...");
  my $url_org = Mojo::URL->new($obj)->to_abs($self->{url_base})->query({'$select'=>$select, '$filter'=>$filter, '$top'=>$top});
  #say $url_org->to_unsafe_string;
  return $self->read_url($url_org);
}


# internal
sub init_si {
  my $self = shift;

  $self->{si} = {
    'Сотрудники' => {
      obj => 'Catalog_Сотрудники',
      select => 'Ref_Key,Description,Code',
      filter => "DeletionMark eq false and ВАрхиве eq false",
      top => undef,
      #print_body => 1,
      # Description, Code
      hash => undef,
    },
    # group hierarhy
    'ФизическиеЛица' => {
      obj => 'Catalog_ФизическиеЛица',
      select => 'Ref_Key,Description,ФИО,Фамилия,Имя,Отчество,ДатаРождения',
      filter => "DeletionMark eq false and IsFolder eq false",
      top => undef,
      #print_body => 1,
      # Description, ФИО, Фамилия, Имя, Отчество, ДатаРождения
      hash => undef,
    },
    'Должности' => {
      obj => 'Catalog_Должности',
      select => 'Ref_Key,Description',
      filter => "DeletionMark eq false",
      top => undef,
      #print_body => 1,
      # Description
      hash => undef,
    },
    # element hierarhy
    #'ШтатноеРасписание' => {
    #  obj => 'Catalog_ШтатноеРасписание',
    #  select => 'Ref_Key,Description,Parent_Key,Подразделение_Key,Должность_Key,Закрыта',
    #  filter => "DeletionMark eq false",
    #  top => undef,
    #  #print_body => 1,
    #  # Description
    #  hash => undef,
    #},
    # element hierarhy
    'ПодразделенияОрганизаций' => {
      obj => 'Catalog_ПодразделенияОрганизаций',
      select => 'Ref_Key,Description,Parent_Key,Сформировано,Расформировано',
      filter => "DeletionMark eq false",
      top => undef,
      #print_body => 1,
      # Description
      hash => undef,
    },
  };
}


# internal
sub read_url {
  my ($self, $url, $print_body) = @_;
  die 'Parameter missing' unless $url;

  # tx->result dies on connection errors
  my $res = $self->get_ua->get(_fix_pluses_in_url($url) => {Accept => 'application/json'})->result;
  if (!$res->is_success) {
    die 'Response error '.$res->code.' '.$res->message.", url: $url\n" if $res->is_error;
    die 'Response unsuccessful '.$res->code.", url: $url\n";
  }
  say $res->body if $print_body;

  my $v = $res->json;
  die "Json response error, url: $url\n" unless $v;

  return $v->{value};
}


# internal, not a method
sub _zero_key {
  local $_ = shift;
  !defined $_ or /^[0-]+$/;
}


# internal, not a method
#my $hier_ref = _unwind_hierarhy($ref_key, $hash_ref);
sub _unwind_hierarhy {
  my ($ref_key, $hash_ref) = @_;
  my @elements;
  local $_ = $ref_key;
  do {
    my $v = $hash_ref->{$_};
    unshift @elements, $v->{Description} if $v;
    $_ = $v->{Parent_Key};
    $v->{_used} = 1; # important: set _used mark
  } until _zero_key($_);
  return \@elements;
}


# internal, not a method
sub _fix_pluses_in_url {
  my $url = shift;
  #croak 'Parameter missing' unless $url;
  my $u = $url->to_unsafe_string;
  $u =~ s/\+/%20/g;
  return $u;
}


1;
