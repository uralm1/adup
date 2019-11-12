use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeAttr;

dies_ok( sub { Adup::Ural::ChangeAttr->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeAttr->new('testname', 'cn=test,dc=test', 'superuser');
isa_ok($c, 'Adup::Ural::ChangeAttr');

is($c->{id}, undef, "Id is undefined");
is($c->{type}, 'Adup::Ural::ChangeAttr', "Type is Adup::Ural::ChangeAttr");
is($c->type_human, 'Изменение аттрибутов', "Human type is 'Изменение аттрибутов'");
is($c->{author}, 'superuser', "Author is superuser");
diag $c->{date};

$c->set_attr('testattr', 111, 222);
is($c->attr_old('testattr'), 111, "Old testattr == 111");
is($c->attr_new('testattr'), 222, "New testattr == 222");
$c->set_attr('testattr', 333);
is($c->attr_old('testattr'), 222, "Old testattr == 222 test2");
is($c->attr_new('testattr'), 333, "New testattr == 333 test2");

$c->set_attr('testattr2', 111);
is($c->attr_old('testattr2'), undef, "Old testattr2 == undef test3");
is($c->attr_new('testattr2'), 111, "New testattr2 == 111 test3");
$c->set_attr('testattr2', 222);
is($c->attr_old('testattr2'), 111, "Old testattr2 == 111 test4");
is($c->attr_new('testattr2'), 222, "New testattr2 == 222 test4");

my $mysql = Mojo::mysql->new($cfg->{adup_db_conn});
my $id;
ok ($id = $c->todb(db=>$mysql->db), "Write to db");
diag $id;


done_testing();
