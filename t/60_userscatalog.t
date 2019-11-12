use Mojo::Base -strict;

use Test::More;
use Test::Exception;
#use Test::Mojo;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::UsersCatalog;

dies_ok( sub { Adup::Ural::UsersCatalog->new() }, 'Empty constructor');

my $dbcfg = eval path('test.conf')->slurp;
my $mysql = Mojo::mysql->new($dbcfg->{adup_db_conn});

my $_users = {
  'login1' => { role=>'superadmin' },
  'login2' => { role=>'dirtcleaner' },
};

my $uc = Adup::Ural::UsersCatalog->new($mysql);
isa_ok($uc, 'Adup::Ural::UsersCatalog');

#diag explain $uc->get_users;

$uc->_test_assign($_users);

is_deeply($uc->get_users, $_users, 'Users inside');

is($uc->get_user(''), undef, 'Empty user');
is($uc->get_user('unknown.login'), undef, 'Unknown user');

is($uc->get_user_role('unknown'), undef, 'User role of unknown user');
is($uc->get_user_role('login1'), 'superadmin', 'User role 1');
is($uc->get_user_role('login2'), 'dirtcleaner', 'User role 2');

done_testing();
