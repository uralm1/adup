use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';
use Mojo::mysql;

use Adup::Ural::ChangeUserFlatGroup;

#dies_ok( sub { Adup::Ural::ChangeUserFlatGroup->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $c = Adup::Ural::ChangeUserFlatGroup->new('testname', 'cn=test,dc=test');
isa_ok($c, 'Adup::Ural::ChangeUserFlatGroup');
$c->member_cn('CNCNCN')
  ->member_dn('CN=CNCNCN,DC=test,DC=local')
  ->flatgroup_name('The long name of flatgroup');
diag explain $c;
diag $c->member_cn;

my $c1 = Adup::Ural::ChangeUserFlatGroup->new('testname', 'cn=test,dc=test', 'superuser');
diag explain $c1;


done_testing();
