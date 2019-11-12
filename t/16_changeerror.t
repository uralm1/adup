use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeError;
use Adup::Ural::ChangeFactory;

dies_ok( sub { Adup::Ural::ChangeError->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeError->new('testname', 'cn=test,dc=test', 'superuser');
isa_ok($c, 'Adup::Ural::ChangeError');

is($c->{type}, 'Adup::Ural::ChangeError', "Type is Adup::Ural::ChangeAttr");
is($c->type_human, 'Ошибка', "Human type is 'Ошибка'");

is($c->error, 'н/д', "Error is not set");

$c->set_error('Сообщение об ошибке');
is($c->error, 'Сообщение об ошибке', "Error is set");

my $mysql = Mojo::mysql->new($cfg->{adup_db_conn});
$mysql->db->query("DELETE FROM changes WHERE name = 'testname'");
my $id;
ok ($id = $c->todb(db=>$mysql->db), "Write to db");
diag $id;

my $r = $mysql->db->query("SELECT id, c FROM changes WHERE name = 'testname'");
my $rh = $r->hash;
my $obj = Adup::Ural::ChangeFactory->fromdb(id=>$rh->{id}, json=>$rh->{c});
diag explain $obj;
diag $obj->error;

done_testing();
