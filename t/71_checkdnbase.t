use Mojo::Base -strict;

use Test::More;
use Test::Exception;

use Adup::Ural::LdapListsUtil qw(checkdnbase);

is(checkdnbase('CN=asdf,OU=1,DC=contoso,DC=local', 'OU=1,DC=contoso,DC=local'), 1, "true");
is(checkdnbase('CN=asdf,OU=1,DC=contoso,DC=local', 'OU=2,DC=contoso,DC=local'), undef, "false");
is(checkdnbase('CN=asdf,OU=1,DC=contoso,DC=local', 'OU=1,DC=contoso,DC=local1'), undef, "false");
is(checkdnbase('CN=asdf,OU=1,DC=contoso,DC=local', 'OU=1,DC=contoso1,DC=local'), undef, "false");

done_testing();
