use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeFlatGroupDelete;
use Adup::Ural::ChangeFactory;

dies_ok( sub { Adup::Ural::ChangeFlatGroupDelete->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeFlatGroupDelete->new('testname', 'cn=test,dc=test', 'superuser');
isa_ok($c, 'Adup::Ural::ChangeFlatGroupDelete');

is($c->{type}, 'Adup::Ural::ChangeFlatGroupDelete', "Type is Adup::Ural::ChangeFlatGroupDelete");
is($c->type_robotic, 11, "RoboticType is 11");
is($c->type_human, 'Удаление группы почтового справочника', "Human type is 'Удаление группы почтового справочника'");

dies_ok ( sub { $c->set_old_dept_name() }, 'set_old_dept_name() without dept name');
$c->set_old_dept_name('test department name');
is($c->old_dept_name, 'test department name', "Old department name is 'test department name'");

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
