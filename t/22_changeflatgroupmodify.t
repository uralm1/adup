use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeFlatGroupModify;
use Adup::Ural::ChangeFactory;

dies_ok( sub { Adup::Ural::ChangeFlatGroupModify->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeFlatGroupModify->new('testname', 'cn=test,dc=test', 'superuser');
isa_ok($c, 'Adup::Ural::ChangeFlatGroupModify');

is($c->{type}, 'Adup::Ural::ChangeFlatGroupModify', "Type is Adup::Ural::ChangeFlatGroupModify");
is($c->type_robotic, 12, "RoboticType is 12");
is($c->type_human, 'Изменение группы почтового справочника', "Human type is 'Изменение группы почтового справочника'");

dies_ok ( sub { $c->set_dept_names() }, 'set_dept_names() without dept name');
dies_ok ( sub { $c->set_dept_names('aaa') }, 'set_dept_names() without second dept name');
$c->set_dept_names('old department name', 'new department name');
is($c->dept_name, 'new department name', "Department name is 'new department name'");
is($c->old_dept_name, 'old department name', "Old department name is 'old department name'");

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
