# cashflow.pm: accounting calculations for intramine_cashserver.pl, month by month.
# GetDatesAndValues() here is called by intramine_cashserver.pl#GetCashFlow().

package cashflow;

use strict;
use warnings;
use utf8;
use Carp;
use warnings;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use dollars;

# Cash event types:
use constant kOpeningBalance => 1;
use constant kLastMonth      => 2;
use constant kIncomeAnnual   => 3;
use constant kIncomeMonthly  => 4;
use constant kExpenseAnnual  => 5;
use constant kExpenseMonthly => 6;
use constant kAssetPurchase  => 7;
use constant kComment        => 8;


sub new {    # make a new cashflow instance
	my ($proto, $eventFilePath) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{'EVENTFILEPATH'} = $eventFilePath;
	$self->{'ERRORMSG'}      = '';

	bless($self, $class);
	return $self;
}

sub RecordFailure {
	my ($self, $msg) = @_;
	$self->{'ERRORMSG'} .= $msg;
}

# The main event here, run the numbers forward month by month.
# Load events, parse them into event hashes, run through the months doing all
# events relevant to the month. Text results go in $$detailsR as an HTML string.
# Results for graphing go in @$dateR and @$valueR. Dates are along the horizontal axis
# of the graph, month-end balances along the vertical axiz.
sub GetDatesAndValues {
	my ($self, $dateR, $valueR, $detailsR) = @_;

	my @CashEvents;
	my $NumEvents = LoadFileIntoArray(\@CashEvents, $self->{'EVENTFILEPATH'}, "cash events", 1);
	$self->{'CASHEVENTS'} = \@CashEvents;
	$self->{'DATES'}      = $dateR;
	$self->{'VALUES'}     = $valueR;
	$self->{'DETAILS'}    = $detailsR;
	ProcessCashEvents($self);
	if ($self->{'ERRORMSG'} ne '')
		{
		print("FAIL after ProcessCashEvents: $self->{'ERRORMSG'}\n");
		$dateR->[0] = "FAIL!$self->{'ERRORMSG'}";
		}
}

sub ProcessCashEvents {
	my ($self) = @_;

	my %eventDetails;
	$self->{'EVENTDETAILS'} = \%eventDetails;

	ParseCashEvents($self);

	if ($self->{'ERRORMSG'} eq '')
		{
		CheckCashEvents($self) || return;
		RunCashEvents($self);
		}
}

