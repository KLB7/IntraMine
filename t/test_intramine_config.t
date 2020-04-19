# test_intramine_config.t: test libs/test_intramine_config.pm.

# prove "C:\perlprogs\mine\t\test_intramine_config.t"

use strict;
use warnings;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use intramine_config;

LoadConfigValues();
ok(CVal('FOLDERMONITOR_PS1_FILE') eq 'bats/foldermonitor.ps1', "found a config value");
my $baseDir = BaseDirectory();
my $testPath = $baseDir . 'bats/foldermonitor.ps1';
ok(-f $testPath, "base directory is correct");
my $imagesDir = FullDirectoryPath('IMAGES_DIR');
my $imageTestPath = $imagesDir . 'hoverleft.png';
ok(-f $imageTestPath, "image directory is correct");

done_testing();
