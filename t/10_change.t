use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::Change;

dies_ok( sub { Adup::Ural::Change->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::Change->new('testname', 'cn=test,dc=test');
isa_ok($c, 'Adup::Ural::Change');
is($c->{id}, undef, "Id is undefined");
is($c->{type}, 'Adup::Ural::Change', "Type is Adup::Ural::Change");
is($c->type_human, 'Абстрактное', "Human type is 'Абстрактное'");
#diag $c->{author};
diag $c->{date};

my $c1 = Adup::Ural::Change->new('testname', 'cn=test,dc=test', 'superuser');
is($c1->{author}, 'superuser', "Author is superuser");
is($c1->name, 'testname', "Name is set");
is($c1->dn, 'cn=test,dc=test', "DN is set");

ok (!$c1->approved, "Fresh is Not approved");
$c1->approve(author=>'commanderСидор');
ok ($c1->approved, "Now is approved");
diag explain $c1->approved;

my $mysql = Mojo::mysql->new($cfg->{adup_db_conn});
my $id;
ok ($id = $c1->todb(db=>$mysql->db), "Write to db");
diag $id;


done_testing();