# Build hashes holding details of each "event" (income or expense).
sub ParseCashEvents {
	my ($self)        = @_;
	my $arr           = $self->{'CASHEVENTS'};
	my $eventDetailsH = $self->{'EVENTDETAILS'};

	my $numRows                 = @$arr;
	my $numIncomeEventsAnnual   = 0;
	my $numIncomeEventsMonthly  = 0;
	my $numExpenseEventsAnnual  = 0;
	my $numExpenseEventsMonthly = 0;
	my $numAssetPurchases       = 0;

	for (my $row = 0 ; $row < $numRows ; ++$row)
		{
		my $dispRow   = $row + 1;
		my $cashEvent = $arr->[$row];
		my @fields;
		_GetCashEventFields($cashEvent, \@fields)
			or (RecordFailure($self, "ERROR, bad row $dispRow: |$cashEvent|\n") && return);
		# Event type is always in $fields[0].
		my $eventType = $fields[0];

		if ($eventType == kOpeningBalance)    # OPENING amount YYYYMM
			{
			$eventDetailsH->{'Opening Balance'}{'Amount'} = $fields[1];
			$eventDetailsH->{'Opening Balance'}{'YYYYMM'} = $fields[2];
			}
		elsif ($eventType == kLastMonth)      # UNTIL YYYYMM
			{
			$eventDetailsH->{'Last Month'}{'YYYYMM'} = $fields[1];
			}
		elsif ($eventType == kIncomeAnnual)    # INCOME_ANNUAL amount YYYYMM YYYYMM Description
			{
			$eventDetailsH->{'Income Annual'}{'Amount'}{$numIncomeEventsAnnual}       = $fields[1];
			$eventDetailsH->{'Income Annual'}{'Start YYYYMM'}{$numIncomeEventsAnnual} = $fields[2];
			$eventDetailsH->{'Income Annual'}{'End YYYYMM'}{$numIncomeEventsAnnual}   = $fields[3];
			$eventDetailsH->{'Income Annual'}{'Description'}{$numIncomeEventsAnnual}  = $fields[4];
			$eventDetailsH->{'Income Annual'}{'Percent Annual Increase'}{$numIncomeEventsAnnual} =
				defined($fields[5]) ? $fields[5] : 0;
			++$numIncomeEventsAnnual;
			}
		elsif ($eventType == kIncomeMonthly)    # INCOME_MONTHLY amount YYYYMM YYYYMM Description
			{
			$eventDetailsH->{'Income Monthly'}{'Amount'}{$numIncomeEventsMonthly} = $fields[1];
			$eventDetailsH->{'Income Monthly'}{'Start YYYYMM'}{$numIncomeEventsMonthly} =
				$fields[2];
			$eventDetailsH->{'Income Monthly'}{'End YYYYMM'}{$numIncomeEventsMonthly}  = $fields[3];
			$eventDetailsH->{'Income Monthly'}{'Description'}{$numIncomeEventsMonthly} = $fields[4];
			$eventDetailsH->{'Income Monthly'}{'Percent Annual Increase'}{$numIncomeEventsMonthly}
				= defined($fields[5]) ? $fields[5] : 0;
			++$numIncomeEventsMonthly;
			}
		elsif ($eventType == kExpenseAnnual)    # EXPENSE_ANNUAL amount YYYYMM YYYYMM Description
			{
			$eventDetailsH->{'Expense Annual'}{'Amount'}{$numExpenseEventsAnnual} = $fields[1];
			$eventDetailsH->{'Expense Annual'}{'Start YYYYMM'}{$numExpenseEventsAnnual} =
				$fields[2];
			$eventDetailsH->{'Expense Annual'}{'End YYYYMM'}{$numExpenseEventsAnnual}  = $fields[3];
			$eventDetailsH->{'Expense Annual'}{'Description'}{$numExpenseEventsAnnual} = $fields[4];
			$eventDetailsH->{'Expense Annual'}{'Percent Annual Increase'}{$numExpenseEventsAnnual}
				= defined($fields[5]) ? $fields[5] : 0;
			++$numExpenseEventsAnnual;
			}
		elsif ($eventType == kExpenseMonthly)    # EXPENSE_MONTHLY amount YYYYMM YYYYMM Description
			{
			$eventDetailsH->{'Expense Monthly'}{'Amount'}{$numExpenseEventsMonthly} = $fields[1];
			$eventDetailsH->{'Expense Monthly'}{'Start YYYYMM'}{$numExpenseEventsMonthly} =
				$fields[2];
			$eventDetailsH->{'Expense Monthly'}{'End YYYYMM'}{$numExpenseEventsMonthly} =
				$fields[3];
			$eventDetailsH->{'Expense Monthly'}{'Description'}{$numExpenseEventsMonthly} =
				$fields[4];
			$eventDetailsH->{'Expense Monthly'}{'Percent Annual Increase'}{$numExpenseEventsMonthly}
				= defined($fields[5]) ? $fields[5] : 0;
			++$numExpenseEventsMonthly;
			}
		elsif ($eventType == kAssetPurchase)    # ASSET amount YYYYMM Description
			{
			$eventDetailsH->{'Asset Purchase'}{'Amount'}{$numAssetPurchases}      = $fields[1];
			$eventDetailsH->{'Asset Purchase'}{'YYYYMM'}{$numAssetPurchases}      = $fields[2];
			$eventDetailsH->{'Asset Purchase'}{'Description'}{$numAssetPurchases} = $fields[3];
			#Output("ASSET amt $fields[1] date $fields[2] desc $fields[3]\n") if ($TESTING);
			++$numAssetPurchases;
			}
		elsif ($eventType == kComment)          # #Comment,skipped
			{
			;
			}
		else
			{
			RecordFailure($self, "ERROR, unknown event type on row $dispRow: |$cashEvent|\n");
			return;
			}
		}
}

