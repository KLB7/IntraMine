# verify_module_installation.pl: after working through IntraMine initial install.txt
# or IntraMine initial install.html, run this program to verify that all needed
# Strawberry Perl modules have been installed. If not, you'll see a message
# about one or more missing modules. To fix a complaint that "X:Y" is missing,
# at your command prompt run "cpan X:Y".

# (Or you can just wait  and see what happens when you run IntraMine after
# installation is complete, you'll get the same error messages if any).

# Running this program:
# At a command prompt, enter
# perl path-to-your-IntraMine-folder\verify_module_installation.pl
#  For my current installation, that's
# perl C:\perlprogs\mine\verify_module_installation.pl

use strict;

use Search::Elasticsearch;
use Date::Business;
use ExportAbove;
use Win32API::File::Time;
use Math::SimpleHisto::XS;
use File::ReadBackwards;
use IO::Socket::Timeout;
use HTML::CalendarMonthSimple;
#use Syntax::Highlight::Perl::Improved;
use Text::MultiMarkdown;
use Win32::RunAsAdmin;
use Text::Unidecode;
#use Browser::Open;
use Selenium::Remote::Driver;

print("Done. Any missing modules are noted above.\n");
