use Mojo::Base -strict;

use Test::More;
use Test::Exception;

use Adup::Ural::LoginAI;

dies_ok( sub { Adup::Ural::LoginAI->new }, 'Empty constuctor');

my $l1 = Adup::Ural::LoginAI->new('Хасанов', 'Урал', 'Флю');
isa_ok($l1, 'Adup::Ural::LoginAI');
is($l1->login, 'hasanovuf', 'hasanovuf'); $l1->next_round;
is($l1->login, 'hasanovurf', 'hasanovurf'); $l1->next_round;
is($l1->login, 'hasanovuraf', 'hasanovuraf'); $l1->next_round;
is($l1->login, 'hasanovuralf', 'hasanovuralf'); $l1->next_round;
is($l1->login, 'hasanovuralfl', 'hasanovuralfl'); $l1->next_round;
is($l1->login, 'hasanovuralflj', 'hasanovuralflj'); $l1->next_round;
is($l1->login, 'hasanovuralflju', 'hasanovuralflju'); $l1->next_round;
is($l1->login, 'hasanovuralflju2', 'hasanovuralflju2'); $l1->next_round;
is($l1->login, 'hasanovuralflju3', 'hasanovuralflju3'); $l1->next_round;

my $l2 = Adup::Ural::LoginAI->new('Хасанов', 'У', '');
is($l2->login, 'hasanovu', 'hasanovu'); $l2->next_round;
is($l2->login, 'hasanovu2', 'hasanovu2'); $l2->next_round;
is($l2->login, 'hasanovu3', 'hasanovu3'); $l2->next_round;

my $l3 = Adup::Ural::LoginAI->new('Хасанов', '', '');
is($l3->login, 'hasanov', 'hasanov'); $l3->next_round;
is($l3->login, 'hasanov2', 'hasanov2'); $l3->next_round;
is($l3->login, 'hasanov3', 'hasanov3'); $l3->next_round;

#for (1..20) {
#  diag $l1->login;
#  $l1->next_round;
#}

done_testing();
