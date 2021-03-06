use strict;
use warnings;

#use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::CPANfile;

my $inst_dir = '/opt/adup';

WriteMakefile(
  NAME => 'Adup',
  AUTHOR => 'Ural Khasanov <uralm@uwc.ufanet.ru>',
  DISTNAME => 'adup',
  VERSION_FROM   => 'lib/Adup.pm',
  #PREREQ_PM => {
  #  'Mojolicious' => '8.09',
  #  'Mojo::mysql' => '1.04',
  #  'Minion' => '9.03',
  #  'Minion::Backend::mysql' => 0,
  #  'XBase' => 0,
  #  'Net::LDAP' => '0.65',
  #  'Net::LDAP::Util' => 0,
  #  'MIME::Base64' => 0,
  #  'Digest::SHA' => 0,
  #},
  test      => {TESTS => 't/*.t'},
  PREFIX => $inst_dir,
  LIB => "$inst_dir/lib",
  #PMLIBDIRS => ['lib'],
  #PM => {
  #  'lib/Adup.pm' => '$(INST_LIB)/Adup.pm',
  #},
  INSTALLSCRIPT => "$inst_dir/script",
  INSTALLSITESCRIPT => "$inst_dir/script",
  EXE_FILES => ['script/adup', 'script/start_server', 'script/check_db_hosts', 'script/smbload'],
  MAN1PODS => {},
  MAN3PODS => {},
);

package MY;
sub install {
  my $inherited = shift->SUPER::install(@_);
  return $inherited.<<"MAKE_FRAG";
install::
	\$(NOECHO) \$(ECHO) "** Installing configuration, public and templates files..."
	\$(NOECHO) install -m 0644 adup.conf_empty \$(DESTDIR)$inst_dir/adup.conf
	\$(NOECHO) for d in \$\$(find public -type d); do install -m 0755 -d \$(DESTDIR)$inst_dir/\"\$\$d\"; done
	\$(NOECHO) for f in \$\$(find public -type f); do install -m 0644 -D \"\$\$f\" \$(DESTDIR)$inst_dir/\"\$\$f\"; done
	\$(NOECHO) for d in \$\$(find templates -type d); do install -m 0755 -d \$(DESTDIR)$inst_dir/\"\$\$d\"; done
	\$(NOECHO) for f in \$\$(find templates -type f); do install -m 0644 -D \"\$\$f\" \$(DESTDIR)$inst_dir/\"\$\$f\"; done
	\$(NOECHO) if [ \"\$\$(id -u)\" != \"0\" ]; then install -m 0755 -d \$(DESTDIR)$inst_dir/run; else install -o adup -g adup -m 0755 -d \$(DESTDIR)$inst_dir/run; fi
	\$(NOECHO) if [ \"\$\$(id -u)\" != \"0\" ]; then install -m 0755 -d \$(DESTDIR)$inst_dir/log; else install -o adup -g adup -m 0755 -d \$(DESTDIR)$inst_dir/log; fi
	\$(NOECHO) if [ \"\$\$(id -u)\" != \"0\" ]; then install -m 0755 -d \$(DESTDIR)$inst_dir/tmp; else install -o adup -g adup -m 0755 -d \$(DESTDIR)$inst_dir/tmp; fi
	\$(NOECHO) install -m 0644 CHANGELOG.md \$(DESTDIR)$inst_dir/CHANGELOG.md
	\$(NOECHO) install -m 0644 README.md \$(DESTDIR)$inst_dir/README.md

MAKE_FRAG
}

sub postamble {
  return <<'MAKE_FRAG';
all::
	$(NOECHO) $(ECHO) "** Checking..."
	$(NOECHO) if grep -q -e "^\s*\$$self->plugin(['|\"]Minion::Admin['|\"]);" lib/Adup.pm ; then echo "\nWARNING! DEBUG MINION ADMIN PAGE in Adup.pm IS NOT DISABLED!!!\n"; fi
	$(NOECHO) if grep -q -e "^\s*\$$remote_user = ['|\"]" lib/Adup.pm ; then echo "\nWARNING! DEBUG ENTRY AUTHORIZATION CODE in Adup.pm IS NOT DISABLED!!!\n"; fi

MAKE_FRAG
}

