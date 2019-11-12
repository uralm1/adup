use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeFlatGroupCreate;
use Adup::Ural::ChangeFactory;

dies_ok( sub { Adup::Ural::ChangeFlatGroupCreate->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeFlatGroupCreate->new('testname', 'cn=test,dc=test', 'superuser');
isa_ok($c, 'Adup::Ural::ChangeFlatGroupCreate');

is($c->{type}, 'Adup::Ural::ChangeFlatGroupCreate', "Type is Adup::Ural::ChangeFlatGroupCreate");
is($c->type_robotic, 10, "RoboticType is 10");
is($c->type_human, 'Создание группы почтового справочника', "Human type is 'Создание группы почтового справочника'");

dies_ok ( sub { $c->set_dept_name() }, 'set_dept_name() without dept name');
$c->set_dept_name('test department name');
is($c->dept_name, 'test department name', "Department name is 'test department name'");

my $mysql = Mojo::mysql->new($cfg->{adup_db_conn});
$mysql->db->query("DELETE FROM changes WHERE name = 'testname'");
my $id;
ok ($id = $c->todb(db=>$mysql->db), "Write to db");
diag $id;

my $r = $mysql->db->query("SELECT id, c FROM changes WHERE name = 'testname'");
my $rh = $r->hash;
my $obj = Adup::Ural::ChangeFactory->fromdb(id=>$rh->{id}, json=>$rh->{c});
diag explain $obj;

done_testing();
