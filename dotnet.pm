# DH Sequence

# © ООО «Лаборатория 50», 2026

use warnings;
use strict;
use Debian::Debhelper::Dh_Lib;

insert_after('dh_install', 'dh_installnuget');

1;
