package Adup::Task::Preprocess;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use POSIX qw(ceil);
use Mojo::mysql;
use XBase;
use Encode qw(decode encode_utf8);
use Digest::SHA qw(sha1_hex);
#use Data::Dumper;

use Adup::Ural::Dblog;
use Adup::Ural::FlatGroupNamingAI qw(flatgroup_ai);

my $TASK_ID = 'preprocess_id';
# $TASK_LOG_STATE_SUCCESS = 0;
# $TASK_LOG_STATE_ERROR = 1;


sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(preprocess => \&_process_dbf);
}


# internal
sub _process_dbf {
  my ($job, $remote_user) = @_;

  $job->app->log->info("Start preprocess $$: ".$job->id);
  my $db_adup = $job->app->mysql_adup->db;

  my $log = Adup::Ural::Dblog->new($db_adup, login=>$remote_user, state=>0);

  $job->app->set_task_state($db_adup, $TASK_ID, $job->id);

  my $dbf = eval { new XBase($job->app->config('galdb_temporary_file')); };

  if (defined $dbf) {
    my $e = eval {
      $db_adup->query("DELETE FROM persons");
      $db_adup->query("DELETE FROM depts");
      $db_adup->query("DELETE FROM flatdepts");
    };
    unless (defined $e) {
      $job->app->reset_task_state($db_adup, $TASK_ID);
      return $job->fail('Tables cleanup error');
    }

    my $loaded_cnt = 0;
    my %path_id_h;
    my %id_dept_h;
    my %fio_dedup_h;
    my %fio_otd_dedup_h;
    my $id_gen_val = 1;
    my %flatdept_dedup_h;
    my $flatdept_id_gen_val = 1;

    my $last_record = $dbf->last_record;
    ###$last_record = 20; #FOR DEBUG
    my $mod = int(($last_record+1) / 20) || 1;

    #
    ### 1.begin of persons loop ###
    #
    for (0 .. $last_record) {
      my ($deleted, $id, $fio, $otdel, $dolj, $tabn) =
        $dbf->get_record($_, 'ID', 'FIO', 'OTDEL', 'DOLJ', 'TABN');
      unless ($deleted) {
	# split fio
	$fio = decode('cp866', $fio);

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

	$id = 0 unless defined $id;
	$otdel = '' unless defined $otdel;
	$dolj = '' unless defined $dolj;
	$tabn = 0 unless defined $tabn;

	$otdel = decode('cp866', $otdel);

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
	unless (exists $flatdept_dedup_h{$otdel}) {
	  $flatdept_dedup_h{$otdel} = $flatdept_id_gen_val;
	  $flatdept_id_gen_val++;
	}

	# split otdel
	process_dept_a(\%path_id_h, \%id_dept_h, \$id_gen_val, split(/\\/, $otdel));

	$e = eval {
	  $db_adup->query("INSERT INTO persons (gal_id, fio, dup, f, i, o, dept_id, flatdept_id, otdel, dolj, tabn) \
	    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
	    $id,
	    $fio,
	    0, #1.7 will update later
	    $fio_f, $fio_i, $fio_o,
	    $path_id_h{$otdel},
	    $flatdept_dedup_h{$otdel},
	    $otdel,
	    decode('cp866', $dolj),
	    $tabn
	  );
	};
        unless (defined $e) {
          $log->l(state => 1, info => "Произошла ошибка записи таблицы persons, $loaded_cnt сотрудников обработано");
          $job->app->reset_task_state($db_adup, $TASK_ID);
          return $job->fail('Mysql insert to table persons error');
	}
	$loaded_cnt++;
      }
      # update progress
      if ($_ % $mod == 0) {
	my $percent = ceil($_ / $last_record * 100);
	$job->note(
	  progress => $percent,
	  info => "$percent% Обработка перечня сотрудников",
	);
      }
    }
    #
    ### end of persons loop ###
    #

    #
    ### 2.update duplicates ###
    #
    for my $fio (keys %fio_dedup_h) {
      if ($fio_dedup_h{$fio} > 0) {
	$e = eval {
	  $db_adup->query("UPDATE persons SET dup = ? WHERE fio = ?", $fio_dedup_h{$fio}, $fio);
	};
	unless (defined $e) {
          $log->l(state => 1, info => "Произошла ошибка обновления дубликатов в таблице persons, $loaded_cnt сотрудников обработано");
	  $job->app->reset_task_state($db_adup, $TASK_ID);
	  return $job->fail('Mysql update dublicates in table persons error');
	}
      }
    }
    #
    ### done ###
    #

    $job->note(
      progress => 100,
      info => 'Выполняется разбор оргструктуры подразделений',
    );

    #
    ### 3.begin of saving processed depts hash ###
    #
    my $dept_loaded_cnt = 0;
    #say Dumper \%id_dept_h;
    for (keys %id_dept_h) {
      $e = eval {
	$db_adup->query("INSERT INTO depts (id, name, level, parent) \
	  VALUES(?, ?, ?, ?)",
	  $_,
	  $id_dept_h{$_}->{name},
	  $id_dept_h{$_}->{level},
	  $id_dept_h{$_}->{parent}
	);
      };
      unless (defined $e) {
	$log->l(state => 1, info => "Произошла ошибка записи таблицы подразделений");
	$job->app->reset_task_state($db_adup, $TASK_ID);
        return $job->fail('Mysql insert to table depts error');
      }
      $dept_loaded_cnt++;
    }
    #
    ### end of saving processed depts hash ###
    #

    #
    ### 4.begin of saving flat depts hash ###
    #
    my $flatdept_loaded_cnt = 0;
    #say Dumper \%flatdept_dedup_h;
    for my $otd (keys %flatdept_dedup_h) {
      my $mod_otd = $otd;
      $mod_otd =~ s/\\/-/g;
      $e = eval {
	$db_adup->query("INSERT INTO flatdepts (id, cn, name) \
	  VALUES(?, ?, ?)",
	  $flatdept_dedup_h{$otd},
	  sha1_hex(encode_utf8($otd)),
	  flatgroup_ai($mod_otd)
	);
      };
      unless (defined $e) {
	$log->l(state => 1, info => "Произошла ошибка записи подразделений в плоском формате");
        $job->app->reset_task_state($db_adup, $TASK_ID);
	die('Mysql insert to table flatdepts error');
      }
      $flatdept_loaded_cnt++;
    }
    #
    ### end of saving flat depts hash ###
    #

    $log->l(info => "Загружен шаблон с информацией по $loaded_cnt сотрудникам и выполнен разбор оргструктуры по $dept_loaded_cnt/$flatdept_loaded_cnt подразделениям");

  } else {
    $log->l(state => 1, info => "Произошла ошибка обработки файла выгрузки");
    $job->app->reset_task_state($db_adup, $TASK_ID);
    return $job->fail('XBase object creation failed');
  }

  $job->app->reset_task_state($db_adup, $TASK_ID);

  $job->app->log->info("Finish $$: ".$job->id);
  $job->finish;
}


# internal
# process_dept_a($path_id_href, $id_dept_href, $id_gen_ref, split(/\\/, $otdel));
sub process_dept_a {
  my $path_id_href = shift;
  my $id_dept_href = shift;
  my $id_gen_ref = shift;
  my @dept_a = @_;

  my $level = 0;
  my $path;
  my $parent_id = 0; # start from root
  for (@dept_a) {
    $path = (defined $path) ? "$path\\$_" : $_;
    if (!defined $path_id_href->{$path}) {
      # add dept to hashes
      $path_id_href->{$path} = $$id_gen_ref;
      $id_dept_href->{$$id_gen_ref} = {
	name => $_,
	level => $level,
	parent => $parent_id,
      };
      $parent_id = $$id_gen_ref;
      $$id_gen_ref++;
    } else {
      $parent_id = $path_id_href->{$path};
    }
    $level++; # go to next level
  }
}


1;
__END__
