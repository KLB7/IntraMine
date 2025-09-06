# dollars.pm: format dollar amounts for pretty printing.

package dollars;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Carp;

sub DollarsAndCents {
	my ($inS) = @_;
	_DollarsPrint($inS, 0);
}

sub Dollars {
	my ($inS) = @_;
	_DollarsPrint($inS, 1);
}

use ExportAbove;

# Returns dollars printed pretty, with or without pennies (default no pennies).
# Result in () if negative.
sub _DollarsPrint {
	my ($inS, $suppressPennies) = @_;
	my $outS      = "\$";
	my $dollars   = '';
	my $cents     = '';
	my $haveCents = 0;
	my $isNeg     = 0;

	##print("Dollar input: $inS\n");
	if ($inS < 0)
		{
		$isNeg = 1;
		$inS   = -$inS;
		}
	$inS = int(($inS + .005) * 100) / 100;

	if ($inS =~ /^(.*?)\.(.*?)$/)
		{
		$dollars   = $1;
		$cents     = $2;
		$haveCents = 1;
		}
	else
		{
		$dollars = $inS;
		}
	$dollars = commify($dollars);
	$outS .= $dollars;

	if (!$suppressPennies)
		{
		$outS .= '.';
		if ($haveCents)
			{
			my $centsDigits = length($cents);
			if ($centsDigits == 2)
				{
				$outS .= $cents;
				}
			elsif (!$centsDigits)
				{
				$outS .= '00';
				}
			elsif ($centsDigits == 1)
				{
				$outS .= $cents;
				$outS .= '0';
				}
			else
				{
				my $roundedCents = int(('.' . $cents) * 100);
				$outS .= $roundedCents;
				}
			}
		else
			{
			$outS .= '00';
			}
		}

	if ($isNeg)
		{
		$outS = '(' . $outS . ')';
		}
	$outS;
}

sub commify {
	local $_ = shift;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

return 1;
