use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::Dblog;

dies_ok( sub { Adup::Ural::Dblog->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;
my $mysql = Mojo::mysql->new($cfg->{adup_db_conn});

my $l1 = Adup::Ural::Dblog->new($mysql->db);
isa_ok($l1, 'Adup::Ural::Dblog');

my $l2 = Adup::Ural::Dblog->new($mysql->db, login=>"testuser");
my $l3 = Adup::Ural::Dblog->new($mysql->db, state=>77);
my $l4 = Adup::Ural::Dblog->new($mysql->db, login=>"testuser", state=>77);

dies_ok( sub { $l1->l(info => "testing 1 log"); }, 'No login and state');
dies_ok( sub { $l2->l(info => "testing 2 log"); }, 'No state');
dies_ok( sub { $l3->l(info => "testing 3 log"); }, 'No login');
$l4->l(info => "testing 4 log");
$l4->l(login => 'newuser', state=>78, info => "testing 4 log - 2");
$l1->l(login => 'newuser', state=>78, info => "testing 1 log - 2");

done_testing();
