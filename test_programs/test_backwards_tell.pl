# test_backwards_tell.pl: dump some output at intervals, back in intramine_commandserver.pl
# we will report on File::ReadBackwards tell() values.

# perl C:\perlprogs\mine\test\test_backwards_tell.pl

use strict;

# When called by a Cmd on IntraMine's Cmd page, unbuffering STDOUT lets us see the print
# results as they happen, instead of waiting to see them dumped at the end all at once.
select((select(STDOUT), $|=1)[0]);

my $i = 0;
for (; $i < 5; ++$i)
	{
	print("Hello $i\n");
	}
print("--\n");
sleep(1);

for (; $i < 10; ++$i)
	{
	print("Hello $i\n");
	}
#print("--\n");
sleep(1);

for (; $i < 15; ++$i)
	{
	print("Hello $i\n");
	}
#print("--\n");
sleep(1);

for (; $i < 20; ++$i)
	{
	print("Hello $i\n");
	}
#print("--\n");

sleep(1);

for (; $i < 25; ++$i)
	{
	print("Hello $i\n");
	}
#print("--\n");

for (; $i < 80; ++$i)
	{
	print("Hello $i\n");
	}
sleep(1);

for (; $i < 100; ++$i)
	{
	print("Hello $i\n");
	}
#sleep(1);
for (; $i < 200; ++$i)
	{
	print("Hello $i\n");
	}

print("\nDone.\n");
