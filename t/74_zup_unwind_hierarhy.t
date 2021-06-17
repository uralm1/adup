use Mojo::Base -strict;

use Test::More;

use Adup::Ural::ZupLoader;

my $h = {
  '1-2-3-4' => { Parent_Key=>'1-2-3-5', Description=>'lvl4' },
  '1-2-3-5' => { Parent_Key=>'1-2-3-6', Description=>'lvl3' },
  '1-2-3-6' => { Parent_Key=>'1-2-3-7', Description=>'lvl2' },
  '1-2-3-7' => { Parent_Key=>'0-0-0-0', Description=>'root' },
  '1-2-3-8' => { Description=>'r2' },
};

ok(! Adup::Ural::ZupLoader::_zero_key('1-2-3-5'), 'zero_key0');
ok(Adup::Ural::ZupLoader::_zero_key('0-0-0-0'), 'zero_key1');
ok(Adup::Ural::ZupLoader::_zero_key(undef), 'zero_key2');
ok(Adup::Ural::ZupLoader::_zero_key(), 'zero_key3');
ok(Adup::Ural::ZupLoader::_zero_key('00000-0000-0000000-000000000000000'), 'zero_key4');

is_deeply(Adup::Ural::ZupLoader::_unwind_hierarhy('1-2-3-5', $h), ['root','lvl2','lvl3'], 'test1');
is_deeply(Adup::Ural::ZupLoader::_unwind_hierarhy('1-2-3-4', $h), ['root','lvl2','lvl3','lvl4'], 'test2');
is_deeply(Adup::Ural::ZupLoader::_unwind_hierarhy('1-2-3-7', $h), ['root'], 'test3');
is_deeply(Adup::Ural::ZupLoader::_unwind_hierarhy('1-2-3-8', $h), ['r2'], 'test4');

done_testing();