sub _GetCashEventFields {
	my ($cashEvent, $fieldsArr) = @_;
	my $result = 1;
	if ($cashEvent =~ m!^\s*\#! || $cashEvent =~ m!^\s*$!)
		{
		$fieldsArr->[0] = kComment;
		}
	else
		{
		@$fieldsArr = split(/\t+/, $cashEvent);
		$fieldsArr->[0] = uc($fieldsArr->[0]);
		# Convert event name to constant number
		# OPENING amount YYYYMM
		# UNTIL YYYYMM
		# INCOME_ANNUAL amount YYYYMM YYYYMM Description
		# INCOME_MONTHLY amount YYYYMM YYYYMM Description
		# EXPENSE_ANNUAL amount YYYYMM YYYYMM Description
		# EXPENSE_MONTHLY amount YYYYMM YYYYMM Description
		# ASSET amount YYYYMM Description
		if ($fieldsArr->[0] eq 'OPENING')
			{
			$fieldsArr->[0] = kOpeningBalance;
			}
		elsif ($fieldsArr->[0] eq 'UNTIL')
			{
			$fieldsArr->[0] = kLastMonth;
			}
		elsif ($fieldsArr->[0] eq 'INCOME_ANNUAL')
			{
			$fieldsArr->[0] = kIncomeAnnual;
			}
		elsif ($fieldsArr->[0] eq 'INCOME_MONTHLY')
			{
			$fieldsArr->[0] = kIncomeMonthly;
			}
		elsif ($fieldsArr->[0] eq 'EXPENSE_ANNUAL')
			{
			$fieldsArr->[0] = kExpenseAnnual;
			}
		elsif ($fieldsArr->[0] eq 'EXPENSE_MONTHLY')
			{
			$fieldsArr->[0] = kExpenseMonthly;
			}
		elsif ($fieldsArr->[0] eq 'ASSET')
			{
			$fieldsArr->[0] = kAssetPurchase;
			}
		else
			{
			$result = 0;
			}
		}
	return ($result);
}

# Apply $percent to $amount annually.
# $percent: a true per cent, eg 4 for 4% annually.
sub _InflatedAmount {
	my ($amount, $startYYYYMM, $nowYYYYMM, $percent) = @_;
	my $result = $amount;

	if (!defined($percent) || $percent == 0)
		{
		return ($result);
		}

	my $ms = sprintf("%06d", $startYYYYMM);
	$ms =~ m!^(\d\d\d\d)(\d\d)$!;
	my $yr  = $1;
	my $mon = $2;
	$ms = sprintf("%06d", $nowYYYYMM);
	$ms =~ m!^(\d\d\d\d)(\d\d)$!;
	my $yrNow         = $1;
	my $monNow        = $2;
	my $elapsedYears  = $yrNow - $yr;
	my $elapsedMonths = $monNow - $mon;
	if ($elapsedMonths < 0)
		{
		--$elapsedYears;
		$elapsedMonths += 12;
		}

	# Apply increase annually.
	for (my $i = 0 ; $i < $elapsedYears ; ++$i)
		{
		$result *= 1.0 + $percent / 100.0;
		}
	if ($elapsedMonths > 0)
		{
		my $elapsedMonthsAsYearFraction = $elapsedMonths / 12.0;
		$result *= 1.0 + ($percent * $elapsedMonthsAsYearFraction) / 100.0;
		}

	return ($result);
}

sub CheckCashEvents {
	my ($self)        = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $result        = 1;

	if (!defined($eventDetailsH->{'Opening Balance'}{'YYYYMM'}))
		{
		RecordFailure($self, "CHECKER ERROR, no opening balance date\n");
		$result = 0;
		}
	if (!defined($eventDetailsH->{'Opening Balance'}{'Amount'}))
		{
		RecordFailure($self, "CHECKER ERROR, no opening balance amount\n");
		$result = 0;
		}
	if (!defined($eventDetailsH->{'Last Month'}{'YYYYMM'}))
		{
		RecordFailure($self, "CHECKER ERROR, no last month\n");
		$result = 0;
		}
	return ($result);
}

sub RunCashEvents {
	my ($self)         = @_;
	my $eventDetailsH  = $self->{'EVENTDETAILS'};
	my $detailsR       = $self->{'DETAILS'};
	my $startYYYYMMStr = $eventDetailsH->{'Opening Balance'}{'YYYYMM'};
	my $startYYYYMM    = $startYYYYMMStr + 0;
	my $balance        = $eventDetailsH->{'Opening Balance'}{'Amount'} + 0;
	my $endYYYYMMStr   = $eventDetailsH->{'Last Month'}{'YYYYMM'};
	my $endYYYYMM      = $endYYYYMMStr + 0;

	$$detailsR .= "<table><caption>Cash flow from $startYYYYMMStr to $endYYYYMMStr</caption>";
	my $balanceDollars = '&nbsp;' . Dollars($balance);
	$$detailsR .=
"<tr class='openingbal'><td>Opening Balance&nbsp;</td><td>$startYYYYMMStr:</td><td>$balanceDollars</td><td>\&nbsp;</td></tr>";

	my $dateR  = $self->{'DATES'};
	my $valueR = $self->{'VALUES'};
	push @$dateR,  $startYYYYMMStr;    # Show opening balance on bar chart.
	push @$valueR, $balance;

	for (my $m = $startYYYYMM ; $m <= $endYYYYMM ; ++$m)
		{
		my $ms = sprintf("%06d", $m);
		$ms =~ m!^(\d\d\d\d)(\d\d)$!;
		my $yr  = $1;
		my $mon = $2;
		if ($mon == 13)
			{
			$yr += 1;
			$mon = 1;
			$ms  = sprintf("%04d%02d", $yr, $mon);
			$m   = $ms + 0;
			$ms =~ m!^(\d\d\d\d)(\d\d)$!;
			$yr  = $1;
			$mon = $2;
			}

		#Output("$ms\n") if ($TESTING);
		RunCashEventsForMonth($self, $startYYYYMMStr, $ms, \$balance);
		$balanceDollars = ($balance > 0) ? '&nbsp;' . Dollars($balance) : Dollars($balance);
		if ($mon != 12)
			{
			my $cls = ($balance > 0) ? 'monthlybal' : 'monthlybalneg';
			$$detailsR .=
"<tr class='$cls'><td>Balance</td><td>$ms</td><td>$balanceDollars</td><td>\&nbsp;</td></tr>";
			}
		else
			{
			push @$dateR,  $yr;
			push @$valueR, $balance;
			my $cls = ($balance > 0) ? 'yebal' : 'yebalneg';
			$$detailsR .=
"<tr class='$cls'><td>Year End</td><td>$yr</td><td>$balanceDollars</td><td>\&nbsp;</td></tr>";
			}
		# else all done.
		}

	my $ms = sprintf("%06d", $endYYYYMM);
	$ms =~ m!^(\d\d\d\d)(\d\d)$!;
	my $yr  = $1;
	my $mon = $2;
	if ($mon != 12)
		{
		push @$dateR,  $ms;
		push @$valueR, $balance;
		}
	$balanceDollars = ($balance > 0) ? '&nbsp;' . Dollars($balance) : Dollars($balance);
	$$detailsR .=
"<tr><td>Final Balance</td><td>$endYYYYMMStr:</td><td>$balanceDollars</td><td>\&nbsp;</td></tr>";
	$$detailsR .= "</table>";
}

sub RunCashEventsForMonth {
	my ($self, $startYYYYMMStr, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};

	$ms =~ m!^(\d\d\d\d)(\d\d)$!;
	my $yr  = $1;
	my $mon = $2;
	my $m   = $ms + 0;

	foreach my $evtType (sort {$a cmp $b} keys %$eventDetailsH)
		{
		#Output("$evtType\n") if ($TESTING);
		if ($evtType eq 'Income Annual')
			{
			RunAnnualIncomeEventForMonth($self, $startYYYYMMStr, $m, $mon, $ms, $balanceR)
				or return;
			}
		elsif ($evtType eq 'Income Monthly')
			{
			RunMonthlyIncomeEventForMonth($self, $startYYYYMMStr, $m, $mon, $ms, $balanceR)
				or return;
			}
		elsif ($evtType eq 'Expense Annual')
			{
			RunAnnualExpenseEventForMonth($self, $startYYYYMMStr, $m, $mon, $ms, $balanceR)
				or return;
			}
		elsif ($evtType eq 'Expense Monthly')
			{
			RunMonthlyExpenseEventForMonth($self, $startYYYYMMStr, $m, $mon, $ms, $balanceR)
				or return;
			}
		elsif ($evtType eq 'Asset Purchase')
			{
			RunAssetPurchaseForMonth($self, $m, $mon, $ms, $balanceR)
				or return;
			}
		}
}

sub RunAnnualIncomeEventForMonth {
	my ($self, $openingYYYYMMStr, $m, $mon, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $detailsR      = $self->{'DETAILS'};
	my $result        = 1;

	foreach my $idx (keys %{$eventDetailsH->{'Income Annual'}{'Amount'}})
		{
		#Output("IDX |$idx|\n") if ($TESTING);
		my $startYYYYMMStr = $eventDetailsH->{'Income Annual'}{'Start YYYYMM'}{$idx};
		$startYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $startM       = $2;
		my $endYYYYMMStr = $eventDetailsH->{'Income Annual'}{'End YYYYMM'}{$idx};
		$endYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $endM = $2;

		my $amt = $eventDetailsH->{'Income Annual'}{'Amount'}{$idx};
		if ($eventDetailsH->{'Income Annual'}{'Percent Annual Increase'}{$idx} > 0)
			{
			my $startYM =
				($openingYYYYMMStr > $startYYYYMMStr) ? $openingYYYYMMStr : $startYYYYMMStr;
			$amt = _InflatedAmount($amt, $startYM, $m,
				$eventDetailsH->{'Income Annual'}{'Percent Annual Increase'}{$idx});
			}
		my $desc        = $eventDetailsH->{'Income Annual'}{'Description'}{$idx};
		my $startYYYYMM = $startYYYYMMStr + 0;
		my $endYYYYMM   = $endYYYYMMStr + 0;
		if ($startM != $endM)
			{
			RecordFailure($self,
				"ERROR, start and end months disagree for annual income \'$desc\'\n");
			$result = 0;
			last;
			}
		#Output("INCOME ANNUAL $ms $desc $amt $startYYYYMMStr $endYYYYMMStr\n") if ($TESTING);
		if ($m >= $startYYYYMM && $m <= $endYYYYMM && $mon == $startM)
			{
			my $amtDollars = '&nbsp;' . Dollars($amt);
			my $isOneShot  = ($startYYYYMMStr eq $endYYYYMMStr);
			if ($isOneShot)
				{
				$$detailsR .=
"<tr><td>ANNUAL INC</td><td>$ms</td><td>$amtDollars</td><td><strong>$desc</strong></td></tr>";
				}
			else
				{
				$$detailsR .=
"<tr><td>ANNUAL INC</td><td>$ms</td><td>$amtDollars</td><td><em>$desc</em></td></tr>";
				}
			$$balanceR += $amt;
			}
		}
	return ($result);
}

sub RunMonthlyIncomeEventForMonth {
	my ($self, $openingYYYYMMStr, $m, $mon, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $detailsR      = $self->{'DETAILS'};
	my $result        = 1;

	foreach my $idx (keys %{$eventDetailsH->{'Income Monthly'}{'Amount'}})
		{
		#Output("IDX |$idx|\n") if ($TESTING);
		my $startYYYYMMStr = $eventDetailsH->{'Income Monthly'}{'Start YYYYMM'}{$idx};
		$startYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $startM       = $2;
		my $endYYYYMMStr = $eventDetailsH->{'Income Monthly'}{'End YYYYMM'}{$idx};
		$endYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $endM = $2;

		my $amt = $eventDetailsH->{'Income Monthly'}{'Amount'}{$idx};
		if ($eventDetailsH->{'Income Monthly'}{'Percent Annual Increase'}{$idx} > 0)
			{
			my $startYM =
				($openingYYYYMMStr > $startYYYYMMStr) ? $openingYYYYMMStr : $startYYYYMMStr;
			$amt = _InflatedAmount($amt, $startYM, $m,
				$eventDetailsH->{'Income Monthly'}{'Percent Annual Increase'}{$idx});
			}
		my $desc        = $eventDetailsH->{'Income Monthly'}{'Description'}{$idx};
		my $startYYYYMM = $startYYYYMMStr + 0;
		my $endYYYYMM   = $endYYYYMMStr + 0;
		#Output("INCOME MONTHLY $ms $desc $amt $startYYYYMMStr $endYYYYMMStr\n") if ($TESTING);
		if ($m >= $startYYYYMM && $m <= $endYYYYMM)
			{
			my $amtDollars = '&nbsp;' . Dollars($amt);
			my $isOneShot  = ($startYYYYMMStr eq $endYYYYMMStr);
			if ($isOneShot)
				{
				$$detailsR .=
"<tr><td>MONTHLY INC</td><td>$ms</td><td>$amtDollars</td><td><strong>$desc</strong></td></tr>";
				}
			else
				{
				$$detailsR .=
"<tr><td>MONTHLY INC</td><td>$ms</td><td>$amtDollars</td><td><em>$desc</em></td></tr>";
				}
			$$balanceR += $amt;
			}
		}
	return ($result);
}

sub RunAnnualExpenseEventForMonth {
	my ($self, $openingYYYYMMStr, $m, $mon, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $detailsR      = $self->{'DETAILS'};
	my $result        = 1;

	foreach my $idx (keys %{$eventDetailsH->{'Expense Annual'}{'Amount'}})
		{
		#Output("IDX |$idx|\n") if ($TESTING);
		my $startYYYYMMStr = $eventDetailsH->{'Expense Annual'}{'Start YYYYMM'}{$idx};
		$startYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $startM       = $2;
		my $endYYYYMMStr = $eventDetailsH->{'Expense Annual'}{'End YYYYMM'}{$idx};
		$endYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $endM = $2;

		my $amt = $eventDetailsH->{'Expense Annual'}{'Amount'}{$idx};
		if ($eventDetailsH->{'Expense Annual'}{'Percent Annual Increase'}{$idx} > 0)
			{
			my $startYM =
				($openingYYYYMMStr > $startYYYYMMStr) ? $openingYYYYMMStr : $startYYYYMMStr;
			$amt = _InflatedAmount($amt, $startYM, $m,
				$eventDetailsH->{'Expense Annual'}{'Percent Annual Increase'}{$idx});
			}
		my $desc        = $eventDetailsH->{'Expense Annual'}{'Description'}{$idx};
		my $startYYYYMM = $startYYYYMMStr + 0;
		my $endYYYYMM   = $endYYYYMMStr + 0;
		if ($startM != $endM)
			{
			RecordFailure($self,
				"ERROR, start and end months disagree for annual expense \'$desc\'\n");
			$result = 0;
			last;
			}
		#Output("INCOME ANNUAL $ms $desc $amt $startYYYYMMStr $endYYYYMMStr\n") if ($TESTING);
		if ($m >= $startYYYYMM && $m <= $endYYYYMM && $mon == $startM)
			{
			my $amtDollars = Dollars(-$amt);
			my $isOneShot  = ($startYYYYMMStr eq $endYYYYMMStr);
			if ($isOneShot)
				{
				$$detailsR .=
"<tr><td>ANNUAL EXP</td><td>$ms</td><td>$amtDollars</td><td><strong>$desc</strong></td></tr>";
				}
			else
				{
				$$detailsR .=
"<tr><td>ANNUAL EXP</td><td>$ms</td><td>$amtDollars</td><td><em>$desc</em></td></tr>";
				}
			$$balanceR -= $amt;
			}
		}
	return ($result);
}

sub RunMonthlyExpenseEventForMonth {
	my ($self, $openingYYYYMMStr, $m, $mon, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $detailsR      = $self->{'DETAILS'};
	my $result        = 1;

	foreach my $idx (keys %{$eventDetailsH->{'Expense Monthly'}{'Amount'}})
		{
		#Output("IDX |$idx|\n") if ($TESTING);
		my $startYYYYMMStr = $eventDetailsH->{'Expense Monthly'}{'Start YYYYMM'}{$idx};
		$startYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $startM       = $2;
		my $endYYYYMMStr = $eventDetailsH->{'Expense Monthly'}{'End YYYYMM'}{$idx};
		$endYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $endM = $2;

		my $amt = $eventDetailsH->{'Expense Monthly'}{'Amount'}{$idx};
		if ($eventDetailsH->{'Expense Monthly'}{'Percent Annual Increase'}{$idx} > 0)
			{
			my $startYM =
				($openingYYYYMMStr > $startYYYYMMStr) ? $openingYYYYMMStr : $startYYYYMMStr;
			$amt = _InflatedAmount($amt, $startYM, $m,
				$eventDetailsH->{'Expense Monthly'}{'Percent Annual Increase'}{$idx});
			}
		my $desc        = $eventDetailsH->{'Expense Monthly'}{'Description'}{$idx};
		my $startYYYYMM = $startYYYYMMStr + 0;
		my $endYYYYMM   = $endYYYYMMStr + 0;
		#Output("INCOME MONTHLY $ms $desc $amt $startYYYYMMStr $endYYYYMMStr\n") if ($TESTING);
		if ($m >= $startYYYYMM && $m <= $endYYYYMM)
			{
			my $amtDollars = Dollars(-$amt);
			my $isOneShot  = ($startYYYYMMStr eq $endYYYYMMStr);
			if ($isOneShot)
				{
				$$detailsR .=
"<tr><td>MONTHLY EXP</td><td>$ms</td><td>$amtDollars</td><td><strong>$desc</strong></td></tr>";
				}
			else
				{
				$$detailsR .=
"<tr><td>MONTHLY EXP</td><td>$ms</td><td>$amtDollars</td><td><em>$desc</em></td></tr>";
				}
			$$balanceR -= $amt;
			}
		}
	return ($result);
}

sub RunAssetPurchaseForMonth {
	my ($self, $m, $mon, $ms, $balanceR) = @_;
	my $eventDetailsH = $self->{'EVENTDETAILS'};
	my $detailsR      = $self->{'DETAILS'};
	my $result        = 1;

	foreach my $idx (keys %{$eventDetailsH->{'Asset Purchase'}{'Amount'}})
		{
		#Output("IDX |$idx|\n") if ($TESTING);
		my $startYYYYMMStr = $eventDetailsH->{'Asset Purchase'}{'YYYYMM'}{$idx};
		$startYYYYMMStr =~ m!^(\d\d\d\d)(\d\d)$!;
		my $startM = $2;

		my $amt         = $eventDetailsH->{'Asset Purchase'}{'Amount'}{$idx};
		my $desc        = $eventDetailsH->{'Asset Purchase'}{'Description'}{$idx};
		my $startYYYYMM = $startYYYYMMStr + 0;
		#Output("ASSET PURCHASE CANDIDATE $ms $desc $amt $startYYYYMMStr\n") if ($TESTING);
		if ($m == $startYYYYMM)
			{
			my $amtDollars = Dollars(-$amt);
			$$detailsR .=
"<tr><td>ASSET PURCH</td><td>$ms</td><td>$amtDollars</td><td><strong>$desc</strong></td></tr>";
			$$balanceR -= $amt;
			}
		}
	return ($result);
}

1;
