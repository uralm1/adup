use Mojo::Base -strict;

use Test::More;
use Test::Exception;
use Mojo::File 'path';

use Adup::Ural::OperatorResolver;

dies_ok( sub { Adup::Ural::OperatorResolver->new }, 'Empty constuctor');

my $cfg = eval path('test.conf')->slurp;

my $r = Adup::Ural::OperatorResolver->new($cfg);
isa_ok($r, 'Adup::Ural::OperatorResolver');

diag $r->resolve('av');
diag $r->resolve('av');
diag $r->resolve('ural');
diag $r->resolve('av1');
diag $r->resolve('av1');
diag $r->resolve('ural1');
diag $r->resolve('ural1');
diag $r->resolve('ural1');

done_testing();
