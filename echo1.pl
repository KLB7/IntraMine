# echo1.pl: just echoes command line arguments.
# perl C:\perlprogs\echo1.pl arg(s)

use strict;
select((select(STDOUT), $| = 1)[0]);

my @args;
while (defined(my $arg = shift @ARGV))
	{
	push @args, $arg;
	}
my $allArgs = join("|", @args);
print("Args: |$allArgs|\n");
sleep(3);
