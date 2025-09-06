# win_user32_local.pm: access functions in user32.dll. For now, just GetDoubleClickTime.

package win_user32_local;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use Carp;
use utf8;
use Win32::API;

BEGIN {
	# Double click time
	Win32::API::More->Import(User32 => qq{UINT GetDoubleClickTime()});
}

# Get system double click time in msec.
sub DoubleClickTime {
	my $dtime = GetDoubleClickTime();
	return ($dtime);
}

use ExportAbove;
1;

