# A debhelper build system class for handling .Net (arcade) based projects.
# It prefers out of source tree building.
#
# Copyright: © 2022 Laboratory 50
# License: GPL-3+

package Debian::Debhelper::Buildsystem::arcade;

use strict;
use warnings;
use JSON;
use File::Basename;
use File::Find::Rule qw/ find rule /;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

sub DESCRIPTION {
        ".Net build (Arcade.SDK)"
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

sub get_sdk_version {
        my $base;
        my @sdk;
        if (-d "/usr/lib/dotnet/sdk") {
                $base = "/usr/lib/dotnet/sdk";
        }
        elsif (-d "/usr/share/dotnet/sdk") {
                $base = "/usr/share/dotnet/sdk";
        }
        else {
                error(".Net not found");
        }

        @sdk = find(
          directory =>
            maxdepth => 1,
            name => qr/\d+\.\d+\.\d+/,
        )->in($base);

        error(".Net SDK not found") if (!@sdk);

        verbose_print("found .Net SDK @sdk");
        return basename(shift(@sdk));
}

sub check_auto_buildable {
        my $this=shift;
        my ($step)=@_;

        return (-e $this->get_sourcepath("eng/common/build.sh")) ? 1 : 0;
}

sub new {
        my $class=shift;
        my $this=$class->SUPER::new(@_);
        $this->prefer_out_of_source_building(@_);
        return $this;
}

sub configure {
        my $this=shift;
        if (-e $this->get_sourcepath("global.json")) {
                my $fh;
                my $modified = 0;

                open ($fh, "<", $this->get_sourcepath("global.json"))
                  or error("Can't open file global.json");
                local $/;
                my $global = decode_json(<$fh>);
                close $fh;

                my $sdk_version = $this->get_sdk_version();

                if (exists $global->{sdk}) {
                        verbose_print("overriding sdk version");
                        $global->{sdk}{rollForward} = "latestMinor";
                        $modified = 1;
                }
                if (exists $global->{tools}) {
                        if (exists $global->{tools}{dotnet}) {
                                verbose_print("overriding tools.dotnet version");
                                $global->{tools}{dotnet} = $sdk_version;
                                $modified = 1;
                        }
                        if (exists $global->{tools}{runtimes}) {
                                verbose_print("dropping tools.runtimes.dotnet");
                                #$global->{tools}{runtimes}{dotnet} = [($sdk_version)];
                                delete $global->{tools}{runtimes};
                                $modified = 1;
                        }
                }
                if (exists $global->{"native-tools"}) {
                        verbose_print("dropping native-tools from global.json");
                        delete $global->{"native-tools"};
                        $modified = 1;
                }

                if ($modified && not $dh{NO_ACT}) {
                        #restore_file_on_clean("global.json");

                        open ($fh, ">", $this->get_sourcepath("global.json"))
                          or error("Can't open file global.json");
                        print $fh to_json($global, {pretty => 1});
                        close $fh;
                }
        }

        my @args = qw/--restore/;
        $this->doit_in_sourcedir("eng/common/build.sh", @args, @_);
}

sub clean {
        my $this=shift;
        my @args = qw/-c Release --clean/;
        $this->doit_in_sourcedir("eng/common/build.sh", @args, @_);
}

sub build {
        my $this=shift;
        my @args = qw/-c Release --build --restore/;
        $this->doit_in_sourcedir("eng/common/build.sh", @args, @_);
}

sub test {
#        my $this=shift;
#        my @args = qw/--test/;
#        $this->doit_in_sourcedir("eng/common/build.sh", @args, @_);
}

1
